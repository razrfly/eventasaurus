# Issue: Missing Daily Coordinate Recalculation for Active Cities

**Status**: Critical Bug - System Design Gap
**Severity**: High - Prevents automatic maintenance of city coordinates
**Affected Component**: City coordinate calculation, Oban job scheduling, CityDiscoveryOrchestrator
**Date Discovered**: 2025-10-17

---

## Problem Summary

The system lacks a **daily scheduled job** to recalculate city coordinates for all active (discovery-enabled) cities. While `CityCoordinateCalculationJob` exists and works correctly, it's only triggered reactively by:

1. City-based scrapers (Bandsintown, Ticketmaster) after each sync
2. VenueProcessor when a city has **no coordinates** (nil check)

**Impact**:
- Sitemap-based scrapers (Sortiraparis) never trigger coordinate updates
- Cities with existing coordinates never get recalculated automatically
- Venue additions/changes don't update city centers
- Manual intervention required via mix task

**Error Message** (symptom):
```
RuntimeError at GET /c/paris
City 'Paris' (slug: paris) exists but has no coordinates.
```

---

## Root Cause Analysis

### Current System Design

**What Works:**
- `CityCoordinateCalculationJob` (lib/eventasaurus_discovery/jobs/city_coordinate_calculation_job.ex)
  - Calculates city center from venue averages
  - Built-in 24h deduplication (line 156-162)
  - Handles force updates and nil coordinate detection

**What's Missing:**
- No daily cron job to schedule updates for all active cities
- No proactive maintenance schedule

### Trigger Points (Current)

#### 1. BaseJob - City-Based Scrapers ✅ (Partial)

File: `lib/eventasaurus_discovery/sources/base_job.ex:60-61`

```elixir
# Schedule coordinate recalculation after successful sync
schedule_coordinate_update(city_id)
```

**Works for:**
- Bandsintown
- Ticketmaster
- Any scraper using BaseJob's default `perform/1`

**Doesn't work for:**
- Sortiraparis (overrides `perform/1`, lines 47-84 in sync_job.ex)
- Other sitemap-based scrapers

#### 2. VenueProcessor - New City Creation ✅ (Limited)

File: `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex:322-324`

```elixir
if is_nil(city.latitude) || is_nil(city.longitude) do
  schedule_city_coordinate_update(city.id)
end
```

**Problem**: This ONLY fires when coordinates are nil. Once a city has coordinates, this check becomes false and never schedules updates again.

#### 3. Daily Scheduled Job ❌ (MISSING)

**Expected**: A daily cron job that:
1. Finds all cities with `discovery_enabled = true`
2. Schedules `CityCoordinateCalculationJob` for each
3. Job's 24h deduplication prevents spam

**Actual**: No such job exists.

**Evidence**:
- `config/config.exs:132-138` shows cron jobs
- `CityDiscoveryOrchestrator` queues scraping jobs only
- No coordinate recalculation worker in cron

---

## System Architecture Analysis

### Oban Cron Configuration

File: `config/config.exs:132-138`

```elixir
{Oban.Plugins.Cron,
 crontab: [
   # Daily sitemap generation at 2 AM UTC
   {"0 2 * * *", Eventasaurus.Workers.SitemapWorker},
   # City discovery orchestration runs daily at midnight UTC
   {"0 0 * * *", EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator},
   # ... other jobs
 ]}
```

**Missing Entry**: No `CityCoordinateRecalculationWorker` or similar

### CityDiscoveryOrchestrator

File: `lib/eventasaurus_discovery/workers/city_discovery_orchestrator.ex`

**What it does** (lines 5-9):
1. Finds cities with `discovery_enabled = true`
2. Checks which sources should run for each city
3. Queues `DiscoverySyncJob` for each due source
4. Updates `next_run_at` timestamps

**What it doesn't do**:
- Schedule coordinate recalculation
- Maintain city coordinate accuracy

### Database State

**Current Active Cities** (discovery_enabled = true):
```
 id |  name  |  slug  | discovery_enabled | has_coordinates
----+--------+--------+-------------------+-----------------
  1 | London | london | true              | true
  2 | Kraków | krakow | true              | true
```

**Total**: 398 cities, only 2 actively watched

