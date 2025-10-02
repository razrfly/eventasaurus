#!/usr/bin/env elixir

# Simple integration test for Kino Krakow scraper
# Run with: mix run scripts/test_kino_simple.exs

alias EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob

IO.puts("\n🎬 Kino Krakow Simple Integration Test\n")
IO.puts("=" |> String.duplicate(60))

# Test just fetching events with a limit of 1
IO.puts("\n1️⃣  Testing event fetch (limit: 1)...")

case SyncJob.fetch_events("Kraków", 1, %{}) do
  {:ok, events} ->
    IO.puts("✅ Successfully fetched #{length(events)} event(s)")

    if length(events) > 0 do
      event = List.first(events)
      IO.puts("\n📋 Sample Event:")
      IO.puts("   Movie: #{event.movie_title}")
      IO.puts("   Cinema: #{event.cinema_data.name}")
      IO.puts("   Time: #{event.datetime}")
      IO.puts("   Location: #{event.cinema_data.latitude}, #{event.cinema_data.longitude}")

      if event.movie_data do
        IO.puts("\n   Movie Metadata:")
        IO.puts("      Director: #{event.movie_data.director}")
        IO.puts("      Year: #{event.movie_data.year}")
        IO.puts("      Runtime: #{event.movie_data.runtime} min")
        IO.puts("      Genre: #{event.movie_data.genre}")
      end

      if event.tmdb_id do
        IO.puts("\n   TMDB Match:")
        IO.puts("      ID: #{event.tmdb_id}")
        IO.puts("      Confidence: #{event.tmdb_confidence}")
      else
        IO.puts("\n   ⚠️  No TMDB match (expected for some films)")
      end
    end

  {:error, reason} ->
    IO.puts("❌ Fetch failed: #{inspect(reason)}")
end

IO.puts("\n" <> ("=" |> String.duplicate(60)))
IO.puts("✨ Test complete\n")
