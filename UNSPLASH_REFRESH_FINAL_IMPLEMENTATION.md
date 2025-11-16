# Unsplash Refresh System - Final Implementation & Testing Guide

## Current System Architecture

### Workers (3 total)

1. **UnsplashRefreshWorker** (Coordinator) - `lib/eventasaurus_app/workers/unsplash_refresh_worker.ex`
   - Acts as coordinator, queues individual city and country jobs
   - Runs on cron schedule: **Daily at 3 AM UTC**
   - Filters:
     - **Cities**: venue_count >= 3
     - **Countries**: Has at least 1 city
   - Queues both UnsplashCityRefreshWorker and UnsplashCountryRefreshWorker jobs

2. **UnsplashCityRefreshWorker** (Per-City) - `lib/eventasaurus_app/workers/unsplash_city_refresh_worker.ex`
   - Refreshes images for a single city
   - Fetches 5 categories: general, architecture, historic, old_town, city_landmarks
   - Checks staleness: Only refreshes if older than configured interval (default: 7 days)
   - **Config**: `UNSPLASH_CITY_REFRESH_DAYS` env var

3. **UnsplashCountryRefreshWorker** (Per-Country) - `lib/eventasaurus_app/workers/unsplash_country_refresh_worker.ex`
   - Refreshes images for a single country
   - Fetches 5 categories: general, architecture, historic, landmarks, nature
   - Checks staleness: Only refreshes if older than configured interval (default: 7 days)
   - **Config**: `UNSPLASH_COUNTRY_REFRESH_DAYS` env var

### Mix Tasks (For Development Testing)

1. **mix unsplash.fetch_category** - `lib/mix/tasks/unsplash.fetch_category.ex`
   - Fetch images for a specific city and category
   - Usage:
     ```bash
     mix unsplash.fetch_category Warsaw general
     mix unsplash.fetch_category Warsaw all  # Fetch all 5 categories
     ```
   - **Note**: Only works for cities, no country equivalent exists

### Current Manual Refresh UI

**Location**: `/admin/discovery` (Discovery Dashboard)
- Section: "City Maintenance" → "Refresh City Images"
- Button: "Refresh City Images Now"
- Handler: `handle_event("refresh_unsplash_images")` in `discovery_dashboard_live.ex:448`
- What it does:
  - Queues **UnsplashRefreshWorker** (coordinator)
  - Coordinator queues individual jobs for ALL cities (venue_count >= 3) AND ALL countries
  - **Problem**: No granular control, triggers everything at once

**Location**: `/admin/unsplash` (Unsplash Test Controller)
- Shows cached images for cities only (no countries)
- Has individual "Fetch All Categories" button per city
- Directly queues UnsplashCityRefreshWorker for that specific city
- **Problem**: City-only, no bulk operations, no countries

## What Needs To Be Done

### 1. Update `/admin/unsplash` Page

**Goal**: Centralize all Unsplash management with bulk refresh capabilities

**Required Changes**:

#### A. Controller Updates (`unsplash_test_controller.ex`)
- Add `fetch_countries_with_galleries/0` function (similar to cities)
- Add handler for bulk city refresh: `refresh_all_cities/2`
- Add handler for bulk country refresh: `refresh_all_countries/2`

#### B. Template Updates (`unsplash_test_html/index.html.heex`)
- Add countries section showing cached country galleries
- Add bulk refresh buttons:
  - **"Refresh All Cities"** button
    - Should queue UnsplashCityRefreshWorker for cities matching: `venue_count >= 3`
    - Shows count of cities that will be refreshed
  - **"Refresh All Countries"** button
    - Should queue UnsplashCountryRefreshWorker for all countries
    - Shows count of countries that will be refreshed
- Display last_refreshed_at for both cities and countries (already fixed in our workers)

#### C. Filtering Logic
- **Cities**: Only refresh cities with `venue_count >= 3` (matches coordinator logic)
- **Countries**: Refresh ALL countries that have at least 1 city
- Display counts: "Refresh All Cities (X cities)" / "Refresh All Countries (Y countries)"

