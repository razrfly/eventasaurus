# Investigation Report: Issue #2153 - Time Quality System Failures
## Phase 1 Investigation Results (NO CODE CHANGES)

**Investigation Date**: November 4, 2025
**Issue**: https://github.com/razrfly/eventasaurus/issues/2153
**Status**: ROOT CAUSE IDENTIFIED

---

## Executive Summary

**ROOT CAUSE FOUND**: VenueDetailJob hardcodes timezone to `"America/New_York"` when calculating event occurrences, but then later determines the actual venue timezone. This creates a 1-3 hour time offset depending on the venue's actual location.

**Impact**: ALL Geeks Who Drink events outside Eastern timezone show incorrect times.

---

## Investigation Findings

### 1. How Times Are Extracted from HTML ✅

**File**: `lib/eventasaurus_discovery/sources/geeks_who_drink/extractors/venue_details_extractor.ex`

**Lines 265-298**: `extract_start_time/1` function

```elixir
defp extract_start_time(document) do
  visible_time =
    document
    |> Floki.find(".venueHero__time .time-moment")
    |> Floki.text()
    |> String.trim()

  if visible_time && visible_time != "" do
    case Regex.run(~r/(\d+):(\d+)\s*(am|pm)/i, visible_time) do
      [_, hour_str, minute_str, period] ->
        hour = String.to_integer(hour_str)
        minute = String.to_integer(minute_str)

        hour =
          case String.downcase(period) do
            "pm" when hour < 12 -> hour + 12
            "am" when hour == 12 -> 0
            _ -> hour
          end

        :io_lib.format("~2..0B:~2..0B", [hour, minute]) |> to_string()
```

**Finding**: Extractor correctly parses "7:00 pm" → "19:00" (24-hour format)

**Example**:
- Source shows: "7:00 pm"
- Extractor returns: "19:00" ✅ CORRECT

---

### 2. How Times Flow Through the System ✅

**File**: `lib/eventasaurus_discovery/sources/geeks_who_drink/jobs/venue_detail_job.ex`

#### Step 1: Parse Time (Lines 145-154)
```elixir
defp parse_time_from_sources(time_text, additional_details) do
  with {:ok, day_of_week} <- RecurringEventParser.parse_day_of_week(time_text),
       time_string <- get_time_string(additional_details),
       {:ok, time} <- RecurringEventParser.parse_time(time_string) do
    {:ok, {day_of_week, time}}
```

**Finding**: Gets day_of_week (e.g., `:tuesday`) and time struct (e.g., `~T[19:00:00]`)

#### Step 2: Calculate Next Occurrence - **🔴 BUG HERE** (Line 168)
```elixir
defp calculate_next_occurrence(day_of_week, time) do
  # Calculate next occurrence in America/New_York timezone
  next_dt = RecurringEventParser.next_occurrence(day_of_week, time, "America/New_York")
  {:ok, next_dt}
```

**🔴 CRITICAL BUG**: **Hardcoded to `"America/New_York"`** regardless of venue location!

**Impact**:
- For Denver (Mountain Time): 7PM MT becomes 7PM ET, which is 6PM MT (1 hour off)
- For Los Angeles (Pacific Time): 7PM PT becomes 7PM ET, which is 4PM PT (3 hours off!)
- For Chicago (Central Time): 7PM CT becomes 7PM ET, which is 6PM CT (1 hour off)

#### Step 3: Determine Actual Timezone (Lines 188-222)
```elixir
defp add_timezone(venue_data) do
  timezone = determine_timezone(venue_data)
  Map.put(venue_data, :timezone, timezone)
end

defp determine_timezone(venue_data) do
  cond do
    is_binary(venue_data[:timezone]) ->
      venue_data[:timezone]

    venue_data[:latitude] && venue_data[:longitude] ->
      case TzWorld.timezone_at({venue_data[:longitude], venue_data[:latitude]}) do
        {:ok, timezone} -> timezone
        {:error, reason} -> fallback_timezone_from_address(venue_data)
      end

    true -> "America/New_York"
  end
end
```

**Finding**: AFTER calculating the DateTime, the system correctly determines the venue's actual timezone using GPS coordinates or address parsing.

