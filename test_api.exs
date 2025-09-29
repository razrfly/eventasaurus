alias EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.Client

{:ok, response} = Client.fetch_next_events_page(50.0647, 19.9450, 1)

events = response["events"] || []
first_event = Enum.at(events, 0)

if first_event do
  IO.puts("First event keys:")
  IO.inspect(Map.keys(first_event))

  IO.puts("\nImage-related fields:")
  IO.puts("artistImageSrc: #{inspect(first_event["artistImageSrc"])}")
  IO.puts("fallbackImageUrl: #{inspect(first_event["fallbackImageUrl"])}")
  IO.puts("artistImageUrl: #{inspect(first_event["artistImageUrl"])}")
  IO.puts("imageUrl: #{inspect(first_event["imageUrl"])}")

  IO.puts("\nFull event:")
  IO.inspect(first_event, limit: :infinity)
else
  IO.puts("No events found")
end