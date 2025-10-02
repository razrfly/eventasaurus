# Kino Krakow Showtimes Not Being Grouped Into Occurrences - CRITICAL BUG

## Issue Summary

**Status**: 🚨 **CRITICAL** - Movie showtimes are creating separate events instead of consolidated occurrences

**Impact**: 
- 280 showtimes scraped successfully ✅
- But creating 1 event per showtime with 1 occurrence each ❌
- Should create ~25 events with 10+ occurrences each ✅

**Example**:
- "Teściowie 3 at Cinema City Bonarka" has 10 showtimes on website
- EXPECTED: 1 event with 10 occurrences
- ACTUAL: 10 separate events, each with 1 occurrence

## Database Evidence

```sql
-- All 25 Kino Krakow events have exactly 1 occurrence each
SELECT 
  id, title, 
  jsonb_array_length(occurrences->'dates') as occurrence_count
FROM public_events pe
JOIN public_event_sources pes ON pe.id = pes.event_id
WHERE pes.source_id = 6
ORDER BY occurrence_count DESC;

-- Result: Every event has occurrence_count = 1 ❌
```

**Scraping Evidence**:
```bash
# Test extraction shows correct data being scraped:
Total: 280 showtimes extracted ✅

Top movies:
- "Zamach na papieża": 37 showtimes
- "Teściowie 3": 37 showtimes  
- "Jedna bitwa po drugiej": 36 showtimes

Top movie+cinema combinations:
- "Jedna bitwa po drugiej at Cinema City Bonarka": 11 showtimes ✅
- "Teściowie 3 at Cinema City Bonarka": 10 showtimes ✅
- "Zamach na papieża at Cinema City Bonarka": 10 showtimes ✅
```

## Root Cause Analysis

### The Data Flow

1. **ShowtimeExtractor** (WORKING CORRECTLY ✅)
   - Scrapes /cinema_program/by_movie page
   - Extracts ALL showtimes for each movie at each cinema
   - Example: 10 separate showtime records for "Teściowie 3 at Cinema City Bonarka"
   - File: `lib/eventasaurus_discovery/sources/kino_krakow/extractors/showtime_extractor.ex:145`

2. **Transformer** (WORKING CORRECTLY ✅)
   - Converts each showtime into event format
   - Includes movie_id, tmdb_id, cinema data
   - Creates title: "{Movie Title} at {Cinema Name}"
   - File: `lib/eventasaurus_discovery/sources/kino_krakow/transformer.ex:103`

3. **EventProcessor.normalize_event_data** (⚠️ LOSING movie_id)
   - Normalizes event data for processing
   - **BUG**: Does NOT extract movie_id or movie_data from incoming event!
   - File: `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:96-134`
   - Lines 97-122: Lists all extracted fields - movie_id is MISSING

4. **EventProcessor.find_recurring_parent** (🚨 BROKEN BY MY FIX)
   - Designed to consolidate recurring events
   - **MY FIX BROKE THIS**: Returns `nil` for ALL titles containing " at "
   - This prevents ANY consolidation for movie events
   - File: `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:890`
   
   ```elixir
   if String.contains?(title, " at ") do
     Logger.debug("🎬 Skipping recurring parent check for movie event: #{title}")
     nil  # ❌ This prevents all consolidation!
   ```

### The Problem Chain

1. Previous bug: Different movies being consolidated together
   - "Teściowie 3 at Cinema City" + "Vinci 2 at Cinema City" → merged ❌
   
2. My "fix": Skip consolidation for all " at " titles
   - Prevented different movies from merging ✅
   - But ALSO prevented same movie showtimes from grouping ❌

3. Current state: Every showtime creates separate event
   - 10 showtimes for "Teściowie 3 at Cinema City Bonarka"
   - Creates 10 events instead of 1 event with 10 occurrences
   
## Why This Is Wrong

### Expected Behavior

