# Test time extraction on multiple venues
alias EventasaurusDiscovery.Sources.GeeksWhoDrink.Extractors.VenueDetailsExtractor

venues = [
  {"1152019366", "Pandora's Box"},
  {"1161188111", "Wild Corgi Pub"},
  {"1784777529", "LUKI Brewery"},
  {"1793242863", "30/70 Sports Bar"}
]

IO.puts("Testing time extraction on multiple venues:\n")

Enum.each(venues, fn {venue_id, venue_name} ->
  url = "https://www.geekswhodrink.com/venues/#{venue_id}/"

  IO.puts("Testing: #{venue_name} (#{venue_id})")
  IO.puts("URL: #{url}")

  case VenueDetailsExtractor.extract_additional_details(url) do
    {:ok, details} ->
      IO.puts("✓ Extracted time: #{inspect(details.start_time)}")

    {:error, reason} ->
      IO.puts("✗ Failed: #{inspect(reason)}")
  end

  IO.puts("")
end)
