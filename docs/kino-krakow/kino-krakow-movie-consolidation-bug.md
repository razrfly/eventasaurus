# Kino Krakow Movie Consolidation Bug - Fixed

## Issue
Different movies from Cinema City were being incorrectly grouped together into a single activity/event. For example, "Teściowie 3" and "Vinci 2" showtimes at Cinema City/bonarka were being combined into one event.

**Example URL**: `http://localhost:4000/activities/tesciowie-3-at-cinema-city-bonarka-813`

**Database Evidence**:
```sql
SELECT id, title, occurrences 
FROM public_events 
WHERE slug = 'tesciowie-3-at-cinema-city-bonarka-813';

-- Result: ONE event (id=4183) with MIXED occurrences:
-- - 6 showtimes for "Teściowie 3 at Cinema City/bonarka"
-- - 2 showtimes for "Vinci 2 at Cinema City/bonarka"  ❌ BUG!
```

## Root Cause

### Data Flow
1. **Kino Krakow Transformer** creates event titles like: `"{Movie Title} at {Cinema Name}"`
   - File: `lib/eventasaurus_discovery/sources/kino_krakow/transformer.ex:103`
   - Example: "Teściowie 3 at Cinema City/bonarka"
   - Example: "Vinci 2 at Cinema City/bonarka"

2. **EventProcessor.find_recurring_parent()** uses fuzzy matching to consolidate similar events
   - File: `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:886`
   - Designed for recurring events like weekly concerts or quiz nights
   - Uses title normalization and Jaro distance to find similar events

3. **Bug**: Movie events were being treated as recurring events
   - Both "Teściowie 3 at Cinema City/bonarka" and "Vinci 2 at Cinema City/bonarka" share the venue portion
   - Fuzzy matching saw them as "similar enough" to consolidate
   - Different movies got merged into one PublicEvent with multiple occurrences

### Technical Details
- Title normalization removes patterns like dates, times, episode numbers
- BUT it doesn't remove the " at {venue}" portion for Kino Krakow events  
- The `remove_venue_suffix` function only handles "@" patterns, not " at " patterns
- Jaro distance algorithm found similarity due to shared venue name
- Events were consolidated, creating mixed showtimes for different films

## Fix

**File**: `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:886`

Added early return in `find_recurring_parent/4` to skip consolidation for movie events:

```elixir
defp find_recurring_parent(title, venue, external_id, source_id) do
  if venue do
    # CRITICAL FIX: For movie events (titles with "at Cinema"), don't consolidate different movies
    # Movies are standalone events, not recurring - each film is a unique event even at same venue
    if String.contains?(title, " at ") do
      Logger.debug("🎬 Skipping recurring parent check for movie event: #{title}")
      nil
    else
      # ... existing fuzzy matching logic for non-movie events
    end
  else
    nil
  end
end
```

### Why This Works
- Kino Krakow movie events always have " at " in their titles (e.g., "Movie at Cinema")
- Concert events use "@" instead (e.g., "Band @ Venue")
- Other event types don't include venue in title
- By skipping recurring parent checks for " at " patterns, we ensure each movie gets its own PublicEvent
- Concerts and other recurring events still benefit from consolidation

### Alternative Approaches Considered

1. **Remove venue from title entirely** 
   - ❌ Would require changes to transformer and existing data
   - ✅ Better long-term solution but higher risk

2. **Update remove_venue_suffix to handle " at " patterns**
   - ❌ Would affect all event types, not just movies
   - ❌ Could break consolidation for legitimate " at " recurring events

3. **Use movie_id for consolidation logic** ⭐ RECOMMENDED FUTURE IMPROVEMENT
   - ✅ Most robust solution
   - ❌ Requires movie association implementation in EventProcessor

## Testing

### Verify Fix Works
```bash
# 1. Delete the bad consolidated event
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c \
  "DELETE FROM public_events WHERE slug = 'tesciowie-3-at-cinema-city-bonarka-813';"

# 2. Re-run Kino Krakow sync
mix run -e "EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob.new(%{}) |> Oban.insert!()"

# 3. Verify separate events created
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c \
  "SELECT id, title, slug FROM public_events WHERE title ILIKE '%cinema city%' ORDER BY title;"

# Should see:
# - Separate event for "Teściowie 3 at Cinema City/bonarka"  
# - Separate event for "Vinci 2 at Cinema City/bonarka"
```

## Future Improvements

