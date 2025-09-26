# Test Ticketmaster API directly to understand the data structure
alias EventasaurusDiscovery.Sources.Ticketmaster.{Client, Config}
alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Locations.City

require Logger

# Get Kraków for testing
city = Repo.get_by!(City, name: "Kraków") |> Repo.preload(:country)
IO.puts("\n🔍 Testing Ticketmaster API for #{city.name}, #{city.country.name}\n")

# Test with different locales
locales = ["en-us", "pl-pl"]
radius = 50

for locale <- locales do
  IO.puts("=" |> String.duplicate(80))
  IO.puts("Testing with locale: #{locale}")
  IO.puts("=" |> String.duplicate(80))

  case Client.fetch_events_by_location(city.latitude, city.longitude, radius, 0, locale) do
    {:ok, response} ->
      events = get_in(response, ["_embedded", "events"]) || []

      if length(events) > 0 do
        # Take first event for detailed analysis
        event = List.first(events)

        IO.puts("\n📍 Event ID: #{event["id"]}")
        IO.puts("📍 Event Name: #{event["name"]}")

        # Check for description fields
        IO.puts("\n📝 Description fields:")
        description_keys = ["description", "info", "pleaseNote", "additionalInfo", "promoter", "seatmap"]

        for key <- description_keys do
          value = event[key]
          if value do
            IO.puts("  ✅ #{key}: #{inspect(String.slice(to_string(value), 0, 100))}...")
          else
            IO.puts("  ❌ #{key}: not found")
          end
        end

        # Check embedded attractions for descriptions
        attractions = get_in(event, ["_embedded", "attractions"]) || []
        if length(attractions) > 0 do
          IO.puts("\n🎭 Attractions found: #{length(attractions)}")
          attraction = List.first(attractions)

          # Check attraction for description/bio
          if attraction["description"] do
            IO.puts("  ✅ Attraction description: #{String.slice(attraction["description"], 0, 100)}...")
          end

          # Check classifications for genre info
          classifications = attraction["classifications"] || []
          if length(classifications) > 0 do
            IO.puts("  ℹ️ Classifications: #{inspect(classifications)}")
          end
        end

        # Check all top-level keys
        IO.puts("\n🔑 All top-level keys in event:")
        event
        |> Map.keys()
        |> Enum.sort()
        |> Enum.each(fn key ->
          value_type =
            case event[key] do
              nil -> "nil"
              v when is_binary(v) -> "string(#{String.length(v)} chars)"
              v when is_map(v) -> "map(#{map_size(v)} keys)"
              v when is_list(v) -> "list(#{length(v)} items)"
              v -> inspect(v) |> String.slice(0, 20)
            end
          IO.puts("  - #{key}: #{value_type}")
        end)

        # Save full event for inspection
        File.write!("ticketmaster_event_#{locale}.json", Jason.encode!(event, pretty: true))
        IO.puts("\n💾 Full event saved to ticketmaster_event_#{locale}.json")
      else
        IO.puts("❌ No events found")
      end

    {:error, reason} ->
      IO.puts("❌ API Error: #{inspect(reason)}")
  end

  IO.puts("")
end

IO.puts("\n✨ API test complete! Check the JSON files for full event structure.")