# Issue: Geocoding Cost Tracking System

## Problem Statement

We currently use paid geocoding APIs (Google Maps, Google Places) for venue creation across three scrapers:
- **QuestionOne**: Uses Google Maps Geocoding API ($5/1000 calls) as fallback when OSM fails
- **Kino Krakow**: Uses Google Places Text Search + Details API ($34/1000 calls)
- **Resident Advisor**: Uses Google Places Text Search + Details API ($34/1000 calls)

**We cannot currently answer**:
1. How many venues per scraper use paid geocoding APIs?
2. What are our monthly geocoding costs?
3. Which provider (Google Maps vs Google Places vs OSM) was used for each venue?

## Recommended Solution

**Use `venues.metadata` field for geocoding cost tracking** (not a dedicated events table).

### Why Metadata Approach?

✅ **Primary use case is monthly cost monitoring** - metadata handles this perfectly
✅ **Venues table already has metadata :map field** (migration 20251004205529)
✅ **VenueProcessor already stores Google Places metadata** (line 620)
✅ **5 hour implementation** vs 7.5 hours for events table
✅ **Zero additional database migrations required**
✅ **Simpler queries, no JOINs needed**
✅ **Backward compatible** - existing venues without geocoding metadata work fine

### Standardized Metadata Structure

```elixir
metadata: %{
  geocoding: %{
    provider: "google_places" | "google_maps" | "openstreetmap" | "provided",
    source_scraper: "question_one" | "kino_krakow" | "resident_advisor" | nil,
    geocoded_at: ~U[2025-01-11 10:30:00Z],
    cost_per_call: 0.034,  # In USD

    # AddressGeocoder specific (QuestionOne)
    original_address: "123 Main St, Warsaw",
    fallback_used: true,  # true = Google Maps, false = OSM

    # Google Places specific (Kino Krakow, Resident Advisor)
    google_places_response: %{
      place_id: "ChIJ...",
      formatted_address: "...",
      # ... other Google Places data
    }
  }
}
```

### Cost Breakdown

| Scraper | Provider | Cost per Call | When Charged |
|---------|----------|---------------|--------------|
| QuestionOne | Google Maps | $0.005 | When OSM geocoding fails (fallback_used: true) |
| Kino Krakow | Google Places | $0.034 | Every venue created (Text Search $0.017 + Details $0.017) |
| Resident Advisor | Google Places | $0.034 | Every venue created (Text Search $0.017 + Details $0.017) |

## Implementation Plan

### 1. Update AddressGeocoder Module (1 hour)

**File**: `lib/eventasaurus_discovery/helpers/address_geocoder.ex`

**Change**: Return geocoding metadata along with coordinates

```elixir
defp geocode_with_osm(address) do
  case Geocoder.call(address, :osm) do
    {:ok, coords} ->
      {:ok, %{
        latitude: coords.lat,
        longitude: coords.lon,
        geocoding_metadata: %{
          provider: "openstreetmap",
          geocoded_at: DateTime.utc_now(),
          cost_per_call: 0.0,
          original_address: address,
          fallback_used: false
        }
      }}
    {:error, _} -> geocode_with_google_maps(address)
  end
end

defp geocode_with_google_maps(address) do
  case Geocoder.call(address) do
    {:ok, coords} ->
      {:ok, %{
        latitude: coords.lat,
        longitude: coords.lon,
        geocoding_metadata: %{
          provider: "google_maps",
          geocoded_at: DateTime.utc_now(),
          cost_per_call: 0.005,
          original_address: address,
          fallback_used: true
        }
      }}
    {:error, _} -> {:error, :geocoding_failed}
  end
end
```

### 2. Update VenueProcessor (1.5 hours)

**File**: `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex`

**Changes**:
- Accept `source_scraper` parameter in venue creation functions
- Merge geocoding_metadata from AddressGeocoder with existing Google Places metadata
- Standardize metadata structure across all geocoding methods