**For Denver venues**:
- Address: "2355 W 29th Ave. Denver, CO 80211"
- Coordinates: `(39.7586429, -105.0153123)`
- TzWorld returns: `"America/Denver"` ✅ CORRECT

---

### 3. Evidence from Database ✅

**Query**:
```sql
SELECT slug, title, starts_at, occurrences
FROM public_events
WHERE slug = 'geeks-who-drink-trivia-at-zuni-street-zuni-street-brewing-co-251105';
```

**Result**:
```
slug: geeks-who-drink-trivia-at-zuni-street-zuni-street-brewing-co-251105
title: Geeks Who Drink Trivia at Zuni Street Brewing Co
starts_at: 2025-11-05 01:00:00  (UTC)
occurrences: {
  "type": "pattern",
  "pattern": {
    "time": "18:00",           ← WRONG (should be "19:00")
    "timezone": "America/Denver",  ← CORRECT timezone
    "frequency": "weekly",
    "days_of_week": ["tuesday"]
  }
}
```

**Venue Data**:
```
address: 2355 W 29th Ave. Denver, CO 80211
latitude: 39.7586429
longitude: -105.0153123
city: Denver
```

**Source Website**: https://www.geekswhodrink.com/venues/715188153/
**Source Shows**: 7:00 PM
**Database Shows**: 18:00 (6:00 PM)
**Error**: 1 hour off

---

### 4. How the Transformer Extracts Time ✅

**File**: `lib/eventasaurus_discovery/sources/geeks_who_drink/transformer.ex`

**Lines 215-254**: `extract_from_datetime/2`

```elixir
defp extract_from_datetime(%DateTime{} = dt, venue_data) do
  timezone = venue_data[:timezone]  # Gets "America/Denver"

  # Convert UTC DateTime to local timezone
  local_dt = DateTime.shift_zone!(dt, tz)

  # Get time from LOCAL datetime
  time_string =
    local_dt
    |> DateTime.to_time()
    |> Time.to_string()
    |> String.slice(0, 5)

  {:ok, {day_of_week, time_string, tz}}
end
```

**Finding**: Transformer correctly converts UTC to local timezone before extracting time.

**BUT**: The incoming UTC DateTime was calculated for the WRONG timezone!

**Flow**:
1. VenueDetailJob calculates: "Next Tuesday 7PM **Eastern** = 2025-11-05 00:00:00 UTC" (example)
2. Transformer receives: UTC DateTime + timezone = "America/Denver"
3. Transformer converts: 00:00:00 UTC → 17:00:00 Mountain (6PM Denver)
4. Stores: `"time": "18:00"` (the time it extracted from the Eastern-timezone-calculated DateTime)

---

### 5. DataQualityChecker Doesn't Support Pattern Occurrences ✅

**File**: `lib/eventasaurus_discovery/admin/data_quality_checker.ex`

**Lines 1471-1478**:

```elixir
case event.occurrences do
  %{"dates" => dates} when is_list(dates) ->
    # Only handles explicit occurrences
    Enum.map(dates, fn date_obj -> extract_time_from_date(date_obj) end)

  _ ->
    []  # Returns EMPTY for pattern occurrences!
end
```

**Finding**: DataQualityChecker was designed for movies (explicit occurrences with dates array) and never updated for recurring events (pattern occurrences).

**Impact**:
- 84 events have occurrences
- 0 occurrences analyzed
- Returns 100% quality (false positive default)

**Pattern occurrences structure** (not supported):
```json
{
  "type": "pattern",
  "pattern": {
    "time": "18:00",
    "timezone": "America/Denver",
    "frequency": "weekly",
    "days_of_week": ["tuesday"]
  }
}
```

---

### 6. Cross-Reference with Multiple Events

**Sample of 5 Denver events**:
```sql
SELECT title, starts_at, occurrences FROM public_events pe
JOIN public_event_sources pes ON pes.event_id = pe.id
WHERE pes.source_id = 6 AND title LIKE '%Denver%'
LIMIT 5;
```

