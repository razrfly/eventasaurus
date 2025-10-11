# Issue: QuestionOne Scraper Failures After Phase 1 Geocoding Fixes

**Status**: 🚨 CRITICAL - Multiple root causes identified
**Created**: 2025-10-11
**Related**: Issue #1643 (Phase 1 implementation)

## Executive Summary

After implementing Phase 1 fixes for OpenStreetMap failures, QuestionOne scraper is still experiencing significant failures:

- **Current State**: 21 jobs failing (12 retryable + 9 discarded) out of 130 total (16% failure rate)
- **Success Rate**: 43 completed successfully (33%)
- **In Progress**: 66 jobs still being processed

## Root Cause Analysis

### Issue 1: OpenStreetMap GenServer Timeouts (CRITICAL - 68% of failures)

**Frequency**: 19 out of 28 failed jobs (68%)

**Symptom**:
```
** (EXIT) time out
GenServer.call(#PID<0.453.0>, {:geocode, [store: true, address: "..."]}, 5000)
```

**Root Cause**:
The `geocoder` library's poolboy worker pool has a hardcoded **5-second timeout**. When OpenStreetMap Nominatim is slow or rate-limited, the GenServer times out BEFORE our retry logic even gets a chance to run.

**Code Flow**:
1. `AddressGeocoder.geocode_address/1` calls `try_openstreetmaps_with_retry/2`
2. `try_openstreetmaps_with_retry/2` calls `Geocoder.call(address)`
3. `Geocoder.call/2` internally uses poolboy with 5-second timeout
4. If OSM takes >5s, poolboy GenServer times out
5. Our rescue block in `try_openstreetmaps/1` (line 74-82) catches this as a crash
6. BUT the rescue block only catches `Jason.DecodeError`, NOT GenServer timeout exits!
7. The timeout bubbles up as an uncaught exception, crashing the entire job

**Why Phase 1 Didn't Fix This**:
- Phase 1 added retry logic for `Jason.DecodeError` when OSM returns HTML
- Phase 1 added exponential backoff for `:osm_rate_limited` errors
- BUT Phase 1 did NOT handle GenServer timeout exits that occur when OSM is simply too slow

**Evidence**:
- All 19 timeout failures show the same pattern
- Stack trace shows timeout in `address_geocoder.ex:66` (inside `try_openstreetmaps/1`)
- Timeout occurs BEFORE Google fallback can be triggered

**Failed Addresses (Sample)**:
- "45 Trinity Gardens, England SW9 8DR, United Kingdom"
- "16 Blackheath Village, England SE3 9LE, United Kingdom"
- "290 Westferry Road, London England E14 3AG, United Kingdom"
- "16 Saint Peter's Street, St Albans England AL1 3NA, United Kingdom"
- "9 Greater, London England W4 4PH, United Kingdom"

---

### Issue 2: Fake Cities Created from Street Addresses (CRITICAL - 50% of cities are fake)

**Frequency**: 23 out of 41 cities are invalid (56% of total cities)

**Symptom**:
Cities table contains completely invalid entries that are actually street addresses:
- "3-4 Moulsham St" (slug: `3-4-moulsham-st`)
- "10 Peas Hill" (slug: `10-peas-hill`)
- "200 Grafton Gate" (slug: `200-grafton-gate`)
- "76-78 Fore St" (slug: `76-78-fore-st`)
- "9 Crutched Friars" (slug: `9-crutched-friars`)
- "Ickenham Rd" (slug: `ickenham-rd`)

These are STREET ADDRESSES, not city names!

**Root Cause**:
The `AddressGeocoder.extract_location_data/2` function (lines 104-151) has overly aggressive fallback logic that treats ANY non-nil value as a valid city name.