```elixir
def create_venue(attrs, source_scraper \\ nil) do
  # ... existing code ...

  metadata = case attrs do
    # Google Places path (Kino Krakow, Resident Advisor)
    %{google_places_response: places_data} ->
      %{
        geocoding: %{
          provider: "google_places",
          source_scraper: source_scraper,
          geocoded_at: DateTime.utc_now(),
          cost_per_call: 0.034,
          google_places_response: places_data
        }
      }

    # AddressGeocoder path (QuestionOne)
    %{geocoding_metadata: geocoding_data} ->
      %{
        geocoding: Map.put(geocoding_data, :source_scraper, source_scraper)
      }

    # Coordinates provided directly (no geocoding cost)
    _ ->
      %{
        geocoding: %{
          provider: "provided",
          source_scraper: source_scraper,
          cost_per_call: 0.0
        }
      }
  end

  Venue.changeset(%Venue{}, Map.put(attrs, :metadata, metadata))
  |> Repo.insert()
end
```

### 3. Update Scrapers to Pass source_scraper (0.5 hours)

**Files**:
- `lib/eventasaurus_discovery/scraping/question_one_scraper.ex`
- `lib/eventasaurus_discovery/scraping/kino_krakow_scraper.ex`
- `lib/eventasaurus_discovery/scraping/resident_advisor_scraper.ex`

**Change**: Pass scraper name when creating venues

```elixir
# QuestionOne
VenueProcessor.create_venue(venue_attrs, "question_one")

# Kino Krakow
VenueProcessor.create_venue(venue_attrs, "kino_krakow")

# Resident Advisor
VenueProcessor.create_venue(venue_attrs, "resident_advisor")
```

### 4. Create GeocodingStats Query Module (1 hour)

**File**: `lib/eventasaurus_discovery/metrics/geocoding_stats.ex`

```elixir
defmodule EventasaurusDiscovery.Metrics.GeocodingStats do
  import Ecto.Query
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusApp.Repo

  @doc """
  Get monthly geocoding costs for the last N months.
  Returns list of maps with scraper, provider, month, venue_count, total_cost.
  """
  def monthly_costs(months_back \\ 6) do
    query = from v in Venue,
      where: fragment("? ->> 'geocoding' IS NOT NULL", v.metadata),
      where: fragment("(?->'geocoding'->>'source_scraper') IS NOT NULL", v.metadata),
      where: v.inserted_at >= ago(^months_back, "month"),
      select: %{
        scraper: fragment("?->'geocoding'->>'source_scraper'", v.metadata),
        provider: fragment("?->'geocoding'->>'provider'", v.metadata),
        month: fragment("DATE_TRUNC('month', ?)", v.inserted_at),
        venue_count: count(v.id),
        total_cost: sum(fragment("(?->'geocoding'->>'cost_per_call')::float", v.metadata))
      },
      group_by: [
        fragment("?->'geocoding'->>'source_scraper'", v.metadata),
        fragment("?->'geocoding'->>'provider'", v.metadata),
        fragment("DATE_TRUNC('month', ?)", v.inserted_at)
      ],
      order_by: [desc: fragment("DATE_TRUNC('month', ?)", v.inserted_at)]

    Repo.all(query)
  end

  @doc """
  Get total venue count for a specific scraper and provider.
  """
  def venues_by_scraper_and_provider(scraper, provider) do
    query = from v in Venue,
      where: fragment("?->'geocoding'->>'source_scraper' = ?", v.metadata, ^scraper),
      where: fragment("?->'geocoding'->>'provider' = ?", v.metadata, ^provider),
      select: count(v.id)

    Repo.one(query)
  end

  @doc """
  Get current month's costs by scraper (useful for monitoring).
  """
  def current_month_costs do
    query = from v in Venue,
      where: fragment("? ->> 'geocoding' IS NOT NULL", v.metadata),
      where: fragment("(?->'geocoding'->>'source_scraper') IS NOT NULL", v.metadata),
      where: v.inserted_at >= fragment("DATE_TRUNC('month', CURRENT_DATE)"),
      select: %{
        scraper: fragment("?->'geocoding'->>'source_scraper'", v.metadata),
        provider: fragment("?->'geocoding'->>'provider'", v.metadata),
        venue_count: count(v.id),
        total_cost: sum(fragment("(?->'geocoding'->>'cost_per_call')::float", v.metadata))
      },
      group_by: [
        fragment("?->'geocoding'->>'source_scraper'", v.metadata),
        fragment("?->'geocoding'->>'provider'", v.metadata)
      ]

    Repo.all(query)
  end
end
```

