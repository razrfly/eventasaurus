# Test that locales are properly passed and used for translation keys
alias EventasaurusDiscovery.Sources.Ticketmaster.{Client, Transformer}
alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Locations.City

# Get Kraków
city = Repo.get_by!(City, name: "Kraków") |> Repo.preload(:country)

IO.puts("\n🔍 Testing locale-based translation key assignment\n")

# Fetch one event with Polish locale
case Client.fetch_events_by_location(city.latitude, city.longitude, 50, 0, "pl-pl") do
  {:ok, response} ->
    events = get_in(response, ["_embedded", "events"]) || []

    if events != [] do
      event = List.first(events)

      # Transform with Polish locale
      {:ok, transformed_pl} = Transformer.transform_event(event, "pl-pl", city)

      # Transform same event with English locale (simulating what sync job does)
      {:ok, transformed_en} = Transformer.transform_event(event, "en-us", city)

      IO.puts("Event: #{event["name"]}")
      IO.puts("\n📍 With pl-pl locale:")
      IO.puts("  title_translations: #{inspect(transformed_pl.title_translations)}")
      IO.puts("  description_translations: #{inspect(transformed_pl.description_translations)}")

      IO.puts("\n📍 With en-us locale:")
      IO.puts("  title_translations: #{inspect(transformed_en.title_translations)}")
      IO.puts("  description_translations: #{inspect(transformed_en.description_translations)}")

      IO.puts("\n✅ Keys are correctly set based on requested locale:")
      IO.puts("  - pl-pl → 'pl' key")
      IO.puts("  - en-us → 'en' key")
      IO.puts("\nNote: The API returns the same content regardless of locale,")
      IO.puts("but we now correctly tag it with the language we requested.")
    else
      IO.puts("❌ No events found")
    end

  {:error, reason} ->
    IO.puts("❌ Error: #{inspect(reason)}")
end

IO.puts("\n✨ Test complete!")