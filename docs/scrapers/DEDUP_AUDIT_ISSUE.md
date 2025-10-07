# Deduplication Implementation Audit & Standardization Plan

**Created**: October 7, 2025
**Context**: Issue #1552 added dedup handlers for Bandsintown and PubQuiz, but they're not integrated into execution flow
**Severity**: High - Missing cross-source deduplication could create duplicate events

---

## Executive Summary

**Current State**: Only 1 out of 7 sources has functional deduplication (Resident Advisor). The others have either stub implementations or no implementation at all.

**Impact**: Events from multiple sources (e.g., same concert from Bandsintown + Karnet) will create duplicate entries in the database.

**Recommendation**: Standardize on the Resident Advisor pattern and implement across all sources systematically.

---

## Source-by-Source Analysis

### Priority Hierarchy

| Source | Priority | Dedup Status | Grade | Notes |
|--------|----------|--------------|-------|-------|
| **Ticketmaster** | 90 | ❌ None | **F** | Highest priority source has NO dedup! |
| **Bandsintown** | 80 | ⚠️ Stub | **C** | Handler exists, not integrated, TODO comments |
| **Resident Advisor** | 75 | ✅ **Functional** | **A+** | **ONLY working implementation** |
| **Karnet** | 30 | ⚠️ Stub | **C** | Handler + wrapper exist, but non-functional |
| **PubQuiz** | 25 | ⚠️ Stub | **C** | Handler exists, not integrated, TODO comments |
| **Cinema City** | 15 | ❌ None | **F** | No implementation |
| **Kino Kraków** | 15 | ❌ None | **F** | No implementation |

---

## Detailed Grading

### Grade A+: Resident Advisor (75)

**Implementation**: `sources/resident_advisor/dedup_handler.ex` (459 lines)

**✅ What Works**:
1. **Real Database Lookups**: Uses `Repo.get_by(Event, external_id: external_id)`
2. **Fuzzy Matching**: Implements `find_matching_events` with title normalization
3. **GPS Proximity**: Checks venue coordinates for location-based matching
4. **Priority Checking**: Compares against higher-priority sources (Ticketmaster 90, Bandsintown 80)
5. **Umbrella Event Detection**: Creates containers for festivals/conferences
6. **Quality Validation**: Comprehensive `validate_event_quality/1` function
7. **Source Module Wrapper**: Has `ResidentAdvisor.deduplicate_event/1`

**❌ What's Missing**:
- Not actually called in jobs (same as others!)
- Missing `enrich_event_data/1` function

**Code Quality**: Excellent documentation, comprehensive logic, production-ready

---

### Grade C: Bandsintown (80)

**Implementation**: `sources/bandsintown/dedup_handler.ex` (335 lines)

**✅ What Exists**:
1. Handler module with all 3 functions (`check_duplicate`, `enrich_event_data`, `validate_event_quality`)
2. Haversine distance calculation for GPS proximity (100m threshold)
3. Fuzzy artist name matching
4. Priority-based conflict resolution
5. Comprehensive documentation

**❌ Critical Issues**:
```elixir
# Line 74-82: TODO comments indicate non-functional
# TODO: Implement actual event lookup when Events module has the proper function
# Temporary - no cross-source deduplication until we have proper event lookup
events = []  # Always returns empty!
```