**Code Flow Analysis**:
```elixir
# lib/eventasaurus_discovery/helpers/address_geocoder.ex:113-125
city =
  Map.get(location, :city) ||
    Map.get(location, "city") ||
    Map.get(location, :town) ||
    Map.get(location, "town") ||
    Map.get(location, :village) ||
    Map.get(location, "village") ||
    Map.get(location, :municipality) ||
    Map.get(location, "municipality") ||
    Map.get(location, :locality) ||
    Map.get(location, "locality") ||
    # Fallback: extract from formatted address
    extract_city_from_formatted(Map.get(location, :formatted_address) || Map.get(location, "formatted_address"))
```

**The Problem**:
When OpenStreetMap/Google Maps returns a location response, it includes MANY fields:
- `:road` (e.g., "3-4 Moulsham St")
- `:house_number` (e.g., "76-78")
- `:street` (e.g., "Ickenham Rd")
- `:locality` (e.g., "Bethnal Green" - which IS a locality but NOT a city)
- `:neighbourhood` (e.g., "Muswell Hill")
- `:suburb` (e.g., "Parkstone")

The current code checks for `:locality`, which in geocoding APIs means "any named area" - this includes:
- Neighborhoods (Bethnal Green)
- Suburbs (Parkstone)
- Street addresses (when no better data exists)

**Why This Happens**:
1. Geocoding services return structured data with multiple address components
2. When a proper `:city` field is missing, we fall back to `:locality`
3. `:locality` can contain street addresses, neighborhoods, or suburbs
4. No validation ensures the value is actually a city name
5. These fake city names are then inserted into the `cities` table
6. Events get associated with these fake cities
7. URLs like `/c/3-4-moulsham-st/trivia/question-one` are generated

**Real-World Example**:
```
Address: "3-4 Moulsham St, Chelmsford, England, CM2 0HU"
OSM Response:
  :road => "3-4 Moulsham St"
  :locality => "3-4 Moulsham St"  # ← THIS is being used as city!
  :city => nil
  :town => "Chelmsford"  # ← THIS is the actual city!
  :country => "United Kingdom"
```

Current code flow:
1. Check `:city` → nil
2. Check `:town` → "Chelmsham" ← **WE SHOULD STOP HERE!**
3. BUT if town is also missing in some responses:
4. Check `:locality` → "3-4 Moulsham St" ← Uses street address as city!

**Impact**:
- 23 fake cities created in last run (56% of all cities)
- Events are categorized under nonsensical city names
- City browsing pages show street addresses instead of cities
- SEO and user experience completely broken

---

### Issue 3: All Events Failed (21% of failures)

**Frequency**: 6 out of 28 failed jobs (21%)

**Symptom**:
```
** (Oban.PerformError) ... failed with {:error, :all_events_failed}
```

**Root Cause**:
This error comes from `EventasaurusDiscovery.Sources.Processor.process_source_data/2` (line 65) when every single event extracted from a venue page fails to process.

**Code Flow**:
1. VenueDetailJob successfully fetches venue page HTML
2. VenueExtractor extracts event data
3. AddressGeocoder enriches with city/country (may succeed or use fake city)
4. EventProcessor tries to create/update each event
5. ALL events fail for unknown reasons
6. Processor returns `{:error, :all_events_failed}`

**Why This Happens**:
Events can fail for many reasons:
- Database constraint violations (duplicate keys, null constraints)
- Validation failures (invalid dates, missing required fields)
- Relationship failures (venue or performer creation failed)
- Data quality issues (malformed event data from scraping)

**Affected Venues** (Sample):
- "pub-quiz-royal-oak-bethnal-green-wednesdays"
- "pub-quiz-three-johns-angel-mondays"
- "pub-quiz-royal-oak-twickenham-every-thursday"
- "pub-quiz-the-new-inn-richmond"
- "pub-quiz-skimmington-castle-reigate-wednesdays"

**Hypothesis**:
These venues likely have:
1. Multiple recurring events (weekly pub quizzes)
2. Complex recurrence rules
3. Edge cases in date parsing or timezone handling
4. Issues with duplicate detection logic

**Evidence Needed**:
- Scrape one of these URLs manually
- Check what event data is extracted
- See where EventProcessor fails
- Check database logs for constraint violations