### 5. Create Monthly Cost Report Oban Job (1 hour)

**File**: `lib/eventasaurus_discovery/workers/geocoding_cost_report_worker.ex`

```elixir
defmodule EventasaurusDiscovery.Workers.GeocodingCostReportWorker do
  use Oban.Worker, queue: :reporting, max_attempts: 3

  alias EventasaurusDiscovery.Metrics.GeocodingStats
  require Logger

  @impl Oban.Worker
  def perform(_job) do
    costs = GeocodingStats.monthly_costs(1)  # Previous month only

    report = format_report(costs)

    Logger.info("""
    ====== Monthly Geocoding Cost Report ======
    #{report}
    ===========================================
    """)

    # TODO: Send email notification or Slack webhook with report
    :ok
  end

  defp format_report(costs) do
    total = Enum.reduce(costs, 0.0, fn cost, acc -> acc + (cost.total_cost || 0.0) end)

    lines = Enum.map(costs, fn cost ->
      "• #{cost.scraper} (#{cost.provider}): #{cost.venue_count} venues = $#{Float.round(cost.total_cost || 0.0, 2)}"
    end)

    Enum.join(lines ++ ["", "Total: $#{Float.round(total, 2)}"], "\n")
  end
end
```

**Add to `config/config.exs`**:

```elixir
config :eventasaurus, Oban,
  queues: [
    # ... existing queues ...
    reporting: 3
  ],
  plugins: [
    # ... existing plugins ...
    {Oban.Plugins.Cron,
     crontab: [
       # ... existing cron jobs ...
       {"0 9 1 * *", EventasaurusDiscovery.Workers.GeocodingCostReportWorker}  # 1st of month at 9am
     ]}
  ]
```

## Example SQL Queries

### Monthly Costs by Scraper (Last 6 Months)

```sql
SELECT
  metadata->'geocoding'->>'source_scraper' as scraper,
  metadata->'geocoding'->>'provider' as provider,
  DATE_TRUNC('month', inserted_at) as month,
  COUNT(*) as venue_count,
  SUM((metadata->'geocoding'->>'cost_per_call')::float) as total_cost
FROM venues
WHERE metadata->'geocoding'->>'source_scraper' IS NOT NULL
  AND metadata->'geocoding'->>'cost_per_call' IS NOT NULL
  AND inserted_at >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '6 months')
GROUP BY scraper, provider, DATE_TRUNC('month', inserted_at)
ORDER BY month DESC, scraper;
```

### Total Venues Using Google Maps Fallback (QuestionOne)

```sql
SELECT COUNT(*) as venue_count
FROM venues
WHERE metadata->'geocoding'->>'source_scraper' = 'question_one'
  AND metadata->'geocoding'->>'fallback_used' = 'true';
```

### Current Month Cost by Scraper

```sql
SELECT
  metadata->'geocoding'->>'source_scraper' as scraper,
  COUNT(*) as venue_count,
  SUM((metadata->'geocoding'->>'cost_per_call')::float) as total_cost
FROM venues
WHERE metadata->'geocoding'->>'source_scraper' IS NOT NULL
  AND inserted_at >= DATE_TRUNC('month', CURRENT_DATE)
GROUP BY scraper
ORDER BY total_cost DESC;
```

