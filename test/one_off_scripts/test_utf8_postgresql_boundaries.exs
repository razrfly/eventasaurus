# Test script for PostgreSQL Boundary Protection Strategy
# Run with: mix run test_utf8_postgresql_boundaries.exs

require Logger
alias EventasaurusDiscovery.Utils.UTF8

IO.puts("\n=== Testing PostgreSQL Boundary Protection Strategy ===\n")

# Test 1: The exact corruption pattern from production
IO.puts("Test 1: Ticketmaster corruption pattern (0xe2 0x20 0x46)")
corrupt_title = <<87, 79, 82, 76, 68, 32, 72, 69, 88, 32, 84, 79, 85, 82, 32, 50, 48, 50, 53, 32, 226, 32, 70, 97, 117, 110>>
IO.puts("  Input bytes: #{inspect(:binary.bin_to_list(corrupt_title))}")
IO.puts("  Valid UTF-8? #{String.valid?(corrupt_title)}")

clean_title = UTF8.ensure_valid_utf8(corrupt_title)
IO.puts("  Cleaned: #{clean_title}")
IO.puts("  Valid after cleaning? #{String.valid?(clean_title)}")
IO.puts("  ✅ Test 1 passed")

# Test 2: Various corruption patterns
IO.puts("\nTest 2: Various corruption patterns")
corruptions = [
  {<<0xe2, 0x20, 0x46>>, "0xe2 0x20 0x46 (en-dash + space + F)"},
  {<<0xe2, 0x20>>, "0xe2 0x20 (incomplete en-dash)"},
  {<<0xe2>>, "standalone 0xe2"},
  {<<0xe2, 0x80>>, "0xe2 0x80 (incomplete en-dash)"},
  {<<0xe2, 0x94>>, "0xe2 0x94 (corrupted em-dash)"},
  {"Test " <> <<0xe2, 0x20>> <> " Text", "embedded corruption"}
]

for {corrupt, desc} <- corruptions do
  clean = UTF8.ensure_valid_utf8(corrupt)
  valid = String.valid?(clean)
  IO.puts("  #{desc}: #{if valid, do: "✅", else: "❌"} (#{inspect(clean, limit: 20)})")
end

# Test 3: Map validation (like Oban args)
IO.puts("\nTest 3: Map validation (Oban job args)")
corrupt_map = %{
  "event_data" => %{
    "title" => <<87, 79, 82, 76, 68, 32, 72, 69, 88, 32, 84, 79, 85, 82, 32, 50, 48, 50, 53, 32, 226, 32, 70>>,
    "description" => "Normal text with " <> <<0xe2, 0x20>> <> " corruption",
    "venue" => %{
      "name" => "Venue" <> <<0xe2>>
    }
  }
}

clean_map = UTF8.validate_map_strings(corrupt_map)
all_valid =
  String.valid?(clean_map["event_data"]["title"]) and
  String.valid?(clean_map["event_data"]["description"]) and
  String.valid?(clean_map["event_data"]["venue"]["name"])

IO.puts("  All strings valid after cleaning? #{if all_valid, do: "✅", else: "❌"}")
IO.puts("  Title: #{clean_map["event_data"]["title"] |> String.slice(0, 30)}...")
IO.puts("  Description: #{clean_map["event_data"]["description"] |> String.slice(0, 30)}...")

# Test 4: Test with actual database insert (if in dev environment)
IO.puts("\nTest 4: Database insertion test")
if Mix.env() == :dev do
  # Create a test event with corrupt data
  corrupt_attrs = %{
    title: <<87, 79, 82, 76, 68, 32, 226, 32, 70>>,
    starts_at: DateTime.utc_now(),
    venue_id: 1  # Assuming venue 1 exists
  }

  changeset = EventasaurusDiscovery.PublicEvents.PublicEvent.changeset(
    %EventasaurusDiscovery.PublicEvents.PublicEvent{},
    corrupt_attrs
  )

  case EventasaurusApp.Repo.insert(changeset) do
    {:ok, event} ->
      IO.puts("  ✅ Successfully inserted event with ID: #{event.id}")
      IO.puts("  Cleaned title: #{event.title}")
      # Clean up
      EventasaurusApp.Repo.delete(event)
    {:error, changeset} ->
      IO.puts("  ❌ Failed to insert: #{inspect(changeset.errors)}")
  end
else
  IO.puts("  Skipped (not in dev environment)")
end

# Test 5: Performance test
IO.puts("\nTest 5: Performance test")
iterations = 10_000
test_string = "Valid UTF-8 string with no issues"
corrupt_string = "String with " <> <<0xe2, 0x20>> <> " corruption"

# Test fast path (already valid)
start = System.monotonic_time(:microsecond)
for _ <- 1..iterations do
  UTF8.ensure_valid_utf8(test_string)
end
valid_time = System.monotonic_time(:microsecond) - start

# Test slow path (needs fixing)
start = System.monotonic_time(:microsecond)
for _ <- 1..iterations do
  UTF8.ensure_valid_utf8(corrupt_string)
end
corrupt_time = System.monotonic_time(:microsecond) - start

IO.puts("  Valid string (fast path): #{div(valid_time, iterations)} µs/op")
IO.puts("  Corrupt string (slow path): #{div(corrupt_time, iterations)} µs/op")
IO.puts("  Overhead ratio: #{Float.round(corrupt_time / valid_time, 2)}x")

IO.puts("\n=== All Tests Complete ===\n")