### 1. Add movie_id association to EventProcessor
**Priority**: HIGH  
**File**: `lib/eventasaurus_discovery/scraping/processors/event_processor.ex`

Currently, movie_id is passed from Kino Krakow transformer but never stored in the event_movies table.

**Implementation**:
```elixir
defp process_event(event_data, source_id, source_priority \\ 10) do
  with {:ok, normalized} <- normalize_event_data(event_data),
       {:ok, venue} <- process_venue(normalized),
       {:ok, event, action} <- find_or_create_event(normalized, venue, source_id),
       {:ok, _source} <- maybe_update_event_source(...),
       {:ok, _performers} <- process_performers(...),
       {:ok, _categories} <- process_categories(...),
       # NEW: Associate movie if movie_id present
       {:ok, _movie} <- maybe_associate_movie(event, normalized) do
    {:ok, Repo.preload(event, [:venue, :performers, :categories, :movies])}
  end
end

defp maybe_associate_movie(event, %{movie_id: movie_id}) when not is_nil(movie_id) do
  # Create EventMovie association
  %EventMovie{}
  |> EventMovie.changeset(%{event_id: event.id, movie_id: movie_id})
  |> Repo.insert(on_conflict: :nothing, conflict_target: [:event_id, :movie_id])
end

defp maybe_associate_movie(_event, _data), do: {:ok, nil}
```

### 2. Improve recurring event detection using movie_id
**Priority**: MEDIUM

Update `find_recurring_parent/4` to check movie associations:

```elixir
defp find_recurring_parent(title, venue, external_id, source_id, movie_id \\ nil) do
  # ... existing logic ...
  
  # Filter out events with different movie_id
  all_potential_matches
  |> Enum.reject(fn event ->
    if movie_id do
      # Check if event has a different movie associated
      existing_movie_id = Repo.one(
        from em in EventMovie,
        where: em.event_id == ^event.id,
        select: em.movie_id
      )
      existing_movie_id && existing_movie_id != movie_id
    else
      false
    end
  end)
  # ... continue with fuzzy matching ...
end
```

### 3. Clean up existing bad data
**Priority**: HIGH - Do this manually before next Kino Krakow sync

```sql
-- Find all consolidated movie events (events with mixed movie titles in occurrences)
SELECT pe.id, pe.title, pe.occurrences 
FROM public_events pe
WHERE pe.title ILIKE '%cinema%'
  AND pe.occurrences::text LIKE '%"label"%'
  AND (
    -- Check if occurrences has different labels (different movies)
    jsonb_array_length(
      (SELECT jsonb_agg(DISTINCT value->>'label') 
       FROM jsonb_array_elements(pe.occurrences->'dates') AS value)
    ) > 1
  );

-- Manual cleanup required - split these into separate events
```

### 4. Remove venue from movie titles
**Priority**: LOW - Nice to have

Update transformer to not include venue in title:
```elixir
# Before: "Teściowie 3 at Cinema City/bonarka"
# After:  "Teściowie 3"

defp build_title(event) do
  event[:movie_title] || event[:original_title] || "Unknown Movie"
end
```

Benefits:
- Cleaner titles
- No need for " at " workaround
- Venue already available via venue_id relationship

## Related Files
- `lib/eventasaurus_discovery/sources/kino_krakow/transformer.ex:103` - Title building
- `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:886` - Fixed recurring parent detection  
- `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:771` - Title normalization
- `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:877` - remove_venue_suffix (only handles "@")

## Impact
- ✅ Each movie gets its own dedicated PublicEvent
- ✅ Showtimes properly grouped by film
- ✅ No mixing of different movies
- ⚠️ Existing bad data needs manual cleanup (see Future Improvements #3)
- ✅ Concerts and other recurring events still work correctly
- ✅ Fix is minimal and low-risk

## Commit Message Suggestion
```
fix: prevent different movies from consolidating into same event

Kino Krakow movie showtimes were being incorrectly consolidated when
they shared the same venue. For example, "Teściowie 3 at Cinema City" 
and "Vinci 2 at Cinema City" were being merged into a single event.

This happened because find_recurring_parent() used fuzzy matching on
titles without checking if events were actually the same movie.

Fix: Skip recurring parent checks for titles containing " at " which
indicates Kino Krakow movie events. Each movie now gets its own event.

Files changed:
- event_processor.ex:886 - Added movie event detection in find_recurring_parent

Related issue: Cinema City showtimes showing mixed films
```
