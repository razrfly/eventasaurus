# Test script for movie creation from TMDB
# Run with: mix run scripts/test_movie_creation.exs

alias EventasaurusDiscovery.Sources.KinoKrakow.TmdbMatcher
alias EventasaurusWeb.Services.TmdbService

# Test TMDB ID 157336 (Interstellar)
tmdb_id = 157336

IO.puts("\n🎬 Testing Movie Creation from TMDB")
IO.puts("TMDB ID: #{tmdb_id}")

# Step 1: Fetch movie details
IO.puts("\n1️⃣ Fetching movie details from TMDB...")
case TmdbService.get_movie_details(tmdb_id) do
  {:ok, details} ->
    IO.puts("✅ Got movie details:")
    IO.puts("   Title: #{details[:title]}")
    IO.puts("   Original Title: #{details[:title]}")
    IO.puts("   Release Date: #{details[:release_date]}")
    IO.puts("   Runtime: #{details[:runtime]} minutes")
    IO.puts("   Overview: #{String.slice(details[:overview] || "", 0..100)}...")

    # Step 2: Try to create/find movie
    IO.puts("\n2️⃣ Creating/finding movie in database...")
    case TmdbMatcher.find_or_create_movie(tmdb_id) do
      {:ok, movie} ->
        IO.puts("✅ SUCCESS! Movie record created/found:")
        IO.puts("   ID: #{movie.id}")
        IO.puts("   Title: #{movie.title}")
        IO.puts("   Original Title: #{movie.original_title}")
        IO.puts("   TMDB ID: #{movie.tmdb_id}")
        IO.puts("   Runtime: #{movie.runtime}")
        IO.puts("   Release Date: #{movie.release_date}")
        IO.puts("\n✨ Movie creation test PASSED!")

      {:error, changeset} ->
        IO.puts("❌ FAILED to create movie")
        IO.puts("Changeset errors:")
        IO.inspect(changeset.errors, label: "Errors")
        IO.puts("\nChangeset changes:")
        IO.inspect(changeset.changes, label: "Changes")
    end

  {:error, reason} ->
    IO.puts("❌ Failed to fetch TMDB details: #{inspect(reason)}")
end
