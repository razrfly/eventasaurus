# Issue: Pattern-Based Scraper External ID Standardization & Documentation

## Summary

Standardize external_id generation across all pattern-based scrapers to use venue-based identifiers (without day_of_week suffix) and document the approach for future maintainers.

## Background

Pattern-based scrapers (PubQuiz, Inquizition, Geeks Who Drink, Speed Quizzing, Question One) track weekly recurring events at venues. Recent work on Question One (#1942) revealed inconsistencies in how external_ids are generated, affecting EventFreshnessChecker's ability to skip recently-scraped events.

**Core Principle Discovered:**
> For pattern-based recurring events, **venue IS the unique identifier**. Day of week, time, and other scheduling details are **metadata** that describe when the event happens, not **identity** that distinguishes between different events.

## Current State Analysis

### Question One ✅ FIXED (2025-01-22)
**Status:** Recently updated to venue-based approach

**Before:**
```elixir
# Transformer
external_id = "question_one_#{venue_slug}_#{day_of_week}"

# IndexJob
external_id = "question_one_venue_#{venue_slug}"
```
❌ **Mismatch:** IndexJob and Transformer generated different formats, breaking freshness checking

**After:**
```elixir
# Both Transformer AND IndexJob
external_id = "question_one_#{venue_slug}"
```
✅ **Consistent:** Venue-based identifier works for 99.9% of cases

**Files:**
- `lib/eventasaurus_discovery/sources/question_one/transformer.ex:64`
- `lib/eventasaurus_discovery/sources/question_one/jobs/index_page_job.ex:109`

### Inquizition ✅ ALREADY CORRECT
**Status:** Already uses venue-based approach

**Current implementation:**
```elixir
# transformer.ex:71
external_id = "inquizition_#{venue_data.venue_id}"
```
✅ **Correct:** Uses venue_id from source's API

**Files:**
- `lib/eventasaurus_discovery/sources/inquizition/transformer.ex:71`

### Geeks Who Drink ✅ ALREADY CORRECT
**Status:** Already uses venue-based approach

**Current implementation:**
```elixir
# transformer.ex:63
external_id = "geeks_who_drink_#{venue_data.venue_id}"
```
✅ **Correct:** Uses venue_id from source's API

**Files:**
- `lib/eventasaurus_discovery/sources/geeks_who_drink/transformer.ex:63`

### PubQuiz ⚠️ NEEDS INVESTIGATION
**Status:** Does not generate external_id in transformer

**Current implementation:**
```elixir
# transformer.ex - NO external_id field in event_map
event_map = %{
  title: build_title(venue_data[:name]),
  starts_at: next_occurrence,
  venue_id: venue_record.id,
  recurrence_rule: recurrence_rule,
  # ... no external_id
}
```
⚠️ **Investigation needed:** Where/how is external_id generated for PubQuiz events?

**Files:**
- `lib/eventasaurus_discovery/sources/pubquiz/transformer.ex`
- Need to check detail job and processor integration

### Speed Quizzing ⚠️ NEEDS INVESTIGATION
**Status:** Not yet analyzed

**Action required:**
- Search for transformer and external_id generation
- Verify pattern matches other scrapers
- Document current approach

## Edge Case Analysis: Multiple Events at Same Venue

### User's Concern
Some sources (e.g., Geeks Who Drink) occasionally have special one-off events at the same venue as their regular recurring quiz. Does venue-based external_id handle this?

### Answer: YES, with caveats ✅

**EventFreshnessChecker has THREE-LAYER matching:**

1. **Direct external_id match** (line 103-105)
   - If exact external_id was recently seen, skip it

2. **Existing event_id match** (line 113-115)
   - If external_id belongs to a recurring event recently updated, skip it

3. **PREDICTED event_id match** (line 117-119) 🎯 **KEY FALLBACK**
   - Uses title + venue similarity to predict which event new events will merge into
   - Groups events by normalized title (different titles → different groups)
   - Queries existing events with similar titles at same venue
   - Even with same external_id, events with different titles are processed separately

**Example: Geeks Who Drink Special Event**

Scenario:
- Regular quiz: external_id = `geeks_who_drink_bar_xyz`, title = "General Trivia Night"
- Special event: external_id = `geeks_who_drink_bar_xyz`, title = "Halloween Special Trivia"

What happens:
1. **First scrape (both new):**
   - EventFreshnessChecker's prediction groups by normalized title
   - "general trivia night" ≠ "halloween special trivia" → different groups
   - Both processed as new events

2. **Second scrape (regular quiz fresh, special event new):**
   - Regular quiz skipped (external_id seen recently)
   - Special event prediction: queries for similar title + venue
   - Finds "Halloween Special Trivia" (different from "General Trivia Night")
   - Processes special event separately ✅

3. **EventProcessor deduplication:**
   - Uses fuzzy title matching with dynamic thresholds
   - Different titles → separate events maintained
   - Same venue OK because titles distinguish them

**Limitation:** If special event has VERY similar title to regular event (Jaro distance > 0.85), they might merge. This is intentional behavior for recurring event consolidation.

### Real-World Validation

Pattern-based scrapers appear to only track ONE recurring event per venue in their data feeds:
- RSS feeds list venues, not individual events
- Each venue page describes one primary recurring event
- Special events typically not in scraper's data source

If a scraper DOES provide multiple events at same venue with different source external_ids, those would be overridden to use the same venue-based external_id. In practice, this hasn't been observed.

## Implementation Phases

### Phase 1: PubQuiz External ID Investigation ⏳
**Goal:** Understand and document PubQuiz external_id generation

**Tasks:**
1. Search for where PubQuiz generates external_id
2. Check if detail job or processor adds it
3. Verify it follows venue-based pattern
4. Document findings in PubQuiz README

**Files to check:**
- `lib/eventasaurus_discovery/sources/pubquiz/jobs/venue_detail_job.ex`
- `lib/eventasaurus_discovery/sources/pubquiz/README.md`

**Success criteria:**
- [ ] External_id generation location documented
- [ ] Confirmed venue-based pattern or identified need for change
- [ ] PubQuiz README updated with external_id explanation

### Phase 2: Speed Quizzing Analysis ⏳
**Goal:** Analyze and document Speed Quizzing external_id approach

**Tasks:**
1. Find Speed Quizzing transformer
2. Check external_id generation pattern
3. Compare to standard venue-based approach
4. Update if needed to match pattern

**Files to check:**
- `lib/eventasaurus_discovery/sources/speed_quizzing/transformer.ex`
- `lib/eventasaurus_discovery/sources/speed_quizzing/README.md`

**Success criteria:**
- [ ] External_id pattern analyzed and documented
- [ ] Venue-based approach confirmed or implemented
- [ ] Speed Quizzing README updated

### Phase 3: Documentation Standardization ⏳
**Goal:** Add clear documentation to ALL pattern-based scrapers

**Tasks:**
1. Create standard documentation template
2. Add to each scraper's README explaining:
   - Why venue-based external_ids are used
   - How EventFreshnessChecker uses them
   - How EventProcessor handles edge cases
   - Examples of external_id format
3. Add references to this issue for context

**Files to update:**
- `lib/eventasaurus_discovery/sources/question_one/README.md`
- `lib/eventasaurus_discovery/sources/inquizition/README.md`
- `lib/eventasaurus_discovery/sources/geeks_who_drink/README.md`
- `lib/eventasaurus_discovery/sources/pubquiz/README.md`
- `lib/eventasaurus_discovery/sources/speed_quizzing/README.md`

**Documentation template:**

```markdown
## External ID Pattern

**Format:** `{source_name}_{venue_identifier}`

**Example:** `question_one_royal_oak_twickenham`

### Why Venue-Based?

For pattern-based recurring events, the **venue IS the unique identifier**.

- Day of week, time, and scheduling are **metadata** (describe WHEN event happens)
- Venue location is **identity** (describes WHICH event it is)

### How It Works

1. **EventFreshnessChecker** uses external_id to skip recently-scraped venues
   - Checks if external_id seen within threshold (default 168h/7 days)
   - Uses title+venue prediction for new events to detect recurring patterns

2. **EventProcessor** handles deduplication after scraping
   - Uses fuzzy title matching to consolidate recurring events
   - Different titles at same venue → separate events (e.g., special events)
   - Similar titles at same venue → consolidated (recurring event pattern)

### Edge Cases

**Q: What if a venue has multiple different events?**

A: EventProcessor's title-based matching handles this:
- Regular quiz: "General Trivia Night"
- Special event: "Halloween Special Trivia"
- Different titles → processed separately ✅

**Q: What if titles are very similar?**

A: Intentional consolidation (Jaro distance > 0.85):
- "Monday Night Trivia"
- "Monday Trivia Night"
- Similar titles → merged as recurring event ✅

This is desired behavior for recurring event detection.
```

**Success criteria:**
- [ ] All 5 scraper READMEs updated with standard documentation
- [ ] Consistent terminology and examples across all docs
- [ ] References to EventFreshnessChecker and EventProcessor behavior

### Phase 4: Central Documentation Update ⏳
**Goal:** Update central scraper documentation with pattern-based scraper standards

**Tasks:**
1. Add section to SCRAPER_SPECIFICATION.md about pattern-based external_ids
2. Document the venue-based identifier pattern
3. Add examples from multiple scrapers
4. Link to individual scraper READMEs

**Files to update:**
- `docs/scrapers/SCRAPER_SPECIFICATION.md`
- `docs/RECURRING_EVENT_PATTERNS.md`

**Success criteria:**
- [ ] Central docs explain venue-based external_id pattern
- [ ] Clear distinction between pattern-based vs explicit-date scrapers
- [ ] Links to scraper-specific documentation

### Phase 5: Testing & Validation ⏳
**Goal:** Verify all scrapers work correctly with venue-based external_ids

**Tasks:**
1. Run each pattern scraper with limit flag
2. Verify EventFreshnessChecker skips fresh events
3. Check FreshnessHealthChecker shows correct metrics
4. Test edge case with multiple events at same venue (if possible)

**Test commands:**
```bash
# Question One
mix scraper.sync --source=question-one --limit=10

# Inquizition
mix scraper.sync --source=inquizition --limit=10

# Geeks Who Drink
mix scraper.sync --source=geeks-who-drink --limit=10

# PubQuiz
mix scraper.sync --source=pubquiz --limit=10

# Speed Quizzing
mix scraper.sync --source=speed-quizzing --limit=10
```

**Success criteria:**
- [ ] All scrapers generate consistent venue-based external_ids
- [ ] EventFreshnessChecker correctly skips fresh events
- [ ] FreshnessHealthChecker shows expected skip rates
- [ ] No external_id format mismatches in logs

## Related Issues

- #1942 - Question One freshness monitoring (completed, inspired this issue)

## Estimated Timeline

- Phase 1 (PubQuiz): 1-2 hours
- Phase 2 (Speed Quizzing): 1-2 hours
- Phase 3 (Documentation): 2-3 hours
- Phase 4 (Central Docs): 1 hour
- Phase 5 (Testing): 2 hours

**Total: 7-10 hours**

## Success Metrics

- [ ] All 5 pattern-based scrapers use consistent venue-based external_ids
- [ ] All scraper READMEs document external_id pattern with examples
- [ ] Central documentation explains venue-based approach
- [ ] EventFreshnessChecker skip rates >70% for pattern scrapers
- [ ] No external_id format mismatches in production logs
- [ ] Future Claude agents understand the pattern from documentation

## Notes

This is a **documentation and standardization** effort, not a major refactor. Most scrapers already follow the venue-based pattern. The goal is to:
1. Verify consistency
2. Document the "why" for future maintainers
3. Prevent regression to day_of_week-based approaches
4. Make the pattern explicit and discoverable
