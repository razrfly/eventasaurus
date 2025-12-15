# Test time extraction fix on Rosso venue
alias EventasaurusDiscovery.Sources.GeeksWhoDrink.Extractors.VenueDetailsExtractor

# Test on Rosso Pomodoro venue (the one showing wrong time)
venue_url = "https://www.geekswhodrink.com/venues/2936708819/"

IO.puts("Testing time extraction on: #{venue_url}")
IO.puts("Expected time: 18:00 (6:00 PM)")
IO.puts("")

case VenueDetailsExtractor.extract_additional_details(venue_url) do
  {:ok, details} ->
    IO.puts("✅ Successfully extracted details")
    IO.puts("Extracted start_time: #{inspect(details.start_time)}")
    IO.puts("")

    if details.start_time == "18:00" do
      IO.puts("🎉 SUCCESS! Time extraction is now correct!")
    else
      IO.puts("❌ FAILURE! Still extracting wrong time")
      IO.puts("Expected: 18:00")
      IO.puts("Got: #{details.start_time}")
    end

    IO.puts("\nOther extracted details:")
    IO.puts("- Website: #{details.website}")
    IO.puts("- Phone: #{details.phone}")
    IO.puts("- Fee: #{details.fee_text}")

    if details.performer do
      IO.puts("- Performer: #{details.performer.name}")
    end

  {:error, reason} ->
    IO.puts("❌ Failed to extract details: #{inspect(reason)}")
end
