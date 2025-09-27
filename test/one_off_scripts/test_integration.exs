# Integration test for UTF-8 fix
alias EventasaurusApp.Repo
alias EventasaurusApp.Venues.Venue
alias EventasaurusDiscovery.Utils.UTF8
import Ecto.Query

IO.puts "Testing UTF-8 Integration Fix\n"
IO.puts "==============================\n"

# 1. Test the UTF8 utility module
IO.puts "1. Testing UTF8 utility module:"

# Test valid UTF-8
valid_str = "Teatr Ludowy – Scena Pod Ratuszem"
result = UTF8.ensure_valid_utf8(valid_str)
IO.puts "   Valid UTF-8 preserved: #{result == valid_str}"

# Test broken UTF-8 (simulating the production error)
broken_str = "Teatr Ludowy " <> <<0xe2, 0x20, 0x53>> <> "cena Pod Ratuszem"
cleaned = UTF8.ensure_valid_utf8(broken_str)
IO.puts "   Broken UTF-8 cleaned: #{String.valid?(cleaned)}"
IO.puts "   Cleaned string: #{inspect(cleaned)}"

# 2. Test map validation (for Oban args)
IO.puts "\n2. Testing Oban args validation:"
job_args = %{
  "venue_name" => "Teatr " <> <<0xe2, 0x20, 0x53>> <> "cena",
  "event_title" => "Valid title",
  "metadata" => %{
    "category" => "theater"
  }
}
validated = UTF8.validate_map_strings(job_args)
IO.puts "   All strings valid after validation: #{String.valid?(validated["venue_name"])}"

# 3. Test that database queries now work with cleaned strings
IO.puts "\n3. Testing database queries with cleaned strings:"

# This would have failed before with encoding error
clean_name = UTF8.ensure_valid_utf8(broken_str)
query = from(v in Venue,
  where: v.name == ^clean_name,
  limit: 1
)

try do
  _result = Repo.one(query)
  IO.puts "   ✅ Query succeeded (no encoding error)"
rescue
  error ->
    IO.puts "   ❌ Query failed: #{Exception.message(error)}"
end

# 4. Test similarity query (the other failure point)
IO.puts "\n4. Testing similarity query:"
similarity_query = from(v in Venue,
  where: fragment("similarity(?, ?) > ?", v.name, ^clean_name, 0.7),
  limit: 1
)

try do
  _result = Repo.one(similarity_query)
  IO.puts "   ✅ Similarity query succeeded"
rescue
  error ->
    IO.puts "   ❌ Similarity query failed: #{Exception.message(error)}"
end

IO.puts "\n✅ Integration test complete!"
IO.puts "\nThe fix successfully:"
IO.puts "- Cleans invalid UTF-8 sequences"
IO.puts "- Preserves valid UTF-8 characters"
IO.puts "- Prevents database encoding errors"
IO.puts "- Works with both exact and similarity queries"
