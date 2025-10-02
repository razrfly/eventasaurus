#!/usr/bin/env elixir

# Test script for MovieExtractor
# Run with: mix run scripts/test_movie_extractor.exs

alias EventasaurusDiscovery.Sources.KinoKrakow.{Config, Extractors.MovieExtractor}

IO.puts("\n🎬 Testing Kino Krakow MovieExtractor\n")
IO.puts("=" |> String.duplicate(60))

# Fetch Interstellar movie page
movie_slug = "interstellar"
url = "https://www.kino.krakow.pl/film/#{movie_slug}.html"
headers = [{"User-Agent", Config.user_agent()}]

IO.puts("\n📥 Fetching: #{url}")

case HTTPoison.get(url, headers, timeout: Config.timeout()) do
  {:ok, %{status_code: 200, body: html}} ->
    IO.puts("✅ Successfully fetched HTML (#{byte_size(html)} bytes)")

    # Extract movie metadata
    IO.puts("\n🔍 Extracting movie metadata...")
    metadata = MovieExtractor.extract(html)

    IO.puts("\n📋 Extracted Metadata:\n")
    IO.puts("   Original Title: #{metadata.original_title}")
    IO.puts("   Polish Title: #{metadata.polish_title}")
    IO.puts("   Director: #{metadata.director}")
    IO.puts("   Year: #{metadata.year}")
    IO.puts("   Country: #{metadata.country}")
    IO.puts("   Runtime: #{metadata.runtime} minutes")
    IO.puts("   Genre: #{metadata.genre}")

    if metadata.cast do
      IO.puts("   Cast: #{Enum.join(metadata.cast, ", ")}")
    else
      IO.puts("   Cast: (none)")
    end

    # Validation
    IO.puts("\n✅ Validation:")

    checks = [
      {"Original title present", metadata.original_title != nil},
      {"Polish title present", metadata.polish_title != nil},
      {"Director present", metadata.director != nil},
      {"Year present", metadata.year != nil},
      {"Country present", metadata.country != nil},
      {"Runtime present", metadata.runtime != nil},
      {"Genre present", metadata.genre != nil},
      {"Cast present", metadata.cast != nil && length(metadata.cast) > 0}
    ]

    Enum.each(checks, fn {check, result} ->
      status = if result, do: "✅", else: "❌"
      IO.puts("   #{status} #{check}")
    end)

    passing = Enum.count(checks, fn {_, result} -> result end)
    total = length(checks)
    IO.puts("\n   Score: #{passing}/#{total} checks passed")

  {:ok, %{status_code: status}} ->
    IO.puts("❌ HTTP #{status}")

  {:error, reason} ->
    IO.puts("❌ Request failed: #{inspect(reason)}")
end

IO.puts("\n" <> ("=" |> String.duplicate(60)))
IO.puts("✨ Test complete\n")
