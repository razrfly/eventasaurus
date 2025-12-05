# Query Optimization Baseline - December 5, 2025

Reference: GitHub Issue #2537

## PlanetScale Insights Summary

These 6 queries consume **65%+ of database runtime** with P99 latencies in the thousands of milliseconds.

### Query 1 & 3: public_events + sources JOIN (33% combined)

**The Problem:**
```sql
SELECT e.*, pes.* FROM public_events e
INNER JOIN public_event_sources pes ON e.id = pes.event_id
WHERE e.occurrences = ?
```

| Metric | Value |
|--------|-------|
| Runtime | 19.4% + 13.6% = **33%** |
| P99 Latency | 3,139ms |
| Rows Read | 17.1M |
| Rows Returned | 1,880 |
| Ratio | 9,096:1 |

**Root Cause:** The `occurrences` JSONB column (~2704 bytes) cannot be indexed (exceeds B-tree limit).

**Fix Applied:** None - structural issue requires schema redesign. Documented for future work.

---

### Query 2: cities unsplash_gallery (14.4%)

**The Problem:**
```sql
SELECT * FROM cities WHERE unsplash_gallery IS NOT NULL
```

| Metric | Value |
|--------|-------|
| Runtime | **14.4%** |
| P99 Latency | 1,640ms |
| Rows Read | 2.13M |
| Rows Returned | 66,600 |
| Ratio | 32:1 |

**Root Cause:** Full table scans on cities table for unsplash_gallery filtering.

**Fix Applied:** Existing partial index `idx_cities_unsplash_gallery` should help. Monitor.

---

### Query 4: oban_jobs aggregation (7.48%) ✅ FIXED

**The Problem:**
```sql
SELECT state, queue, COUNT(*) FROM oban_jobs GROUP BY state, queue
```

| Metric | Value |
|--------|-------|
| Runtime | **7.48%** |
| P99 Latency | 2,069ms |
| Rows Read | 19.8M |
| Rows Returned | 2 |
| Ratio | 9,900,000:1 |

**Root Cause:**
- Dashboard queries hitting **primary database** instead of read replica
- PlanetScale Recommendation #43 correctly identified `oban_jobs_state_queue_idx` as **redundant**
- Oban already maintains compound index `[:state, :queue, :priority, :scheduled_at, :id]`

**Fixes Applied:**
1. ✅ `DashboardStats` module: Changed all `Repo` calls to `Repo.replica()`
2. ✅ `JobRegistry` module: Changed discovery workers query to use `Repo.replica()`
3. ✅ `JobMetadata` module: Changed `get_job_stats/3` to use `Repo.replica()`
4. ✅ Migration: Remove redundant `oban_jobs_state_queue_idx` index

---

### Query 5: venues metadata JOIN (5.58%) ✅ FIXED

**The Problem:**
```sql
SELECT v.* FROM venues v
INNER JOIN public_events e ON e.venue_id = v.id
WHERE v.metadata IS NOT NULL
```

| Metric | Value |
|--------|-------|
| Runtime | **5.58%** |
| P99 Latency | 1,089ms |
| Rows Read | 2.1M |
| Rows Returned | 3,298 |
| Ratio | 637:1 |

**Root Cause:** Full table scan on venues when only ~0.15% have metadata.

**Fixes Applied:**
1. ✅ Migration: Add partial index `idx_venues_with_metadata`
   - Reduces scan from 2.1M rows to ~3K rows with metadata

---

### Query 6: description translations (4.44%)

**The Problem:**
```sql
SELECT * FROM description_translations GROUP BY ... HAVING ...
```

| Metric | Value |
|--------|-------|
| Runtime | **4.44%** |
| P99 Latency | 3,254ms |
| Rows Read | 1.14M |
| Rows Returned | 1,180 |
| Ratio | 966:1 |

**Root Cause:** Aggregation on large translations table.

**Fix Applied:** None yet - monitor after other fixes deployed.

---

## Changes Summary

### Migrations Created

1. `20251205162629_remove_redundant_oban_state_queue_index.exs`
   - Removes redundant `oban_jobs_state_queue_idx` per PlanetScale recommendation

2. `20251205172759_add_venues_metadata_partial_index.exs`
   - Adds partial index `idx_venues_with_metadata` for venues with metadata

### Code Changes

| File | Change |
|------|--------|
| `lib/eventasaurus_app/cache/dashboard_stats.ex` | All `Repo` → `Repo.replica()` |
| `lib/eventasaurus_app/monitoring/job_registry.ex` | Discovery workers query uses replica |
| `lib/eventasaurus_discovery/scraping/helpers/job_metadata.ex` | `get_job_stats/3` uses replica |

### New Benchmark System

| File | Purpose |
|------|---------|
| `lib/eventasaurus_app/monitoring/query_benchmark.ex` | Query performance tracking module |
| `lib/mix/tasks/benchmark/queries.ex` | CLI interface for benchmarks |

---

## How to Measure Success

### 1. Before Deploying (Capture Baseline)

```bash
mix benchmark.queries baseline
```

### 2. Deploy Migrations

```bash
mix ecto.migrate
```

### 3. After 1 Hour (Compare Results)

```bash
mix benchmark.queries report
```

### 4. Check PlanetScale Insights

Monitor these metrics in PlanetScale dashboard:
- Query runtime percentages should decrease
- P99 latencies should improve
- Rows read vs returned ratios should improve

---

## Expected Improvements

| Query | Expected Change |
|-------|-----------------|
| oban_jobs aggregation | **Major** - Removed from primary DB load entirely |
| venues metadata JOIN | **Major** - Partial index reduces scan by 99.8% |
| public_events sources | Minimal - Structural issue |
| cities unsplash | Minimal - Already indexed |
| description translations | Minimal - Monitor |

---

## Monitoring Commands

```bash
# Quick status check
mix benchmark.queries status

# View original PlanetScale baseline values
mix benchmark.queries planetscale

# Full benchmark report with comparison
mix benchmark.queries report
```
