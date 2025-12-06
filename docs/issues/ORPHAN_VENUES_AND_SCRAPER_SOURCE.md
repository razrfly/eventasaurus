# Issue: Orphan Venues with Missing Scraper Source and Wrong Country Assignment

## Summary

Venues are being created with:
1. **Wrong country assignments** (e.g., Irish venues assigned to UK)
2. **No linked events** (orphan venues)
3. **No visible scraper source** (UI shows nil/blank)

This affects ~49 venues (32 from Mapbox geocoding, 17 from HERE geocoding) with the primary offending scraper being `speed-quizzing`.

## Evidence

### Specific Examples

| Venue ID | Name | Assigned Country | Actual Location | Scraper | Events |
|----------|------|------------------|-----------------|---------|--------|
| 5320 | Galway Greyhound Stadium | United Kingdom | Ireland (Galway) | speed-quizzing | 0 |
| 5374 | Wexford, Ireland | United Kingdom | Ireland (Wexford) | speed-quizzing | 0 |
| 5095 | Brewery Bar Sligo | United Kingdom | Ireland (Sligo) | speed-quizzing | 0 |
| 5042 | Tapped Late Night Venue | United Kingdom | Ireland (Dublin) | speed-quizzing | 0 |

### Query to Find Orphan Venues

```sql
SELECT v.source, COUNT(*) as venue_count,
       SUM(CASE WHEN (SELECT COUNT(*) FROM public_events pe WHERE pe.venue_id = v.id) = 0 THEN 1 ELSE 0 END) as orphan_count
FROM venues v
WHERE v.source IN ('mapbox', 'here')
GROUP BY v.source;
```

Results:
- Mapbox: 710 venues, 32 orphans (4.5%)
- HERE: 465 venues, 17 orphans (3.7%)

## Root Causes

### 1. Speed-Quizzing Scraper Data Quality

The speed-quizzing scraper defaults to "United Kingdom" as the country for ALL venues, including Irish ones. Evidence from metadata:

```json
{
  "source_data": {
    "source_scraper": "speed-quizzing",
    "country_name": "United Kingdom",  // WRONG!
    "city_name": "Gaillimh",           // Irish name for Galway
    "original_address": "College Road, Galway, H91 F880"  // Irish Eircode!
  }
}
```

The scraper is not detecting Ireland from:
- Irish city names (Galway, Dublin, Cork, Wexford, Sligo)
- Irish postcodes (Eircode format: H91 F880)
- "Ireland" in venue names or addresses

### 2. Geocoder Country Ignored

Even when the geocoder correctly identifies the country, the system uses the scraper's wrong country:

```json
{
  "geocoding": {
    "raw_response": {
      "address": {
        "countryCode": "IRL",      // Geocoder got it RIGHT
        "countryName": "Ireland"   // Geocoder got it RIGHT
      }
    }
  },
  "source_data": {
    "country_name": "United Kingdom"  // But system uses THIS
  }
}
```

### 3. Non-Atomic Venue/Event Creation

The data flow appears to be:
1. Scraper fetches event with venue info
2. Venue is created/resolved (COMMIT)
3. Event is created and linked to venue
4. Event sources are linked

If step 3 or 4 fails after step 2 commits, the venue remains as an orphan with no events.

### 4. Scraper Source Lookup Broken for Orphans

The `get_venue_scraper_source/1` function queries:
```elixir
from(pe in PublicEvent,
  join: pes in PublicEventSource,
  on: pes.event_id == pe.id,
  join: s in Source,
  on: s.id == pes.source_id,
  where: pe.venue_id == ^venue_id,
  ...)
```

For orphan venues with 0 events, this query returns `nil`.

**BUT** the scraper source IS stored in venue metadata at `metadata["source_data"]["source_scraper"]` - it's just not being used!

## Proposed Solutions

### Phase 1: Immediate Fixes (Low Effort)

#### 1.1 Fix Scraper Source Display in UI

Update `VenueCountryCheckJob.get_venue_scraper_source/1` to fall back to metadata:

```elixir
defp get_venue_scraper_source(%Venue{id: venue_id, metadata: metadata}) do
  # First try to get from events
  event_source = query_event_sources(venue_id)

  # Fall back to metadata if no events
  event_source ||
    get_in(metadata, ["source_data", "source_scraper"]) ||
    get_in(metadata, ["geocoding", "source_scraper"])
end
```

#### 1.2 Store Scraper Source in country_check

Update `check_and_update_venue/1` to include metadata source:

```elixir
scraper_source = get_venue_scraper_source(venue) ||
                 get_in(venue.metadata, ["source_data", "source_scraper"])
```

### Phase 2: Prevent Future Issues (Medium Effort)

#### 2.1 Validate Geocoder vs Scraper Country

Add validation during venue creation:

```elixir
def validate_country(scraper_country, geocoder_response) do
  geocoder_country = get_in(geocoder_response, ["address", "countryCode"])

  if scraper_country != geocoder_country do
    # Log discrepancy
    Logger.warning("Country mismatch: scraper=#{scraper_country}, geocoder=#{geocoder_country}")

    # Prefer geocoder for high-confidence matches
    if geocoder_confidence > 0.8, do: geocoder_country, else: scraper_country
  else
    scraper_country
  end
end
```

#### 2.2 Fix Speed-Quizzing Scraper

Add Ireland detection:

```elixir
@irish_cities ~w(dublin galway cork limerick waterford wexford sligo kilkenny
                 drogheda dundalk tralee killarney athlone ennis navan)

def detect_country(city_name, postal_code, address) do
  cond do
    # Irish city detection
    String.downcase(city_name) in @irish_cities -> "Ireland"

    # Irish Eircode pattern (e.g., H91 F880, D02 XY45)
    Regex.match?(~r/^[A-Z]\d{2}\s?[A-Z0-9]{4}$/i, postal_code || "") -> "Ireland"

    # "Ireland" in address
    String.contains?(String.downcase(address || ""), "ireland") -> "Ireland"

    # Default
    true -> "United Kingdom"
  end
end
```

#### 2.3 Atomic Venue+Event Creation

Wrap in transaction:

```elixir
Ecto.Multi.new()
|> Ecto.Multi.insert(:venue, venue_changeset)
|> Ecto.Multi.insert(:event, fn %{venue: venue} ->
     event_changeset(venue.id)
   end)
|> Ecto.Multi.insert(:event_source, fn %{event: event} ->
     event_source_changeset(event.id)
   end)
|> Repo.transaction()
```

### Phase 3: Data Cleanup (One-Time)

#### 3.1 Categorize Orphan Venues

```sql
-- Find orphans with GPS in wrong country
SELECT v.id, v.name, v.latitude, v.longitude,
       v.metadata->'country_check'->>'current_country' as assigned_country,
       v.metadata->'country_check'->>'expected_country' as gps_country,
       v.metadata->'source_data'->>'source_scraper' as scraper
FROM venues v
WHERE (SELECT COUNT(*) FROM public_events pe WHERE pe.venue_id = v.id) = 0
  AND (v.metadata->'country_check'->>'is_mismatch')::boolean = true;
```

#### 3.2 Delete Orphans with Wrong GPS

Venues where GPS also points to wrong country (e.g., Galway Greyhound Stadium with GPS in Suffolk, UK) should be deleted - both the country assignment AND the GPS coordinates are wrong.

```elixir
def delete_bad_orphans do
  venues = get_orphan_venues_with_bad_gps()
  Enum.each(venues, &Repo.delete/1)
end
```

#### 3.3 Fix Orphans with Correct GPS

Venues where GPS is correct but country is wrong can be fixed:

```elixir
def fix_orphans_with_correct_gps do
  venues = get_orphan_venues_with_correct_gps()
  Enum.each(venues, &DataQualityChecker.fix_venue_country_from_metadata/1)
end
```

#### 3.4 Periodic Orphan Cleanup Job

Add Oban job to clean up old orphan venues:

```elixir
defmodule OrphanVenueCleanupJob do
  use Oban.Worker

  @impl true
  def perform(_job) do
    # Delete venues with no events older than 30 days
    cutoff = DateTime.add(DateTime.utc_now(), -30, :day)

    from(v in Venue,
      where: v.inserted_at < ^cutoff,
      where: fragment("NOT EXISTS (SELECT 1 FROM public_events pe WHERE pe.venue_id = ?)", v.id)
    )
    |> Repo.delete_all()
  end
end
```

## Affected Files

- `lib/eventasaurus_discovery/admin/venue_country_check_job.ex` - Scraper source lookup
- `lib/eventasaurus_discovery/sources/speed_quizzing/` - Country detection
- Venue creation/resolution logic (location TBD)
- New: `lib/eventasaurus_discovery/admin/orphan_venue_cleanup_job.ex`

## Priority

1. **High**: Fix scraper source display (1.1, 1.2) - users need visibility
2. **High**: Fix speed-quizzing scraper (2.2) - stop creating new bad data
3. **Medium**: Validate geocoder country (2.1) - prevent silent failures
4. **Medium**: Atomic transactions (2.3) - prevent orphans
5. **Low**: Data cleanup (3.x) - fix existing bad data
6. **Low**: Periodic cleanup job (3.4) - ongoing maintenance

## Testing

After implementation:
1. Verify scraper source shows in mismatch table for all venues
2. Verify new Irish venues from speed-quizzing get correct country
3. Verify orphan venues are not created when events fail
4. Verify cleanup job only deletes appropriate venues

## Related

- VenueCountryCheckJob - checks for country mismatches
- VenueCountryFixJob - fixes identified mismatches
- DataQualityChecker - core fix logic
