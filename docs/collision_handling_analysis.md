# Event Collision Handling Analysis

## Current State Assessment

### Database Structure

1. **Public Events Table (`public_events`)**
   - Single event record with core fields (title, starts_at, venue_id, etc.)
   - Has a unique slug field (auto-generated)
   - No direct source relationship

2. **Public Event Sources Table (`public_event_sources`)**
   - Links events to sources (many-to-many relationship)
   - Unique constraints:
     - `(event_id, source_id)` - One record per event-source pair
     - `(source_id, external_id)` - Prevents duplicate external IDs per source
   - Stores metadata including priority in JSON
   - Tracks `last_seen_at` for freshness

3. **Sources Table**
   - Has priority field (Ticketmaster=100, BandsInTown=80, StubHub=60)
   - Used for conflict resolution

### Current Collision Detection Logic

From `EventProcessor.find_or_create_event()`:

```elixir
# Step 1: Check if this source already has this event (by external_id)
find_existing_event(data.external_id, source_id)

# Step 2: If not found, check for similar events from ANY source
find_similar_event(title, start_at, venue)
  - Matches by: exact title + time window (±1 hour) + optional venue
  - If found, links existing event to new source
  - If not found, creates new event
```

### Current Issues

1. **Weak Matching**: Only matches exact titles within 1-hour window
2. **No Fuzzy Matching**: "Avi Kaplan" vs "Avi Kaplan & Band" would create duplicates
3. **No Venue Deduplication**: Venues from different sources aren't matched
4. **No Performer Deduplication**: Same artist from different sources creates duplicates
5. **No Confidence Scoring**: No way to determine match quality

## Proposed Solutions

### Option 1: Enhanced Current System (Minimal Changes)

**Implementation:**
1. Improve `find_similar_event()` with fuzzy matching
2. Add venue deduplication by name/location
3. Track all sources in `public_event_sources`

**Pros:**
- Minimal database changes
- Works with existing structure
- Quick to implement

**Cons:**
- Limited matching sophistication
- No confidence tracking
- Hard to review/audit matches

### Option 2: Event Matching Table (Recommended)

**New Table: `event_matches`**
```sql
CREATE TABLE event_matches (
  id BIGSERIAL PRIMARY KEY,
  event_id BIGINT REFERENCES public_events(id),
  source_id BIGINT REFERENCES sources(id),
  external_id VARCHAR(255),
  match_confidence DECIMAL(3,2), -- 0.00 to 1.00
  match_criteria JSONB, -- what matched: title, venue, time, performers
  is_primary BOOLEAN DEFAULT FALSE, -- is this the primary source?
  inserted_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

**Workflow:**
1. New event comes in from source
2. Run matching algorithm:
   - Exact external_id match: 1.0 confidence
   - Title + venue + time match: 0.9 confidence
   - Fuzzy title + time match: 0.7 confidence
   - Performer + venue + time match: 0.8 confidence
3. If match found above threshold (e.g., 0.7):
   - Add to `event_matches` table
   - Update event with higher priority source data
4. Store match details for review

**Pros:**
- Full match history and audit trail
- Confidence scoring for review
- Can adjust thresholds over time
- Supports manual match corrections

**Cons:**
- Requires new table
- More complex logic

### Option 3: Event Clustering System (Advanced)

**New Tables:**
```sql
-- Event clusters group related events
CREATE TABLE event_clusters (
  id BIGSERIAL PRIMARY KEY,
  canonical_event_id BIGINT REFERENCES public_events(id),
  cluster_metadata JSONB,
  inserted_at TIMESTAMP,
  updated_at TIMESTAMP
);

-- Track all events in a cluster
CREATE TABLE event_cluster_members (
  id BIGSERIAL PRIMARY KEY,
  cluster_id BIGINT REFERENCES event_clusters(id),
  event_id BIGINT REFERENCES public_events(id),
  source_id BIGINT REFERENCES sources(id),
  confidence DECIMAL(3,2),
  is_canonical BOOLEAN DEFAULT FALSE,
  inserted_at TIMESTAMP
);
```

**Pros:**
- Most flexible for complex matching
- Supports event variations (early/late shows)
- Can handle series/recurring events

**Cons:**
- Most complex to implement
- Requires significant refactoring

## Venue & Performer Deduplication

### Venues
Current: Creates duplicates if name varies slightly

**Proposed Solution:**
1. Add `venue_aliases` table for name variations
2. Match by: name similarity + location proximity
3. Use Google Places API place_id as canonical identifier

### Performers
Current: Creates duplicates for each source

**Proposed Solution:**
1. Add `performer_aliases` table
2. Match by: exact name, fuzzy name, MusicBrainz ID
3. Merge duplicate performers with redirect

## Recommended Implementation Plan

### Phase 1: Immediate Improvements (1-2 days)
1. Add fuzzy matching to `find_similar_event()`
2. Improve venue matching by location
3. Add logging for collision detection

### Phase 2: Event Matching Table (3-5 days)
1. Create `event_matches` table
2. Implement confidence scoring
3. Build review interface for low-confidence matches

### Phase 3: Venue/Performer Dedup (2-3 days)
1. Implement venue matching by location
2. Add performer fuzzy matching
3. Create merge tools for duplicates

### Phase 4: Advanced Features (Future)
1. Machine learning for match confidence
2. User feedback on match quality
3. Automatic source priority adjustment

## Key Decisions Needed

1. **Match Threshold**: What confidence level auto-merges vs requires review?
2. **Primary Source**: How to choose which source data to display?
3. **Update Strategy**: When source A updates, do we update merged event?
4. **User Visibility**: Show users event is from multiple sources?
5. **Historical Data**: Keep all versions or just latest?

## Sample Matching Algorithm

```elixir
defmodule EventMatcher do
  def calculate_match_score(event1, event2) do
    scores = %{
      title: calculate_title_similarity(event1.title, event2.title) * 0.3,
      time: calculate_time_proximity(event1.starts_at, event2.starts_at) * 0.2,
      venue: calculate_venue_match(event1.venue, event2.venue) * 0.3,
      performers: calculate_performer_overlap(event1.performers, event2.performers) * 0.2
    }

    total_score = Enum.sum(Map.values(scores))
    {total_score, scores}
  end

  defp calculate_title_similarity(title1, title2) do
    # Use Jaro-Winkler or Levenshtein distance
    String.jaro_distance(String.downcase(title1), String.downcase(title2))
  end

  defp calculate_time_proximity(time1, time2) do
    # Score based on time difference
    diff_seconds = abs(DateTime.diff(time1, time2))
    cond do
      diff_seconds == 0 -> 1.0
      diff_seconds <= 3600 -> 0.8  # Within 1 hour
      diff_seconds <= 7200 -> 0.5  # Within 2 hours
      true -> 0.0
    end
  end
end
```

## Next Steps

1. Review and approve approach (Option 2 recommended)
2. Create migration for new tables
3. Implement matching algorithm
4. Add admin interface for reviewing matches
5. Run retroactive matching on existing data