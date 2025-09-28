#!/usr/bin/env elixir
# Test script that simulates the exact production error (0xc5 0x73)
# Run with: mix run test_production_utf8_error.exs

require Logger
alias EventasaurusDiscovery.Utils.UTF8
alias EventasaurusDiscovery.Performers.PerformerStore

IO.puts("\n=== Simulating Production UTF-8 Error (0xc5 0x73) ===\n")

# The actual corrupt bytes from production error
# 0xc5 is expecting a continuation byte, but 0x73 ('s') is not valid
corrupt_name = <<82, 111, 99, 107, 45, 83, 101, 114, 119, 105, 115, 32,
                 80, 105, 111, 116, 114, 32, 75, 111, 0xc5, 0x73, 107, 105>>

IO.puts("Test 1: Corrupt Name Analysis")
IO.puts("=" <> String.duplicate("=", 60))
IO.puts("  Corrupt bytes: #{inspect(:binary.bin_to_list(corrupt_name))}")
IO.puts("  Valid UTF-8? #{String.valid?(corrupt_name)}")

# Clean it
clean_name = UTF8.ensure_valid_utf8(corrupt_name)
IO.puts("  After cleaning: #{inspect(clean_name)}")
IO.puts("  Clean valid? #{String.valid?(clean_name)}")

# Test 2: PerformerStore with corrupt attrs
IO.puts("\nTest 2: PerformerStore with Corrupt Attributes")
IO.puts("=" <> String.duplicate("=", 60))

corrupt_attrs = %{
  "name" => corrupt_name,
  "source_id" => 1,
  "external_id" => "tm_performer_test"
}

IO.puts("  Testing find_or_create_performer with corrupt name...")
case PerformerStore.find_or_create_performer(corrupt_attrs) do
  {:ok, performer} ->
    IO.puts("  ✅ Success! Created/found performer: #{performer.name}")
    IO.puts("     ID: #{performer.id}, Slug: #{performer.slug}")
  {:error, reason} ->
    IO.puts("  ❌ Error: #{inspect(reason)}")
end

# Test 3: Direct changeset test
IO.puts("\nTest 3: Direct Performer Changeset Test")
IO.puts("=" <> String.duplicate("=", 60))

alias EventasaurusDiscovery.Performers.Performer

changeset = Performer.changeset(%Performer{}, %{
  name: corrupt_name,
  source_id: 1
})

if changeset.valid? do
  name = Ecto.Changeset.get_field(changeset, :name)
  slug = Ecto.Changeset.get_field(changeset, :slug)
  IO.puts("  ✅ Changeset valid")
  IO.puts("     Name: #{inspect(name)}")
  IO.puts("     Slug: #{inspect(slug)}")
  IO.puts("     Name valid UTF-8? #{String.valid?(name)}")
else
  IO.puts("  ❌ Changeset invalid: #{inspect(changeset.errors)}")
end

# Test 4: Simulate the exact flow from EventProcessorJob
IO.puts("\nTest 4: Full Event Processing Flow Simulation")
IO.puts("=" <> String.duplicate("=", 60))

# Simulate corrupted job args like in production
job_args = %{
  "event_data" => %{
    "performers" => [
      %{"name" => "Kwoon"},
      %{"name" => corrupt_name}  # The corrupt one
    ]
  },
  "source_id" => 1
}

IO.puts("  Step 1: Clean job args (EventProcessorJob)")
clean_args = UTF8.validate_map_strings(job_args)
performer2_name = clean_args["event_data"]["performers"] |> Enum.at(1) |> Map.get("name")
IO.puts("    Performer 2 name after cleaning: #{inspect(performer2_name)}")
IO.puts("    Valid UTF-8? #{String.valid?(performer2_name)}")

IO.puts("\n  Step 2: Process performers (Sources.Processor)")
performers_data = clean_args["event_data"]["performers"]
for performer_data <- performers_data do
  name = performer_data["name"]
  IO.puts("    Processing: #{inspect(name, limit: 30)}")

  # This is what Sources.Processor does
  attrs_with_source = Map.put(performer_data, "source_id", 1)

  case PerformerStore.find_or_create_performer(attrs_with_source) do
    {:ok, performer} ->
      IO.puts("      ✅ Created/found: #{performer.name} (ID: #{performer.id})")
    {:error, reason} ->
      IO.puts("      ❌ Error: #{inspect(reason)}")
  end
end

IO.puts("\n=== Test Complete ===")
IO.puts("\nSummary:")
IO.puts("The production error '0xc5 0x73' is handled by:")
IO.puts("1. UTF8.validate_map_strings in EventProcessorJob")
IO.puts("2. UTF8.ensure_valid_utf8 in PerformerStore.normalize_performer_attrs")
IO.puts("3. UTF8 sanitization in Performer.changeset")
IO.puts("4. UTF8.ensure_valid_utf8 after Normalizer in EventProcessor")
IO.puts("\nAll layers of protection are now in place.")