---

### Issue 4: Protocol Error - Enumerable Not Implemented for nil (4% of failures)

**Frequency**: 1 out of 28 failed jobs (4%)

**Symptom**:
```
** (Protocol.UndefinedError) protocol Enumerable not implemented for type Atom
Got value: nil
(eventasaurus 0.1.0) lib/eventasaurus_discovery/scraping/processors/event_processor.ex:1317
```

**Root Cause**:
Code at `event_processor.ex:1317` expects a list/enumerable but receives `nil`.

**Code Context**:
```elixir
# Line 1317 is in add_occurrence_to_event/2
# This function adds a new occurrence to an event's occurrences list
# Something is passing nil where a list is expected
```

**Impact**:
Very rare (1 occurrence) but indicates a data quality issue where expected fields are missing.

---

### Issue 5: Other Errors (7% of failures)

**Frequency**: 2 out of 28 failed jobs (7%)

**Details**: Need to investigate these individually - likely edge cases or data quality issues.

---

## Failure Distribution

| Error Type | Count | Percentage | Severity |
|------------|-------|------------|----------|
| GenServer Timeout | 19 | 68% | 🚨 CRITICAL |
| Fake Cities | 23 | 56% of cities | 🚨 CRITICAL |
| All Events Failed | 6 | 21% | ⚠️ HIGH |
| Protocol Error | 1 | 4% | 🔔 MEDIUM |
| Other | 2 | 7% | 🔔 MEDIUM |

---

## Why Phase 1 Didn't Solve This

**What Phase 1 Fixed**:
✅ Config for Google Maps API key
✅ Rescue blocks for `Jason.DecodeError` when OSM returns HTML
✅ Retry logic with exponential backoff for `:osm_rate_limited`
✅ Google fallback when OSM explicitly fails

**What Phase 1 MISSED**:
❌ GenServer timeout exits from poolboy (not caught by rescue block)
❌ Validation of city names to prevent fake cities
❌ Preference for `:town` over `:locality` when both exist
❌ Fallback when Google Maps also times out or fails
❌ Event processing failures downstream of geocoding

---

## Impact Assessment

### User-Facing Impact (CRITICAL)
- **City Browse Pages**: Show street addresses like "3-4 Moulsham St" instead of real cities
- **URLs**: Generate nonsensical URLs like `/c/3-4-moulsham-st/trivia/question-one`
- **Event Discovery**: Users cannot find events by city because cities are wrong
- **SEO**: Search engines index pages with fake city names
- **Data Integrity**: 56% of cities in database are invalid

### Operational Impact (HIGH)
- **Failure Rate**: 16% of jobs failing (21 out of 130)
- **Job Retries**: Wasting Oban queue capacity on doomed retries
- **Database Pollution**: 23 fake city records need cleanup
- **Google Maps Costs**: Not falling back to Google when we should be

### Data Quality Impact (CRITICAL)
- **Events**: Associated with wrong cities, affecting categorization
- **Venues**: May have incorrect city associations
- **Analytics**: City-based metrics are completely invalid

---

## Proposed Solutions

### Fix 1: Handle GenServer Timeouts (CRITICAL - Fixes 68% of failures)

**Problem**: Poolboy GenServer times out before our retry logic runs.

**Solution**: Wrap the `Geocoder.call/2` in a try/catch block to handle timeout exits.

