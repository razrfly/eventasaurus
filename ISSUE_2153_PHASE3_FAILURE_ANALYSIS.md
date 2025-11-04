# Issue #2153 Phase 3 - Why The Fix Didn't Work

**Date**: November 4, 2025
**Status**: INCOMPLETE FIX - NEW BUG DISCOVERED

---

## What I Thought I Fixed

**Phase 3 Changes**:
1. ✅ Fixed VenueDetailJob hardcoded timezone bug (Line 64, 169-179)
2. ✅ Triggered full re-scrape (Job 7394, 170 jobs completed)
3. ✅ DataQualityChecker now detects dubious data (40% quality, 100% same time)

**Expected Result**: All events show correct times matching source websites

---

## What Actually Happened

**User Report**:
- Event URL: http://localhost:4000/activities/geeks-who-drink-trivia-at-rosso-rosso-pomodoro-pizza-251107
- Shows: **8:00 PM**
- Source: https://www.geekswhodrink.com/venues/2936708819/
- Source Shows: **6:00 PM** ("Thursdays at 6:00 pm")
- **Error: Still 2 hours off!**

---

## Root Cause Analysis

### Database Evidence

```sql
slug: geeks-who-drink-trivia-at-rosso-rosso-pomodoro-pizza-251107
pattern_time: 20:00         (8:00 PM)
pattern_timezone: America/Denver
updated_at: 2025-11-04 15:42:11    (AFTER re-scrape!)
```

**Key Finding**: Event WAS re-scraped with my fix (updated at 15:42:11, after 15:17 trigger), but STILL has wrong time.

### Oban Job Evidence

```sql
worker: VenueDetailJob
venue_url: %2936708819%
extracted_time: NULL         ← EXTRACTION FAILED!
time_text: "Thursdays at"
state: completed
completed_at: 2025-11-04 15:42:11
```

**Critical Discovery**: `extracted_time` is **NULL**!

---

## The Real Problem

I fixed the **TIMEZONE BUG** but there's a **SEPARATE TIME EXTRACTION BUG**:

### Code Flow

**File**: `lib/eventasaurus_discovery/sources/geeks_who_drink/jobs/venue_detail_job.ex`

**Lines 158-164**:
```elixir
defp get_time_string(additional_details) do
  case additional_details[:start_time] do
    time when is_binary(time) and time != "" -> time
    # Default fallback matching trivia_advisor
    _ -> "20:00"    # ← HARDCODED FALLBACK!
  end
end
```

### What Happens

1. **HTML Extraction Fails**: VenueDetailsExtractor returns `additional_details[:start_time] = nil`
2. **Fallback Triggered**: Code falls back to hardcoded `"20:00"` (8PM)
3. **My Timezone Fix Works**: Correctly calculates "next Thursday 8PM America/Denver"
4. **But 8PM is WRONG**: Should be 6PM from source!

---

## Why HTML Extraction Failed

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
        # Parse and return time
```

**Hypothesis**: The HTML structure for venue #2936708819 doesn't match the expected `.venueHero__time .time-moment` selector, or the time isn't in the expected format.

---

## Two Separate Bugs

### Bug 1: Timezone Calculation ✅ FIXED
- **Location**: VenueDetailJob:168
- **Problem**: Hardcoded "America/New_York" for all venues
- **Status**: FIXED in Phase 3
- **Evidence**: New scrapes use correct timezone (America/Denver)

### Bug 2: Time Extraction ❌ NOT FIXED
- **Location**: VenueDetailsExtractor:265-298 + VenueDetailJob:158-164
- **Problem**: HTML extraction fails → falls back to hardcoded 20:00
- **Status**: NOT ADDRESSED
- **Impact**: When extraction fails, ALL venues default to 8PM

---

## Why This Went Undetected

### Test Venue Bias

**Phase 1 Investigation Used**: Zuni Street Brewing Co
- URL: https://www.geekswhodrink.com/venues/715188153/
- This venue's HTML structure works with the extractor
- Time was correctly extracted as "19:00" from "7:00 pm"
- Only the timezone bug was visible

**Rosso Pomodoro**: Different HTML structure or format
- Time extraction returns null
- Fallback triggers
- Both bugs compound (but I only fixed one)

### My Mistake

1. **Assumed extraction always works**: Never verified extraction success rate
2. **Didn't test multiple venues**: Only verified one venue structure
3. **Didn't check extraction failures**: Never looked at null start_times
4. **Didn't question the 20:00 pattern**: Stats show 100% at 20:00 - should have been red flag

---

## Evidence I Should Have Seen

**Quality Stats Show**:
```
WARNING: 100.0% of events at 20:00
Time diversity: 0%
44 occurrences analyzed
```

**This screams**: "All times are hardcoded fallback!"

**If extraction was working**, we'd see diversity:
- Some venues at 6PM, some at 7PM, some at 8PM, some at 9PM
- Diversity score > 0%
- Multiple different times

**Instead**: 100% at 20:00 = extraction failing for ALL or MOST venues

---

## What Needs To Be Fixed (For Real)

### Phase 4: Fix Time Extraction

1. **Investigate HTML Structure**:
   - Fetch multiple venue pages
   - Identify different HTML structures
   - Find where time is actually stored

2. **Update VenueDetailsExtractor**:
   - Add multiple selectors for different layouts
   - Add fallback extraction strategies
   - Log extraction failures

3. **Fix Fallback Behavior**:
   - Don't use hardcoded 20:00
   - Either: fail the job (retry later)
   - Or: mark event as "time unknown" (don't publish)

4. **Add Extraction Validation**:
   - Log extraction success rate
   - Alert when extraction < 80%
   - DataQualityChecker should check extraction success

---

## Test Plan For Real Fix

### Before Fix
```sql
SELECT count(*), occurrences->'pattern'->>'time' as time
FROM public_events pe
JOIN public_event_sources pes ON pes.event_id = pe.id
WHERE pes.source_id = 6
GROUP BY time
ORDER BY count DESC;

Expected: 44 events at 20:00
```

### After Fix
```
Expected: Diverse times (18:00, 19:00, 20:00, 21:00, etc.)
Expected: Time diversity > 50%
Expected: Different venues show different times
```

### Manual Verification
1. Pick 5 random venues
2. Check source website time
3. Verify database matches exactly
4. All 5 must match

---

## Lessons Learned

1. **Always check extraction success**: Don't assume scrapers work
2. **Test multiple samples**: One venue isn't enough
3. **Question 100% patterns**: 100% same time = red flag
4. **Verify end-to-end**: Check source → extraction → storage → display
5. **Read the warning signs**: Quality stats were screaming "extraction failure"

---

## Status

❌ **Phase 3: INCOMPLETE**
- ✅ Fixed timezone calculation bug
- ❌ Did not fix time extraction bug
- ❌ Did not verify extraction success rate
- ❌ Did not test multiple venue structures

🚨 **Phase 4: REQUIRED**
- Fix time extraction for all venue HTML structures
- Remove hardcoded 20:00 fallback
- Add extraction monitoring
- Test with diverse venue sample

---

## Immediate Next Steps

1. Investigate 5-10 random venue pages manually
2. Document all HTML structures for time display
3. Update extractor to handle all structures
4. Re-scrape with logging to verify extraction
5. Confirm times match sources before declaring victory