**Paris Status**:
```
 id  | name  | slug  | discovery_enabled | latitude | longitude
-----+-------+-------+-------------------+----------+-----------
 371 | Paris | paris | false             | null     | null
```

Paris is **not** in the active cities list (discovery_enabled = false), which explains why it has no coordinates even if a daily job existed.

---

## Why This Matters

### Design Intent vs. Reality

**Design Intent** (from user requirements):
> "For cities that we're watching, we should be the ones who create the cities. Intentionally. And we should be the ones that, it should basically once per day, for all the cities that are active, we should be re-centering them based on the venues that they have."

**Current Reality:**
- Only 2 cities actively watched (London, Kraków)
- No daily recalculation job exists
- Sortiraparis events go to Paris but Paris isn't watched
- Coordinate updates happen reactively, not proactively

### Impact on Different Scraper Types

| Scraper Type | Uses BaseJob | Triggers Coordinates | Example |
|--------------|--------------|----------------------|---------|
| **City-Based** | Yes (default perform) | ✅ After each sync | Bandsintown, Ticketmaster |
| **Sitemap-Based** | Yes (custom perform) | ❌ Never | Sortiraparis |
| **All Types** | N/A | ❌ Never proactive | No daily job |

### When Coordinates Get Stale

1. **New venues added**: City center should shift
2. **Venues updated**: Coordinate changes affect center
3. **Venues removed**: Center needs recalculation
4. **Sitemap scrapers run**: No coordinate update triggered

---

## Solution Design

### Option 1: Add Daily Coordinate Recalculation Worker (RECOMMENDED)

**Implementation**:

1. Create new worker: `lib/eventasaurus_discovery/workers/city_coordinate_recalculation_worker.ex`

```elixir
defmodule EventasaurusDiscovery.Workers.CityCoordinateRecalculationWorker do
  @moduledoc """
  Daily worker to recalculate coordinates for all discovery-enabled cities.

  Runs daily to ensure city centers stay accurate as venues are added/updated.
  Uses CityCoordinateCalculationJob's built-in 24h deduplication.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 3

  alias EventasaurusDiscovery.Admin.DiscoveryConfigManager
  alias EventasaurusDiscovery.Jobs.CityCoordinateCalculationJob
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("🌍 City Coordinate Recalculation: Starting daily run")

    # Get all cities with discovery enabled
    cities = DiscoveryConfigManager.list_discovery_enabled_cities()

    Logger.info("Found #{length(cities)} active cities for coordinate recalculation")

    # Schedule coordinate calculation for each city
    scheduled_count =
      Enum.reduce(cities, 0, fn city, count ->
        case CityCoordinateCalculationJob.schedule_update(city.id) do
          {:ok, _} ->
            Logger.debug("  ✅ Scheduled coordinate update for #{city.name}")
            count + 1
          {:error, reason} ->
            Logger.warning("  ⚠️ Failed to schedule update for #{city.name}: #{inspect(reason)}")
            count
        end
      end)

    Logger.info("✅ Scheduled coordinate recalculation for #{scheduled_count}/#{length(cities)} cities")

    {:ok, %{cities_scheduled: scheduled_count}}
  end
end
```

2. Add to cron schedule in `config/config.exs:133`:

```elixir
{Oban.Plugins.Cron,
 crontab: [
   # Daily sitemap generation at 2 AM UTC
   {"0 2 * * *", Eventasaurus.Workers.SitemapWorker},
   # City discovery orchestration runs daily at midnight UTC
   {"0 0 * * *", EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator},
   # City coordinate recalculation runs daily at 1 AM UTC
   {"0 1 * * *", EventasaurusDiscovery.Workers.CityCoordinateRecalculationWorker},
   # Monthly geocoding cost report...
 ]}
```

**Pros**:
- Simple, focused implementation
- Reuses existing job and deduplication logic
- Runs daily for all active cities
- Self-documenting purpose

**Cons**:
- Adds another scheduled job (minimal overhead)
- One more worker to maintain

---

### Option 2: Extend CityDiscoveryOrchestrator

**Implementation**: Add coordinate scheduling to existing orchestrator (lines 50-85)