### 2. Remove Old Button from `/admin/discovery`

**Location**: `discovery_dashboard_live.html.heex` lines 773-829

- Remove the entire "Refresh City Images" section
- Update link to `/admin/unsplash` in the header (line 22-26) to say "Manage Images" instead of "City Images"
- This reduces clutter and centralizes all Unsplash management

## Testing Plan for Development

### Pre-requisites

1. **Environment Variables Set**:
   ```bash
   export UNSPLASH_ACCESS_KEY="your_key_here"
   export UNSPLASH_CITY_REFRESH_DAYS=7
   export UNSPLASH_COUNTRY_REFRESH_DAYS=7
   ```

2. **Database has test data**:
   ```bash
   # Check cities with venues
   mix ecto.query "SELECT name, (SELECT COUNT(*) FROM venues WHERE city_id = cities.id) as venue_count FROM cities ORDER BY venue_count DESC LIMIT 10"

   # Check countries
   mix ecto.query "SELECT name, (SELECT COUNT(*) FROM cities WHERE country_id = countries.id) as city_count FROM countries ORDER BY city_count DESC LIMIT 10"
   ```

### Manual Testing Steps

#### 1. Test Individual City Refresh (Using Mix Task)
```bash
# Fetch all categories for a single city
mix unsplash.fetch_category Warsaw all

# Verify in database
mix ecto.query "SELECT name, unsplash_gallery->'categories' FROM cities WHERE name = 'Warsaw'"
```

#### 2. Test Bulk City Refresh (Using Updated `/admin/unsplash`)
1. Navigate to http://localhost:4000/admin/unsplash
2. Click "Refresh All Cities (X cities)" button
3. Check Oban dashboard at http://localhost:4000/admin/oban
   - Should see X jobs queued in `:unsplash` queue
   - Each job is `UnsplashCityRefreshWorker`
4. Watch logs for:
   ```
   🖼️  Unsplash City Refresh: Starting refresh for city_id=X
   🔄 Refreshing [City Name] - no gallery exists
   ✅ Successfully refreshed 5 categories with 50 images for [City Name]
   ```
5. Refresh page - should see last_refreshed_at updated for each city

#### 3. Test Bulk Country Refresh (Using Updated `/admin/unsplash`)
1. Navigate to http://localhost:4000/admin/unsplash
2. Click "Refresh All Countries (Y countries)" button
3. Check Oban dashboard
   - Should see Y jobs queued in `:unsplash` queue
   - Each job is `UnsplashCountryRefreshWorker`
4. Watch logs for:
   ```
   🖼️  Unsplash Country Refresh: Starting refresh for country_id=X
   🔄 Refreshing [Country Name] - no gallery exists
   ✅ Successfully refreshed 5 categories with 50 images for [Country Name]
   ```
5. Refresh page - should see countries with galleries displayed

#### 4. Test Staleness Check (Verify No Re-fetch)
1. After refreshing cities/countries, immediately click refresh button again
2. Check logs - should see:
   ```
   ⏭️  Skipping [Name] - images are fresh (0 days old, threshold: 7 days)
   ```
3. Verify in Oban - jobs complete immediately without API calls

#### 5. Test Coordinator (Scheduled Job)
```bash
# Manually trigger coordinator to test full flow
iex -S mix
iex> EventasaurusApp.Workers.UnsplashRefreshWorker.new(%{}) |> Oban.insert()
```
- Check Oban dashboard
- Should queue multiple jobs (cities + countries)
- Each city/country job runs independently

## Implementation Checklist

### Code Changes Required

- [ ] Update `lib/eventasaurus_web/controllers/admin/unsplash_test_controller.ex`:
  - [ ] Add `get_countries_with_galleries/0` private function
  - [ ] Add `enrich_country_data/1` for country galleries
  - [ ] Add `refresh_all_cities/2` handler
  - [ ] Add `refresh_all_countries/2` handler
  - [ ] Update `index/2` to pass countries to template