**Missing Components**:
- No source module wrapper (`sources/bandsintown.ex` doesn't exist)
- No job integration
- Event lookup always returns `nil`

**Code Quality**: Well-written stub, ready for integration

---

### Grade C: Karnet (30)

**Implementation**: `sources/karnet/dedup_handler.ex` (279 lines)

**✅ What Exists**:
1. Handler module with all 3 functions
2. Source module wrapper: `Karnet.deduplicate_event/1` ✅
3. Fuzzy title/date/venue matching
4. Quality validation

**❌ Critical Issues**:
```elixir
# Line 11: TODO comment
# alias EventasaurusApp.Events  # TODO: Re-enable when we have proper event lookup

# Line 71: Stub implementation
# Temporary - no deduplication until we have proper event lookup
events = []  # Always returns empty!
```

**Missing Components**:
- Not called in jobs despite having wrapper function
- Event lookup always returns `nil`

**Code Quality**: Has proper structure, needs activation

---

### Grade C: PubQuiz (25)

**Implementation**: `sources/pubquiz/dedup_handler.ex` (325 lines)

**✅ What Exists**:
1. Handler module with all 3 functions
2. Recurring event deduplication logic
3. GPS proximity matching (50m threshold, tighter than others)
4. Schedule change detection for recurring events
5. Comprehensive validation

**❌ Critical Issues**:
```elixir
# Line 73-78: TODO comments
# TODO: Implement actual recurring event lookup
# Temporary - no cross-run deduplication until we have proper event lookup
events = []  # Always returns empty!
```

**Missing Components**:
- No source module wrapper (`sources/pubquiz.ex` doesn't exist)
- No job integration
- Event lookup always returns `nil`

**Code Quality**: Well-designed for recurring events, needs integration

---

### Grade F: Ticketmaster (90)

**Status**: **No dedup implementation at all**

**Critical Issue**: This is the HIGHEST priority source (90) but has no deduplication!

**Impact**: Ticketmaster events could duplicate events from Bandsintown (80), RA (75), or any other source.

**Files Missing**:
- `sources/ticketmaster/dedup_handler.ex` ❌
- `sources/ticketmaster.ex` (main module) ❌

---

### Grade F: Cinema City (15)

**Status**: No dedup implementation

**Rationale**: Low priority (15), movie-specific events unlikely to overlap with other sources

**Files Missing**:
- `sources/cinema_city/dedup_handler.ex` ❌
- `sources/cinema_city.ex` ❌

---

### Grade F: Kino Kraków (15)

**Status**: No dedup implementation

**Rationale**: Low priority (15), movie-specific events unlikely to overlap with other sources

**Files Missing**:
- `sources/kino_krakow/dedup_handler.ex` ❌
- `sources/kino_krakow.ex` ❌

---

## Pattern Analysis

### The Resident Advisor Pattern (Recommended Standard)

**Structure**:
```text
sources/
├── resident_advisor/
│   ├── dedup_handler.ex          ← Dedup logic
│   ├── jobs/
│   │   └── event_import_job.ex   ← WHERE TO INTEGRATE
│   └── ...
└── resident_advisor.ex            ← Source module with wrapper
```

**Integration Points**:

1. **DedupHandler Module** (`sources/{source}/dedup_handler.ex`):
```elixir
defmodule EventasaurusDiscovery.Sources.{Source}.DedupHandler do
  def validate_event_quality(event_data)  # Required
  def check_duplicate(event_data)         # Required
  def enrich_event_data(event_data)       # Optional
end
```

2. **Source Module Wrapper** (`sources/{source}.ex`):
```elixir
defmodule EventasaurusDiscovery.Sources.{Source} do
  alias EventasaurusDiscovery.Sources.{Source}.DedupHandler

  def deduplicate_event(event_data) do
    case DedupHandler.validate_event_quality(event_data) do
      {:ok, validated} -> DedupHandler.check_duplicate(validated)
      {:error, reason} -> {:error, reason}
    end
  end
end
```

3. **Job Integration** (`sources/{source}/jobs/event_detail_job.ex`):
```elixir
defp process_event(event_data, source) do
  case {Source}.deduplicate_event(event_data) do
    {:unique, _} ->
      # Proceed with import
      EventProcessor.process_event(event_data, source.id, source.priority)

    {:duplicate, existing} ->
      Logger.info("⏭️  Skipping duplicate from higher-priority source")
      {:ok, :skip_duplicate}

    {:error, reason} ->
      {:error, reason}
  end
end
```

---

## Critical Gaps

### 1. Event Lookup Module Missing

**Problem**: All stub implementations return `events = []` because there's no event lookup function.

**Evidence**:
```elixir
# Bandsintown line 82:
# Temporary - no cross-source deduplication until we have proper event lookup
events = []

# Karnet line 71:
# Temporary - no deduplication until we have proper event lookup
events = []

# PubQuiz line 78:
# Temporary - no cross-run deduplication until we have proper event lookup
events = []
```

**Solution**: Resident Advisor uses `Repo.get_by(Event, external_id: external_id)` - this works!

**Question**: Why do stubs say "when Events module has the proper function"? The Events module exists and Resident Advisor uses it successfully.

---

### 2. Job Integration Gap

**Problem**: Even Karnet and Resident Advisor, which have wrapper functions, never call them.

**Evidence**:
```bash
$ grep -r "deduplicate_event" lib/eventasaurus_discovery/sources/*/jobs/
# No results!
```

**None of the jobs integrate deduplication**, not even Resident Advisor.

---

### 3. Ticketmaster Priority Gap

**Critical Issue**: Highest priority source (90) has no dedup implementation at all.

**Impact**: Could create duplicates that override lower-priority sources incorrectly.

---

## Recommended Implementation Plan

### Phase 1: Activate Existing Implementations (Priority: High)

**Goal**: Make existing dedup handlers functional

#### Step 1.1: Fix Event Lookup (All Stubs)
Replace `events = []` with actual database queries:

**Bandsintown**:
```elixir
# Replace line 82-83:
events = []

# With:
from(pe in PublicEvent,
  join: pes in PublicEventSource,
  on: pes.event_id == pe.id,
  where: pe.starts_at >= ^DateTime.add(date, -86400, :second) and
         pe.starts_at <= ^DateTime.add(date, 86400, :second)
)
|> Repo.all()
```

**Karnet**: Same pattern
**PubQuiz**: Query for recurring events with same venue

#### Step 1.2: Create Missing Source Module Wrappers

**Bandsintown** needs `sources/bandsintown.ex`:
```elixir
defmodule EventasaurusDiscovery.Sources.Bandsintown do
  alias EventasaurusDiscovery.Sources.Bandsintown.{Source, Jobs.SyncJob, DedupHandler}

  def deduplicate_event(event_data) do
    case DedupHandler.validate_event_quality(event_data) do
      {:ok, validated} -> DedupHandler.check_duplicate(validated)
      {:error, reason} -> {:error, reason}
    end
  end

  def sync(options \\ %{}), do: # ... (similar to Karnet)
  def config, do: Source.config()
  def enabled?, do: Source.enabled?()
end
```

**PubQuiz** needs `sources/pubquiz.ex`: Same pattern

#### Step 1.3: Integrate into Jobs

**All sources** need job integration in their detail/import jobs:

Add after transformation, before processing:
```elixir
{:ok, transformed_event} <- transform_event(event_data),

# ADD THIS:
{:ok, dedup_result} <- check_deduplication(transformed_event),

{:ok, result} <- process_event(transformed_event, source)
```

With helper:
```elixir
defp check_deduplication(event) do
  case {Source}.deduplicate_event(event) do
    {:unique, _} -> {:ok, :unique}
    {:duplicate, existing} -> {:ok, :skip_duplicate}
    {:error, reason} -> {:error, reason}
  end
end
```

---

### Phase 2: Implement Missing Sources (Priority: Medium-High)

#### Step 2.1: Ticketmaster Deduplication (Critical)

**Priority**: High (it's priority 90!)

**Create**:
1. `sources/ticketmaster/dedup_handler.ex`
2. `sources/ticketmaster.ex`
3. Integrate into `sources/ticketmaster/jobs/` (find the job files)

**Pattern**: Copy Resident Advisor pattern (it works!)

#### Step 2.2: Cinema City & Kino Kraków (Optional)

**Priority**: Low (priority 15, movie-specific)

**Rationale**: Movie showtimes unlikely to overlap with concerts/events from other sources.

**Decision**: Skip unless evidence shows duplication is occurring.

---

### Phase 3: Standardization & Testing (Priority: Medium)

#### Step 3.1: Standardize on Resident Advisor Pattern

**Create standard template**: `docs/scrapers/DEDUP_HANDLER_TEMPLATE.md`

**Enforce consistency**:
- All handlers must have 3 functions (validate, check, enrich)
- All sources must have wrapper module
- All jobs must call wrapper before processing

#### Step 3.2: Integration Testing

**Create test suite**: `test/eventasaurus_discovery/deduplication_integration_test.exs`

**Test scenarios**:
1. Same event from two sources → higher priority wins
2. Cross-source GPS proximity matching
3. Fuzzy title matching with variations
4. Priority override behavior
5. Recurring event deduplication (PubQuiz)

#### Step 3.3: Monitor Production Impact

**Metrics to track**:
- Events skipped due to deduplication
- Source priority override frequency
- False positive detection (legitimate events rejected)

---

## Implementation Risks

### High Risk

1. **False Positives**: Overly aggressive fuzzy matching could reject legitimate events
2. **Performance**: Database queries in hot path could slow down scraping
3. **Priority Conflicts**: Incorrect priority scoring could override better data

### Medium Risk

1. **GPS Inaccuracy**: Venue coordinates may differ slightly between sources
2. **Title Normalization**: Different sources format titles differently
3. **Timezone Issues**: Date matching across timezones

### Low Risk

1. **Code Complexity**: Dedup handlers are well-isolated
2. **Breaking Changes**: Pattern is already established (Resident Advisor)

---

## Success Criteria

### Phase 1 (Activate Existing)
- ✅ All stub implementations use real database queries
- ✅ All handlers have source module wrappers
- ✅ All jobs call deduplication before processing
- ✅ Manual testing shows duplicates are detected

### Phase 2 (Ticketmaster)
- ✅ Ticketmaster has functional dedup handler
- ✅ Ticketmaster dedup tested in production
- ✅ No false positives detected

### Phase 3 (Standardization)
- ✅ All sources follow identical pattern
- ✅ Integration tests pass
- ✅ Documentation updated with standard template

---

## Decision Points

### Question 1: Why do stubs say "when Events module has proper function"?

Resident Advisor successfully uses:
```elixir
alias EventasaurusApp.Events.Event
Repo.get_by(Event, external_id: external_id)
```

**Action**: Investigate if there's a different Events module that was planned, or if stubs are outdated.

### Question 2: Should we enable dedup for all sources at once?

**Options**:
- **A**: Enable all at once (risky but comprehensive)
- **B**: Phased rollout (Bandsintown → Karnet → PubQuiz → Ticketmaster)
- **C**: Start with Resident Advisor integration first (prove the pattern)

**Recommendation**: Option B (phased rollout)

### Question 3: What to do about Cinema City / Kino Kraków?

**Options**:
- **A**: Implement dedup for completeness
- **B**: Skip (low priority, movie-specific)
- **C**: Implement basic external_id check only

**Recommendation**: Option B (skip for now)

---

## Next Steps

1. **Immediate**: Create GitHub issue from this document
2. **Day 1**: Investigate Event module confusion (why do stubs think it doesn't exist?)
3. **Day 2**: Implement Phase 1 for Bandsintown (highest impact)
4. **Day 3**: Test Bandsintown dedup in production
5. **Week 2**: Roll out to Karnet, PubQuiz, Ticketmaster
6. **Week 3**: Integration testing and standardization

---

## References

- Issue #1552: Scraper Audit Implementation (created dedup handlers)
- `docs/scrapers/ISSUE_1552_COMPLETION.md`: Phase 3 completion notes
- `docs/scrapers/SCRAPER_SPECIFICATION.md`: Dedup handler spec (line 485+)
- Resident Advisor dedup handler: Reference implementation

---

**Signed**: Claude Code
**Date**: October 7, 2025
**Status**: Awaiting approval for implementation
