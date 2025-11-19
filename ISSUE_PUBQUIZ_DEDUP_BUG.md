# PubQuiz Deduplication Bug: Incorrect Event Merging

## Issue Summary

PubQuiz recurring trivia events are being incorrectly merged with unrelated events from higher-priority sources (like Karnet film screenings), causing category misclassification.

**Example**: Event ID 247 merged:
- PubQuiz: "Weekly Trivia Night - Project Manhattan" (karaoke bar, Trivia category)
- Karnet: "Palestyna w Krakowie" (cinema, Film category)
- **Result**: Trivia event displays as "Film" category ❌

## Root Cause Analysis

### Current Deduplication Logic Flow

1. **Phase 1**: Check by external_id (same source) ✅
2. **Phase 2**: Fuzzy matching by:
   - GPS proximity (50m threshold)
   - Date similarity (same week)
   - Venue name contains/similarity
   - Title similarity (10% weight)

### The Bug

The deduplication logic in `lib/eventasaurus_discovery/sources/pubquiz/dedup_handler.ex` is **too aggressive** and lacks critical safeguards:

#### Problem 1: Venue Name Matching Too Loose
```elixir
# Current code (lines 222-234)
defp similar_venue?(venue1, venue2) do
  normalized1 = normalize_venue_name(venue1)
  normalized2 = normalize_venue_name(venue2)

  normalized1 == normalized2 ||
    String.contains?(normalized1, normalized2) ||  # ❌ TOO LOOSE
    String.contains?(normalized2, normalized1)     # ❌ TOO LOOSE
end
```

**Issue**: "Project Manhattan" and "Kino Pod Baranami" could match if normalization removes enough chars, or if GPS proximity is the primary signal.

#### Problem 2: No Recurrence Pattern Check
```elixir
# Missing validation
# PubQuiz events are ALWAYS recurring (weekly trivia nights)
# Should NEVER match one-time events (film screenings, concerts, etc.)
```

#### Problem 3: No Category Domain Check
```elixir
# Missing validation
# Trivia events should not match Film/Concert/Theater events
# Even if at same venue (e.g., venue hosts both trivia and film nights)
```

#### Problem 4: No Event Type Validation
```elixir
# Missing validation
# PubQuiz = trivia nights at bars/restaurants
# Should not match cinema screenings, theater shows, concerts
```

## Impact

- **Data Quality**: Events show wrong categories, confusing users
- **Category Trust**: Users lose trust in category filtering
- **Search Relevance**: Film searches return trivia events
- **Auto-Healing**: System cannot self-correct on next scrape

## Affected Events

```sql
-- Found 1 PubQuiz event with Film category (should be Trivia)
SELECT pe.id, pe.title, s.slug, c.name as category
FROM public_events pe
JOIN public_event_sources pes ON pe.id = pes.event_id
JOIN sources s ON pes.source_id = s.id
JOIN public_event_categories pec ON pe.id = pec.event_id
JOIN categories c ON pec.category_id = c.id
WHERE s.slug = 'pubquiz-pl' AND c.slug != 'trivia';

-- Result: Event 247 "Weekly Trivia Night - Project Manhattan" has Film category
```

---

## Solution: Two-Phase Fix

### Phase 1: Immediate Data Cleanup + Preventive Measures

**Goal**: Fix existing bad data and prevent future incorrect merges.

#### 1.1 Data Cleanup Script
```sql
-- Unmerge incorrectly matched events
-- Split event 247 into two separate events:
--   - PubQuiz trivia night (keep ID 247 with Trivia category)
--   - Karnet film screening (create new event with Film category)

-- Step 1: Update event 247 to correct category
UPDATE public_event_categories
SET category_id = 29  -- Trivia category
WHERE event_id = 247 AND is_primary = true;

-- Step 2: Remove Karnet source from event 247
-- (This will be re-imported as separate event on next Karnet scrape)
DELETE FROM public_event_sources
WHERE event_id = 247 AND source_id = (
  SELECT id FROM sources WHERE slug = 'karnet'
);
```

#### 1.2 Add Stricter Deduplication Rules

**File**: `lib/eventasaurus_discovery/sources/pubquiz/dedup_handler.ex`

**Changes**:

1. **Add Recurrence Pattern Check** (lines 93-100)
```elixir
# Only match recurring events with recurring events
# PubQuiz events are ALWAYS recurring (weekly trivia nights)
defp check_fuzzy_duplicate(event_data, source) do
  # ... existing code ...

  # Filter by recurrence pattern
  recurring_matches =
    Enum.filter(matches, fn %{event: event} ->
      # Only match if target event is also recurring
      has_recurrence_rule?(event) and similar_venue?(venue_name, event.venue.name)
    end)

  # Continue with recurring_matches instead of venue_matches
end

defp has_recurrence_rule?(%{recurrence_rule: nil}), do: false
defp has_recurrence_rule?(%{recurrence_rule: rule}) when is_map(rule), do: true
defp has_recurrence_rule?(_), do: false
```

2. **Add Category Domain Check** (lines 168-202)
```elixir
defp calculate_match_confidence(pubquiz_event, existing_event) do
  scores = []

  # NEW: Category compatibility (20% weight)
  # Trivia should only match Trivia, Community, Education
  scores =
    if category_compatible?(existing_event),
      do: [0.2 | scores],
      else: return 0.0  # Hard reject if categories incompatible

  # Venue name similarity (40% - reduced from 50%)
  # ... existing venue check ...

  # GPS proximity (30% - reduced from 40%)
  # ... existing GPS check ...

  # Title similarity (10%)
  # ... existing title check ...

  Enum.sum(scores)
end

defp category_compatible?(event) do
  # Load event categories
  categories = Repo.preload(event, :categories).categories
  category_slugs = Enum.map(categories, & &1.slug)

  # PubQuiz trivia should only match compatible categories
  compatible_categories = ["trivia", "community", "education", "nightlife", "other"]

  Enum.any?(category_slugs, fn slug -> slug in compatible_categories end)
end
```

3. **Stricter Venue Name Matching** (lines 222-243)
```elixir
defp similar_venue?(venue1, venue2) do
  cond do
    is_nil(venue1) || is_nil(venue2) ->
      false

    true ->
      normalized1 = normalize_venue_name(venue1)
      normalized2 = normalize_venue_name(venue2)

      # Require exact match OR very high similarity (>= 80%)
      normalized1 == normalized2 ||
        string_similarity(normalized1, normalized2) >= 0.8
  end
end

# Add Jaro-Winkler or Levenshtein distance for fuzzy matching
defp string_similarity(str1, str2) do
  # Use String.jaro_distance/2 (available in Elixir 1.13+)
  # OR implement Levenshtein distance
  # OR use a library like :fuzzywuzzy

  String.jaro_distance(str1, str2)
end
```

4. **Add Venue Type Validation** (new function)
```elixir
defp venue_type_compatible?(pubquiz_venue_name, existing_venue_name) do
  # PubQuiz events happen at bars, pubs, restaurants, gaming cafes
  # NOT at cinemas, theaters, opera houses, stadiums

  incompatible_patterns = [
    "kino",      # cinema (Polish)
    "cinema",
    "theater",
    "theatre",
    "teatr",     # theater (Polish)
    "opera",
    "filharmonia", # philharmonic
    "arena",
    "stadium"
  ]

  existing_lower = String.downcase(existing_venue_name)

  # Reject if existing venue matches incompatible patterns
  not Enum.any?(incompatible_patterns, fn pattern ->
    String.contains?(existing_lower, pattern)
  end)
end
```

#### 1.3 Update Match Confidence Thresholds

**File**: `lib/eventasaurus_discovery/sources/base_dedup_handler.ex`

Increase minimum confidence for PubQuiz matches:
```elixir
# Current: probably uses default threshold (0.5-0.6)
# New: Require higher confidence for cross-source matches

def should_defer_to_match?(match, source, confidence) do
  # Special handling for PubQuiz source
  threshold =
    if source.slug == "pubquiz-pl",
      do: 0.85,  # Higher threshold for PubQuiz (was likely 0.6)
      else: 0.6

  # ... existing logic with new threshold ...
end
```

---

### Phase 2: Auto-Healing on Next Scrape

**Goal**: System automatically detects and fixes incorrectly merged events on subsequent scrapes.

#### 2.1 Add Conflict Detection

**File**: `lib/eventasaurus_discovery/sources/pubquiz/dedup_handler.ex`

