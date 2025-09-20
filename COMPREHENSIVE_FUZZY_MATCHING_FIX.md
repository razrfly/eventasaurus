# 🚨 COMPREHENSIVE FIX: Event Consolidation & Fuzzy Matching Issues

## Executive Summary
After extensive analysis of issues #1182, #1181, #1174, #1172, #1177, #1176, and #1179, the fuzzy matching and event consolidation system is **96.6% broken**. Only 9 out of 264 events (3.4%) have proper occurrence tracking, resulting in massive duplication.

## Current Status: CRITICAL ❌

### Database Evidence (264 events analyzed)
- **Total Events**: 264
- **With Occurrences**: 9 (3.4%) ❌
- **Without Occurrences**: 255 (96.6%) ❌
- **Events with no source tracking**: 174 (65.9%) ❌

## Specific Test Cases to Verify Fix

### Test Case 1: NutkoSfera Duplicate Events ❌
**Current State**: Two separate events exist
```sql
ID: 34, Title: "NutkoSfera - CeZik Dzieciom @ Nowohuckie Centrum Kultury"
- Date: 2025-09-22 17:00, Venue: 5, Has occurrences: YES
- External ID: 105967765, Source: Bandsintown

ID: 36, Title: "NutkoSfera - CeZik Dzieciom @ Nowohuckie Centrum Kultury"
- Date: 2025-09-23 17:00, Venue: 5, Has occurrences: NO
- External ID: 106401802, Source: Bandsintown
```
**Expected After Fix**: Single consolidated event with both dates in occurrences

### Test Case 2: Vanden Plas Venue Mismatch ❌
**Current State**: Two events at "same" venue with different IDs
```sql
ID: 35, Title: "Vanden Plas @ Klub Zaścianek"
- Date: 2025-09-22 20:00, Venue: 11 ("Klub Zaścianek")
- External ID: 1035531484, Source: Bandsintown

ID: 65, Title: "Vanden Plas w Zaścianku"
- Date: 2025-09-22 20:00, Venue: 36 ("Zaścianek")
- External ID: karnet_59168, Source: Karnet
```
**Expected After Fix**: Single event (venues should be deduplicated first)

### Test Case 3: Disturbed Cross-Source Success ✅
**Current State**: WORKING CORRECTLY
```sql
ID: 8, Title: "Disturbed: The Sickness 25th Anniversary Tour"
- Has 2 occurrences from different sources (Bandsintown + Ticketmaster)
```
**Keep Working**: This is the model for how it should work

### Test Case 4: Muzeum Banksy Recurring Success ✅
**Current State**: WORKING CORRECTLY
```sql
ID: 1, Title: "Muzeum Banksy"
- Has 60 occurrences properly consolidated
```
**Keep Working**: Recurring event detection working here

## Root Causes Identified

### 1. Occurrences Field Not Initialized (PRIMARY ISSUE)
- **Problem**: 96.6% of events have NULL occurrences
- **Location**: `event_processor.ex:create_event/3`
- **Impact**: Consolidation impossible without occurrence tracking

### 2. Venue Deduplication Broken
- **Problem**: Same venues with different names not matched
- **Example**: "Klub Zaścianek" (ID: 11) vs "Zaścianek" (ID: 36)
- **Impact**: Events at same venue treated as different

### 3. No Fuzzy Matching in Collision Detection
- **Problem**: CollisionDetector only uses exact venue + time window
- **Location**: `collision_detector.ex:find_similar_event/3`
- **Impact**: Similar titles not consolidated

### 4. Missing Source Tracking
- **Problem**: 174 events (65.9%) have no source data
- **Impact**: Cannot track event origins for consolidation

### 5. Uncommitted Code Issues
- **Problem**: Recurring event detection added but not applied to all events
- **Location**: `event_processor.ex:find_recurring_parent/4`
- **Impact**: Only works for explicit recurring patterns

## Comprehensive Fix Strategy

### Phase 1: Initialize Occurrences for ALL Events

