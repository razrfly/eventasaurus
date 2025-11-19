# Simple Fix: Prevent PubQuiz Trivia/Film Event Merging

## Problem

Event #247: PubQuiz trivia event merged with Karnet film screening, showing wrong category.

**What happened:**
- PubQuiz: "Weekly Trivia Night - Project Manhattan" (bar, Trivia category)
- Karnet: "Palestyna w Krakowie" film screening at "Kino Pod Baranami" (cinema, Film category)
- Result: Merged into one event, Karnet's Film category won ❌

**Root cause:**
1. Karnet venue "Kino Pod Baranami" (cinema) not in database
2. Venue resolution incorrectly matched to "Project Manhattan" (bar)
3. Dedup logic merged them (same venue, similar date)
4. No category compatibility check
5. Higher priority Karnet (70) overwrote PubQuiz category (25)

---

## Three Simple Fixes

These minimal tweaks prevent this specific bug without changing the overall dedup strategy.

### Fix #1: Add Category Compatibility Check ⭐ **CRITICAL**

**What:** Don't merge events with incompatible categories.

**Why:** Trivia events should never merge with Film/Theater/Concert events.

**Where:** `lib/eventasaurus_discovery/sources/pubquiz/dedup_handler.ex` line ~168

**Change:**
```elixir
defp calculate_match_confidence(pubquiz_event, existing_event) do
  scores = []

  # NEW: Category compatibility check - HARD REJECT incompatible categories
  existing_event_with_cats = Repo.preload(existing_event, :categories)
  category_slugs = Enum.map(existing_event_with_cats.categories, & &1.slug)

  # PubQuiz = Trivia events only
  # Compatible: trivia, community, education, nightlife, other
  # Incompatible: film, theatre, concerts, sports, arts
  incompatible_categories = ["film", "theatre", "concerts", "sports", "arts", "opera", "dance", "comedy"]

  if Enum.any?(category_slugs, fn slug -> slug in incompatible_categories end) do
    return 0.0  # Hard reject - return immediately with 0 confidence
  end

  # ... rest of existing scoring logic ...
end
```

**Impact:** Would have prevented this exact bug. Film category would have triggered hard reject.

---

### Fix #2: Stricter Venue Name Matching ⭐ **IMPORTANT**

**What:** Require 70%+ similarity instead of simple substring matching.

**Why:** "Kino Pod Baranami" should NOT match "Project Manhattan"

**Where:** `lib/eventasaurus_discovery/sources/pubquiz/dedup_handler.ex` line ~222

**Current code (TOO LOOSE):**
```elixir
defp similar_venue?(venue1, venue2) do
  normalized1 = normalize_venue_name(venue1)
  normalized2 = normalize_venue_name(venue2)

  normalized1 == normalized2 ||
    String.contains?(normalized1, normalized2) ||  # ❌ Too loose
    String.contains?(normalized2, normalized1)     # ❌ Too loose
end
```

**New code (STRICTER):**
```elixir
defp similar_venue?(venue1, venue2) do
  cond do
    is_nil(venue1) || is_nil(venue2) ->
      false

    true ->
      normalized1 = normalize_venue_name(venue1)
      normalized2 = normalize_venue_name(venue2)

      # Require exact match OR high similarity (70%+)
      normalized1 == normalized2 || string_similarity(normalized1, normalized2) >= 0.7
  end
end

# Use built-in Jaro distance (available in Elixir 1.13+)
defp string_similarity(str1, str2) do
  String.jaro_distance(str1, str2)
end
```

**Impact:** "Kino Pod Baranami" vs "Project Manhattan" = ~25% similarity → REJECT

---

### Fix #3: Venue Type Keyword Blocker ⭐ **SAFETY NET**

**What:** Block merges between incompatible venue types (cinema vs bar).

**Why:** Even if names somehow match, venue types shouldn't mix.

**Where:** `lib/eventasaurus_discovery/sources/pubquiz/dedup_handler.ex` line ~102 (in check_fuzzy_duplicate)

