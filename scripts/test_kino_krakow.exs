#!/usr/bin/env elixir

# Quick test script for Kino Krakow scraper
# Run with: mix run scripts/test_kino_krakow.exs

alias EventasaurusDiscovery.Sources.KinoKrakow.{
  Config,
  Extractors.ShowtimeExtractor,
  DateParser
}

IO.puts("\n🎬 Testing Kino Krakow Scraper\n")
IO.puts("=" |> String.duplicate(50))

# Test 1: Fetch showtimes page
IO.puts("\n📥 Fetching showtimes page...")
url = Config.showtimes_url()
headers = [{"User-Agent", Config.user_agent()}]

case HTTPoison.get(url, headers, timeout: Config.timeout()) do
  {:ok, %{status_code: 200, body: html}} ->
    IO.puts("✅ Successfully fetched HTML (#{byte_size(html)} bytes)")

    # Test 2: Extract showtimes
    IO.puts("\n🔍 Extracting showtimes...")
    date = Date.utc_today()
    showtimes = ShowtimeExtractor.extract(html, date)

    IO.puts("✅ Found #{length(showtimes)} showtimes")

    if length(showtimes) > 0 do
      # Show first 3 showtimes
      IO.puts("\n📋 Sample showtimes:\n")

      showtimes
      |> Enum.take(3)
      |> Enum.with_index(1)
      |> Enum.each(fn {showtime, idx} ->
        IO.puts("#{idx}. Movie: #{showtime.movie_title || showtime.movie_slug}")
        IO.puts("   Cinema: #{showtime.cinema_name || showtime.cinema_slug}")
        IO.puts("   Time: #{showtime.datetime}")
        IO.puts("   Ticket URL: #{showtime.ticket_url}\n")
      end)

      # Show unique movies and cinemas
      unique_movies = showtimes |> Enum.map(& &1.movie_slug) |> Enum.uniq() |> length()
      unique_cinemas = showtimes |> Enum.map(& &1.cinema_slug) |> Enum.uniq() |> length()

      IO.puts("\n📊 Summary:")
      IO.puts("   - Total showtimes: #{length(showtimes)}")
      IO.puts("   - Unique movies: #{unique_movies}")
      IO.puts("   - Unique cinemas: #{unique_cinemas}")
    else
      IO.puts("⚠️  No showtimes found - check HTML selectors")
    end

  {:ok, %{status_code: status}} ->
    IO.puts("❌ HTTP #{status}")

  {:error, reason} ->
    IO.puts("❌ Request failed: #{inspect(reason)}")
end

IO.puts("\n" <> ("=" |> String.duplicate(50)))
IO.puts("✨ Test complete\n")
