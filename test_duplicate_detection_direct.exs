# Direct Test of DuplicateDetection Logic
# This script tests if DuplicateDetection can find the actual duplicates that were created

alias EventasaurusApp.Repo
alias EventasaurusApp.Venues.{Venue, DuplicateDetection}
alias EventasaurusDiscovery.Locations.City

IO.puts("\n=== DIRECT TEST OF DUPLICATE DETECTION LOGIC ===\n")

# Get London city ID (most UK venues are in London)
london = Repo.get_by(City, name: "London") || Repo.get_by(City, slug: "london")

if is_nil(london) do
  IO.puts("❌ Could not find London city. Checking all cities...")
  cities = Repo.all(City)
  IO.puts("Available cities: #{inspect(Enum.map(cities, & &1.name))}")
  IO.puts("\nPlease update the script with the correct city")
  System.halt(1)
end

IO.puts("✓ Using city: #{london.name} (ID: #{london.id})\n")

# Test Case 1: The Crabtree (86m apart, concurrent insertion)
IO.puts("TEST CASE 1: The Crabtree")
IO.puts("Venue 334: (51.48286, -0.22336)")
IO.puts("Venue 335: (51.482083, -0.22336)")
IO.puts("Expected: Should find each other (86m apart)\n")

IO.puts("Testing: Can venue 335 coordinates find venue 334?")

result1 = DuplicateDetection.find_duplicate(%{
  latitude: 51.482083,
  longitude: -0.22336,
  city_id: london.id,
  name: "The Crabtree"
})

if result1 do
  IO.puts("✅ FOUND duplicate: ID #{result1.id}, distance #{Float.round(result1.distance, 1)}m")
else
  IO.puts("❌ NO DUPLICATE FOUND - Detection failed!")
end

IO.puts("\nTesting: Can venue 334 coordinates find venue 335?")

result2 = DuplicateDetection.find_duplicate(%{
  latitude: 51.48286,
  longitude: -0.22336,
  city_id: london.id,
  name: "The Crabtree"
})

if result2 do
  IO.puts("✅ FOUND duplicate: ID #{result2.id}, distance #{Float.round(result2.distance, 1)}m")
else
  IO.puts("❌ NO DUPLICATE FOUND - Detection failed!")
end

# Test Case 2: The Edinboro Castle (1m apart, sequential insertion)
IO.puts("\n\nTEST CASE 2: The Edinboro Castle")
IO.puts("Venue 61: (51.5361268, -0.1448409), name='The Edinboro Castle'")
IO.puts("Venue 287: (51.5361199, -0.1448555), name='Edinboro Castle, Camden'")
IO.puts("Expected: Should find each other (1m apart, 64% name similarity)\n")

IO.puts("Testing: Can venue 287 find venue 61?")

result3 = DuplicateDetection.find_duplicate(%{
  latitude: 51.5361199,
  longitude: -0.1448555,
  city_id: london.id,
  name: "Edinboro Castle, Camden"
})

if result3 do
  similarity = DuplicateDetection.calculate_name_similarity("The Edinboro Castle", "Edinboro Castle, Camden")
  IO.puts("✅ FOUND duplicate: ID #{result3.id}, distance #{Float.round(result3.distance, 1)}m, similarity #{Float.round(similarity * 100, 1)}%")
else
  IO.puts("❌ NO DUPLICATE FOUND - Detection failed!")
  IO.puts("\nThis is critical - venue 61 was inserted 63 seconds BEFORE venue 287.")
  IO.puts("If detection fails here, it means find_existing_venue has a bug!")
end

IO.puts("\nTesting: Can venue 61 find venue 287?")

result4 = DuplicateDetection.find_duplicate(%{
  latitude: 51.5361268,
  longitude: -0.1448409,
  city_id: london.id,
  name: "The Edinboro Castle"
})

if result4 do
  similarity = DuplicateDetection.calculate_name_similarity("Edinboro Castle, Camden", "The Edinboro Castle")
  IO.puts("✅ FOUND duplicate: ID #{result4.id}, distance #{Float.round(result4.distance, 1)}m, similarity #{Float.round(similarity * 100, 1)}%")
else
  IO.puts("❌ NO DUPLICATE FOUND - Detection failed!")
end

# Summary
IO.puts("\n\n=== TEST SUMMARY ===")
IO.puts("Test 1 (Crabtree, 335→334): #{if result1, do: "✅ PASS", else: "❌ FAIL"}")
IO.puts("Test 2 (Crabtree, 334→335): #{if result2, do: "✅ PASS", else: "❌ FAIL"}")
IO.puts("Test 3 (Edinboro, 287→61): #{if result3, do: "✅ PASS", else: "❌ FAIL - CRITICAL!"}")
IO.puts("Test 4 (Edinboro, 61→287): #{if result4, do: "✅ PASS", else: "❌ FAIL"}")

IO.puts("\n=== DIAGNOSIS ===")

cond do
  is_nil(result1) and is_nil(result2) and is_nil(result3) and is_nil(result4) ->
    IO.puts("❌ ALL TESTS FAILED")
    IO.puts("Duplicate detection logic is completely broken!")
    IO.puts("Likely issues:")
    IO.puts("  1. PostGIS queries not working")
    IO.puts("  2. City ID mismatch")
    IO.puts("  3. Distance threshold too strict")

  is_nil(result3) ->
    IO.puts("❌ CRITICAL: Test 3 failed (sequential duplicate)")
    IO.puts("This proves duplicate detection has a bug.")
    IO.puts("Venue 61 existed for 63 seconds before venue 287 was created.")
    IO.puts("find_existing_venue should have found it but didn't!")

  result1 and result2 and result3 and result4 ->
    IO.puts("✅ ALL TESTS PASSED")
    IO.puts("Duplicate detection logic works correctly!")
    IO.puts("This means the problem is elsewhere:")
    IO.puts("  1. find_existing_venue not being called")
    IO.puts("  2. Different city IDs being used")
    IO.puts("  3. Advisory lock code not executing")

  true ->
    IO.puts("⚠️  MIXED RESULTS")
    IO.puts("Some tests passed, some failed.")
    IO.puts("Review individual test results above.")
end

IO.puts("")