For "Teściowie 3 at Cinema City Bonarka" with 10 showtimes at different times:

```
ONE PublicEvent:
  id: 4183
  title: "Teściowie 3 at Cinema City Bonarka"
  starts_at: 2025-10-02 09:00:00 (earliest)
  occurrences: {
    "type": "explicit",
    "dates": [
      {"date": "2025-10-02", "time": "09:00", "external_id": "..."},
      {"date": "2025-10-02", "time": "11:15", "external_id": "..."},
      {"date": "2025-10-02", "time": "13:30", "external_id": "..."},
      ... (10 total)
    ]
  }
```

### Actual Behavior

```
TEN separate PublicEvents:
  - Event #4201: "Teściowie 3 at Cinema City Bonarka" @ 09:00 (1 occurrence)
  - Event #4202: "Teściowie 3 at Cinema City Bonarka" @ 11:15 (1 occurrence)
  - Event #4203: "Teściowie 3 at Cinema City Bonarka" @ 13:30 (1 occurrence)
  ... (10 total events)
```

## The Correct Fix (Not Yet Implemented)

### Requirements

1. ✅ Consolidate SAME movie at SAME venue (multiple showtimes → occurrences)
2. ✅ Do NOT consolidate DIFFERENT movies at same venue
3. ✅ Use movie_id to determine if movies are the same (not just title matching)

### Implementation Plan

#### Step 1: Preserve movie_id through normalization

**File**: `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:96`

```elixir
defp normalize_event_data(data) do
  normalized = %{
    external_id: data[:external_id] || data["external_id"],
    title: Normalizer.normalize_text(data[:title] || data["title"]),
    # ... existing fields ...
    
    # NEW: Preserve movie data for movie events
    movie_id: data[:movie_id] || data["movie_id"],
    movie_data: data[:movie_data] || data["movie_data"]
  }
  # ... rest of function ...
end
```

#### Step 2: Pass movie_id to find_recurring_parent

**File**: `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:156`

```elixir
defp find_or_create_event(data, venue, source_id) do
  # ... existing code ...
  with_recurring_event_lock(venue, data.title, fn ->
    do_find_or_create_event(data, venue, source_id, slug, data[:movie_id])
  end)
end

defp do_find_or_create_event(data, venue, source_id, slug, movie_id \\ nil) do
  # ... existing code ...
  recurring_parent = find_recurring_parent(
    data.title, 
    venue, 
    data.external_id, 
    source_id,
    movie_id  # NEW: Pass movie_id
  )
  # ... rest of function ...
end
```

#### Step 3: Update find_recurring_parent to use movie_id

**File**: `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:886`

```elixir
defp find_recurring_parent(title, venue, external_id, source_id, movie_id \\ nil) do
  if venue do
    # REMOVE THIS BROKEN FIX:
    # if String.contains?(title, " at ") do
    #   nil
    # end
    
    # ... existing fuzzy matching logic ...
    
    all_potential_matches
    |> Enum.uniq_by(& &1.id)
    |> Enum.map(fn event ->
      # ... existing scoring logic ...
      
      # NEW: For movie events, check if movie IDs match
      movie_ids_match = 
        if movie_id do
          # Check if event has movie association
          event_movie_id = Repo.one(
            from em in EventMovie,
            where: em.event_id == ^event.id,
            select: em.movie_id,
            limit: 1
          )
          
          # Check metadata as fallback
          metadata_movie_id = get_in(event_movie_id, [:metadata, "movie_id"])
          
          # Only match if movie IDs are the same (or if no movie_id for event yet)
          is_nil(event_movie_id) || event_movie_id == movie_id || metadata_movie_id == movie_id
        else
          true  # Non-movie events proceed with normal matching
        end
      
      # Skip if movie IDs don't match
      if movie_ids_match do
        # ... existing scoring and matching logic ...
      else
        {event, 0.0}  # Score 0 for different movies
      end
    end)
    # ... rest of function ...
  end
end
```

