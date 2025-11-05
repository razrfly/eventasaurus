# Issue: VenueNameValidator uses HERE API addresses when resultType is "houseNumber"

## Problem Summary

Event URL slugs contain full addresses instead of venue names when HERE geocoding API returns `resultType: "houseNumber"`.

**Example:**
- **Bad URL**: `http://localhost:4000/activities/geeks-who-drink-trivia-at-origins-bar-266-s-downing-st-co-80209-251106`
- **Expected URL**: `http://localhost:4000/activities/geeks-who-drink-trivia-at-origins-bar-denver-251106`

**Database Issue:**
- **Venue ID 345 Name**: `"266 S Downing St, Denver, CO 80209-2433, United States"` ❌ (address)
- **Venue ID 409 Name**: `"Otto Pint Fort Collins"` ✅ (business name)

## Root Cause: HERE API Result Type

### The Real Problem

HERE geocoding API returns **two different types of results**:

1. ✅ **`resultType: "place"`** - HERE found a POI/business in their database
   - `title` field contains: Business name (e.g., "Mighty River Brewing")
   - **These work perfectly!**

2. ❌ **`resultType: "houseNumber"`** - HERE only found a street address, no POI
   - `title` field contains: Formatted address (e.g., "266 S Downing St, Denver, CO 80209-2433, United States")
   - **VenueNameValidator uses this address as the venue name!**

### Evidence from Database

```sql
SELECT id, name, source,
       metadata->'geocoding'->'raw_response'->>'resultType' as result_type,
       metadata->'geocoding'->'raw_response'->>'title' as geocoded_title
FROM venues
WHERE source = 'here'
ORDER BY id DESC LIMIT 10;
```

**Results:**

| ID  | Name | Source | Result Type | Geocoded Title |
|-----|------|--------|-------------|----------------|
| 406 | Mighty River Brewing | here | **place** | ✅ Business name |
| 404 | 330 N Cleveland Ave, Loveland, CO 80537... | here | **houseNumber** | ❌ Address |
| 403 | MeadKrieger Meadery | here | **place** | ✅ Business name |
| 398 | Snowpack Taproom | here | **place** | ✅ Business name |
| 345 | 266 S Downing St, Denver, CO 80209... | here | **houseNumber** | ❌ Address |

**Pattern:**
- `resultType: "place"` → Good venue names (9 out of 11 HERE venues)
- `resultType: "houseNumber"` → Addresses used as names (2 out of 11 HERE venues)

### Why Most Venues Work

**Most Geeks Who Drink venues have good names because:**

1. **HERE API found them as POIs** (most common)
   - Large/popular venues are in HERE's business database
   - Returns `resultType: "place"` with business name

2. **Mapbox geocoded them instead** (second most common)
   - Mapbox has different (sometimes better) POI coverage
   - Mapbox doesn't have this two-type issue

3. **OpenStreetMap geocoded them** (less common)
   - OSM has community-contributed POI data
   - Also doesn't have this issue

**The bad venues fail because:**
- Smaller/newer venues not in HERE's POI database
- Origins Bar (ID 345) - small neighborhood bar
- 330 N Cleveland Ave venue (ID 404) - unknown business
- HERE falls back to address geocoding → `resultType: "houseNumber"`
- VenueNameValidator compares scraped name to address → low similarity → uses address

## The Bug Flow

### What Should Happen (Venue ID 406 - Mighty River Brewing)

1. **Scraper** extracts: `title: "Geeks Who Drink Trivia at Mighty River Brewing"`
2. **VenueProcessor** geocodes address via HERE API
3. **HERE API** returns:
   ```json
   {
     "title": "Mighty River Brewing",
     "resultType": "place"
   }
   ```
4. **VenueNameValidator** compares:
   - Scraped: "Geeks Who Drink Trivia at Mighty River Brewing"
   - Geocoded: "Mighty River Brewing"
   - Similarity: High (venue name is in scraped title)
5. **Result**: Venue created with name `"Mighty River Brewing"` ✅

### What Actually Happens (Venue ID 345 - Origins Bar)

1. **Scraper** extracts: `title: "Geeks Who Drink Trivia at Origins Bar (Wash Park)"`
2. **VenueProcessor** geocodes address via HERE API
3. **HERE API** can't find POI, returns:
   ```json
   {
     "title": "266 S Downing St, Denver, CO 80209-2433, United States",
     "resultType": "houseNumber"
   }
   ```
4. **VenueNameValidator** compares:
   - Scraped: "Geeks Who Drink Trivia at Origins Bar (Wash Park)"
   - Geocoded: "266 S Downing St, Denver, CO 80209-2433, United States"
   - Similarity: Very low (0.1 or less)
