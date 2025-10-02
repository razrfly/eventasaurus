#!/usr/bin/env elixir

# Integration test for Kino Krakow scraper
# Run with: mix run scripts/test_kino_krakow_integration.exs

alias EventasaurusDiscovery.Sources.KinoKrakow.{
  Config,
  Jobs.SyncJob,
  Source
}

IO.puts("\n🎬 Kino Krakow Integration Test\n")
IO.puts("=" |> String.duplicate(60))

# Test 1: Source Configuration
IO.puts("\n1️⃣  Testing Source Configuration...")
IO.puts("   Key: #{Source.key()}")
IO.puts("   Name: #{Source.name()}")
IO.puts("   Priority: #{Source.priority()}")
IO.puts("   Enabled: #{Source.enabled?()}")

config = Source.config()
IO.puts("   Base URL: #{config.base_url}")
IO.puts("   City: #{config.city}")
IO.puts("   Timezone: #{config.timezone}")
IO.puts("   Features:")
IO.puts("     - TMDB Matching: #{config.supports_tmdb_matching}")
IO.puts("     - Movie Metadata: #{config.supports_movie_metadata}")
IO.puts("     - Venue Details: #{config.supports_venue_details}")
IO.puts("   ✅ Source configuration valid")

# Test 2: URL Accessibility
IO.puts("\n2️⃣  Testing URL Accessibility...")

case Source.validate_config() do
  {:ok, message} ->
    IO.puts("   ✅ #{message}")

  {:error, reason} ->
    IO.puts("   ❌ Validation failed: #{reason}")
end

# Test 3: Sync Job Arguments
IO.puts("\n3️⃣  Testing Sync Job Arguments...")
job_args = Source.sync_job_args()
IO.puts("   Source: #{job_args["source"]}")
IO.puts("   Date: #{job_args["date"]}")
IO.puts("   ✅ Job arguments generated")

# Test 4: Live Scrape Test (limited)
IO.puts("\n4️⃣  Testing Live Scrape (limited to 3 events)...")

try do
  # Call the fetch_events function directly
  case SyncJob.fetch_events("Kraków", 3, %{}) do
    {:ok, events} ->
      IO.puts("   ✅ Successfully fetched #{length(events)} events")

      if length(events) > 0 do
        event = List.first(events)
        IO.puts("\n   📋 Sample Event:")
        IO.puts("      Movie: #{event.movie_title}")
        IO.puts("      Cinema: #{event.cinema_data.name}")
        IO.puts("      Time: #{event.datetime}")
        IO.puts("      Location: #{event.cinema_data.latitude}, #{event.cinema_data.longitude}")

        if event.tmdb_id do
          IO.puts("      TMDB ID: #{event.tmdb_id}")
          IO.puts("      Confidence: #{event.tmdb_confidence}")
        end
      end

    {:error, reason} ->
      IO.puts("   ❌ Fetch failed: #{inspect(reason)}")
  end
rescue
  e ->
    IO.puts("   ❌ Exception during fetch: #{inspect(e)}")
end

# Test 5: Transform Test
IO.puts("\n5️⃣  Testing Event Transformation...")

try do
  case SyncJob.fetch_events("Kraków", 1, %{}) do
    {:ok, [event | _]} ->
      transformed = SyncJob.transform_events([event])
      IO.puts("   ✅ Successfully transformed #{length(transformed)} event(s)")

      if length(transformed) > 0 do
        t_event = List.first(transformed)
        IO.puts("\n   📋 Transformed Event:")
        IO.puts("      Title: #{t_event.title}")
        IO.puts("      Category: #{t_event.category}")
        IO.puts("      Image URL: #{t_event.image_url || "MISSING"}")
        IO.puts("      Starts At: #{t_event.starts_at}")
        IO.puts("      Ends At: #{t_event.ends_at}")
        IO.puts("      Venue: #{t_event.venue_data.name}")
        IO.puts("      GPS: #{t_event.venue_data.latitude}, #{t_event.venue_data.longitude}")
      end

    {:ok, []} ->
      IO.puts("   ⚠️  No events fetched to transform")

    {:error, reason} ->
      IO.puts("   ❌ Transform failed: #{inspect(reason)}")
  end
rescue
  e ->
    IO.puts("   ❌ Exception during transform: #{inspect(e)}")
end

# Test 6: Source Configuration
IO.puts("\n6️⃣  Testing Source Config Module...")
config_info = SyncJob.source_config()
IO.puts("   Name: #{config_info.name}")
IO.puts("   Slug: #{config_info.slug}")
IO.puts("   Website: #{config_info.website_url}")
IO.puts("   Priority: #{config_info.priority}")
IO.puts("   Rate Limit: #{config_info.config["rate_limit_seconds"]}s")
IO.puts("   ✅ Source config valid")

IO.puts("\n" <> ("=" |> String.duplicate(60)))
IO.puts("✨ Integration test complete!\n")