```elixir
# In event_processor.ex, modify create_event/3:

defp create_event(data, venue, slug) do
  attrs = %{
    title: data.title,
    slug: slug,
    starts_at: data.start_at,
    ends_at: data.ends_at,
    category_id: data.category_id,
    venue_id: if(venue, do: venue.id, else: nil),
    # CRITICAL FIX: Always initialize occurrences
    occurrences: initialize_occurrence_with_source(data)
  }

  %PublicEvent{}
  |> PublicEvent.changeset(attrs)
  |> Repo.insert()
end

defp initialize_occurrence_with_source(data) do
  %{
    "type" => "explicit",
    "dates" => [
      %{
        "date" => format_date_only(data.start_at),
        "time" => format_time_only(data.start_at),
        "external_id" => data.external_id,
        "source" => detect_source_from_external_id(data.external_id)
      }
    ]
  }
end

defp detect_source_from_external_id(nil), do: "unknown"
defp detect_source_from_external_id(id) do
  cond do
    String.starts_with?(id, "tm_") -> "ticketmaster"
    String.starts_with?(id, "karnet_") -> "karnet"
    String.starts_with?(id, "bandsintown_") -> "bandsintown"
    true -> "unknown"
  end
end
```

### Phase 2: Enhanced Collision Detection with Fuzzy Matching

```elixir
# In collision_detector.ex, enhance find_similar_event/3:

def find_similar_event(venue, starts_at, title \\ nil) do
  start_window = DateTime.add(starts_at, -@collision_window_seconds, :second)
  end_window = DateTime.add(starts_at, @collision_window_seconds, :second)

  # Step 1: Venue + Time matching (existing)
  venue_time_matches = if venue do
    from(pe in PublicEvent,
      where: pe.venue_id == ^venue.id and
             pe.starts_at >= ^start_window and
             pe.starts_at <= ^end_window,
      limit: 10
    ) |> Repo.all()
  else
    []
  end

  # Step 2: Fuzzy title matching at same venue
  fuzzy_matches = if venue && title do
    normalized_title = normalize_for_matching(title)

    from(pe in PublicEvent,
      where: pe.venue_id == ^venue.id,
      select: %{
        event: pe,
        similarity: fragment("similarity(?, ?)", pe.title, ^title)
      },
      where: fragment("similarity(?, ?) > ?", pe.title, ^title, 0.7),
      order_by: [desc: fragment("similarity(?, ?)", pe.title, ^title)],
      limit: 5
    ) |> Repo.all()
  else
    []
  end

  # Step 3: Combine and score matches
  all_matches = (venue_time_matches ++ Enum.map(fuzzy_matches, & &1.event))
    |> Enum.uniq_by(& &1.id)
    |> score_and_rank_matches(venue, starts_at, title)

  List.first(all_matches)
end

defp score_and_rank_matches(events, venue, starts_at, title) do
  events
  |> Enum.map(fn event ->
    time_score = calculate_time_proximity_score(event.starts_at, starts_at)
    title_score = if title, do: String.jaro_distance(event.title, title), else: 0
    venue_score = if event.venue_id == venue.id, do: 1.0, else: 0.0

    total_score = (time_score * 0.3) + (title_score * 0.5) + (venue_score * 0.2)
    {event, total_score}
  end)
  |> Enum.filter(fn {_, score} -> score > 0.7 end)
  |> Enum.sort_by(fn {_, score} -> -score end)
  |> Enum.map(fn {event, _} -> event end)
end
```

### Phase 3: Apply Fuzzy Matching to ALL Events

```elixir
# Modify find_or_create_event to use fuzzy matching for all paths:

defp find_or_create_event(data, venue, source_id) do
  existing_from_source = find_existing_event(data.external_id, source_id)

  # ALWAYS check for similar events, not just recurring
  similar_event = find_similar_event_enhanced(data, venue, source_id)

  case {existing_from_source, similar_event} do
    {nil, nil} ->
      # Create new with occurrences
      create_event_with_occurrences(data, venue, slug)

    {nil, similar} ->
      # Add to existing as occurrence
      add_occurrence_to_event(similar, data)

    {existing, nil} ->
      # Update existing
      maybe_update_event(existing, data, venue)

    {existing, similar} when existing.id != similar.id ->
      # Consolidate duplicates
      consolidate_events(existing, similar, data)

    {existing, _} ->
      # Same event, just update
      maybe_update_event(existing, data, venue)
  end
end
```

### Phase 4: Venue Deduplication