- [ ] Update `lib/eventasaurus_web/controllers/admin/unsplash_test_html/index.html.heex`:
  - [ ] Add "Refresh All Cities" button with count
  - [ ] Add "Refresh All Countries" button with count
  - [ ] Add countries section with gallery display
  - [ ] Show last_refreshed_at for both cities and countries

- [ ] Update `lib/eventasaurus_web/live/admin/discovery_dashboard_live.html.heex`:
  - [ ] Remove "Refresh City Images" section (lines 773-829)
  - [ ] Update header link text to "Manage Images"

### Testing Checklist

- [ ] Mix task works for single city: `mix unsplash.fetch_category Warsaw all`
- [ ] Bulk city refresh queues correct number of jobs
- [ ] Bulk country refresh queues correct number of jobs
- [ ] Staleness check prevents unnecessary refreshes
- [ ] Last_refreshed_at displays correctly for cities
- [ ] Last_refreshed_at displays correctly for countries
- [ ] Coordinator queues both city and country jobs
- [ ] Old button removed from discovery dashboard

## Expected Behavior After Implementation

### `/admin/unsplash` Page Will Show:

**Cities Section**:
- List of all cities with galleries (venue_count >= 3)
- Each city shows: name, category tabs, images, last_refreshed_at
- Button: **"Refresh All Cities (X cities)"**
  - Queues X jobs (one per city)
  - Only refreshes if images are stale (>7 days old)

**Countries Section**:
- List of all countries with galleries
- Each country shows: name, category tabs, images, last_refreshed_at
- Button: **"Refresh All Countries (Y countries)"**
  - Queues Y jobs (one per country)
  - Only refreshes if images are stale (>7 days old)

### `/admin/discovery` Page Will Show:
- **Removed**: "Refresh City Images" section
- Link to `/admin/unsplash` remains in header as "Manage Images"

## Rate Limiting Considerations

- Unsplash API limit: **5000 requests/hour**
- Each city refresh: ~5 API calls (one per category)
- Each country refresh: ~5 API calls (one per category)
- Oban `:unsplash` queue concurrency: **3** (configurable)
- With staleness checking: **~85% reduction** in actual API calls

**Example calculation**:
- 50 cities + 20 countries = 70 locations
- Without staleness: 70 × 5 = 350 API calls
- With staleness (7-day interval): ~50 API calls on average
- Well under 5000/hour limit

## Environment Variables

```bash
# Required
UNSPLASH_ACCESS_KEY=your_key_here

# Optional (defaults shown)
UNSPLASH_CITY_REFRESH_DAYS=7      # Refresh cities every 7 days
UNSPLASH_COUNTRY_REFRESH_DAYS=7   # Refresh countries every 7 days
```

## Files to Review

1. **Workers**:
   - `lib/eventasaurus_app/workers/unsplash_refresh_worker.ex`
   - `lib/eventasaurus_app/workers/unsplash_city_refresh_worker.ex` ✅ FIXED (Enum.min bug)
   - `lib/eventasaurus_app/workers/unsplash_country_refresh_worker.ex` ✅ FIXED (Enum.min bug)

2. **Controllers**:
   - `lib/eventasaurus_web/controllers/admin/unsplash_test_controller.ex`
   - `lib/eventasaurus_web/controllers/admin/unsplash_test_html.ex`

3. **Templates**:
   - `lib/eventasaurus_web/controllers/admin/unsplash_test_html/index.html.heex`
   - `lib/eventasaurus_web/live/admin/city_index_live.html.heex` ✅ FIXED (template bugs)

4. **Mix Tasks**:
   - `lib/mix/tasks/unsplash.fetch_category.ex`

5. **Config**:
   - `config/config.exs` ✅ UPDATED (env vars)
   - `config/runtime.exs` ✅ UPDATED (env vars)

## Summary

The system is already **95% complete**. We just need to:
1. Add bulk refresh buttons to `/admin/unsplash` page
2. Add countries display to `/admin/unsplash` page
3. Remove old button from `/admin/discovery` page

The workers are already fixed and working correctly with staleness checking. The coordinator already schedules daily refreshes. We just need better manual testing UI in development.
