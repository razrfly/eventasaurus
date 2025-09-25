# City Filters Broken: Hard-coded 100 event limit, category filtering non-functional, radius always active

## Problem Summary

The city event filtering functionality has multiple critical issues that make it appear broken to users. All issues stem from architectural problems in the event fetching pipeline.

## Issues Identified

### 1. **Hard-coded 100 Event Limit (Most Critical)**

**Problem**: Changing radius from 50km to 100km still shows exactly 100 events
**Root Cause**: PublicEventsEnhanced.list_events() has @max_limit 100 that caps all results

**Location**: `lib/eventasaurus_discovery/public_events_enhanced.ex:14`
```elixir
@max_limit 100  # This caps ALL results regardless of radius
```

**Code Flow**:
```elixir
# lib/eventasaurus_web/live/city_live/index.ex:575
query_filters = Map.merge(filters, %{
  page_size: 1000,  # Requesting 1000 events
  page: 1
})

all_events = PublicEventsEnhanced.list_events(query_filters)  # Returns max 100
# Then radius filtering on only 100 events -> same result for any radius
```

**Fix Needed**: Remove or significantly increase @max_limit for geographic filtering, OR implement radius filtering at database level instead of post-processing.

### 2. **Radius Filter Always Shows as "Active"**

**Problem**: Radius filter shows as active even with default 50km setting
**Root Cause**: active_filter_count() checks `filters.radius_km != 25` but default changed to 50km

**Location**: `lib/eventasaurus_web/live/city_live/index.ex:712-713`
```elixir
@default_radius_km 50  # Changed from 25
count = if filters.radius_km && filters.radius_km != 25, do: count + 1, else: count  # Still checking != 25
```

**Fix Needed**: Update logic to check against actual default: `filters.radius_km != @default_radius_km`

### 3. **Category Filtering Non-Functional**

**Problem**: Checking categories doesn't filter events, still shows all categories
**Root Cause**: Categories passed to PublicEventsEnhanced but no verification it applies filtering

**Location**: `lib/eventasaurus_web/live/city_live/index.ex:560-570`
```elixir
query_filters = Map.merge(filters, %{
  categories: filters.categories,  # Passed but not working?
  # ...
})
```

**Fix Needed**: Verify PublicEventsEnhanced.filter_by_categories() works properly, OR implement category filtering in city-specific pipeline.

### 4. **Wrong Category Display (Museum Banksy)**

**Problem**: Museum Banksy shows as "Festivals" instead of "Theatre" like on Activities page
**Root Cause**: Using `List.first(@event.categories)` instead of preferred category logic

**Location**: `lib/eventasaurus_web/live/city_live/index.ex:462`
```elixir
<% category = List.first(@event.categories) %>  # Naive first category
```

**Same Issue**: Activities page has identical code at `lib/eventasaurus_web/live/public_events_index_live.ex:634`

**Fix Needed**: Implement preferred category logic that:
- Never shows "Other" if other categories exist
- Shows most relevant/preferred category based on priority system

### 5. **"Other" Category Regression**

**Problem**: Events showing "Other" category when they have more specific categories
**Root Cause**: Same as #4 - naive `List.first()` approach lost preferred category logic
**Fix Needed**: Same as #4

## Expected Behavior

City pages should mirror Activities page functionality exactly, with only radius filtering as the difference:

- ✅ **Radius filtering**: Should actually change event count when radius changes
- ✅ **Category filtering**: Should filter events when categories selected
- ✅ **Category display**: Should show preferred category, never "Other" if alternatives exist
- ✅ **Filter state**: Should only show filters as active when they differ from defaults

## Files Modified in Recent Changes

```bash
$ git status --porcelain
M lib/eventasaurus_discovery/locations.ex
M lib/eventasaurus_web/live/city_live/index.ex
M lib/eventasaurus_web/live/city_live/search.ex
? lib/eventasaurus_web/live/city_live/search.html.heex
```

## Proposed Solutions

### Short-term (Fix Critical Issues)
1. **Increase @max_limit** in PublicEventsEnhanced to 500+ for geographic contexts
2. **Fix active_filter_count** to check against @default_radius_km
3. **Debug category filtering** in PublicEventsEnhanced pipeline

### Long-term (Architectural Fix)
1. **Implement radius filtering at database level** instead of post-processing
2. **Create preferred category logic** that both Activities and City pages use
3. **Add integration tests** for city filtering to prevent regressions

## Testing Steps to Reproduce

1. Navigate to http://localhost:4000/c/krakow
2. Open Filters panel (should work now)
3. Change radius from 50km → 100km → Notice count stays exactly 100 events
4. Select any category → Notice no filtering happens
5. Observe Museum Banksy shows as "Festivals" instead of preferred category

## Business Impact

- **User Confusion**: Filters appear broken, radius changes don't work
- **Poor UX**: Users can't effectively filter city events
- **Data Inconsistency**: Same events show different categories on different pages
- **Trust Issues**: Static 100 event count looks suspicious and hard-coded