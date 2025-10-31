# Test City-Agnostic Duplicate Detection
# Verify that venues in different cities can now be detected as duplicates

alias EventasaurusApp.Repo
alias EventasaurusApp.Venues.DuplicateDetection

IO.puts("\n=== CITY-AGNOSTIC DUPLICATE DETECTION TEST ===\n")

# Test: Can venue 280 (London, city 1) find venue 54 (Camden Town, city 15)?
# These are 13m apart with 64% name similarity

IO.puts("Test: Can 'Edinboro Castle, Camden' (London, city 1) find 'The Edinboro Castle' (Camden Town, city 15)?")
IO.puts("Expected: YES (because we removed city_id filter)\n")

result = DuplicateDetection.find_duplicate(%{
  latitude: 51.53606,
  longitude: -0.14499,
  city_id: 1,  # London
  name: "Edinboro Castle, Camden"
})

if result do
  similarity = DuplicateDetection.calculate_name_similarity("The Edinboro Castle", "Edinboro Castle, Camden")
  IO.puts("✅ SUCCESS - Found venue ID #{result.id}")
  IO.puts("   Name: '#{result.name}'")
  IO.puts("   Distance: #{Float.round(result.distance, 1)}m")
  IO.puts("   Name similarity: #{Float.round(similarity * 100, 1)}%")
  IO.puts("\n🎉 City-agnostic duplicate detection is WORKING!")
  IO.puts("   Venues in different cities (London vs Camden Town) are now detected as duplicates")
else
  IO.puts("❌ FAILED - No duplicate found")
  IO.puts("   This suggests the fix didn't work or venue 54 doesn't exist")
end

IO.puts("\n=== TEST COMPLETE ===\n")
