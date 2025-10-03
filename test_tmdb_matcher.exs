# Test script for TMDB matcher improvements
# Run with: mix run test_tmdb_matcher.exs

alias EventasaurusDiscovery.Sources.KinoKrakow.TmdbMatcher

IO.puts("\n=== Testing TMDB Matcher Improvements ===\n")

# Test case 1: Avatar - should now match with 70% threshold
IO.puts("Test 1: Avatar: Istota wody / Avatar 2")
test1 = %{
  original_title: "Avatar 2",
  polish_title: "Avatar: Istota wody",
  year: 2022,
  director: "James Cameron",
  runtime: 192,
  country: "USA"
}

case TmdbMatcher.match_movie(test1) do
  {:ok, tmdb_id, confidence} ->
    IO.puts("✅ MATCHED! TMDB ID: #{tmdb_id}, Confidence: #{Float.round(confidence * 100, 1)}%")
  {:needs_review, _, _} ->
    IO.puts("⚠️  Needs review (60-79% confidence)")
  {:error, reason} ->
    IO.puts("❌ Failed: #{inspect(reason)}")
end

IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

# Test case 2: Bluey - Polish normalized title
IO.puts("Test 2: Bluey w kinie: Kolekcja Pobawmy się w szefa kuchni")
test2 = %{
  original_title: "Bluey w kinie: Kolekcja Pobawmy się w szefa kuchni",
  polish_title: "Bluey w kinie: Kolekcja Pobawmy się w szefa kuchni",
  year: 2024,
  director: nil,
  runtime: 90,
  country: "Australia"
}

case TmdbMatcher.match_movie(test2) do
  {:ok, tmdb_id, confidence} ->
    IO.puts("✅ MATCHED! TMDB ID: #{tmdb_id}, Confidence: #{Float.round(confidence * 100, 1)}%")
  {:needs_review, _, _} ->
    IO.puts("⚠️  Needs review (50-69% confidence)")
  {:error, reason} ->
    IO.puts("❌ Failed: #{inspect(reason)}")
end

IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

# Test case 3: Exit 8 - Japanese title
IO.puts("Test 3: Exit 8 / 8-ban deguchi")
test3 = %{
  original_title: "8-ban deguchi",
  polish_title: "Exit 8",
  year: 2023,
  director: nil,
  runtime: nil,
  country: "Japan"
}

case TmdbMatcher.match_movie(test3) do
  {:ok, tmdb_id, confidence} ->
    IO.puts("✅ MATCHED! TMDB ID: #{tmdb_id}, Confidence: #{Float.round(confidence * 100, 1)}%")
  {:needs_review, _, _} ->
    IO.puts("⚠️  Needs review (50-69% confidence)")
  {:error, reason} ->
    IO.puts("❌ Failed: #{inspect(reason)}")
end

IO.puts("\n" <> String.duplicate("-", 60) <> "\n")

# Test case 4: Niesamowite przygody skarpetek - Polish normalization
IO.puts("Test 4: Niesamowite przygody skarpetek 2. Skarpetki górą!")
test4 = %{
  original_title: "Niesamowite przygody skarpetek 2. Skarpetki górą!",
  polish_title: "Niesamowite przygody skarpetek 2. Skarpetki górą!",
  year: 2024,
  director: nil,
  runtime: nil,
  country: "Poland"
}

case TmdbMatcher.match_movie(test4) do
  {:ok, tmdb_id, confidence} ->
    IO.puts("✅ MATCHED! TMDB ID: #{tmdb_id}, Confidence: #{Float.round(confidence * 100, 1)}%")
  {:needs_review, _, _} ->
    IO.puts("⚠️  Needs review (50-69% confidence)")
  {:error, reason} ->
    IO.puts("❌ Failed: #{inspect(reason)}")
end

IO.puts("\n=== Test Complete ===\n")