**Implementation**:
```elixir
# In try_openstreetmaps/1
defp try_openstreetmaps(address) do
  Logger.debug("Geocoding with OpenStreetMaps: #{address}")

  try do
    case Geocoder.call(address) do
      {:ok, coordinates} ->
        extract_location_data(coordinates, "OpenStreetMaps")

      {:error, reason} ->
        Logger.debug("OpenStreetMaps failed: #{inspect(reason)}")
        {:error, :osm_failed}
    end
  catch
    # Catch GenServer timeout exits from poolboy
    :exit, {:timeout, _} ->
      Logger.warning("⏱️ OSM GenServer timeout for: #{address}")
      {:error, :osm_timeout}

    :exit, reason ->
      Logger.error("❌ OSM exited with reason: #{inspect(reason)}")
      {:error, :osm_crashed}
  rescue
    Jason.DecodeError ->
      Logger.warning("⚠️ OSM returned HTML instead of JSON for: #{address} (likely rate limited)")
      {:error, :osm_rate_limited}

    error ->
      Logger.error("❌ OSM unexpected error for #{address}: #{inspect(error)}")
      {:error, :osm_failed}
  end
end

# Update retry logic to handle timeout
defp try_openstreetmaps_with_retry(address, attempts_left \\ 3) do
  case try_openstreetmaps(address) do
    {:ok, result} ->
      {:ok, result}

    # Retry on rate limiting AND timeouts
    {:error, reason} when reason in [:osm_rate_limited, :osm_timeout] and attempts_left > 1 ->
      backoff_ms = (4 - attempts_left) * 1000
      Logger.info("🔄 Retrying OSM after #{backoff_ms}ms (#{attempts_left - 1} attempts left)")
      Process.sleep(backoff_ms)
      try_openstreetmaps_with_retry(address, attempts_left - 1)

    {:error, reason} ->
      Logger.debug("❌ OSM failed after retries: #{inspect(reason)}")
      {:error, reason}
  end
end
```

**Expected Impact**:
- Fix 19 out of 21 failures (90% reduction)
- Jobs will retry OSM on timeout, then fall back to Google
- Success rate should increase from 33% to >90%

---

### Fix 2: Validate City Names and Prefer :town over :locality (CRITICAL - Fixes fake cities)

**Problem**: Using `:locality` field captures street addresses as city names.

**Solution**:
1. Prioritize `:town` field over `:locality`
2. Validate city names against known patterns
3. Reject obvious street addresses

**Implementation**:
```elixir
# In extract_location_data/2
defp extract_location_data(coordinates, provider) do
  location = coordinates.location || %{}

  lat = coordinates.lat
  lon = coordinates.lon

  # Extract city with proper priority and validation
  city =
    Map.get(location, :city) ||
      Map.get(location, "city") ||
      Map.get(location, :town) ||  # PRIORITIZE TOWN
      Map.get(location, "town") ||
      Map.get(location, :village) ||
      Map.get(location, "village") ||
      Map.get(location, :municipality) ||
      Map.get(location, "municipality") ||
      # Only use locality as LAST resort and validate it
      validate_city_name(Map.get(location, :locality) || Map.get(location, "locality")) ||
      # Final fallback to formatted address
      extract_city_from_formatted(
        Map.get(location, :formatted_address) || Map.get(location, "formatted_address")
      )

  # Extract country
  country =
    Map.get(location, :country) ||
      Map.get(location, "country") ||
      Map.get(location, :country_name) ||
      Map.get(location, "country_name") ||
      "Unknown"

  case {city, lat, lon} do
    {nil, _, _} ->
      Logger.warning(
        "No city found in #{provider} response for coordinates #{lat}, #{lon}. Location: #{inspect(location)}"
      )
      {:error, :no_city_found}

    {city, lat, lon} when is_binary(city) and is_float(lat) and is_float(lon) ->
      Logger.info("✅ Geocoded via #{provider}: #{city}, #{country} (#{lat}, #{lon})")
      {:ok, {city, country, {lat, lon}}}

    _ ->
      Logger.warning("Invalid data from #{provider}: #{inspect({city, lat, lon})}")
      {:error, :invalid_response}
  end
end

# NEW: Validate city names to reject street addresses
defp validate_city_name(nil), do: nil

defp validate_city_name(name) when is_binary(name) do
  # Reject if it looks like a street address
  cond do
    # Contains house numbers like "3-4 Moulsham St" or "76-78 Fore St"
    Regex.match?(~r/^\d+-?\d*\s+/, name) ->
      Logger.debug("Rejecting locality '#{name}' - looks like street address with number")
      nil

    # Contains "St", "Rd", "Ave", "Lane" etc - likely a street
    Regex.match?(~r/\b(St|Rd|Ave|Lane|Road|Street|Drive|Way|Court|Pl|Place|Cres|Crescent)\b/i, name) ->
      Logger.debug("Rejecting locality '#{name}' - contains street suffix")
      nil

    # Too short (less than 3 chars) - likely abbreviation or invalid
    String.length(name) < 3 ->
      Logger.debug("Rejecting locality '#{name}' - too short")
      nil

    # Looks valid
    true ->
      name
  end
end
```

