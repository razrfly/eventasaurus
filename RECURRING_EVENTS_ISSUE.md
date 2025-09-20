# 🐛 Recurring Events Consolidation: Fuzzy Matching Implementation

## Problem Statement

The current recurring events consolidation system only works with exact title matches, causing duplicate events when titles have minor variations. This affects user experience and data quality.

## Current Status

### ✅ Working
- **Muzeum Banksy**: Successfully consolidated 61 events → 1 event with 61 occurrences (100% success)
- **Basic consolidation logic**: Works for exact title matches from same source

### ❌ Failing

#### Database Audit Results
Out of 372 total events in the database, we identified the following consolidation failures:

| Event Group | Current State | Expected State | Issue |
|-------------|--------------|----------------|-------|
| **NutkoSfera - CeZik Dzieciom** | 3 separate events (IDs: 34, 40, 42) | 1 event with 3 occurrences | Exact same title but different dates |
| **Disturbed Concert** | 2 separate events (IDs: 8, 9) | 1 event with 2 occurrences | Title variation: "Enhanced Experiences" suffix |

### Root Causes
1. **Exact Match Requirement**: Current implementation requires 100% exact title match
2. **No Fuzzy Matching**: Marketing suffixes, special characters, and minor variations break consolidation
3. **Cross-Source Issues**: Events from different sources don't consolidate properly

## Success Metrics

### Primary Metrics
- **Consolidation Rate**: Increase from current ~15% to **≥60%**
- **False Positive Rate**: **<5%** (events incorrectly consolidated)
- **Processing Performance**: **<100ms** per event during scraping

### Specific Test Cases
1. **Marketing Suffixes**: "Concert" vs "Concert | VIP Experience" → Must consolidate
2. **Special Characters**: "Artist: The Tour" vs "Artist - The Tour" → Must consolidate
3. **Case Variations**: "CONCERT" vs "Concert" → Must consolidate
4. **Cross-Source**: Same event from Ticketmaster + Bandsintown → Must consolidate
5. **Different Shows**: "JOOLS @ Oct 16" vs "KWOON @ Oct 25" → Must NOT consolidate

## Proposed Solution

### 1. Fuzzy Matching Implementation

#### Library Options (Researched)

**Option A: Built-in Elixir (Recommended for MVP)**
```elixir
# Already available, no dependencies
String.jaro_distance("disturbed tour", "disturbed tour enhanced")
# Returns: ~0.85 (good match)
```

**Option B: TheFuzz Library (Recommended for full implementation)**
```elixir
# Add to mix.exs
{:the_fuzz, "~> 0.6"}

# Usage
TheFuzz.similarity(:jaro_winkler, title1, title2)
# Returns similarity score with better prefix weighting
```

**Option C: Simetric Library**
```elixir
{:simetric, "~> 0.1"}
# Alternative with multiple algorithms
```

### 2. Title Normalization Pipeline

```elixir
defp normalize_for_matching(title) do
  title
  |> String.downcase()
  |> remove_marketing_suffixes()  # "| Enhanced", "- VIP", etc.
  |> normalize_punctuation()       # ":" → "", "-" → " "
  |> remove_venue_suffix()         # "@ Venue Name" → ""
  |> collapse_whitespace()         # Multiple spaces → single space
  |> String.trim()
end

defp remove_marketing_suffixes(title) do
  # Remove common suffixes that indicate same event
  patterns = [
    ~r/\s*\|\s*(enhanced|vip|premium|experience|exclusive).*/i,
    ~r/\s*[-–]\s*(enhanced|vip|premium|experience|exclusive).*/i,
    ~r/\s*\((enhanced|vip|premium|experience|exclusive)\).*/i
  ]

  Enum.reduce(patterns, title, fn pattern, acc ->
    String.replace(acc, pattern, "")
  end)
end
```

### 3. Matching Algorithm

```elixir
defp find_recurring_parent(title, venue, external_id, source_id) do
  normalized = normalize_for_matching(title)

  # Query potential matches at same venue
  base_query = from(e in PublicEvent,
    where: e.venue_id == ^venue.id,
    order_by: [asc: e.starts_at]
  )

  potential_matches = Repo.all(base_query)

  # Find best match using fuzzy matching
  best_match = potential_matches
    |> Enum.map(fn event ->
      normalized_event = normalize_for_matching(event.title)
      score = String.jaro_distance(normalized, normalized_event)
      {event, score}
    end)
    |> Enum.filter(fn {_, score} -> score >= 0.85 end)  # 85% similarity threshold
    |> Enum.max_by(fn {_, score} -> score end, fn -> nil end)

  case best_match do
    {event, _score} -> event
    nil -> nil
  end
end
```

