# Issue: Venue Deduplication Workflow Redesign

## Problem Statement

The current venue deduplication system is fundamentally broken and unusable:

1. **Inflated/inaccurate numbers**: Kraków shows "112 potential duplicates (42 groups)" - this seems excessively high and needs validation
2. **Group-based detection is flawed**: The algorithm groups venues transitively (A matches B, B matches C → A,B,C grouped) creating "super groups" of 8+ unrelated venues
3. **Dangerous UX**: "Merge All Venues in Group" button can destroy data
4. **No city context**: Global duplicate management doesn't help city-by-city cleanup
5. **No false positive handling**: Can't mark pairs as "not duplicates" to exclude from future detection
6. **Broken navigation**: Links from city health page don't work properly (minor, already fixed)

## Root Cause

The core issue is **group-based detection** instead of **pair-based detection**. When venue A is similar to B, and B is similar to C, the current system groups A, B, C together even if A and C have nothing in common.

**Example of bad grouping observed:**
- "Duplicate Group 1" contained 8 completely unrelated Kraków venues: Cricoteka, Rynek Główny, Stary Teatr, etc.

---

## Proposed Solution: Pair-Based Duplicate Management

### Key Principles

1. **Pair-based, not group-based**: Each duplicate relationship is a pair with its own confidence score
2. **City-first workflow**: Start from city health, review duplicates for THAT city
3. **One pair at a time**: No bulk operations, review each pair individually
4. **Safe merges**: Preview what will happen, soft-delete with undo capability
5. **Exclusion support**: Mark false positives as "not duplicates" permanently
6. **Full audit trail**: Log every decision with who/when/why

---

## Phases

### Phase 1: Validation & Metrics ✅ COMPLETED
**Goal:** Verify detection accuracy before building UI

**Tasks:**
- [x] Audit current duplicate detection algorithm
- [x] Sample 20 random "duplicate pairs" from Kraków, manually verify
- [x] Calculate true positive vs false positive rate
- [x] Identify false positive patterns
- [x] Document recommended threshold adjustments

---

## Phase 1 Audit Report

### Algorithm Analysis

**Two detection systems exist:**

1. **`Venues.find_duplicate_groups/1`** (`venues.ex:625-685`)
   - Global detection across all venues
   - Uses distance-based similarity thresholds

2. **`VenueDeduplication.find_duplicates_for_city/2`** (`venue_deduplication.ex:91-106`)
   - City-scoped detection
   - Calls `group_into_clusters()` which creates **transitive super-groups**

**Current Threshold Logic:**
```sql
CASE
  WHEN distance < 50 THEN name_similarity >= 0.0   -- PROBLEM: Any venue within 50m flagged!
  WHEN distance < 100 THEN name_similarity >= 0.4
  WHEN distance < 200 THEN name_similarity >= 0.5
  ELSE name_similarity >= 0.6
END
```

### Sample Verification (25 Random Kraków Pairs)

| Category | Count | Percentage |
|----------|-------|------------|
| **True Duplicates** | 5-6 | 20-24% |
| **False Positives** | 17-19 | 68-76% |
| **Uncertain** | 2 | 8% |

**True Duplicates Found:**
- "Teatr Cabaret" / "Cabaret" (13.7m, 57.1% sim) ✅
- "Klub Gwarek" / "Gwarek" (17.8m, 58.3% sim) ✅
- "Kuźnia | Ośrodek Kultury Norwida" / "Klub Kuźnia" (14.7m, 21.2% sim) ✅
- "Main Square" / "Rynek Główny" (44.9m, 0% sim - EN/PL names) ✅

**Common False Positive Patterns:**
1. Different venues at same address: "Teatr Bez Rzdów" / "Pałac Nieśmiertelności"
2. Unrelated neighbors: "Lastriko" / "MyPub" (48.6m apart, 0% similarity)
3. Rynek Główny clustering: 10+ distinct venues flagged as "duplicates"

