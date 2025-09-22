# Test script to verify Karnet fix
# Run with: mix run test_karnet_fix.exs

require Logger

# Get the Karnet source
source = EventasaurusApp.Repo.get_by!(EventasaurusDiscovery.Sources.Source, slug: "karnet")

Logger.info("Testing with source: #{source.name} (ID: #{source.id})")

# Create test event data similar to what we extract
test_event_data = %{
  title: "Test Concert",
  url: "https://karnet.krakowculture.pl/60674-test",
  starts_at: DateTime.add(DateTime.utc_now(), 30 * 86400, :second),  # 30 days from now
  ends_at: nil,
  venue_data: %{
    name: "Kraków City Center",
    city: "Kraków",
    country: "Poland"
  },
  performers: [],
  description: "Test event description",
  category: "concert",
  date_text: "czwartek, 4 września 2025"
}

# Transform for processor
transformed = %{
  title: test_event_data[:title],
  source_url: test_event_data[:url],
  # CRITICAL: Using 'start_at' not 'starts_at'
  start_at: test_event_data[:starts_at],
  ends_at: test_event_data[:ends_at],
  venue_data: test_event_data[:venue_data],
  venue: test_event_data[:venue_data],
  performers: [],
  performer_names: [],
  description: test_event_data[:description],
  category: test_event_data[:category],
  external_id: "karnet_60674",
  source_metadata: %{
    "url" => test_event_data[:url],
    "date_text" => test_event_data[:date_text]
  }
}

Logger.info("Transformed data has start_at: #{inspect(transformed[:start_at])}")

# Try processing through the unified processor
result = EventasaurusDiscovery.Sources.Processor.process_single_event(transformed, source)

case result do
  {:ok, event} ->
    Logger.info("✅ SUCCESS! Event created: #{event.id} - #{event.title}")
    Logger.info("   Event starts at: #{event.starts_at}")
    Logger.info("   Venue: #{event.venue.name}")

  {:error, reason} ->
    Logger.error("❌ FAILED: #{inspect(reason)}")
end

IO.puts("\nTest complete!")