```elixir
defp process_city(city, now, dry_run) do
  Logger.info("Processing discovery for #{city.name}")

  # Get sources that are due to run
  due_sources = DiscoveryConfigManager.get_due_sources(city)

  # Queue scraping jobs
  jobs_queued = # ... existing code ...

  # Schedule coordinate recalculation for this city
  case CityCoordinateCalculationJob.schedule_update(city.id) do
    {:ok, _} -> Logger.debug("  ✅ Scheduled coordinate update")
    {:error, _} -> :ok  # Already scheduled, skip silently
  end

  {city.id, jobs_queued}
end
```

**Pros**:
- No new worker needed
- Coordinates update when scraping happens
- Single orchestration point

**Cons**:
- Mixes concerns (discovery + maintenance)
- Less obvious where coordinate updates happen
- Harder to schedule independently (e.g., different times)

---

### Option 3: Fix Sortiraparis to Call BaseJob Coordinate Update

**Implementation**: Add coordinate update to Sortiraparis SyncJob

**Problem**: Sortiraparis is **not city-based** - it scrapes from sitemaps without a city parameter. We don't know which cities to update until venues are processed.

**Verdict**: Not feasible without major architectural changes.

---

## Recommended Solution

**Implement Option 1**: Add dedicated `CityCoordinateRecalculationWorker`

**Rationale**:
1. **Single Responsibility**: One job, one purpose
2. **Independent Scheduling**: Can run at different time than discovery (avoids resource contention)
3. **Works for ALL scraper types**: City-based and sitemap-based
4. **Reuses Existing Logic**: Leverages `CityCoordinateCalculationJob`'s deduplication
5. **Easy to Monitor**: Clear logs and metrics for coordinate updates

**Schedule Recommendation**:
- Run at 1 AM UTC (after midnight discovery, before 2 AM sitemap generation)
- Gives time for new venues to be processed before coordinate recalculation

---

## Manual Workaround (Current)

### Calculate Coordinates for All Cities

```bash
# Calculate all cities (respects 24h deduplication)
mix discovery.calculate_city_coordinates

# Force recalculation (bypasses 24h window)
mix discovery.calculate_city_coordinates --force
```

### Calculate Specific City

```bash
# By city ID
mix discovery.calculate_city_coordinates --city-id=371

# Force specific city
mix discovery.calculate_city_coordinates --city-id=371 --force
```

### Enable Discovery for Paris

```elixir
# In iex console or migration
alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Locations.City
import Ecto.Query

paris = Repo.get_by!(City, slug: "paris")
Ecto.Changeset.change(paris, discovery_enabled: true) |> Repo.update!()

# Then manually calculate coordinates
CityCoordinateCalculationJob.schedule_update(371, true)
```

---

## Testing Strategy

### 1. Worker Implementation Test

```bash
# Create worker and add to cron config
# Start app and wait for next scheduled run
# Or manually enqueue:

%{}
|> EventasaurusDiscovery.Workers.CityCoordinateRecalculationWorker.new()
|> Oban.insert!()

# Check logs for:
# - "City Coordinate Recalculation: Starting daily run"
# - Number of cities scheduled
# - Success/failure for each city
```

### 2. Verify Scheduling

```sql
-- Check scheduled jobs
SELECT id, worker, args, scheduled_at, state
FROM oban_jobs
WHERE worker = 'EventasaurusDiscovery.Jobs.CityCoordinateCalculationJob'
ORDER BY scheduled_at DESC
LIMIT 10;
```

### 3. Verify Coordinate Updates

```sql
-- Check Paris after job runs
SELECT id, name, slug, latitude, longitude, updated_at
FROM cities
WHERE id = 371;

-- Should see:
-- - latitude and longitude populated
-- - updated_at timestamp recent
```

### 4. Verify Deduplication

```bash
# Schedule twice in quick succession
mix discovery.calculate_city_coordinates --city-id=371
mix discovery.calculate_city_coordinates --city-id=371

# Second should be skipped (already scheduled)
# Check Oban jobs - should only see one job
```

---

## File References

### Key Files Involved

1. **CityCoordinateCalculationJob** (`lib/eventasaurus_discovery/jobs/city_coordinate_calculation_job.ex`)
   - Line 22: `@hours_between_updates 24`
   - Line 68-89: `check_update_needed/2` - Handles 24h deduplication
   - Line 91-112: `calculate_coordinates/1` - Averages venue locations
   - Line 143-168: `schedule_update/2` - Public API for scheduling