### Alternative Simpler Fix

**If movie association is too complex, use title normalization:**

```elixir
defp find_recurring_parent(title, venue, external_id, source_id) do
  if venue do
    # For movie events (title with " at "), extract just the movie part
    movie_title = 
      if String.contains?(title, " at ") do
        title
        |> String.split(" at ")
        |> List.first()
        |> String.trim()
      else
        title
      end
    
    # Now use movie_title for matching instead of full title
    normalized_title = normalize_for_matching(movie_title)
    
    # ... continue with fuzzy matching using movie_title ...
    # This ensures "Teściowie 3" matches "Teściowie 3" 
    # But NOT "Vinci 2"
  end
end
```

## Testing Plan

### 1. Delete existing bad data
```sql
DELETE FROM public_events 
WHERE id IN (
  SELECT pe.id
  FROM public_events pe
  JOIN public_event_sources pes ON pe.id = pes.event_id
  WHERE pes.source_id = 6
);
```

### 2. Re-run scraper
```bash
mix run -e "EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob.new(%{}) |> Oban.insert!()"
```

### 3. Verify results
```sql
-- Should see ~25 events with multiple occurrences each
SELECT 
  COUNT(*) as total_events,
  AVG(jsonb_array_length(occurrences->'dates')) as avg_occurrences,
  MAX(jsonb_array_length(occurrences->'dates')) as max_occurrences
FROM public_events pe
JOIN public_event_sources pes ON pe.id = pes.event_id
WHERE pes.source_id = 6;

-- Expected:
-- total_events: ~25-30
-- avg_occurrences: ~8-10
-- max_occurrences: ~11-15

-- Check specific movie
SELECT 
  id, title,
  starts_at,
  jsonb_array_length(occurrences->'dates') as occurrence_count,
  occurrences->'dates'
FROM public_events pe
WHERE title LIKE '%Teściowie 3 at Cinema City%'
ORDER BY occurrence_count DESC;

-- Should see ONE event with ~10 occurrences for Cinema City Bonarka
```

### 4. Verify different movies not consolidated
```sql
-- Should NOT see mixed movies in occurrences
SELECT 
  id, title,
  jsonb_agg(DISTINCT value->>'label') as occurrence_labels
FROM public_events pe,
  jsonb_array_elements(pe.occurrences->'dates') AS value
WHERE title LIKE '%Cinema City%'
GROUP BY id, title
HAVING jsonb_array_length(jsonb_agg(DISTINCT value->>'label')) > 1;

-- Should return 0 rows (no mixed movies)
```

## Summary

### What's Working
- ✅ ShowtimeExtractor finds all 280 showtimes correctly
- ✅ Transformer creates proper event data with movie_id
- ✅ Data reaches EventProcessor

### What's Broken  
- ❌ normalize_event_data loses movie_id
- ❌ find_recurring_parent prevents ALL consolidation for movies
- ❌ Each showtime creates separate event instead of occurrence

### What Needs To Be Fixed
1. Preserve movie_id through normalization
2. Pass movie_id to consolidation logic
3. Use movie_id to allow same-movie consolidation
4. Prevent different-movie consolidation

### Impact
- Current: 280 events with 1 occurrence each (wrong)
- Expected: ~25 events with 8-11 occurrences each (correct)
- User Impact: Movies show 1 showtime instead of all available times

## Related Files
- `lib/eventasaurus_discovery/sources/kino_krakow/extractors/showtime_extractor.ex:145` - Extraction (working)
- `lib/eventasaurus_discovery/sources/kino_krakow/transformer.ex:103` - Title building (working)
- `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:96` - Normalization (loses movie_id)
- `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:890` - Consolidation (broken by my fix)
- `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:156` - find_or_create_event (needs movie_id)

## Previous Related Issues
- `docs/kino-krakow-movie-consolidation-bug.md` - Different movies being merged (my fix went too far)