```elixir
def check_duplicate(event_data, source) do
  case BaseDedupHandler.find_by_external_id(event_data[:external_id], source.id) do
    %Event{} = existing ->
      # NEW: Detect if existing event has conflicting sources
      if has_conflicting_sources?(existing, event_data) do
        Logger.warning("""
        🔧 Auto-healing: Event ##{existing.id} has conflicting sources.
        PubQuiz data conflicts with higher-priority source.
        Creating new separate event.
        """)

        {:unique, event_data}  # Force creation of new event
      else
        Logger.info("🔍 Found existing PubQuiz event by external_id (same source)")
        {:duplicate, existing}
      end

    nil ->
      check_fuzzy_duplicate(event_data, source)
  end
end

defp has_conflicting_sources?(event, pubquiz_data) do
  event = Repo.preload(event, [:sources, :categories])

  # Check if event has multiple sources with incompatible data
  cond do
    # If event has > 1 source AND categories are incompatible
    length(event.sources) > 1 and not category_compatible?(event) ->
      true

    # If event has recurrence_rule = nil but PubQuiz expects recurring
    is_nil(event.recurrence_rule) and not is_nil(pubquiz_data[:recurrence_rule]) ->
      true

    # If venue names are completely different
    event.venue && not similar_venue?(pubquiz_data[:venue_data][:name], event.venue.name) ->
      true

    true ->
      false
  end
end
```

#### 2.2 Add Source Priority Override

**File**: `lib/eventasaurus_discovery/scraping/processors/event_processor.ex`

```elixir
# When processing event updates, check for priority conflicts
# If lower-priority source (PubQuiz=50) is being overridden by
# higher-priority source (Karnet=70) with incompatible data,
# trigger un-merge and create separate events

defp process_source_update(event, new_source_data, source) do
  existing_sources = Repo.preload(event, :sources).sources

  # Check if any existing source has higher priority AND incompatible data
  conflicting_source = Enum.find(existing_sources, fn existing_source ->
    existing_source.priority > source.priority and
      data_conflicts?(event, new_source_data)
  end)

  if conflicting_source do
    Logger.warning("""
    🔧 Auto-healing: Detected priority conflict.
    Lower-priority source trying to update event owned by higher-priority source.
    Creating separate event instead.
    """)

    # Remove lower-priority source from event
    remove_source_from_event(event, source)

    # Create new event for this source
    create_new_event(new_source_data, source)
  else
    # Normal update flow
    update_event(event, new_source_data, source)
  end
end
```

#### 2.3 Add Monitoring & Alerting

**File**: `lib/eventasaurus_discovery/monitors/dedup_health_monitor.ex` (new file)

```elixir
defmodule EventasaurusDiscovery.Monitors.DedupHealthMonitor do
  @moduledoc """
  Monitors deduplication health and detects anomalies.

  Runs daily to check for:
  - Events with conflicting source data
  - Category mismatches
  - Venue name mismatches
  """

  use Oban.Worker,
    queue: :monitoring,
    max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("🔍 Running deduplication health check...")

    anomalies = detect_anomalies()

    if length(anomalies) > 0 do
      Logger.warning("""
      ⚠️ Deduplication Health Check: Found #{length(anomalies)} anomalies
      #{format_anomalies(anomalies)}
      """)

      # TODO: Send alert to monitoring system
    end

    {:ok, %{anomalies_found: length(anomalies)}}
  end

  defp detect_anomalies do
    # Query for events with multiple sources where:
    # 1. Categories don't match expected for source type
    # 2. Venue names are very different
    # 3. Recurrence patterns conflict

    query = """
    SELECT pe.id, pe.title,
      COUNT(DISTINCT pes.source_id) as source_count,
      COUNT(DISTINCT pec.category_id) as category_count,
      string_agg(DISTINCT s.slug, ', ') as sources,
      string_agg(DISTINCT c.slug, ', ') as categories
    FROM public_events pe
    JOIN public_event_sources pes ON pe.id = pes.event_id
    JOIN sources s ON pes.source_id = s.id
    LEFT JOIN public_event_categories pec ON pe.id = pec.event_id
    LEFT JOIN categories c ON pec.category_id = c.id
    GROUP BY pe.id, pe.title
    HAVING COUNT(DISTINCT pes.source_id) > 1
      AND (
        -- Multiple categories from different sources
        COUNT(DISTINCT pec.category_id) > 1
        -- Or specific problematic patterns
        OR (string_agg(DISTINCT s.slug, ', ') LIKE '%pubquiz-pl%'
            AND string_agg(DISTINCT c.slug, ', ') NOT LIKE '%trivia%')
      )
    """

    Repo.query!(query).rows
  end

  defp format_anomalies(anomalies) do
    Enum.map_join(anomalies, "\n", fn [id, title, source_count, cat_count, sources, cats] ->
      "  - Event ##{id}: #{title}\n" <>
      "    Sources (#{source_count}): #{sources}\n" <>
      "    Categories (#{cat_count}): #{cats}"
    end)
  end
end
```