### Quantitative Analysis (All Kraków Pairs)

**Pairs by Distance Band:**
| Distance | Total Pairs | High Sim (≥50%) | Low Sim (<30%) | Avg Sim |
|----------|-------------|-----------------|----------------|---------|
| < 50m | 77 | **5 (6.5%)** | 67 (87%) | 8.0% |
| 50-100m | 167 | 0 | 165 (99%) | 3.4% |
| 100-200m | 637 | 0 | 625 (98%) | 3.1% |
| 200-500m | 2,974 | 0 | 2,967 (99.8%) | 2.3% |

**Key Finding:** Of 77 pairs within 50m, only **5 (6.5%) have high name similarity**. The other 72 are false positives caused by the "< 50m = 0% similarity" threshold.

**Threshold Comparison:**
```
Total proximity pairs (<500m): 3,855
Currently flagged (distance-based): 80 pairs (2.1%)

If we required minimum similarity regardless of distance:
  ≥50% similarity: 5 pairs (0.1%) - likely TRUE duplicates
  ≥40% similarity: 11 pairs (0.3%)
  ≥30% similarity: 31 pairs (0.8%)
```

### Root Cause Summary

1. **< 50m threshold allows 0% similarity** - flags any nearby venues as duplicates
2. **Transitive grouping** - `group_into_clusters()` creates connected components where A↔B and B↔C → {A,B,C}
3. **Urban density** - Kraków's Rynek Główny has 10+ venues within 50m of each other

### Recommendations

**Threshold Changes:**
```sql
-- BEFORE (current - broken)
WHEN distance < 50 THEN name_similarity >= 0.0

-- AFTER (recommended)
WHEN distance < 50 THEN name_similarity >= 0.30
WHEN distance < 100 THEN name_similarity >= 0.40
WHEN distance < 200 THEN name_similarity >= 0.45
ELSE name_similarity >= 0.50
```

**Architecture Changes:**
1. **Eliminate transitive grouping** - switch to pair-based detection
2. **Store pairs in database** - pre-compute instead of computing on page load
3. **Add confidence scoring** - combine distance + similarity for ranking

**Decision:** Proceed with Phase 2 (pair-based refactor). The current algorithm has ~76% false positive rate and is unusable.

---

### Phase 2: Algorithm Refactor ✅ COMPLETED
**Goal:** Switch from group-based to pair-based detection

**Completed:**
- [x] Refactor `find_duplicate_groups` → `find_duplicate_pairs`
- [x] Add city_id filter for city-scoped queries
- [x] Respect exclusions - never return pairs marked "not_duplicate"
- [x] Add confidence scoring (similarity * 0.7 + distance_weight * 0.3)
- [x] Update city health template for pair-based display
- [x] 22 tests passing

**Algorithm Changes Implemented:**
```sql
-- NEW thresholds (require minimum similarity at all distances)
WHEN distance < 50 THEN name_similarity >= 0.30
WHEN distance < 100 THEN name_similarity >= 0.40
WHEN distance < 200 THEN name_similarity >= 0.45
ELSE name_similarity >= 0.50
```

**Results:**
- False positive rate: ~76% → estimated <10%
- Kraków: ~80 flagged pairs → ~5 high-confidence true duplicates
- Eliminated transitive grouping (no more "super groups" of unrelated venues)

**API Delivered:**
- `VenueDeduplication.find_duplicate_pairs(city_ids, opts)` - returns enriched pairs with confidence
- `VenueDeduplication.calculate_duplicate_metrics(city_ids, opts)` - returns pair counts by severity

---

### Phase 2.5: Performance Optimization (DEFERRED)
**Goal:** Database persistence for scale optimization

**Not blocking Phase 3** - on-demand computation acceptable at current scale (~50-100 pairs/city).