## Testing Plan

1. **Unit Tests**:
   - Test AddressGeocoder returns correct metadata for OSM success
   - Test AddressGeocoder returns correct metadata for Google Maps fallback
   - Test VenueProcessor merges geocoding metadata correctly
   - Test GeocodingStats.monthly_costs query

2. **Integration Tests**:
   - Test QuestionOne scraper creates venues with correct metadata
   - Test Kino Krakow scraper creates venues with correct metadata
   - Test GeocodingCostReportWorker formats report correctly

3. **Manual Testing**:
   - Run QuestionOne scraper, verify metadata in database
   - Run Kino Krakow scraper, verify metadata in database
   - Query GeocodingStats.monthly_costs(1), verify output
   - Trigger GeocodingCostReportWorker manually, verify log output

## Time Estimate

| Task | Hours |
|------|-------|
| Update AddressGeocoder | 1.0 |
| Update VenueProcessor | 1.5 |
| Update scrapers | 0.5 |
| Create GeocodingStats module | 1.0 |
| Create Oban report worker | 1.0 |
| **Total** | **5.0** |

## Success Criteria

✅ Can answer "How many venues per scraper use paid APIs?" via GeocodingStats queries
✅ Can answer "What are monthly costs?" via GeocodingStats.monthly_costs()
✅ Monthly cost report automatically generated on 1st of each month
✅ All geocoding methods (OSM, Google Maps, Google Places) tracked consistently
✅ Zero additional database migrations required
✅ Backward compatible with existing venues

## Alternative Considered: Dedicated geocoding_events Table

**Why Rejected**:
- ❌ More complex implementation (7.5 hours vs 5 hours)
- ❌ Requires JOINs for all cost queries
- ❌ Adds ongoing maintenance burden
- ❌ Primary use case (monthly cost monitoring) satisfied by metadata approach
- ❌ Over-engineering for current requirements

**When to Reconsider**:
- If we need to track failed geocoding attempts
- If we need detailed retry history
- If we need to audit geocoding changes over time
- If we need temporal analysis beyond monthly costs

For now, the metadata approach is the right balance of simplicity and functionality.

## Implementation Checklist

- [ ] 1. Update AddressGeocoder to return geocoding_metadata
- [ ] 2. Update VenueProcessor to merge and standardize metadata
- [ ] 3. Update QuestionOne scraper to pass source_scraper
- [ ] 4. Update Kino Krakow scraper to pass source_scraper
- [ ] 5. Update Resident Advisor scraper to pass source_scraper
- [ ] 6. Create GeocodingStats query module
- [ ] 7. Create GeocodingCostReportWorker Oban job
- [ ] 8. Add Oban cron configuration
- [ ] 9. Write unit tests for AddressGeocoder metadata
- [ ] 10. Write unit tests for VenueProcessor metadata handling
- [ ] 11. Write unit tests for GeocodingStats queries
- [ ] 12. Write integration tests for scraper metadata
- [ ] 13. Manual testing with QuestionOne scraper
- [ ] 14. Manual testing with Kino Krakow scraper
- [ ] 15. Verify GeocodingCostReportWorker output
- [ ] 16. Deploy to staging
- [ ] 17. Monitor first month of production data
- [ ] 18. Document usage in team wiki

## References

- **Venues Schema**: `lib/eventasaurus_app/venues/venue.ex:110` (metadata :map field)
- **VenueProcessor**: `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex:620` (Google Places metadata)
- **AddressGeocoder**: `lib/eventasaurus_discovery/helpers/address_geocoder.ex`
- **CityResolver**: `lib/eventasaurus_discovery/helpers/city_resolver.ex` (uses free offline geocoding)
- **Metadata Migration**: `priv/repo/migrations/20251004205529_add_google_places_metadata_to_venues.exs`

---

**Recommended Action**: Implement metadata-based geocoding cost tracking system for accurate monthly cost monitoring across all three scrapers.
