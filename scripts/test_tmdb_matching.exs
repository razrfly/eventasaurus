#!/usr/bin/env elixir

# Test TMDB matching with improved algorithm
# Run with: mix run scripts/test_tmdb_matching.exs

alias EventasaurusDiscovery.Sources.KinoKrakow.{
  Config,
  Extractors.MovieExtractor,
  TmdbMatcher
}

IO.puts("\n🎯 Testing TMDB Matching Improvements\n")
IO.puts("=" |> String.duplicate(60))

# Test with Interstellar (should have high confidence match)
movie_slug = "interstellar"
url = "https://www.kino.krakow.pl/film/#{movie_slug}.html"
headers = [{"User-Agent", Config.user_agent()}]

IO.puts("\n📥 Fetching movie: #{movie_slug}")

case HTTPoison.get(url, headers, timeout: Config.timeout()) do
  {:ok, %{status_code: 200, body: html}} ->
    IO.puts("✅ Fetched HTML")

    # Extract movie metadata
    movie_data = MovieExtractor.extract(html)

    IO.puts("\n📋 Extracted Metadata:")
    IO.puts("   Original Title: #{movie_data.original_title}")
    IO.puts("   Polish Title: #{movie_data.polish_title}")
    IO.puts("   Year: #{movie_data.year}")
    IO.puts("   Director: #{movie_data.director}")

    # Attempt TMDB matching
    IO.puts("\n🔍 Attempting TMDB match...")

    case TmdbMatcher.match_movie(movie_data) do
      {:ok, tmdb_id, confidence, provider} ->
        IO.puts("✅ SUCCESS! Matched with high confidence")
        IO.puts("   TMDB ID: #{tmdb_id}")
        IO.puts("   Confidence: #{Float.round(confidence * 100, 1)}%")
        IO.puts("   Provider: #{provider}")

        # Fetch movie details to verify
        case TmdbMatcher.find_or_create_movie(tmdb_id) do
          {:ok, movie} ->
            IO.puts("\n📽️  Matched Movie:")
            IO.puts("   Title: #{movie.title}")
            IO.puts("   Original Title: #{movie.original_title}")
            IO.puts("   Runtime: #{movie.runtime} min")

          {:error, reason} ->
            IO.puts("   ⚠️  Could not fetch movie details: #{inspect(reason)}")
        end

      {:needs_review, _kino_movie, candidates} ->
        IO.puts("⚠️  NEEDS REVIEW - Low confidence match")
        IO.puts("   Found #{length(candidates)} candidates")

        if length(candidates) > 0 do
          IO.puts("\n   Top candidates:")
          candidates
          |> Enum.take(3)
          |> Enum.each(fn candidate ->
            IO.puts("      - #{candidate[:title]} (#{candidate[:original_title]}) - #{candidate[:release_date]}")
          end)
        end

      {:error, :missing_title} ->
        IO.puts("❌ FAILED - Missing title in extracted data")

      {:error, :no_results} ->
        IO.puts("❌ FAILED - No TMDB results found")

      {:error, :no_candidates} ->
        IO.puts("❌ FAILED - No matching candidates after filtering")

      {:error, reason} ->
        IO.puts("❌ FAILED - #{inspect(reason)}")
    end

  {:ok, %{status_code: status}} ->
    IO.puts("❌ HTTP #{status}")

  {:error, reason} ->
    IO.puts("❌ Request failed: #{inspect(reason)}")
end

IO.puts("\n" <> ("=" |> String.duplicate(60)))
IO.puts("✨ Test complete\n")