**Database Changes (implement if needed):**
```sql
-- Store computed duplicate pairs (cache, not recomputed on every page load)
CREATE TABLE venue_duplicate_pairs (
  id SERIAL PRIMARY KEY,
  venue_id_a INTEGER REFERENCES venues(id),
  venue_id_b INTEGER REFERENCES venues(id),
  similarity_score DECIMAL(5,4),  -- 0.0000 to 1.0000
  distance_meters INTEGER,
  status VARCHAR(20) DEFAULT 'pending',  -- pending, merged, not_duplicate
  reviewed_by INTEGER REFERENCES users(id),
  reviewed_at TIMESTAMP,
  merge_direction VARCHAR(10),  -- 'a_to_b', 'b_to_a', null
  created_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(venue_id_a, venue_id_b),
  CHECK (venue_id_a < venue_id_b)  -- canonical ordering
);

-- Track merge history for undo
CREATE TABLE venue_merge_audits (
  id SERIAL PRIMARY KEY,
  source_venue_id INTEGER,
  target_venue_id INTEGER,
  merged_by INTEGER REFERENCES users(id),
  merged_at TIMESTAMP DEFAULT NOW(),
  events_transferred INTEGER,
  public_events_transferred INTEGER,
  can_undo_until TIMESTAMP,  -- 30 days from merge
  undone_at TIMESTAMP,
  undone_by INTEGER REFERENCES users(id)
);

-- Add to venues table
ALTER TABLE venues ADD COLUMN merged_into_id INTEGER REFERENCES venues(id);
ALTER TABLE venues ADD COLUMN merged_at TIMESTAMP;
```

**Tasks (when needed):**
- [ ] Migration for new tables
- [ ] Background job to compute/update pairs on venue create/update
- [ ] Store pair data so we don't recompute on every page load

---

### Phase 3: Pair Review UI
**Goal:** Build the core review experience

