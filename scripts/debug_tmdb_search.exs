#!/usr/bin/env elixir

# Debug TMDB search results
# Run with: mix run scripts/debug_tmdb_search.exs

alias EventasaurusWeb.Services.TmdbService

IO.puts("\n🔍 Debugging TMDB Search Results\n")
IO.puts("=" |> String.duplicate(60))

# Search for "Interstellar"
query = "Interstellar"
IO.puts("\n📥 Searching TMDB for: #{query}")

case TmdbService.search_multi(query, 1) do
  {:ok, results} ->
    IO.puts("✅ Found #{length(results)} results\n")

    results
    |> Enum.with_index(1)
    |> Enum.each(fn {result, idx} ->
      IO.puts("#{idx}. Type: #{result[:type]}")
      IO.puts("   Title: #{result[:title]}")
      IO.puts("   Original Title: #{result[:original_title]}")
      IO.puts("   Original Language: #{result[:original_language]}")
      IO.puts("   Release Date: #{result[:release_date]}")
      IO.puts("   Vote Average: #{result[:vote_average]}")
      IO.puts("   Popularity: #{result[:popularity]}")
      IO.puts("")
    end)

    # Test year filtering
    movies = Enum.filter(results, &(&1[:type] == :movie))
    IO.puts("📊 Filtered to #{length(movies)} movies")

    if length(movies) > 0 do
      movie = List.first(movies)
      IO.puts("\n🎬 First movie result:")
      IO.puts("   Map keys: #{inspect(Map.keys(movie))}")
      IO.puts("   Full map: #{inspect(movie)}")
    end

  {:error, reason} ->
    IO.puts("❌ Search failed: #{inspect(reason)}")
end

IO.puts("\n" <> ("=" |> String.duplicate(60)))
IO.puts("✨ Debug complete\n")