2. **BaseJob** (`lib/eventasaurus_discovery/sources/base_job.ex`)
   - Line 60-61: Schedules coordinate update after successful sync
   - Line 112-121: `schedule_coordinate_update/1` helper

3. **VenueProcessor** (`lib/eventasaurus_discovery/scraping/processors/venue_processor.ex`)
   - Line 322-324: Nil-check that triggers initial coordinate calculation
   - Line 878-890: `schedule_city_coordinate_update/1` helper

4. **Sortiraparis SyncJob** (`lib/eventasaurus_discovery/sources/sortiraparis/jobs/sync_job.ex`)
   - Line 34: `use EventasaurusDiscovery.Sources.BaseJob`
   - Line 47-84: Overrides `perform/1` - DOES NOT call coordinate update

5. **CityDiscoveryOrchestrator** (`lib/eventasaurus_discovery/workers/city_discovery_orchestrator.ex`)
   - Line 45: `list_discovery_enabled_cities()` - Gets active cities
   - Line 67-85: `process_city/3` - Queues scraping jobs (no coordinate updates)

6. **Oban Config** (`config/config.exs`)
   - Line 132-138: Cron schedule configuration
   - Missing: Coordinate recalculation worker

7. **Mix Task** (`lib/mix/tasks/discovery.calculate_city_coordinates.ex`)
   - Line 11: `mix discovery.calculate_city_coordinates` - All cities
   - Line 14: `--city-id=123` - Specific city
   - Line 17: `--force` - Bypass 24h window

8. **City Schema** (`lib/eventasaurus_discovery/locations/city.ex`)
   - `discovery_enabled` field - Boolean flag for active cities
   - `latitude`, `longitude` fields - Calculated from venues

---

## Impact Analysis

### Current Impact

**Severity**: High
- Sitemap-based scrapers don't trigger coordinate updates
- Cities don't get proactive maintenance
- Manual intervention required for coordinate accuracy
- Paris specifically broken (not watched + no coordinates)

### User Impact

**Severity**: Medium-High
- URLs like `/c/paris` fail with 500 errors
- City centers become stale as venues change
- Inconsistent behavior between scraper types
- Admin must manually trigger coordinate calculation

### Similar Issues at Risk

Any city that:
1. Has `discovery_enabled = false` (not watched)
2. Gets events from sitemap-based scrapers
3. Has existing coordinates (passes nil check in VenueProcessor)

Will never get automatic coordinate updates.

---

## Related Issues

- #1821 - Paris City Missing Coordinates (symptom of this issue)
- City hierarchy problem (arrondissement granularity)
- Sitemap scraper design vs. city-based scraper assumptions

---

## Next Steps

1. **Immediate**: Enable discovery for Paris and manually calculate coordinates
   ```bash
   # In iex:
   paris = Repo.get_by!(City, slug: "paris")
   Ecto.Changeset.change(paris, discovery_enabled: true) |> Repo.update!()

   # Then:
   mix discovery.calculate_city_coordinates --city-id=371 --force
   ```

2. **Short-term**: Implement `CityCoordinateRecalculationWorker` and add to cron schedule

3. **Long-term**: Consider consolidating all city maintenance into a single orchestrator or review city-based vs. sitemap-based scraper architecture

4. **Documentation**: Update scraper documentation about coordinate calculation triggers and active city requirements

---

## UPDATE 2025-10-17: Geographic-Based City Matching Implementation

### Problem Discovery

After implementing `CityCoordinateRecalculationWorker`, Paris still doesn't show in city statistics despite:
- Paris enabled (discovery_enabled = true) ✅
- Worker running daily ✅
- 84 Sortiraparis events exist ✅

**Root Cause**: The current system uses `venue.city_id` for matching, which fragments Paris into 19 arrondissements:
- Main Paris (ID 371): 0 venues, 0 events
- Paris 1-19: 64 venues split across arrondissements
- Highest is Paris 3 with 9 events (below 10-event threshold)
- **Result**: Paris is invisible in statistics

### Fundamental Architecture Issue