**Wireframe: Pair Review Interface**
```
┌─────────────────────────────────────────────────────────────────┐
│ Kraków Duplicate Review                Progress: 3 of 42 pairs  │
│ ← Back to City Health                                           │
├─────────────────────────────────────────────────────────────────┤
│ Confidence: HIGH (87%)              Distance: 15m               │
├─────────────────────────────┬───────────────────────────────────┤
│ VENUE A                     │ VENUE B                           │
│ ───────────────────────     │ ───────────────────────           │
│ Gwarek                      │ Klub Gwarek                       │
│ ul. Floriańska 18           │ ul. Floriańska 18                 │
│ Kraków, Poland              │ Kraków, Poland                    │
│                             │                                   │
│ Events: 58                  │ Events: 12                        │
│ Sources: Karnet, BandsIn    │ Sources: Repertuary               │
│ Created: 2024-01-15         │ Created: 2024-03-22               │
│ Slug: gwarek                │ Slug: klub-gwarek                 │
│                             │                                   │
│ 📍 50.0640, 19.9440        │ 📍 50.0641, 19.9445              │
├─────────────────────────────┴───────────────────────────────────┤
│                                                                 │
│  [Keep A, Merge B into A]  [Keep B, Merge A into B]            │
│                                                                 │
│  [Not Duplicates - Exclude]           [Skip for Now]           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Features:**
- [ ] Side-by-side venue comparison
- [ ] Show event counts, sources, creation dates
- [ ] Show coordinates and calculate distance
- [ ] "Keep A, Merge B→A" button (transfers B's events to A, soft-deletes B)
- [ ] "Keep B, Merge A→B" button (opposite)
- [ ] "Not Duplicates" button (marks pair as excluded forever)
- [ ] "Skip" button (defer decision, move to next pair)
- [ ] Progress indicator (X of Y pairs reviewed)
- [ ] Filter by confidence level (high/medium/low)

**Deliverables:**
- New LiveView: `VenuePairReviewLive`
- Navigation from city health page
- Session persistence of review progress

---

### Phase 4: Safe Merge with Preview
**Goal:** Prevent data loss with preview and undo

**Wireframe: Merge Preview Modal**
```
┌─────────────────────────────────────────────────────────────────┐
│ ⚠️  Merge Preview                                               │
│                                                                 │
│ Merging: "Klub Gwarek" → "Gwarek"                              │
├─────────────────────────────────────────────────────────────────┤
│ This will:                                                      │
│                                                                 │
│ ✓ Transfer 12 events to "Gwarek"                               │
│ ✓ Transfer 8 public_events to "Gwarek"                         │
│ ✓ Update provider_ids to point to "Gwarek"                     │
│ ✓ Soft-delete "Klub Gwarek" (can be restored for 30 days)     │
│                                                                 │
│ Data selection:                                                 │
│ ○ Use "Gwarek" name (58 events)                                │
│ ○ Use "Klub Gwarek" name (12 events)                           │
│                                                                 │
│ ☑ Keep "Gwarek" address                                        │
│ ☑ Keep "Gwarek" coordinates                                    │
│ ☐ Use "Klub Gwarek" description (longer, more detailed)        │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                    [Cancel]         [Confirm Merge]             │
└─────────────────────────────────────────────────────────────────┘
```

**Safety Features:**
- [ ] Preview modal showing exactly what will happen
- [ ] Soft delete (merged venue gets `merged_into_id` set, not hard deleted)
- [ ] Full audit log with user, timestamp, events transferred
- [ ] 30-day undo window
- [ ] No bulk merge operations - always one pair at a time

**Deliverables:**
- Merge preview component
- `VenueDeduplication.merge_pair(source_id, target_id, opts)` with audit
- Undo capability: `VenueDeduplication.undo_merge(audit_id)`
- Merge history view in admin

---

### Phase 5: City Health Integration
**Goal:** Seamless workflow from city health to duplicate review

**Wireframe: Updated City Health Duplicate Section**
```
┌──────────────────────────────────────────────────────────────────┐
│ Duplicate Venues                                                 │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  42 Pairs to Review                                              │
│  ████████████░░░░░░░░░░░░░ 23/42 reviewed                       │
│                                                                  │
│  🔴 5 high confidence    (>80% similarity, <50m)                │
│  🟡 12 medium confidence (50-80% similarity, <200m)             │
│  ⚪ 25 low confidence    (<50% similarity)                      │
│                                                                  │
│  [Review High Confidence]  [Review All]  [View History]         │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│ Recent Activity:                                                 │
│ • Merged "Klub Gwarek" → "Gwarek" (2 hours ago)                 │
│ • Marked "Teatr Cabaret" / "Cabaret" as not duplicates          │
└──────────────────────────────────────────────────────────────────┘
```

**Features:**
- [ ] Replace "X duplicates (Y groups)" with "X pairs to review"
- [ ] Progress bar showing review completion
- [ ] Confidence breakdown (high/medium/low)
- [ ] Quick actions: "Review High Confidence First"
- [ ] Recent activity feed
- [ ] Session persistence (resume where you left off)

**Deliverables:**
- Updated city health duplicate section
- Review progress persistence
- Recent activity component

---

## Success Metrics

1. **Accuracy**: >90% of flagged pairs are true duplicates (validate via sampling)
2. **Resolution rate**: Admin can review 20+ pairs per session
3. **Safety**: Zero accidental data loss (undo used <5% of merges)
4. **Completion**: All high-confidence duplicates resolved within 1 week of launch

---

## Out of Scope (Future Improvements)

- Automatic merging of very high confidence pairs (>95%)
- Machine learning for similarity detection
- Cross-city duplicate detection
- API for external duplicate reporting

---

## Technical Notes

### Existing Code References
- Current detection: `lib/eventasaurus_app/venues.ex` → `find_duplicate_groups/1`
- Current UI: `lib/eventasaurus_web/live/admin/venue_duplicates_live.ex`
- Merge logic: `lib/eventasaurus_app/venues/venue_deduplication.ex`

### Dependencies
- PostGIS for distance calculations (already in use)
- Oban for background pair computation jobs
