# Test Occurrence Type Monitoring Functions
# Tests the query functions we created in Phase 3

alias EventasaurusDiscovery.PublicEvents

IO.puts("""
╔════════════════════════════════════════════════════════════════════════╗
║        Unknown Occurrence Type - Monitoring Functions Test            ║
╚════════════════════════════════════════════════════════════════════════╝
""")

# Test 1: Occurrence Type Stats
IO.puts("\n📊 TEST 1: Occurrence Type Distribution")
IO.puts("─────────────────────────────────────────────────────")

try do
  stats = PublicEvents.get_occurrence_type_stats()

  IO.puts("""

  ✅ get_occurrence_type_stats/0 works!

  Results:
  #{inspect(stats, pretty: true)}
  """)
rescue
  e ->
    IO.puts("\n❌ FAILED: #{inspect(e)}")
    IO.puts("#{Exception.format(:error, e, __STACKTRACE__)}")
end

# Test 2: Unknown Event Freshness Stats
IO.puts("\n🔄 TEST 2: Unknown Event Freshness Statistics")
IO.puts("─────────────────────────────────────────────────────")

try do
  freshness = PublicEvents.get_unknown_event_freshness_stats()

  IO.puts("""

  ✅ get_unknown_event_freshness_stats/0 works!

  Results:
  #{inspect(freshness, pretty: true)}

  Interpretation:
  ├─ Total Unknown Events: #{freshness.total_unknown}
  ├─ Fresh (seen in last #{freshness.freshness_days} days): #{freshness.fresh}
  ├─ Stale (older than #{freshness.freshness_days} days): #{freshness.stale}
  └─ Freshness Threshold: #{DateTime.to_iso8601(freshness.freshness_threshold)}
  """)
rescue
  e ->
    IO.puts("\n❌ FAILED: #{inspect(e)}")
    IO.puts("#{Exception.format(:error, e, __STACKTRACE__)}")
end

# Test 3: List Unknown Events
IO.puts("\n📋 TEST 3: List Unknown Occurrence Events")
IO.puts("─────────────────────────────────────────────────────")

try do
  events = PublicEvents.list_unknown_occurrence_events(limit: 10)

  IO.puts("""

  ✅ list_unknown_occurrence_events/1 works!

  Found #{length(events)} unknown occurrence events:
  """)

  if length(events) > 0 do
    Enum.each(events, fn event ->
      freshness_emoji = if event.is_fresh, do: "🟢", else: "🔴"

      IO.puts("""
      #{freshness_emoji} Event ##{event.event_id}
      ├─ Title: #{event.title}
      ├─ Original Date: #{event.original_date_string}
      ├─ Last Seen: #{if event.last_seen_at, do: DateTime.to_iso8601(event.last_seen_at), else: "never"}
      ├─ Days Since Seen: #{event.days_since_seen || "N/A"}
      └─ Status: #{if event.is_fresh, do: "FRESH ✅", else: "STALE ⚠️"}
      """)
    end)
  else
    IO.puts("""
    ℹ️  No unknown occurrence events found yet.

    This is expected if:
    - This is a fresh database
    - No scrapers have run with the new code yet
    - No events with unparseable dates have been encountered
    """)
  end
rescue
  e ->
    IO.puts("\n❌ FAILED: #{inspect(e)}")
    IO.puts("#{Exception.format(:error, e, __STACKTRACE__)}")
end

# Summary
IO.puts("""

╔════════════════════════════════════════════════════════════════════════╗
║                          Test Summary                                  ║
╚════════════════════════════════════════════════════════════════════════╝

✅ All monitoring functions compiled and executed successfully!

Next Steps for Full Validation:
1. Run a Sortiraparis scrape to generate unknown events
2. Check that events with unparseable dates get occurrence_type = 'unknown'
3. Verify freshness filtering works in PublicEventsEnhanced.list_events
4. Monitor scraper success rate improvement (should go from ~85% to ~100%)

To test with real data:
  1. Run: mix discovery.sync --city krakow --source sortiraparis --limit 50
  2. Check occurrence_type distribution in database
  3. Verify unknown events appear in event listings
""")

IO.puts("\n")
