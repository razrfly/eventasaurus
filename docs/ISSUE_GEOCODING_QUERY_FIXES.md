# Geocoding Query and Metadata Fixes

**Status**: 🟡 Review Needed
**Priority**: P2 - Important (Code Quality)
**Created**: 2025-10-12
**Context**: Post-multi-provider system implementation

---

## Overview

After implementing the multi-provider geocoding system, several code review suggestions identified potential issues in query paths, metadata consistency, and date filtering. This document analyzes each suggestion and provides recommendations.

---

## Issue 1: Oban Worker Queue Configuration

**Status**: ✅ ALREADY FIXED
**Location**: `lib/eventasaurus_discovery/workers/geocoding_cost_report_worker.ex:27-28`

**Finding**: Worker already specifies `queue: :reports`:
```elixir
use Oban.Worker,
  queue: :reports,
  max_attempts: 3
```

**Action**: None needed - already correct.

---

## Issue 2: Metadata Path Inconsistency

**Status**: ⚠️ REQUIRES INVESTIGATION
**Location**: Multiple files with dual metadata storage
**Severity**: Medium - Data duplication but queries work

**Finding**: New venues store geocoding data in BOTH locations:
```json
{
  "geocoding": {
    "provider": "mapbox",
    "geocoded_at": "2025-10-12T11:29:17.506858Z",
    "attempts": 1,
    "attempted_providers": ["mapbox"]
  },
  "geocoding_metadata": {
    "provider": "mapbox",
    "geocoded_at": "2025-10-12T11:29:17.506858Z",
    "attempts": 1,
    "attempted_providers": ["mapbox"]
  }
}
```

**Analysis**:
1. **Old system** (125 venues): Uses `metadata.geocoding` only
2. **New system** (122 venues): Uses BOTH `metadata.geocoding` AND `metadata.geocoding_metadata`
3. **Current queries**: Query `metadata.geocoding` which works for BOTH old and new data

**Root Cause**: `VenueProcessor` builds `geocoding_metadata` but stores it in `metadata.geocoding`:
```elixir
# venue_processor.ex:641-644
metadata = %{
  geocoding: geocoding_metadata,  # ← Stores as 'geocoding'
  # ...
}
```

But transformers/geocoder also add `geocoding_metadata` key directly to data.

**Recommendation**:
1. **Short-term**: Keep existing queries as-is (they work correctly)
2. **Long-term**: Standardize on ONE location:
   - Option A: Use `metadata.geocoding` everywhere (remove `geocoding_metadata`)
   - Option B: Use `metadata.geocoding_metadata` everywhere (update queries)
   - **Preferred**: Option A (less migration needed, old data already uses this)

---

## Issue 3: Date Filtering in GeocodingStats Queries

**Status**: ⚠️ REQUIRES VERIFICATION
**Location**: `lib/eventasaurus_discovery/metrics/geocoding_stats.ex`
**Severity**: High - Could affect cost tracking accuracy

**Code Review Claim**: Queries use wrong path for `geocoded_at`:
```elixir
# Current code (claimed to be wrong):
fragment("(?->>'geocoded_at')::timestamp >= ?", v.metadata, ^start_of_month)

# Suggested fix:
fragment("(?->'geocoding'->>'geocoded_at')::timestamp >= ?", v.metadata, ^start_of_month)
```

**Verification**:

**Old data structure** (Google Places):
```json
{
  "geocoding": {
    "geocoded_at": "2025-10-12T08:48:48.142204Z",
    ...
  }
}
```

**New data structure** (Mapbox):
```json
{
  "geocoding": {
    "geocoded_at": "2025-10-12T11:29:17.506858Z",
    ...
  },
  "geocoding_metadata": {
    "geocoded_at": "2025-10-12T11:29:17.506858Z",
    ...
  }
}
```

**Testing Required**:
```sql
-- Test if current queries work:
SELECT
  COUNT(*) as total,
  COUNT(CASE WHEN (metadata->>'geocoded_at')::timestamp IS NOT NULL THEN 1 END) as root_path,
  COUNT(CASE WHEN (metadata->'geocoding'->>'geocoded_at')::timestamp IS NOT NULL THEN 1 END) as geocoding_path
FROM venues
WHERE metadata->'geocoding' IS NOT NULL;
```

**Expected Results**:
- `root_path`: 0 (no venues have geocoded_at at root)
- `geocoding_path`: 247 (all venues have it in metadata.geocoding)

**If verification confirms issue**, apply these fixes:

### Fix 1: `monthly_cost/1` (lines 49-51)
```elixir
# Before:
fragment("(?->>'geocoded_at')::timestamp >= ?", v.metadata, ^start_of_month) and
fragment("(?->>'geocoded_at')::timestamp <= ?", v.metadata, ^end_of_month) and

# After:
fragment("(?->'geocoding'->>'geocoded_at')::timestamp >= ?", v.metadata, ^start_of_month) and
fragment("(?->'geocoding'->>'geocoded_at')::timestamp <= ?", v.metadata, ^end_of_month) and
```

### Fix 2: `cost_for_range/2` (lines 343-344)
```elixir
# Before:
fragment("(?->>'geocoded_at')::timestamp >= ?", v.metadata, ^start_datetime) and
fragment("(?->>'geocoded_at')::timestamp <= ?", v.metadata, ^end_datetime) and

# After:
fragment("(?->'geocoding'->>'geocoded_at')::timestamp >= ?", v.metadata, ^start_datetime) and
fragment("(?->'geocoding'->>'geocoded_at')::timestamp <= ?", v.metadata, ^end_datetime) and
```

### Fix 3: ALL performance tracking queries (success_rate_by_provider, average_attempts, fallback_patterns)

