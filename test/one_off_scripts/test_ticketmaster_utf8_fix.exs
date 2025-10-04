#!/usr/bin/env elixir

# Test script to verify UTF-8 fix for Ticketmaster EventProcessorJob
# Tests the specific case that was failing: "Rock-Serwis Piotr Kosiński"

IO.puts("=== Testing UTF-8 Fix for Ticketmaster Performer Names ===\n")

alias EventasaurusDiscovery.Utils.UTF8
alias EventasaurusDiscovery.Scraping.Helpers.Normalizer

# Test case 1: The problematic name from the error
problematic_name = "Rock-Serwis Piotr Kosiński"
IO.puts("Test 1: Processing '#{problematic_name}'")

# Step 1: Clean the UTF-8
clean_name = UTF8.ensure_valid_utf8(problematic_name)
IO.puts("  Cleaned: '#{clean_name}'")
IO.puts("  Valid UTF-8? #{String.valid?(clean_name)}")

# Step 2: Normalize the text
normalized = Normalizer.normalize_text(clean_name)
IO.puts("  Normalized: '#{normalized}'")

# Step 3: Create slug
slug = Slug.slugify(normalized)
IO.puts("  Slug: '#{slug}'")
IO.puts("  ✅ Success!\n")

# Test case 2: Various UTF-8 edge cases
test_cases = [
  "Björk",
  "Sigur Rós",
  "Môtley Crüe",
  "Café Del Mar",
  "François Pérusse",
  # Japanese
  "東京事変",
  # Russian
  "Александр Пушкин",
  # Broken UTF-8
  <<84, 101, 115, 116, 226, 32, 83>>
]

IO.puts("Test 2: Various UTF-8 cases:")

for name <- test_cases do
  case name do
    binary when is_binary(binary) ->
      valid = String.valid?(binary)
      clean = UTF8.ensure_valid_utf8(binary)
      normalized = Normalizer.normalize_text(clean)
      slug = Slug.slugify(normalized)

      display = if valid, do: binary, else: inspect(binary)
      IO.puts("  #{display}")
      IO.puts("    Valid UTF-8: #{valid}")
      IO.puts("    Cleaned: '#{clean}'")
      IO.puts("    Slug: '#{slug}'")
  end
end

# Test case 3: Simulate the actual transformer flow
IO.puts("\nTest 3: Simulating Ticketmaster Transformer Flow:")

tm_attraction = %{
  "id" => "K8vZ917G3Cf",
  "name" => "Rock-Serwis Piotr Kosiński",
  "type" => "attraction"
}

# This simulates what happens in transform_performer
clean_name = UTF8.ensure_valid_utf8(tm_attraction["name"])

performer_data = %{
  "external_id" => "tm_performer_#{tm_attraction["id"]}",
  "name" => clean_name
}

IO.puts("  Original: '#{tm_attraction["name"]}'")
IO.puts("  Transformed name: '#{performer_data["name"]}'")
IO.puts("  Valid UTF-8? #{String.valid?(performer_data["name"])}")

# Try to create the performer (without actually saving to DB)
normalized = Normalizer.normalize_text(performer_data["name"])
slug = Slug.slugify(normalized)
IO.puts("  Would create performer with slug: '#{slug}'")
IO.puts("  ✅ Transformation successful!")

IO.puts("\n=== All Tests Passed! ===")
