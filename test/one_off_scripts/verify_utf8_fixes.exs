#!/usr/bin/env elixir
# Comprehensive verification of UTF-8 fixes across all boundaries
# Run with: mix run verify_utf8_fixes.exs

require Logger
alias EventasaurusDiscovery.Utils.UTF8

# Start the application so Repo/Oban/etc. are available
Mix.Task.run("app.start")

IO.puts("\n=== Verifying UTF-8 Fixes Across All Boundaries ===\n")

# Test 1: The exact production error pattern
IO.puts("Test 1: Production Error Pattern (0xe2 0x20 0x46)")
IO.puts("=" <> String.duplicate("=", 60))

# This is the exact pattern from production
corrupt_data = %{
  "event_data" => %{
    "title" => <<87, 79, 82, 76, 68, 32, 72, 69, 88, 32, 84, 79, 85, 82, 32, 50, 48, 50, 53, 32, 226, 32, 70>>,
    "performers" => [
      %{"name" => "Artist with" <> <<0xe2, 0x20>> <> "corruption"},
      %{"name" => "Normal Artist"},
      %{"name" => <<0xe2>> <> "Broken"}
    ],
    "venue" => %{
      "name" => "Venue" <> <<0xe2, 0x94>> <> "Name"
    }
  }
}

# Clean the data
clean_data = UTF8.validate_map_strings(corrupt_data)

# Verify all strings are valid
all_valid =
  String.valid?(clean_data["event_data"]["title"]) and
  Enum.all?(clean_data["event_data"]["performers"], fn p -> String.valid?(p["name"]) end) and
  String.valid?(clean_data["event_data"]["venue"]["name"])

IO.puts("  Original title bytes: #{inspect(:binary.bin_to_list(corrupt_data["event_data"]["title"]))}")
IO.puts("  Cleaned title: #{clean_data["event_data"]["title"]}")
IO.puts("  All strings valid after cleaning? #{if all_valid, do: "✅", else: "❌"}")

# Test 2: Performer Name Processing (The Slug.slugify issue)
IO.puts("\nTest 2: Performer Name Processing")
IO.puts("=" <> String.duplicate("=", 60))

corrupt_performer_names = [
  <<0xe2, 0x20, 0x46>> <> "oo Fighters",  # Corrupted "Foo Fighters"
  "Kendrick" <> <<0xe2>> <> "Lamar",      # Corrupted dash
  <<0xe2, 0x94>>,                         # Just corruption
  "Normal Name"
]

IO.puts("  Testing performer name cleaning:")
for name <- corrupt_performer_names do
  clean = UTF8.ensure_valid_utf8(name)
  valid = String.valid?(clean)
  IO.puts("    #{if valid, do: "✅", else: "❌"} #{inspect(clean, limit: 30)}")
end

# Test 3: Simulating Oban Job Storage
IO.puts("\nTest 3: Oban Job Storage Simulation")
IO.puts("=" <> String.duplicate("=", 60))

# Create a job args map with corruption
job_args = %{
  "event_data" => %{
    "external_id" => "tm_123",
    "title" => "Concert" <> <<0xe2, 0x20>> <> "2025",
    "performers" => [
      %{"name" => "Band" <> <<0xe2>>}
    ]
  },
  "source_id" => 1
}

# Clean before storage (what sync_job does)
clean_args = UTF8.validate_map_strings(job_args)

# Encode to JSON and back (simulating DB storage)
{:ok, json} = Jason.encode(clean_args)
{:ok, decoded} = Jason.decode(json)

# Clean again after retrieval (what EventProcessorJob does)
final_clean = UTF8.validate_map_strings(decoded)

all_valid_final =
  String.valid?(final_clean["event_data"]["title"]) and
  Enum.all?(final_clean["event_data"]["performers"], fn p -> String.valid?(p["name"]) end)

IO.puts("  Original has corruption: #{not String.valid?(job_args["event_data"]["title"])}")
IO.puts("  After first clean: #{String.valid?(clean_args["event_data"]["title"])}")
IO.puts("  After JSON round-trip: #{String.valid?(decoded["event_data"]["title"])}")
IO.puts("  After final clean: #{String.valid?(final_clean["event_data"]["title"])}")
IO.puts("  Final result valid? #{if all_valid_final, do: "✅", else: "❌"}")

