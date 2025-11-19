# Fix: Domain Compatibility Logic to Prevent Incompatible Event Merging

## Issue

PubQuiz trivia event (Event #247) incorrectly merged with Karnet film screening, showing "Film" category instead of "Trivia".

**Bug:** "Weekly Trivia Night - Project Manhattan" merged with "Palestyna w Krakowie" (film screening at cinema)

**Root cause:** "general" domain in sources table makes Karnet compatible with ALL domains, including trivia-only sources.

---

## Analysis

### Current Domain Configuration

```sql
-- Sources with "general" domain (wildcard compatibility)
id |     slug     | priority |             domains
----+--------------+----------+----------------------------------
  1 | ticketmaster |      100 | {music,sports,theater,general}
  4 | karnet       |       70 | {music,theater,cultural,general}
 11 | sortiraparis |       65 | {music,cultural,theater,general}
 14 | waw4free     |       35 | {cultural,general}

-- PubQuiz (trivia-only)
  8 | pubquiz-pl   |       25 | {trivia}
```

### Why The Bug Occurred

**Existing domain compatibility check at `lib/eventasaurus_discovery/sources/source.ex:125-139`:**

```elixir
def domains_compatible?(domains1, domains2) when is_list(domains1) and is_list(domains2) do
  has_general = "general" in domains1 or "general" in domains2
  has_overlap = not MapSet.disjoint?(MapSet.new(domains1), MapSet.new(domains2))
  has_general or has_overlap  # ← Problem: "general" matches EVERYTHING
end
```

**What happened:**
1. Karnet event at "Kino Pod Baranami" (cinema) matched to "Project Manhattan" (bar) via fuzzy venue matching
2. System checked: `domains_compatible?({trivia}, {music,theater,cultural,general})`
3. Function returned `true` because Karnet has "general" → allowed merge
4. Karnet's higher priority (70 > 25) → Film category won over Trivia

**The system already has domain compatibility checking via:**
- `lib/eventasaurus_discovery/sources/pubquiz/dedup_handler.ex:109-110` calls `BaseDedupHandler.filter_higher_priority_matches/2`
- Which calls `Source.domains_compatible?/2` to filter matches

**The problem:** "general" domain breaks the compatibility check.

---

## Solution

Fix the domain compatibility logic in ONE function to be stricter about "general" domain matching.

**Total changes:** ~10 lines in ONE file (`lib/eventasaurus_discovery/sources/source.ex`)

---

## Implementation

### Change 1: Fix Domain Compatibility Logic ⭐ **PRIMARY FIX**

**Location:** `lib/eventasaurus_discovery/sources/source.ex` lines 125-139

**Before:**
```elixir
def domains_compatible?(domains1, domains2) when is_list(domains1) and is_list(domains2) do
  # If either has "general", they're compatible with everything
  has_general = "general" in domains1 or "general" in domains2
  # Check if there's any overlap
  has_overlap = not MapSet.disjoint?(MapSet.new(domains1), MapSet.new(domains2))
  has_general or has_overlap
end
```

**After:**
```elixir
def domains_compatible?(domains1, domains2) when is_list(domains1) and is_list(domains2) do
  # Extract specific domains (excluding "general")
  specific1 = MapSet.new(domains1) |> MapSet.delete("general")
  specific2 = MapSet.new(domains2) |> MapSet.delete("general")

  # Check for overlap in specific domains
  has_specific_overlap = not MapSet.disjoint?(specific1, specific2)

  # ONLY compatible if both have "general" (not just one)
  both_general = "general" in domains1 and "general" in domains2

  has_specific_overlap or both_general
end
```

**Impact:**
- `{trivia}` vs `{music,theater,cultural,general}` → **FALSE** ✅ (no specific overlap, only one has general)
- `{music}` vs `{music,theater,cultural,general}` → **TRUE** (overlap in "music")
- `{general}` vs `{music,theater,cultural,general}` → **TRUE** (both have general)
- `{cultural,general}` vs `{music,theater,cultural,general}` → **TRUE** (overlap in "cultural")

**Why this works:**
- Removes "general" as a wildcard that matches everything
- Requires actual domain overlap (e.g., both have "music" or "cultural")
- Sources with ONLY "general" can still match other "general" sources
- Fixes the bug system-wide, not just for PubQuiz

---

### Change 2: Stricter Venue Name Matching (OPTIONAL)

**Location:** `lib/eventasaurus_discovery/sources/pubquiz/dedup_handler.ex` lines 222-234

**Before:**
```elixir
defp similar_venue?(venue1, venue2) do
  cond do
    is_nil(venue1) || is_nil(venue2) ->
      false

    true ->
      normalized1 = normalize_venue_name(venue1)
      normalized2 = normalize_venue_name(venue2)

      normalized1 == normalized2 ||
        String.contains?(normalized1, normalized2) ||
        String.contains?(normalized2, normalized1)
  end
end
```

**After:**
```elixir
defp similar_venue?(venue1, venue2) do
  cond do
    is_nil(venue1) || is_nil(venue2) ->
      false

    true ->
      normalized1 = normalize_venue_name(venue1)
      normalized2 = normalize_venue_name(venue2)

      # Require exact match OR 70%+ similarity (Jaro distance)
      normalized1 == normalized2 || String.jaro_distance(normalized1, normalized2) >= 0.7
  end
end
```

**Why:** `String.jaro_distance/2` is built into Elixir 1.13+, no dependencies needed.

**Impact:**
- "Kino Pod Baranami" vs "Project Manhattan" = ~25% similarity → **REJECT** ✅
- "Project Manhattan" vs "Project Manhattan Bar" = >70% similarity → **ACCEPT**

---

### Change 3: Venue Type Blocker (OPTIONAL)

**Location:** `lib/eventasaurus_discovery/sources/pubquiz/dedup_handler.ex` line 103

**Before:**
```elixir
# Filter by venue name similarity
venue_matches =
  Enum.filter(matches, fn %{event: event} ->
    similar_venue?(venue_name, event.venue.name)
  end)
```

**After:**
```elixir
# Filter by venue name similarity AND venue type compatibility
venue_matches =
  Enum.filter(matches, fn %{event: event} ->
    similar_venue?(venue_name, event.venue.name) &&
      venue_type_compatible?(venue_name, event.venue.name)
  end)
```

**Add new function at end of file (after line 243):**
```elixir
# Check if venue types are compatible (bars/pubs vs cinemas/theaters)
defp venue_type_compatible?(pubquiz_venue, existing_venue) do
  # PubQuiz events happen at bars, pubs, restaurants, game cafes
  # NOT at cinemas, theaters, opera houses
  incompatible_keywords = [
    "kino",       # cinema (Polish)
    "cinema",     # cinema (English)
    "theater",
    "theatre",
    "teatr",      # theater (Polish)
    "opera",
    "filharmonia" # philharmonic (Polish)
  ]

  existing_lower = String.downcase(existing_venue)

  # Reject if existing venue contains incompatible keywords
  not Enum.any?(incompatible_keywords, fn keyword ->
    String.contains?(existing_lower, keyword)
  end)
end
```

**Impact:** "Kino Pod Baranami" contains "kino" → REJECT merge with bar venue ✅

---

## Complete Diff Summary

**Primary Fix (Required):**
- **File:** `lib/eventasaurus_discovery/sources/source.ex`
- **Lines:** 125-139
- **Changes:** Replace domain compatibility logic (~10 lines)

**Secondary Fixes (Optional, Defense in Depth):**
- **File:** `lib/eventasaurus_discovery/sources/pubquiz/dedup_handler.ex`
- **Change 2:** Line 228 - Replace `String.contains?` with `String.jaro_distance(...) >= 0.7`
- **Change 3:** Line 103 - Add `&& venue_type_compatible?(...)`
- **Change 3:** Lines 245-260 - Add `venue_type_compatible?/2` function

---

## Testing

### Manual Test in IEx

```elixir
# Start IEx with project
iex -S mix

# Test 1: Domain compatibility (PRIMARY TEST)
alias EventasaurusDiscovery.Sources.Source

# Should now return FALSE (no specific domain overlap)
Source.domains_compatible?(["trivia"], ["music", "theater", "cultural", "general"])
# Expected: false ✅

# Should return TRUE (overlap in "music")
Source.domains_compatible?(["music"], ["music", "theater", "cultural", "general"])
# Expected: true

# Should return TRUE (both have "general")
Source.domains_compatible?(["general"], ["music", "theater", "cultural", "general"])
# Expected: true

# Should return TRUE (overlap in "cultural")
Source.domains_compatible?(["cultural", "general"], ["music", "theater", "cultural", "general"])
# Expected: true

# Test 2: Venue name similarity (if implementing Change 2)
alias EventasaurusDiscovery.Sources.Pubquiz.DedupHandler

DedupHandler.similar_venue?("Kino Pod Baranami", "Project Manhattan")
# Expected: false (only ~25% similar)

DedupHandler.similar_venue?("Project Manhattan", "Project Manhattan Bar")
# Expected: true (>70% similar)

# Test 3: Venue type compatibility (if implementing Change 3)
DedupHandler.venue_type_compatible?("Test Pub", "Kino Pod Baranami")
# Expected: false (contains "kino")

DedupHandler.venue_type_compatible?("Test Pub", "Another Bar")
# Expected: true (both bars)
```

### Integration Test

**Test scenario:** Re-run scrapers and verify no incorrect merges

```bash
# 1. Clear event #247 incorrect merge
mix run -e """
alias EventasaurusApp.Repo
alias EventasaurusDiscovery.PublicEvents.PublicEventSource

# Remove Karnet source from event 247
Repo.get_by(PublicEventSource, event_id: 247, source_id: 4) |> Repo.delete()
"""

# 2. Run PubQuiz scraper for Krakow
mix scraper.run pubquiz --city krakow

# 3. Run Karnet scraper for Krakow
mix scraper.run karnet --city krakow

# 4. Verify: Event 247 has Trivia category
# 5. Verify: New film event created separately (not merged)
```

---

## Acceptance Criteria

### Must Pass
- [ ] Domain compatibility: `Source.domains_compatible?(["trivia"], ["music", "theater", "cultural", "general"]) == false`
- [ ] Event #247 shows "Trivia" category (not "Film")
- [ ] All existing tests still pass: `mix test`
- [ ] No regression in other source deduplication

### Integration Tests
- [ ] PubQuiz scraper runs successfully
- [ ] No PubQuiz events merge with Film/Theater events from Karnet
- [ ] Karnet film events create separate entries
- [ ] Sources with legitimate domain overlap (e.g., both "music") still merge correctly

---

## Deployment Steps

### Day 1: Implement & Test
1. Make changes to `lib/eventasaurus_discovery/sources/source.ex`
2. Optionally make changes to `lib/eventasaurus_discovery/sources/pubquiz/dedup_handler.ex`
3. Run manual IEx tests (see above)
4. Run unit tests: `mix test`
5. Commit: `git commit -m "fix: prevent 'general' domain from matching incompatible events"`

### Day 2: Deploy Staging
1. Deploy to staging
2. Run integration tests with real scrapers
3. Monitor logs for any errors
4. Verify no incorrect merges occur
5. Verify sources with legitimate overlap still merge

### Day 3: Deploy Production
1. Deploy to production
2. Fix event #247 in database:
```sql
-- Remove incorrect Karnet source
DELETE FROM public_event_sources
WHERE event_id = 247 AND source_id = 4;

-- Verify event now shows Trivia category
SELECT e.id, e.title, c.name as category
FROM public_events e
JOIN public_event_categories pec ON pec.event_id = e.id AND pec.is_primary = true
JOIN categories c ON c.id = pec.category_id
WHERE e.id = 247;
```
3. Re-run Karnet scraper for Krakow
4. Verify film event created as separate entry

### Day 4: Monitor
1. Check logs for any dedup warnings
2. Verify no new category mismatches
3. Monitor scraper success rates across ALL sources
4. Check that legitimate merges (same domains) still work

---

## Rollback Plan

If issues occur:

1. **Revert code:**
```bash
git revert <commit-hash>
git push origin main
```

2. **Temporary workaround:** Disable PubQuiz scraper
```elixir
# In lib/eventasaurus_discovery/sources/pubquiz.ex
def enabled?, do: false
```

---

## Success Metrics

**Immediate (Day 1):**
- ✅ Domain compatibility logic working correctly in IEx
- ✅ Unit tests pass

**Short-term (Week 1):**
- ✅ Event #247 shows "Trivia" category
- ✅ 0 PubQuiz events with Film/Theater categories
- ✅ Scraper success rate unchanged for all sources
- ✅ No false negatives (legitimate merges still work)

**Long-term (Month 1):**
- ✅ <1% category mismatches across all sources
- ✅ No user reports of incorrect categorization
- ✅ Dedup system works correctly for all domain combinations

---

## Why This Solution is Better

### Compared to Hardcoding Categories

**Old approach (hardcoded):**
```elixir
# In pubquiz/dedup_handler.ex
incompatible = ["film", "theatre", "concerts", "sports", "arts", "opera", "dance", "comedy"]
```
- ❌ Duplicates domain logic already in sources table
- ❌ Requires maintenance when new categories added
- ❌ Only fixes PubQuiz, not system-wide issue
- ❌ Reinvents the wheel

**New approach (fix domain logic):**
```elixir
# In source.ex
specific1 = MapSet.new(domains1) |> MapSet.delete("general")
specific2 = MapSet.new(domains2) |> MapSet.delete("general")
has_specific_overlap = not MapSet.disjoint?(specific1, specific2)
```
- ✅ Uses existing domain system in sources table
- ✅ Fixes bug system-wide for all sources
- ✅ Self-maintaining (domains defined per source)
- ✅ Cleaner, more maintainable code

---

## Related Issues

- **#2317** - Comprehensive root cause analysis (reference)
- **#2319** - Simple fix approach (superseded by this issue)
- **Event #247** - Example of bug in production database

## Files Changed

**Required:**
- `lib/eventasaurus_discovery/sources/source.ex` (~10 lines modified)

**Optional (defense in depth):**
- `lib/eventasaurus_discovery/sources/pubquiz/dedup_handler.ex` (+20 lines, ~2 modified)

## Priority

**HIGH** - Affects data quality and user experience across all sources with "general" domain

## Estimated Effort

- Implementation: 30 minutes (primary fix) + 30 minutes (optional fixes)
- Testing: 1 hour
- Deployment: 30 minutes
- **Total: 2-2.5 hours**