**Current (Broken) Approach:**
```sql
-- Coordinate calculation
SELECT AVG(latitude), AVG(longitude)
FROM venues
WHERE city_id = 371  -- Returns 0 venues for main Paris

-- City statistics
SELECT city_name, COUNT(events)
FROM events
JOIN venues ON venue.id = event.venue_id
JOIN cities ON city.id = venue.city_id  -- Uses venue.city_id
WHERE city.discovery_enabled = true
HAVING COUNT(events) >= 10
```

**Problem**: City names are unreliable. Geocoding returns granular subdivisions (Paris 5, Paris 9, etc.), fragmenting data across multiple city records.

### New Architecture: Geographic-Based Matching

**Design Principle**: For active cities (discovery_enabled = true), use **geographic coordinates** as source of truth, not city names.

**New Approach:**
```sql
-- Coordinate calculation (for active cities)
SELECT AVG(v.latitude), AVG(v.longitude)
FROM venues v
WHERE ST_DWithin(
  ST_MakePoint(v.longitude, v.latitude)::geography,
  ST_MakePoint(city.longitude, city.latitude)::geography,
  20000  -- 20km radius in meters
)

-- City statistics (for active cities)
SELECT c.name, COUNT(DISTINCT e.id)
FROM cities c
WHERE c.discovery_enabled = true
  AND c.latitude IS NOT NULL
JOIN venues v ON ST_DWithin(
  ST_MakePoint(v.longitude, v.latitude)::geography,
  ST_MakePoint(c.longitude, c.latitude)::geography,
  20000
)
JOIN events e ON e.venue_id = v.id
HAVING COUNT(e.id) >= 10
```

### Two Separate Systems

**System 1: Coordinate Recalculation (No Threshold)**
- Runs for ALL discovery-enabled cities
- No minimum venue/event count required
- Geographic radius matching for active cities
- Fallback to venue.city_id for inactive cities

**System 2: Statistics Display (10-Event Threshold)**
- Shows cities with >= 10 events only
- Geographic radius matching for active cities
- Provides meaningful dashboard metrics

### Implementation Requirements

#### 1. CityCoordinateCalculationJob Enhancement
**File**: `lib/eventasaurus_discovery/jobs/city_coordinate_calculation_job.ex`

**Changes**:
- Add `calculate_coordinates_geographic/2` for active cities
- Use geographic radius query (20km default)
- Fallback to venue.city_id for inactive cities
- Initial coordinates required (manually set once)

#### 2. Dashboard Statistics Enhancement
**File**: `lib/eventasaurus_web/live/admin/discovery_dashboard_live.ex`

**Changes**:
- Update `get_city_statistics/0` to use geographic matching
- Query active cities separately with radius matching
- Query inactive cities with traditional city_id matching
- Combine results for display

#### 3. Initial Setup
**One-time manual coordinate setting**:
```elixir
# Set Paris initial coordinates (city center)
paris = Repo.get_by!(City, slug: "paris")
Ecto.Changeset.change(paris, %{
  latitude: Decimal.new("48.8566"),
  longitude: Decimal.new("2.3522"),
  discovery_enabled: true
}) |> Repo.update!()
```

### Expected Results for Paris

**Before** (city_id-based):
- Paris (ID 371): 0 venues → 0 events → invisible
- Paris 1-19: 64 venues → 71 events fragmented → none exceed 10-event threshold

**After** (geographic-based):
- Paris (ID 371): Coordinates set → finds all 64 venues within 20km
- Paris shows: 71 events ✅ (exceeds 10-event threshold)
- Paris appears in city statistics dashboard ✅
- Coordinate recalculation works correctly ✅

### Benefits

1. **Solves Arrondissement Problem**: Bypasses city name fragmentation entirely
2. **Location-Based Truth**: Geographic coordinates are absolute and reliable
3. **Flexible City Boundaries**: 20km radius captures metro areas appropriately
4. **Manual Control**: Admins explicitly create and activate cities
5. **Backward Compatible**: Inactive cities still use venue.city_id matching

### Configuration Options

**Default Radius**: 20km (suitable for major cities)
**Configurable per city**: Could add `city.radius_km` field for flexibility
- Large metro areas (Paris, London): 20-30km
- Medium cities (Kraków): 10-15km
- Small cities: 5-10km

### Technical Notes

- PostGIS already configured (config.exs:19)
- ST_DWithin uses geography type for accurate spherical distance
- Can use bounding box for performance if needed
- Geographic index on venues recommended for large datasets