**Expected Impact**:
- Prevent creation of fake city records
- Existing 23 fake cities need manual cleanup
- Future runs will use proper city names
- URLs and city browse pages will be correct

---

### Fix 3: Add Logging for :all_events_failed Cases (HIGH)

**Problem**: Don't know WHY all events failed for these venues.

**Solution**: Add detailed logging before returning `:all_events_failed` error.

**Implementation**:
```elixir
# In EventasaurusDiscovery.Sources.Processor.process_source_data/2
case {successful, failed} do
  {[], [_ | _] = failed} ->
    # All events failed - log detailed error info
    Logger.error("All #{length(failed)} events failed processing")

    # Log each failure reason
    Enum.each(failed, fn {:error, reason} ->
      Logger.error("  - Event failed: #{inspect(reason)}")
    end)

    {:error, :all_events_failed}

  # ... rest of function
end
```

**Expected Impact**:
- Identify root causes for the 6 `:all_events_failed` cases
- Enable targeted fixes for event processing issues

---

### Fix 4: Database Cleanup Task (REQUIRED)

**Problem**: 23 fake cities in database need removal.

**Solution**: Create migration or manual cleanup script.

**SQL to identify fake cities**:
```sql
-- Find cities that look like street addresses
SELECT id, name, slug
FROM cities
WHERE
  -- Contains house numbers
  name ~ '^\d+-?\d*\s+'
  -- Contains street suffixes
  OR name ~* '\b(St|Rd|Ave|Lane|Road|Street|Drive|Way|Court|Pl|Place|Cres|Crescent)\b'
  -- Too short
  OR length(name) < 3
ORDER BY id;
```

**Cleanup Process**:
1. Identify all fake cities
2. Find events associated with these cities
3. Re-geocode those venue addresses properly
4. Update events with correct cities
5. Delete fake city records
6. Verify no broken foreign key references

---

## Implementation Priority

### Phase 2A: Critical Fixes (IMMEDIATE)

**Fixes 90% of current failures**

1. ✅ **GenServer Timeout Handling** - Fixes 68% of failures
   - Add try/catch around `Geocoder.call/2`
   - Retry on timeout
   - Fallback to Google after retries

2. ✅ **City Name Validation** - Fixes 56% of fake cities
   - Add `validate_city_name/1` function
   - Prioritize `:town` over `:locality`
   - Reject street addresses

3. ✅ **Enhanced Logging** - Diagnose remaining issues
   - Log all event processing failures
   - Capture failure reasons for analysis

**Estimated Effort**: 2-3 hours
**Risk**: LOW - Additive changes, no breaking modifications
**Testing**: Requeue failed jobs and monitor success rate

---

### Phase 2B: Database Cleanup (REQUIRED)

**Clean up data pollution**

1. ✅ **Identify Fake Cities** - Query existing database
2. ✅ **Re-geocode Affected Venues** - Get proper city names
3. ✅ **Update Event Associations** - Fix foreign keys
4. ✅ **Delete Fake Cities** - Remove invalid records

**Estimated Effort**: 1-2 hours
**Risk**: MEDIUM - Data migration, needs careful verification
**Testing**: Verify no broken references after cleanup

---

### Phase 2C: Long-term Improvements (DEFERRED)

**Improvements for Phase 3**