**Add before venue matching:**
```elixir
# Filter by venue name similarity AND venue type compatibility
venue_matches =
  Enum.filter(matches, fn %{event: event} ->
    similar_venue?(venue_name, event.venue.name) &&
      venue_type_compatible?(venue_name, event.venue.name)
  end)

# New function (add at end of file)
defp venue_type_compatible?(pubquiz_venue, existing_venue) do
  # PubQuiz events happen at bars, pubs, restaurants, cafes
  # NOT at cinemas, theaters, opera houses

  incompatible_keywords = [
    "kino",      # cinema (Polish)
    "cinema",    # cinema (English)
    "theater",   # theater
    "theatre",   # theatre
    "teatr",     # theater (Polish)
    "opera",     # opera
    "filharmonia" # philharmonic
  ]

  existing_lower = String.downcase(existing_venue)

  # Reject if existing venue contains incompatible keywords
  not Enum.any?(incompatible_keywords, fn keyword ->
    String.contains?(existing_lower, keyword)
  end)
end
```

**Impact:** "Kino Pod Baranami" contains "kino" → REJECT merge with bar venue

---

## Implementation

### File to Modify
**Only one file:** `lib/eventasaurus_discovery/sources/pubquiz/dedup_handler.ex`

### Changes Summary
1. **Line ~168**: Add category compatibility check (10 lines)
2. **Line ~222**: Replace substring matching with Jaro distance (5 lines)
3. **Line ~102**: Add venue type check (2 lines)
4. **Line ~245**: Add venue_type_compatible? function (15 lines)

**Total:** ~30 lines of code changes in ONE file

---

## Testing

### Manual Test
```elixir
# Test category blocking
iex> DedupHandler.calculate_match_confidence(
  %{title: "Weekly Trivia Night", venue_data: %{name: "Test Pub"}},
  %{title: "Film Screening", categories: [%{slug: "film"}]}
)
0.0  # ✅ Hard reject

# Test venue similarity
iex> DedupHandler.similar_venue?("Kino Pod Baranami", "Project Manhattan")
false  # ✅ Too different (25% similarity < 70% threshold)

# Test venue type blocking
iex> DedupHandler.venue_type_compatible?("Test Pub", "Kino Pod Baranami")
false  # ✅ Contains "kino" - cinema incompatible with pub
```

### Integration Test
1. Run PubQuiz scraper for Krakow
2. Run Karnet scraper for Krakow
3. Verify: Film events don't merge with Trivia events

---

## Rollout

### Immediate (Today)
- [ ] Apply 3 fixes to `pubquiz/dedup_handler.ex`
- [ ] Run manual tests in IEx
- [ ] Deploy to staging

### Day 2
- [ ] Test on staging with real scrapers
- [ ] Verify no incorrect merges
- [ ] Deploy to production

### Day 3
- [ ] Fix event #247 in database:
```sql
-- Remove Karnet source from event 247
DELETE FROM public_event_sources
WHERE event_id = 247 AND source_id = (SELECT id FROM sources WHERE slug = 'karnet');

-- Update category to Trivia
UPDATE public_event_categories
SET category_id = 29  -- Trivia
WHERE event_id = 247 AND is_primary = true;
```
- [ ] Re-run Karnet scraper
- [ ] Verify: Film event created as separate event

---

## Success Criteria

✅ Event #247 shows "Trivia" category (not "Film")
✅ No PubQuiz events merge with Film/Theater/Concert events
✅ Venue names require 70%+ similarity to match
✅ Cinemas don't match with bars/pubs

---

## Why These Fixes Work

| Fix | Prevents | Example |
|-----|----------|---------|
| **Category check** | Cross-category merges | Trivia ≠ Film |
| **Stricter similarity** | Wrong venue matches | "Kino Pod Baranami" ≠ "Project Manhattan" |
| **Venue type blocker** | Cinema/bar confusion | "kino" = cinema, reject |

**All three are independent safety checks** - even if one fails, the others catch the bug.

---

## Related

- Original issue: #2317 (comprehensive analysis, keep open for reference)
- This issue: Simple, focused fix for immediate deployment
- Root cause: Venue resolution + missing validation checks