5. **VenueNameValidator** logic:
   ```elixir
   {:ok, chosen_name, :geocoded_low_similarity, similarity} ->
     Logger.warning("🔴 Replacing bad venue name...")
     chosen_name  # Returns the address!
   ```
6. **Result**: Venue created with name `"266 S Downing St, Denver, CO 80209-2433, United States"` ❌

## The Fix

### Solution: Skip HERE Provider When No POI Found

Instead of accepting addresses and detecting them later, we make the HERE provider itself reject `resultType: "houseNumber"` results. This allows the orchestrator to try other providers (Mapbox, Geoapify, etc.) that might have the POI in their database.

**Why This Approach?**
- Simpler: One provider check instead of complex address pattern detection
- Better Results: Other providers get a chance to find the POI
- Cleaner Architecture: Each provider determines what counts as a quality result
- No False Positives: We're using HERE's explicit signal instead of pattern matching

**Implementation in `here.ex`**:

```elixir
defp extract_result(item) do
  # Extract coordinates from position
  position = get_in(item, ["position"])
  lat = get_in(position, ["lat"])
  lng = get_in(position, ["lng"])

  # Extract address components
  address = get_in(item, ["address"]) || %{}

  # Extract result type - "place" means POI found, "houseNumber" means address only
  result_type = Map.get(item, "resultType")

  # Try multiple fields for city
  city =
    Map.get(address, "city") ||
      Map.get(address, "district") ||
      Map.get(address, "county")

  country = Map.get(address, "countryName")
  formatted_address = Map.get(address, "label")

  place_id =
    case Map.get(item, "id") do
      nil -> nil
      id when is_integer(id) -> Integer.to_string(id)
      id when is_binary(id) -> id
      other -> to_string(other)
    end

  cond do
    is_nil(lat) or is_nil(lng) ->
      Logger.warning("⚠️ HERE: missing coordinates in response")
      {:error, :invalid_response}

    not is_number(lat) or not is_number(lng) ->
      Logger.warning("⚠️ HERE: invalid coordinate types")
      {:error, :invalid_response}

    is_nil(city) ->
      Logger.warning("⚠️ HERE: could not extract city. Address: #{inspect(address)}")
      {:error, :no_city_found}

    # NEW: Reject houseNumber results - these are addresses, not POIs
    # This allows the orchestrator to try other providers that might have the POI
    result_type == "houseNumber" ->
      Logger.info(
        "📍 HERE: skipping houseNumber result (address only, not a POI). " <>
        "Title: '#{Map.get(item, "title")}'. Orchestrator will try next provider."
      )
      {:error, :no_poi_found}

    true ->
      {:ok,
       %{
         latitude: lat * 1.0,
         longitude: lng * 1.0,
         city: city,
         country: country || "Unknown",
         address: formatted_address,
         provider_id: place_id,
         place_id: place_id,
         raw_response: item
       }}
  end
end
```

### Why This Works

1. **Provider-Level Quality Check**: HERE checks its own `resultType` before returning success
   - When `resultType == "houseNumber"`, HERE returns `{:error, :no_poi_found}`
   - Orchestrator automatically tries next provider (Mapbox, Geoapify, etc.)
   - Other providers might have the POI that HERE doesn't

2. **Preserves Good Behavior**:
   - `resultType: "place"` → HERE succeeds normally, returns business name
   - Other providers → Work exactly as before, unaffected by this change
   - No false positives - using HERE's explicit signal, not pattern matching

3. **Graceful Degradation**:
   - If all providers fail → Falls back to scraped name (existing behavior)
   - If any provider finds POI → Uses that provider's result
   - Most Geeks Who Drink venues already work (9/11 have POI in HERE)

## Affected Venues

Current venues with addresses as names (need data cleanup):

```sql
SELECT id, name, slug
FROM venues
WHERE source = 'here'
  AND metadata->'geocoding'->'raw_response'->>'resultType' = 'houseNumber';
```

**Results:**
- Venue ID 345: "266 S Downing St, Denver, CO 80209-2433, United States"
- Venue ID 404: "330 N Cleveland Ave, Loveland, CO 80537-5506, United States"

Both are Geeks Who Drink venues.

## Implementation Plan

### Phase 0: CRITICAL FIX (1-2 hours)

1. ✅ Implement `resultType` check in HERE provider's `extract_result/1`
2. 🔴 Add unit tests:
   ```elixir
   # Should reject HERE houseNumber results
   test "rejects houseNumber results to try other providers" do
     item = %{
       "position" => %{"lat" => 39.7, "lng" => -105.0},
       "address" => %{"city" => "Denver", "countryName" => "USA"},
       "resultType" => "houseNumber",
       "title" => "266 S Downing St, Denver, CO 80209"
     }
     assert Here.extract_result(item) == {:error, :no_poi_found}
   end

   # Should accept HERE place results
   test "accepts place results with POI" do
     item = %{
       "position" => %{"lat" => 39.7, "lng" => -105.0},
       "address" => %{"city" => "Denver", "countryName" => "USA"},
       "resultType" => "place",
       "title" => "Mighty River Brewing"
     }
     {:ok, result} = Here.extract_result(item)
     assert result.latitude == 39.7
   end
   ```