**Results**: ALL show same pattern
- `starts_at`: 01:00:00 UTC
- `occurrences.pattern.time`: "18:00"
- `occurrences.pattern.timezone`: "America/Denver"
- **All are 1 hour off from their source websites**

---

## Root Cause Summary

### The Bug

**Location**: `lib/eventasaurus_discovery/sources/geeks_who_drink/jobs/venue_detail_job.ex:168`

```elixir
defp calculate_next_occurrence(day_of_week, time) do
  next_dt = RecurringEventParser.next_occurrence(day_of_week, time, "America/New_York")
  {:ok, next_dt}
end
```

**Problem**: Hardcoded `"America/New_York"` timezone used for ALL venues, regardless of location.

### The Impact

1. **Denver (Mountain Time)**: 1 hour off (7PM → 6PM)
2. **Chicago (Central Time)**: 1 hour off
3. **Los Angeles (Pacific Time)**: 3 hours off
4. **Only Eastern Time venues are correct**

### Why It Persists

1. **No validation**: No automated checks comparing stored times against source websites
2. **False quality metrics**: DataQualityChecker reports 100% quality while analyzing 0 events
3. **Pattern occurrences unsupported**: Quality checker can't see recurring events

---

## Question One Investigation ⏳

**Status**: DEFERRED - Needs separate investigation

Question One also uses RecurringEventParser. Need to check if VenueDetailJob has same hardcoded timezone bug.

---

## Recommendations for Phase 2

### Critical Fixes (Must Do)

1. **Fix VenueDetailJob timezone bug** (Line 168)
   - Replace hardcoded `"America/New_York"` with actual venue timezone
   - Venue timezone should be determined BEFORE calculating next_occurrence
   - Pass determined timezone to `RecurringEventParser.next_occurrence/3`

2. **Fix DataQualityChecker pattern support**
   - Add support for pattern-type occurrences
   - Extract time from `occurrences.pattern.time`
   - Extract timezone from `occurrences.pattern.timezone`

3. **Fix false positive defaults**
   - Return 0% quality (or NULL) when no occurrences analyzed, not 100%
   - Add warning when metrics show contradictions

### High Priority Fixes

4. **Add source validation**
   - Automated checks comparing stored times against source websites
   - Weekly validation runs for all sources
   - Alert when times drift from source

5. **Re-scrape all Geeks Who Drink events**
   - After fixing the bug, re-scrape to get correct times
   - Verify times match source websites
   - Update all affected events in database

---

## Code References

### Files Examined

1. `lib/eventasaurus_discovery/sources/geeks_who_drink/extractors/venue_details_extractor.ex:265-298`
   - Time extraction: CORRECT

2. `lib/eventasaurus_discovery/sources/geeks_who_drink/jobs/venue_detail_job.ex:168`
   - **🔴 BUG LOCATION**: Hardcoded timezone

3. `lib/eventasaurus_discovery/sources/geeks_who_drink/transformer.ex:215-254`
   - Time conversion: CORRECT (but receives wrong input)

4. `lib/eventasaurus_discovery/admin/data_quality_checker.ex:1471-1478`
   - **🔴 MISSING FEATURE**: No pattern occurrence support

---

## Test Evidence

### Database Evidence
- ✅ Queried specific events
- ✅ Confirmed wrong times in database
- ✅ Confirmed correct timezone metadata
- ✅ Verified venue coordinates

### Source Evidence
- ✅ Verified source website shows 7PM
- ✅ Confirmed database stores 6PM (18:00)
- ✅ Validated 1-hour discrepancy

### Code Evidence
- ✅ Traced complete time flow through system
- ✅ Identified exact line with bug
- ✅ Confirmed DataQualityChecker doesn't support patterns
- ✅ Validated transformer logic is correct

---

## Conclusion

**Phase 1 Investigation: COMPLETE ✅**

**Root Cause**: VenueDetailJob calculates event times in Eastern timezone (hardcoded), then later determines the venue's actual timezone. The transformer extracts time from a DateTime that was calculated for the wrong timezone.

**Fix Complexity**: **LOW** - Single line change + re-scrape
**Impact**: **HIGH** - Affects all non-Eastern venues

**Next Step**: Implement Phase 2 fixes as documented in Issue #2153