---

## Testing Plan

### 1. Unit Tests

**File**: `test/eventasaurus_discovery/sources/pubquiz/dedup_handler_test.exs`

```elixir
test "rejects match when categories are incompatible" do
  # PubQuiz trivia event should NOT match Karnet film event
  pubquiz_event = %{
    title: "Weekly Trivia Night - Test Venue",
    venue_data: %{name: "Test Pub", latitude: 50.0, longitude: 19.0},
    recurrence_rule: %{"frequency" => "weekly"}
  }

  film_event = insert(:event,
    title: "Film Screening",
    venue: build(:venue, name: "Test Cinema", latitude: 50.0001, longitude: 19.0001),
    categories: [build(:category, slug: "film")]
  )

  confidence = DedupHandler.calculate_match_confidence(pubquiz_event, film_event)

  assert confidence == 0.0, "Should hard reject incompatible categories"
end

test "requires high venue name similarity" do
  pubquiz_event = %{venue_data: %{name: "Project Manhattan"}}
  cinema_event = %{venue: %{name: "Kino Pod Baranami"}}

  refute DedupHandler.similar_venue?(
    pubquiz_event.venue_data.name,
    cinema_event.venue.name
  ), "Should not match completely different venue names"
end

test "matches only recurring events with recurring events" do
  # PubQuiz recurring event should NOT match one-time event
  # even if at same venue
end
```

### 2. Integration Test

```elixir
test "auto-heals incorrectly merged event on next scrape" do
  # 1. Create scenario: Event merged with wrong source
  # 2. Run PubQuiz scraper again
  # 3. Verify: System detects conflict and creates separate event
end
```

### 3. Manual Verification

1. Run data cleanup script
2. Verify event 247 now shows "Trivia" category
3. Run PubQuiz scraper for Krakow
4. Verify: No incorrect merges occur
5. Run Karnet scraper
6. Verify: Film event re-created as separate event

---

## Rollout Plan

### Week 1: Phase 1 Implementation
- [ ] Day 1-2: Implement stricter dedup rules
- [ ] Day 2-3: Add unit tests
- [ ] Day 3-4: Test on staging with real data
- [ ] Day 4-5: Code review and refinement

### Week 2: Phase 1 Deployment
- [ ] Day 1: Run data cleanup script on production
- [ ] Day 2: Deploy stricter dedup rules
- [ ] Day 3: Monitor for any issues
- [ ] Day 4-5: Verify no new incorrect merges

### Week 3: Phase 2 Implementation
- [ ] Day 1-3: Implement auto-healing logic
- [ ] Day 3-4: Add dedup health monitor
- [ ] Day 4-5: Test auto-healing scenarios

### Week 4: Phase 2 Deployment
- [ ] Day 1: Deploy auto-healing logic
- [ ] Day 2-3: Trigger re-scrape of affected cities
- [ ] Day 3-5: Monitor auto-healing in action

---

## Success Metrics

### Immediate (After Phase 1)
- ✅ Event 247 shows "Trivia" category (not "Film")
- ✅ No new PubQuiz events merge with Film/Theater/Concert events
- ✅ Dedup confidence threshold prevents >95% of false matches

### Long-term (After Phase 2)
- ✅ System automatically detects and fixes conflicts within 24h
- ✅ <1% of PubQuiz events have incorrect categories
- ✅ Dedup health monitor catches anomalies before users report them

---

## Related Issues

- Original bug discovery: User screenshot showing "Film" badge on PubQuiz event
- Deduplication framework: `BaseDedupHandler` and priority system
- Category assignment: `CategoryExtractor` and YAML mappings working correctly

## Files Modified

### Phase 1
- `lib/eventasaurus_discovery/sources/pubquiz/dedup_handler.ex`
- `lib/eventasaurus_discovery/sources/base_dedup_handler.ex`
- `test/eventasaurus_discovery/sources/pubquiz/dedup_handler_test.exs`

### Phase 2
- `lib/eventasaurus_discovery/scraping/processors/event_processor.ex`
- `lib/eventasaurus_discovery/monitors/dedup_health_monitor.ex` (new)
- `test/eventasaurus_discovery/monitors/dedup_health_monitor_test.exs` (new)

## References

- PubQuiz source: `lib/eventasaurus_discovery/sources/pubquiz/`
- Category mappings: `priv/category_mappings/_defaults.yml` (working correctly)
- Dedup framework: `lib/eventasaurus_discovery/sources/base_dedup_handler.ex`