3. 🔴 Deploy immediately
4. 🔴 Re-scrape Geeks Who Drink (existing bad venues will be fixed automatically)

**Impact**:
- HERE will skip venues not in their POI database
- Orchestrator tries next provider (Mapbox, Geoapify, etc.)
- Better chance of finding venue name from alternative sources
- Existing bad data cleaned on next scrape

### Phase 1: Monitoring (Ongoing)

1. 📊 Monitor orchestrator logs for:
   - Frequency of `HERE: skipping houseNumber result`
   - Which providers succeed after HERE fails
   - Pattern: HERE → Mapbox success, HERE → all fail, etc.

2. 📊 Track provider success rates:
   - HERE place results (should remain ~82% for Geeks Who Drink)
   - Fallback provider success after HERE houseNumber
   - Overall venue name quality improvement

3. 📊 Alert if HERE rejection rate increases significantly (>20%)

**Impact**: Early detection of provider coverage changes or new venue types

## Testing Strategy

### Unit Tests

```elixir
defmodule EventasaurusDiscovery.Geocoding.Providers.HereTest do
  describe "extract_result/1" do
    test "rejects houseNumber results" do
      item = %{
        "position" => %{"lat" => 39.7, "lng" => -105.0},
        "address" => %{"city" => "Denver", "countryName" => "USA"},
        "resultType" => "houseNumber",
        "title" => "266 S Downing St, Denver, CO 80209"
      }

      assert Here.extract_result(item) == {:error, :no_poi_found}
    end

    test "accepts place results" do
      item = %{
        "position" => %{"lat" => 39.7, "lng" => -105.0},
        "address" => %{"city" => "Denver", "countryName" => "USA"},
        "resultType" => "place",
        "title" => "Mighty River Brewing",
        "id" => "here:pds:place:123abc"
      }

      {:ok, result} = Here.extract_result(item)
      assert result.latitude == 39.7
      assert result.city == "Denver"
    end

    test "accepts street results (not houseNumber)" do
      # street results are still acceptable (they're not addresses)
      item = %{
        "position" => %{"lat" => 39.7, "lng" => -105.0},
        "address" => %{"city" => "Denver", "countryName" => "USA"},
        "resultType" => "street",
        "title" => "Main Street"
      }

      {:ok, result} = Here.extract_result(item)
      assert result.latitude == 39.7
    end
  end
end
```

### Integration Tests

1. Mock HERE API with `houseNumber` response
2. Verify orchestrator tries next provider
3. Mock Mapbox success after HERE failure
4. Verify venue gets correct name from Mapbox

### Manual Testing

1. Re-scrape Geeks Who Drink venues
2. Check logs for "skipping houseNumber result" messages
3. Verify venue ID 345 (Origins Bar) and 404 now have correct names
4. Check event URLs no longer contain addresses

## Related Files

- `lib/eventasaurus_discovery/geocoding/providers/here.ex:118-190` - ✅ Modified `extract_result/1` to reject houseNumber
- `lib/eventasaurus_discovery/geocoding/orchestrator.ex` - Fallback chain logic (no changes needed)
- `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex:619-693` - Venue creation (no changes needed)
- `lib/eventasaurus_discovery/validation/venue_name_validator.ex` - Name comparison (no changes needed)

## Success Metrics

After implementation:
- ✅ 0 new venues created with address names
- ✅ Existing 2 bad venues cleaned up
- ✅ Event URLs all contain venue names, not addresses
- ✅ HERE `resultType: houseNumber` correctly detected and rejected
- ✅ Logs show clear reasoning for name choices

## Additional Context

### HERE API Documentation

From HERE Geocoding API docs:
- `resultType: "place"` - A defined place, like a landmark, POI, or building
- `resultType: "houseNumber"` - A street address with a specific house number
- `resultType: "street"` - A street without a specific house number

**Key insight**: When HERE can't find a business/POI, it falls back to `houseNumber` and returns the formatted address as the `title`. This is expected API behavior, but our validator needs to handle it.

### Why This Affects Geeks Who Drink

Geeks Who Drink events are at many small neighborhood bars that aren't in geocoding POI databases. These venues work fine for human readers but aren't registered businesses in mapping databases, causing HERE to fall back to address geocoding.

**Examples of venues likely to have this issue:**
- Small neighborhood bars
- Pop-up venues
- Venues in residential areas
- Newer businesses (< 1 year old)
- Venues that don't appear on Google Maps business listings