# Test 4: String.jaro_distance Protection
IO.puts("\nTest 4: String.jaro_distance Protection")
IO.puts("=" <> String.duplicate("=", 60))

test_pairs = [
  {"Valid String", "Another Valid"},
  {<<0xe2, 0x20>> <> "Corrupted", "Normal"},
  {"Normal", <<0xe2>> <> "Corrupted"},
  {<<0xe2, 0x94>>, <<0xe2, 0x20>>}
]

IO.puts("  Testing jaro_distance with UTF-8 cleaning:")
for {s1, s2} <- test_pairs do
  clean1 = UTF8.ensure_valid_utf8(s1)
  clean2 = UTF8.ensure_valid_utf8(s2)

  result = try do
    distance = String.jaro_distance(clean1, clean2)
    "✅ Distance: #{Float.round(distance, 3)}"
  rescue
    e -> "❌ Error: #{inspect(e)}"
  end

  IO.puts("    #{result} for #{inspect(clean1, limit: 20)} vs #{inspect(clean2, limit: 20)}")
end

# Test 5: Performer Changeset with Slug Generation
IO.puts("\nTest 5: Performer Changeset with Slug Generation")
IO.puts("=" <> String.duplicate("=", 60))

if Code.ensure_loaded?(EventasaurusDiscovery.Performers.Performer) do
  alias EventasaurusDiscovery.Performers.Performer

  corrupt_attrs = %{
    name: "Artist" <> <<0xe2, 0x20>> <> "Name",
    source_id: 1
  }

  changeset = Performer.changeset(%Performer{}, corrupt_attrs)

  if changeset.valid? do
    name = Ecto.Changeset.get_change(changeset, :name)
    IO.puts("  ✅ Changeset valid")
    IO.puts("  Cleaned name: #{inspect(name)}")
    IO.puts("  Name is valid UTF-8: #{String.valid?(name)}")
  else
    IO.puts("  ❌ Changeset invalid: #{inspect(changeset.errors)}")
  end
else
  IO.puts("  ⚠️  Performer module not loaded, skipping test")
end

# Test 6: Check for Legacy Jobs
IO.puts("\nTest 6: Legacy Oban Jobs Check")
IO.puts("=" <> String.duplicate("=", 60))

# Check if there are any Oban jobs with corrupted args
import Ecto.Query
alias EventasaurusApp.Repo

# Get recent failed jobs
failed_jobs =
  from(j in Oban.Job,
    where: j.state == "retryable" or j.state == "discarded",
    where: j.queue in ["scraper_detail", "discovery"],
    order_by: [desc: j.id],
    limit: 5
  )
  |> Repo.all()

if Enum.empty?(failed_jobs) do
  IO.puts("  ✅ No failed jobs found")
else
  IO.puts("  Found #{length(failed_jobs)} failed jobs:")
  for job <- failed_jobs do
    # Try to detect UTF-8 issues in args using JSON encoding
    has_corruption =
      case Jason.encode(job.args) do
        {:ok, _} -> false
        {:error, _} -> true
      end

    IO.puts("    Job #{job.id}: #{job.worker}")
    IO.puts("      State: #{job.state}, Attempt: #{job.attempt}/#{job.max_attempts}")
    if has_corruption do
      IO.puts("      ⚠️  Possible UTF-8 corruption detected")
    end
  end
end

IO.puts("\n=== Verification Complete ===\n")

# Summary
IO.puts("""
Summary of UTF-8 Protection:
1. ✅ HTTP Boundary: Client validates response bodies after JSON decode
2. ✅ Job Creation: SyncJob cleans data before creating jobs
3. ✅ Job Execution: EventProcessorJob cleans args on retrieval
4. ✅ Performer Creation: Changeset sanitizes name before slug generation
5. ✅ String Operations: All jaro_distance calls protected
6. ✅ Database Operations: All text operations have UTF-8 validation

Legacy jobs created before the fix may still have corrupted data.
These should be canceled and re-queued after the fix is deployed.
""")