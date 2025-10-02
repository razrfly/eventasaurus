#!/usr/bin/env elixir

# Debug script to examine actual Kino Krakow movie detail page HTML
# Run with: mix run scripts/debug_kino_movie_page.exs

alias EventasaurusDiscovery.Sources.KinoKrakow.Config

IO.puts("\n🔍 Fetching Kino Krakow Movie Detail Page\n")
IO.puts("=" |> String.duplicate(60))

# Fetch a sample movie page
movie_slug = "interstellar"
url = "https://www.kino.krakow.pl/film/#{movie_slug}.html"
headers = [{"User-Agent", Config.user_agent()}]

IO.puts("\n📥 Fetching: #{url}")

case HTTPoison.get(url, headers, timeout: Config.timeout()) do
  {:ok, %{status_code: 200, body: html}} ->
    IO.puts("✅ Successfully fetched HTML (#{byte_size(html)} bytes)")

    doc = Floki.parse_document!(html)

    # Debug: Show all h1 tags
    IO.puts("\n🔍 All <h1> tags:")
    doc
    |> Floki.find("h1")
    |> Enum.with_index(1)
    |> Enum.each(fn {element, idx} ->
      text = Floki.text(element) |> String.trim()
      IO.puts("  #{idx}. #{inspect(element)}")
      IO.puts("     Text: #{text}\n")
    end)

    # Debug: Show all elements with class containing "title"
    IO.puts("\n🔍 Elements with class containing 'title':")
    doc
    |> Floki.find("[class*='title']")
    |> Enum.take(10)
    |> Enum.with_index(1)
    |> Enum.each(fn {element, idx} ->
      text = Floki.text(element) |> String.trim()
      IO.puts("  #{idx}. #{inspect(element)}")
      IO.puts("     Text: #{text}\n")
    end)

    # Debug: Show all elements with itemprop
    IO.puts("\n🔍 Elements with [itemprop] attribute:")
    doc
    |> Floki.find("[itemprop]")
    |> Enum.take(15)
    |> Enum.with_index(1)
    |> Enum.each(fn {element, idx} ->
      text = Floki.text(element) |> String.trim()
      IO.puts("  #{idx}. #{inspect(element)}")
      IO.puts("     Text: #{text}\n")
    end)

    # Debug: Show all meta tags
    IO.puts("\n🔍 Meta tags:")
    doc
    |> Floki.find("meta")
    |> Enum.take(20)
    |> Enum.each(fn element ->
      IO.puts("  #{inspect(element)}")
    end)

    # Save HTML for manual inspection
    File.write!("/tmp/kino_krakow_movie_debug.html", html)
    IO.puts("\n💾 Saved full HTML to /tmp/kino_krakow_movie_debug.html for inspection")

  {:ok, %{status_code: status}} ->
    IO.puts("❌ HTTP #{status}")

  {:error, reason} ->
    IO.puts("❌ Request failed: #{inspect(reason)}")
end

IO.puts("\n" <> ("=" |> String.duplicate(60)))
IO.puts("✨ Debug complete\n")