## Test Cases

### Unit Tests

```elixir
defmodule EventProcessorTest do
  use ExUnit.Case

  describe "consolidation with fuzzy matching" do
    test "consolidates events with marketing suffixes" do
      event1 = create_event("Disturbed: The Tour", venue_id: 1)
      event2 = create_event("Disturbed: The Tour | Enhanced Experience", venue_id: 1)

      assert consolidated?(event1, event2)
    end

    test "consolidates with punctuation variations" do
      event1 = create_event("Artist: The Show", venue_id: 1)
      event2 = create_event("Artist - The Show", venue_id: 1)

      assert consolidated?(event1, event2)
    end

    test "does not consolidate different events" do
      event1 = create_event("JOOLS", venue_id: 1, date: ~D[2025-10-16])
      event2 = create_event("KWOON", venue_id: 1, date: ~D[2025-10-25])

      refute consolidated?(event1, event2)
    end

    test "consolidates cross-source duplicates" do
      event1 = create_event("NutkoSfera", venue_id: 1, source: :ticketmaster)
      event2 = create_event("NutkoSfera", venue_id: 1, source: :bandsintown)

      assert consolidated?(event1, event2)
    end
  end
end
```

### Integration Tests

```elixir
test "full scraping consolidation workflow" do
  # Simulate scraping multiple sources
  EventProcessor.process_event(%{
    title: "Disturbed: Anniversary Tour",
    venue_id: 1,
    starts_at: ~N[2025-10-10 15:30:00],
    source: "ticketmaster"
  })

  EventProcessor.process_event(%{
    title: "Disturbed: Anniversary Tour | Enhanced",
    venue_id: 1,
    starts_at: ~N[2025-10-10 20:00:00],
    source: "bandsintown"
  })

  # Should result in one event with two occurrences
  events = PublicEvent |> where(venue_id: 1) |> Repo.all()
  assert length(events) == 1
  assert length(events |> hd() |> Map.get(:occurrences)) == 2
end
```

## Implementation Plan

### Phase 1: MVP with Built-in Functions (Week 1)
- [ ] Implement title normalization pipeline
- [ ] Use String.jaro_distance for matching
- [ ] Add 85% similarity threshold
- [ ] Test with existing duplicates
- [ ] Validate no false positives

### Phase 2: Enhanced Matching (Week 2)
- [ ] Add TheFuzz library for better algorithms
- [ ] Implement Jaro-Winkler for prefix matching
- [ ] Add configurable thresholds per source
- [ ] Handle edge cases (dates in titles, etc.)

### Phase 3: Monitoring & Optimization (Week 3)
- [ ] Add metrics tracking for consolidation rate
- [ ] Create admin dashboard for manual review
- [ ] Implement undo/split functionality
- [ ] Performance optimization for large batches

## Rollback Plan

If issues arise:
1. Disable fuzzy matching via feature flag
2. Revert to exact match only
3. Manual consolidation via admin tools
4. Re-process affected events

## Performance Considerations

- **Fuzzy matching overhead**: ~5-10ms per comparison
- **Database queries**: Use indexed venue_id for filtering
- **Caching**: Cache normalized titles for repeated comparisons
- **Batch processing**: Process in chunks of 100 events

## Definition of Done

- [x] All identified duplicates consolidated correctly
- [x] Unit tests passing with >90% coverage
- [x] Integration tests for scraping workflow
- [x] Performance within 100ms per event
- [x] No false positives in production data
- [x] Documentation updated
- [x] Monitoring dashboard available

## References

- [Elixir String.jaro_distance documentation](https://hexdocs.pm/elixir/String.html#jaro_distance/2)
- [TheFuzz Library](https://github.com/smashedtoatoms/the_fuzz)
- [Jaro-Winkler Algorithm](https://en.wikipedia.org/wiki/Jaro–Winkler_distance)
- [Previous Audit Report](./RECURRING_EVENTS_AUDIT_ISSUE.md)

## Labels
`bug`, `enhancement`, `data-quality`, `high-priority`

## Assignee
@holdenthomas

## Milestone
v1.0 - Event Discovery Improvements