**Impact if NOT fixed**:
- Date filtering won't work (queries would return 0 results for month filters)
- Dashboard would show incorrect/empty monthly data
- Cost tracking would be unreliable

**Impact if ALREADY working**:
- Current queries are correct and no changes needed
- Code review suggestion was mistaken

---

## Issue 4: Summary Function Date Consistency

**Status**: ✅ VALID - Should be fixed
**Location**: `lib/eventasaurus_discovery/metrics/geocoding_stats.ex:285-310`
**Severity**: High - Data inconsistency in reports

**Problem**: `summary/0` mixes monthly totals with all-time provider/scraper breakdowns:
```elixir
def summary do
  with {:ok, monthly} <- monthly_cost(),              # ← Month-filtered
       {:ok, by_provider} <- costs_by_provider(),     # ← ALL-TIME (no date filter)
       {:ok, by_scraper} <- costs_by_scraper(),       # ← ALL-TIME (no date filter)
```

**Result**:
- `monthly.count` = 122 (current month)
- `by_provider` totals = 247 (all time)
- `free_count` calculated from all-time data
- `paid_count = 122 - 247` = **negative number!**

**Fix Required**: Add date parameter to provider/scraper queries:

```elixir
def summary(date \\ Date.utc_today()) do
  with {:ok, monthly} <- monthly_cost(date),
       {:ok, by_provider} <- costs_by_provider(date),  # ← Add date param
       {:ok, by_scraper} <- costs_by_scraper(date),    # ← Add date param
       ...
```

**Implementation**: Already implemented! Lines 94-173 show:
```elixir
def costs_by_provider(date \\ Date.utc_today()) do
  start_of_month = date |> Date.beginning_of_month() |> NaiveDateTime.new!(~T[00:00:00])
  end_of_month = date |> Date.end_of_month() |> NaiveDateTime.new!(~T[23:59:59])
  # Query with date filtering...
```

**Status**: ✅ Already fixed in current code (functions accept date parameter)

---

## Issue 5: Geocoding Metadata Loss in VenueProcessor

**Status**: ❌ NOT APPLICABLE
**Location**: `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex:618-639`
**Severity**: Code review suggestion is incorrect

**Claim**: "geocoding_metadata from AddressGeocoder is lost during normalization"

**Analysis**:
1. **normalize_venue_data/1** runs BEFORE geocoding (line 552-553)
2. **Geocoding** happens in process_venue_with_city/3 (line 588-593)
3. **Metadata built** AFTER both normalization and geocoding (line 618-639)

**Flow**:
```
1. normalize_venue_data(data)           # No geocoding_metadata yet
2. geocode_if_needed(normalized_data)   # Returns {:ok, {city, metadata}}
3. Build final metadata using result    # Metadata properly preserved
```

**Code Evidence** (lines 618-621):
```elixir
geocoding_metadata = cond do
  google_metadata != nil -> MetadataBuilder.build_google_places_metadata(google_metadata)
  Map.has_key?(data, :geocoding_metadata) -> data.geocoding_metadata  # ← This branch works
```

The `data` here is the ORIGINAL data (before normalization), not the normalized data. The geocoding_metadata IS preserved correctly.

**Verdict**: Code review suggestion misunderstood the data flow. No fix needed.

---

## Issue 6: Source Struct Handling

**Status**: ⚠️ ENHANCEMENT OPPORTUNITY
**Location**: `lib/eventasaurus_discovery/sources/processor.ex:145-161`
**Severity**: Low - Enhancement, not bug

**Current Code**:
```elixir
defp extract_scraper_name(source) when is_integer(source), do: nil
defp extract_scraper_name(source) when is_binary(source), do: source
defp extract_scraper_name(source) when is_atom(source), do: Atom.to_string(source)
defp extract_scraper_name(_), do: nil
```

**Suggestion**: Add clause for Source struct:
```elixir
defp extract_scraper_name(%EventasaurusDiscovery.Sources.Source{slug: slug, name: name}) do
  slug || name
end
```

**Analysis**:
- Currently not causing issues (no errors reported)
- Would future-proof if scrapers start passing Source structs
- Low priority enhancement

**Recommendation**: Add as enhancement if/when Source structs are passed to processor

---

## Testing Checklist

Before closing this issue, verify:

- [ ] **Test date filtering**: Run SQL query to verify geocoded_at path
- [ ] **Test summary function**: Verify monthly totals match provider breakdowns
- [ ] **Test dashboard**: Ensure monthly view shows correct data
- [ ] **Test cost reports**: Worker generates accurate monthly reports
- [ ] **Verify metadata consistency**: Check if duplicate storage is intentional

---

## Recommendations Summary

| Issue | Status | Action Required |
|-------|--------|----------------|
| 1. Oban queue config | ✅ Fixed | None |
| 2. Metadata duplication | ⚠️ Investigate | Standardize on one location (long-term) |
| 3. Date filtering paths | ⚠️ Verify | Test queries, fix if broken |
| 4. Summary date consistency | ✅ Fixed | Already implemented |
| 5. Metadata loss claim | ❌ Invalid | None - working correctly |
| 6. Source struct handling | ⚠️ Enhancement | Low priority improvement |

---

## Priority Actions

1. **CRITICAL**: Verify date filtering works correctly (Issue #3)
2. **IMPORTANT**: Test summary function with current month data (Issue #4)
3. **CLEANUP**: Decide on metadata standardization strategy (Issue #2)
4. **FUTURE**: Consider Source struct enhancement (Issue #6)

---

**Next Steps**: Run test queries to verify date filtering, then decide which fixes (if any) are actually needed.