1. ⏳ **Geocoding Cache** - Reduce API calls
2. ⏳ **Cost Tracking Dashboard** - Monitor spending
3. ⏳ **Batch Geocoding** - Process multiple addresses efficiently
4. ⏳ **City Lookup Service** - Pre-validation against known cities

---

## Testing Strategy

### Unit Tests
- Test `validate_city_name/1` with various inputs:
  - Valid cities: "London", "Cambridge", "San Francisco"
  - Street addresses: "3-4 Moulsham St", "76-78 Fore St"
  - Edge cases: "St Albans" (valid city with "St"), "St"

### Integration Tests
- Test full geocoding flow with timeout simulation
- Test retry logic with mocked OSM failures
- Test Google fallback activation

### Manual Testing
1. Requeue all 21 failed jobs
2. Monitor success rate over 10 minutes
3. Check no new fake cities created
4. Verify Google Maps fallback is used when needed

---

## Success Criteria

**Phase 2A Success**:
- ✅ Job success rate >90% (currently 33%)
- ✅ No GenServer timeout failures in logs
- ✅ No new fake cities created
- ✅ Google Maps fallback working correctly

**Phase 2B Success**:
- ✅ All 23 fake cities removed from database
- ✅ All events associated with correct cities
- ✅ No broken foreign key references
- ✅ City browse pages show only valid cities

---

## Related Issues

- Issue #1643: Phase 1 Geocoding Implementation
- (New issue needed): Database cleanup task

---

## Notes

- OSM Nominatim rate limit is 1 req/sec
- Google Maps Geocoding API costs $5 per 1,000 requests
- Current QuestionOne job volume: ~130 venues per scrape
- Expected Google fallback usage: 10-20% of requests (after fixes)

---

## Appendix: Failed Job Details

### All GenServer Timeout Addresses
1. "45 Trinity Gardens, England SW9 8DR, United Kingdom"
2. "16 Blackheath Village, England SE3 9LE, United Kingdom"
3. "290 Westferry Road, London England E14 3AG, United Kingdom"
4. "16 Saint Peter's Street, St Albans England AL1 3NA, United Kingdom"
5. "9 Greater, London England W4 4PH, United Kingdom"
6. "63 Lamb's Conduit Street, England WC1N 3NB, United Kingdom"
7. "56 Wellesley Road, England W4 4BZ, United Kingdom"
8. "Mill Bridge, Hertford England SG14 1PZ, United Kingdom"
9. "262 High Street, England HP4 1AQ, United Kingdom"
10. "32 Saint Andrew's Street, Cambridge England CB2 3AR, United Kingdom"
11. "123 Acre Lane, London England SW2 5UA, United Kingdom"
12. "202 Barkly Street, Footscray Victoria 3011, Australia"
13. "Gold Hill West, Chalfont Saint Peter England SL9 9HH, United Kingdom"
14. (6 more similar addresses)

### All Fake Cities
1. "3-4 Moulsham St" (slug: `3-4-moulsham-st`)
2. "10 Peas Hill" (slug: `10-peas-hill`)
3. "200 Grafton Gate" (slug: `200-grafton-gate`)
4. "76-78 Fore St" (slug: `76-78-fore-st`)
5. "9 Crutched Friars" (slug: `9-crutched-friars`)
6. "Ickenham Rd" (slug: `ickenham-rd`)
7. "Parkstone" (suburb, not city)
8. "Bethnal Green" (neighborhood, not city)
9. "Muswell Hill" (neighborhood, not city)
10. "Histon" (village/suburb)
11. (13 more similar entries)

### :all_events_failed Venue URLs
1. https://questionone.com/venues/pub-quiz-royal-oak-bethnal-green-wednesdays/
2. https://questionone.com/venues/pub-quiz-three-johns-angel-mondays/
3. https://questionone.com/venues/pub-quiz-royal-oak-twickenham-every-thursday/
4. https://questionone.com/venues/pub-quiz-the-new-inn-richmond/
5. https://questionone.com/venues/pub-quiz-skimmington-castle-reigate-wednesdays/
6. (1 more)
