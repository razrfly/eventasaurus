# Simple test to compare Ticketmaster API responses for different locales
alias EventasaurusDiscovery.Sources.Ticketmaster.Client
alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Locations.City

# Get Kraków
city = Repo.get_by!(City, name: "Kraków") |> Repo.preload(:country)

IO.puts("\n🔍 Comparing Ticketmaster API responses for different locales\n")

# Store results for comparison
results = %{}

for locale <- ["en-us", "pl-pl"] do
  IO.puts("\n" <> String.duplicate("=", 60))
  IO.puts("Fetching with locale: #{locale}")
  IO.puts(String.duplicate("=", 60))

  case Client.fetch_events_by_location(city.latitude, city.longitude, 50, 0, locale) do
    {:ok, response} ->
      events = get_in(response, ["_embedded", "events"]) || []

      if events != [] do
        # Take first 3 events for comparison
        sample_events = Enum.take(events, 3)

        locale_results = for event <- sample_events do
          # Look for description in various places
          description =
            event["description"] ||
            event["info"] ||
            event["pleaseNote"] ||
            event["additionalInfo"] ||
            get_in(event, ["_embedded", "attractions", Access.at(0), "description"])

          # Check if there's any promotional text
          promoter_info = get_in(event, ["promoter", "description"])

          %{
            id: event["id"],
            name: event["name"],
            url: event["url"],
            has_description: description != nil,
            description_preview: if(description, do: String.slice(to_string(description), 0, 100), else: nil),
            promoter_info: promoter_info,
            locale: event["locale"],
            all_keys: Map.keys(event) |> Enum.sort()
          }
        end

        results = Map.put(results, locale, locale_results)

        # Print summary for this locale
        for event_data <- locale_results do
          IO.puts("\n📍 Event: #{event_data.name}")
          IO.puts("   ID: #{event_data.id}")
          IO.puts("   Has description: #{event_data.has_description}")
          if event_data.description_preview do
            IO.puts("   Description: #{event_data.description_preview}...")
          end
        end
      else
        IO.puts("❌ No events found")
      end

    {:error, reason} ->
      IO.puts("❌ Error: #{inspect(reason)}")
  end
end

# Compare results
IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("COMPARISON RESULTS")
IO.puts(String.duplicate("=", 60))

if results["en-us"] && results["pl-pl"] do
  en_events = results["en-us"]
  pl_events = results["pl-pl"]

  # Match events by ID and compare
  for en_event <- en_events do
    pl_event = Enum.find(pl_events, fn pe -> pe.id == en_event.id end)

    if pl_event do
      IO.puts("\n🎫 Event ID: #{en_event.id}")
      IO.puts("  English name: #{en_event.name}")
      IO.puts("  Polish name: #{pl_event.name}")
      IO.puts("  Names match: #{en_event.name == pl_event.name}")
      IO.puts("  EN has description: #{en_event.has_description}")
      IO.puts("  PL has description: #{pl_event.has_description}")

      if en_event.name == pl_event.name do
        IO.puts("  ⚠️  ISSUE: Same name in both locales - likely not translated!")
      end
    end
  end

  # Save one full event from each locale for inspection
  if length(en_events) > 0 && length(pl_events) > 0 do
    # Find the first event ID
    first_id = List.first(en_events).id

    # Fetch that specific event with both locales to get full data
    for locale <- ["en-us", "pl-pl"] do
      case Client.fetch_events_by_location(city.latitude, city.longitude, 50, 0, locale) do
        {:ok, response} ->
          events = get_in(response, ["_embedded", "events"]) || []
          event = Enum.find(events, fn e -> e["id"] == first_id end)
          if event do
            filename = "ticketmaster_event_#{locale}_full.json"
            File.write!(filename, Jason.encode!(event, pretty: true))
            IO.puts("\n💾 Full event data saved to #{filename}")
          end
        _ -> nil
      end
    end
  end
end

IO.puts("\n✅ Test complete!")