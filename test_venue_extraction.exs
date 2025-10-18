alias EventasaurusDiscovery.Sources.Sortiraparis.{Client, Extractors}

# Test URL that failed
url = "https://www.sortiraparis.com/en/what-to-visit-in-paris/exhibit-museum/articles/327359-open-air-exhibition-of-works-by-andrea-roggi-quartier-faubourg-saint-honore"

IO.puts("Testing venue extraction for: #{url}")
IO.puts("")

case Client.fetch_page(url) do
  {:ok, html} ->
    IO.puts("✅ Successfully fetched HTML (#{byte_size(html)} bytes)")
    IO.puts("")

    # Test venue extraction
    case Extractors.VenueExtractor.extract(html) do
      {:ok, venue_data} ->
        IO.puts("✅ Venue extraction succeeded!")
        IO.inspect(venue_data, label: "Venue data")

      {:error, reason} ->
        IO.puts("❌ Venue extraction failed: #{inspect(reason)}")

        # Try extracting venue name specifically
        case Extractors.VenueExtractor.extract_venue_name(html) do
          {:ok, name} ->
            IO.puts("  ℹ️  But venue name was found: #{name}")
          {:error, name_reason} ->
            IO.puts("  ℹ️  Venue name not found: #{inspect(name_reason)}")
        end

        # Try extracting address specifically
        case Extractors.VenueExtractor.extract_address_data(html) do
          {:ok, address} ->
            IO.puts("  ℹ️  But address was found: #{inspect(address)}")
          {:error, addr_reason} ->
            IO.puts("  ℹ️  Address not found: #{inspect(addr_reason)}")
        end
    end

  {:error, reason} ->
    IO.puts("❌ Failed to fetch page: #{inspect(reason)}")
end
