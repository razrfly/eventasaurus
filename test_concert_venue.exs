alias EventasaurusDiscovery.Sources.Sortiraparis.{Client, Extractors}

# Test a concert URL (should have venue)
concert_url = "https://www.sortiraparis.com/en/what-to-see-in-paris/concerts-music-festival/articles/326487-the-hives-in-concert-at-zenith-de-paris-in-november-2025"

# Test the exhibition URL (no venue)
exhibition_url = "https://www.sortiraparis.com/en/what-to-visit-in-paris/exhibit-museum/articles/327359-open-air-exhibition-of-works-by-andrea-roggi-quartier-faubourg-saint-honore"

test_url = fn url, label ->
  IO.puts("\n" <> String.duplicate("=", 80))
  IO.puts("Testing: #{label}")
  IO.puts(String.duplicate("=", 80))
  IO.puts("URL: #{url}")
  IO.puts("")

  case Client.fetch_page(url) do
    {:ok, html} ->
      IO.puts("✅ Fetched HTML (#{byte_size(html)} bytes)")

      case Extractors.VenueExtractor.extract(html) do
        {:ok, venue_data} ->
          IO.puts("✅ Venue extraction SUCCEEDED!")
          IO.inspect(venue_data, label: "Venue")

        {:error, reason} ->
          IO.puts("❌ Venue extraction FAILED: #{inspect(reason)}")
      end

    {:error, reason} ->
      IO.puts("❌ Failed to fetch: #{inspect(reason)}")
  end
end

test_url.(concert_url, "CONCERT (The Hives at Zenith)")
test_url.(exhibition_url, "EXHIBITION (Outdoor district event)")