```elixir
# Add venue fuzzy matching before event processing:

defp find_or_create_venue(venue_data) do
  # First try exact match
  exact = Repo.get_by(Venue, name: venue_data.name, city_id: venue_data.city_id)

  if exact do
    {:ok, exact}
  else
    # Try fuzzy match
    similar_venues = from(v in Venue,
      where: v.city_id == ^venue_data.city_id,
      select: %{
        venue: v,
        similarity: fragment("similarity(?, ?)", v.name, ^venue_data.name)
      },
      where: fragment("similarity(?, ?) > ?", v.name, ^venue_data.name, 0.7),
      order_by: [desc: fragment("similarity(?, ?)", v.name, ^venue_data.name)],
      limit: 1
    ) |> Repo.all()

    case similar_venues do
      [%{venue: venue, similarity: score}] when score > 0.8 ->
        Logger.info("Found similar venue: #{venue.name} (#{score})")
        {:ok, venue}
      _ ->
        create_venue(venue_data)
    end
  end
end
```

### Phase 5: Data Migration for Existing Events

```elixir
# Migration to populate missing occurrences:

defmodule PopulateMissingOccurrences do
  def run do
    # Get all events without occurrences
    events_without_occurrences = from(e in PublicEvent,
      where: is_nil(e.occurrences) or e.occurrences == ^%{},
      preload: :sources
    ) |> Repo.all()

    Enum.each(events_without_occurrences, fn event ->
      occurrences = %{
        "type" => "explicit",
        "dates" => event.sources |> Enum.map(fn source ->
          %{
            "date" => format_date(event.starts_at),
            "time" => format_time(event.starts_at),
            "external_id" => source.external_id,
            "source" => detect_source(source.external_id)
          }
        end)
      }

      event
      |> PublicEvent.changeset(%{occurrences: occurrences})
      |> Repo.update()
    end)
  end
end
```

## Verification Queries

Run these queries after implementing the fix:

```sql
-- 1. Check occurrence population (should be 100%)
SELECT
  COUNT(*) as total,
  COUNT(CASE WHEN occurrences IS NOT NULL THEN 1 END) as with_occurrences,
  ROUND(COUNT(CASE WHEN occurrences IS NOT NULL THEN 1 END)::numeric / COUNT(*)::numeric * 100, 2) as percentage
FROM public_events;

-- 2. Check NutkoSfera consolidation (should be 1 event)
SELECT id, title, starts_at, occurrences
FROM public_events
WHERE title LIKE '%NutkoSfera%';

-- 3. Check Vanden Plas consolidation (should be 1 event)
SELECT id, title, venue_id, starts_at
FROM public_events
WHERE title LIKE '%Vanden Plas%';

-- 4. Check duplicate titles at same venue (should be 0)
SELECT COUNT(*)
FROM public_events e1
JOIN public_events e2 ON e1.id < e2.id
WHERE e1.title = e2.title
  AND e1.venue_id = e2.venue_id;
```

## Success Criteria

1. ✅ 100% of events have occurrences populated
2. ✅ NutkoSfera events consolidated into single event
3. ✅ Vanden Plas events consolidated after venue dedup
4. ✅ No exact duplicate titles at same venue
5. ✅ Cross-source consolidation working (like Disturbed)
6. ✅ Recurring events still working (like Banksy)

## Implementation Priority

1. **CRITICAL**: Initialize occurrences for all new events (Phase 1)
2. **HIGH**: Run migration to populate existing occurrences (Phase 5)
3. **HIGH**: Implement fuzzy matching in collision detection (Phase 2)
4. **MEDIUM**: Venue deduplication (Phase 4)
5. **LOW**: Enhanced consolidation logic (Phase 3)

## Testing Approach

1. Backup current database
2. Apply Phase 1 fix
3. Run migration (Phase 5)
4. Test with new scraped data
5. Verify test cases pass
6. Apply remaining phases
7. Full regression test

## Related Issues to Close

Once this fix is implemented and verified:
- Close #1182 (Fuzzy matching not working)
- Close #1181 (Same-source consolidation)
- Close #1174 (Collision detection)
- Close #1172 (Event deduplication)
- Close #1177 (Cross-source matching)
- Close #1176 (Recurring events)
- Close #1179 (Occurrence tracking)