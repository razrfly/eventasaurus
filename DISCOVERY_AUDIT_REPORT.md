# Discovery System Audit Report
*Generated: 2025-10-07*

## Executive Summary

**Overall Grade: B+**

Two major features were implemented and audited:
1. **Issue #1545**: Discovery Stats Migration to Oban - **Grade: B+**
2. **Issue #1539**: Admin Discovery Dashboard - **Grade: A-**

### Critical Finding 🚨
The orchestrator will queue duplicate jobs on every cron run because `next_run_at` is never updated in `discovery_config` after queueing. **This must be fixed before production use.**

---

## Issue #1545: Discovery Stats Migration to Oban

### Grade: B+ (87%)

### Requirements Checklist

| Requirement | Status | Completion | Notes |
|------------|--------|------------|-------|
| Query Oban directly | ✅ | 100% | Clean implementation with proper SQL aggregation |
| Total runs tracking | ✅ | 100% | `COUNT(j.id)` for all completed/discarded jobs |
| Success count | ✅ | 100% | `COUNT(CASE WHEN state='completed')` |
| Error count | ✅ | 100% | `COUNT(CASE WHEN state='discarded')` |
| Last run time | ✅ | 100% | `max(j.completed_at)` from Oban |
| Next run time | ⚠️ | 70% | Calculated for display only, not persisted |
| Stats Collector module | ✅ | 100% | `DiscoveryStatsCollector` created |
| Update LiveViews | ✅ | 100% | Both dashboard and city config updated |
| Clean up manual tracking | ⚠️ | 50% | `update_source_stats` still exists unused |
| Performance optimization | ❌ | 0% | Optional - not implemented |

### Implementation Details

**Created Files:**
- `lib/eventasaurus_discovery/admin/discovery_stats_collector.ex` (132 lines)

**Modified Files:**
- `lib/eventasaurus_web/live/admin/city_discovery_config_live.ex`
- `lib/eventasaurus_web/live/admin/city_discovery_config_live.html.heex`
- `lib/eventasaurus_web/live/admin/discovery_dashboard_live.ex`
- `lib/eventasaurus_web/live/admin/discovery_dashboard_live.html.heex`
- `lib/eventasaurus_discovery/admin/discovery_config_manager.ex`
- `lib/eventasaurus_discovery/admin/source_options_builder.ex`

**Key Features:**
- ✅ Direct Oban `oban_jobs` table queries
- ✅ Source-to-worker mapping with "Elixir." prefix handling
- ✅ Efficient SQL aggregation (single query per source)
- ✅ Error fetching only when `error_count > 0`
- ✅ Handles both `NaiveDateTime` and `DateTime`
- ✅ Safe nil/struct handling with `normalize_config`

**Code Review Improvements Implemented:**
1. ✅ Fixed PubSub broadcast to use atom status (`:stats_updated`)
2. ✅ Fixed nil schedule handling in `get_due_sources`
3. ✅ Added "Elixir." prefix normalization for worker names
4. ✅ Fixed struct access crash with `normalize_config`
5. ✅ Added safe integer parsing with `parse_city_id`

### Issues Found

**Medium Priority:**
1. **Unused Code**: `update_source_stats` function still exists in `DiscoveryConfigManager` but is never called
2. **Display-Only Next Run**: `next_run_at` is calculated in dashboard for display but not persisted
3. **No Caching**: Stats are queried on every page load (acceptable for now)

### Recommendations

**Should Fix:**
- Remove or deprecate `update_source_stats` to avoid confusion
- Document that `next_run_at` calculation is display-only

**Could Add:**
- Caching layer with TTL for stats queries
- Metrics tracking for stats query performance

---

## Issue #1539: Admin Discovery Dashboard

### Grade: A- (91%)

### Requirements Checklist

| Requirement | Status | Completion | Notes |
|------------|--------|------------|-------|
| Database fields | ✅ | 100% | `discovery_enabled`, `discovery_config` exist |
| 24-hour cron job | ✅ | 100% | Configured in `config.exs` line 136 |
| Orchestrator worker | ✅ | 95% | Implemented but missing next_run_at update |
| Admin UI - Toggle | ✅ | 100% | Enable/disable discovery per city |
| Admin UI - Configure | ✅ | 100% | Add/edit/delete sources with settings |
| Admin UI - View stats | ✅ | 100% | Real-time Oban stats display |
| Admin UI - Manual trigger | ✅ | 100% | Trigger discovery for any city |
| Per-source config | ✅ | 100% | Settings, frequency, enable/disable |
| Schedule gating | ✅ | 100% | `schedule.enabled` flag supported |
| Duplicate prevention | 🚨 | 0% | **CRITICAL: Not implemented** |

### Implementation Details

**Oban Configuration:**
```elixir
# config/config.exs:136
{"0 23 * * *", EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator}
# Note: Temporarily set to 23:00 UTC for testing (6 PM CDT)
# TODO: Revert to {"0 0 * * *"} after verification
```

**Queue Configuration:**
- `discovery_sync` queue: concurrency 2
- `discovery` queue: concurrency 3
- `maintenance` queue (orchestrator): concurrency 2

**Orchestrator Flow:**
1. ✅ Runs on cron schedule (daily at configured time)
2. ✅ Calls `DiscoveryConfigManager.list_discovery_enabled_cities()`
3. ✅ For each city, calls `get_due_sources(city)`
4. ✅ Checks: `enabled = true` AND `next_run_at <= now` AND `schedule.enabled != false`
5. ✅ Builds job args using `SourceOptionsBuilder.build_job_args()`
6. ✅ Queues `DiscoverySyncJob` with proper arguments
7. 🚨 **Does NOT update `next_run_at` after queueing**

**Admin UI Features:**
- ✅ City list with discovery status
- ✅ Per-city configuration page
- ✅ Add/edit/remove sources
- ✅ Source-specific settings (limit, radius, etc.)
- ✅ Real-time stats from Oban
- ✅ Manual trigger with "Trigger Now" button
- ✅ Source enable/disable toggles
- ✅ Schedule enable/disable at city level

### Critical Issue 🚨

**Problem:** Jobs Will Be Queued Multiple Times

**Root Cause:**
1. `CityDiscoveryOrchestrator.queue_discovery_job()` successfully queues a job
2. But it does NOT update `discovery_config.sources[].next_run_at`
3. On the next cron run (24 hours later), `get_due_sources()` checks `next_run_at`
4. Since `next_run_at` was never updated, it's still in the past
5. Same job gets queued again
6. This repeats daily, creating duplicate jobs

**Impact:**
- Daily duplicate jobs for every enabled source
- Wasted API calls and processing
- Potential rate limiting from external APIs
- Database bloat with duplicate events

**Solution Required:**
After successfully queueing a job, update the source's `next_run_at`:
```elixir
next_run_at = DateTime.add(DateTime.utc_now(), frequency_hours * 3600, :second)
DiscoveryConfigManager.update_source_next_run(city_id, source_name, next_run_at)
```

### Additional Issues

**Medium Priority:**
1. **No Unique Constraint**: Oban doesn't prevent duplicate jobs
2. **Stats Persistence**: After migrating to Oban stats, JSONB stats fields are stale
3. **Dry Run Mode**: Exists but not exposed in admin UI

**Low Priority:**
4. No admin UI to view/edit `next_run_at` directly
5. No validation for reasonable `frequency_hours` (must be > 0)
6. No monitoring/alerting for orchestrator failures

### Recommendations

**Must Fix Before Production:**
1. 🚨 Add `next_run_at` update after successful job queueing
2. 🚨 Add Oban unique constraint to prevent duplicate jobs:
   ```elixir
   use Oban.Worker,
     queue: :discovery_sync,
     max_attempts: 3,
     unique: [period: 3600, fields: [:args], states: [:available, :scheduled, :executing]]
   ```

**Should Add:**
3. Helper function to update `next_run_at` in `DiscoveryConfigManager`
4. Admin UI to view orchestrator run history
5. Monitoring/alerting for failed orchestrator runs

**Nice to Have:**
6. Dry run mode toggle in admin UI
7. Manual `next_run_at` editing in admin UI
8. Orchestrator metrics dashboard
9. Email notifications for discovery failures

---

## Overall Assessment

### What We Did Excellently ✅

1. **Clean Architecture**: Well-organized modules with clear responsibilities
2. **Oban Integration**: Proper use of Oban for background jobs and stats
3. **Admin UI**: Comprehensive, user-friendly configuration interface
4. **Error Handling**: Robust nil/struct handling and safe parsing
5. **Code Quality**: Clean, documented, maintainable code
6. **Source Abstraction**: `SourceOptionsBuilder` for consistent job creation
7. **Schedule Control**: Multiple levels of enable/disable flags

### What Needs Improvement ⚠️

1. **Duplicate Prevention**: Critical - jobs will queue multiple times
2. **Code Cleanup**: Remove unused `update_source_stats` function
3. **Documentation**: Need docs for scheduling system
4. **Monitoring**: No visibility into orchestrator health
5. **Testing**: No mention of tests for orchestrator logic

### Production Readiness

**Before Tonight's Cron Run (23:00 UTC):**
- 🚨 **MUST FIX**: Add `next_run_at` update after queueing
- 🚨 **MUST FIX**: Add Oban unique constraint

**Before General Production Use:**
- Remove/deprecate `update_source_stats`
- Add orchestrator monitoring
- Document scheduling system
- Add tests for orchestrator

**Optional Improvements:**
- Add caching layer for stats
- Add admin UI for dry run mode
- Add email notifications
- Add metrics dashboard

---

## Detailed Fix Instructions

### Critical Fix: Update next_run_at After Queueing

**File:** `lib/eventasaurus_discovery/workers/city_discovery_orchestrator.ex`

**Current Code (lines 87-118):**
```elixir
defp queue_discovery_job(city, source, _now, dry_run) do
  # ... builds job args ...

  case DiscoverySyncJob.new(job_args) |> Oban.insert() do
    {:ok, job} ->
      Logger.info("✅ Queued #{source_name} sync for #{city.name}")
      {:ok, job}
    # ...
  end
end
```

**Required Fix:**
After successful queueing, update `next_run_at` in `discovery_config`:
```elixir
{:ok, job} ->
  Logger.info("✅ Queued #{source_name} sync for #{city.name}")

  # Update next_run_at to prevent duplicate queueing
  frequency_hours = source["frequency_hours"] || 24
  next_run = DateTime.add(DateTime.utc_now(), frequency_hours * 3600, :second)
  update_source_next_run(city.id, source_name, next_run)

  {:ok, job}
```

**New Helper Function Needed:**
Add to `DiscoveryConfigManager`:
```elixir
def update_source_next_run(city_id, source_name, next_run_at) do
  # Similar to update_source_settings but only updates next_run_at
end
```

### Secondary Fix: Add Oban Unique Constraint

**File:** `lib/eventasaurus_discovery/admin/discovery_sync_job.ex`

**Change line 7:**
```elixir
use Oban.Worker,
  queue: :discovery_sync,
  max_attempts: 3,
  unique: [period: 3600, fields: [:args], states: [:available, :scheduled, :executing]]
```

This prevents queueing duplicate jobs within 1 hour window.

---

## Testing Checklist for Tonight (23:00 UTC)

**Before Cron Runs:**
- [ ] Verify at least one city has `discovery_enabled = true`
- [ ] Verify that city has at least one source with `enabled = true`
- [ ] Check `next_run_at` is nil or in the past for that source
- [ ] Check `schedule.enabled` is not false

**After Cron Runs:**
- [ ] Check Oban dashboard for queued jobs
- [ ] Verify correct number of jobs queued (one per due source)
- [ ] Check `next_run_at` was updated in `discovery_config`
- [ ] Monitor job completion in Oban
- [ ] Check stats update correctly in admin UI
- [ ] Verify no duplicate jobs queued

**Logging to Watch:**
```
🌍 City Discovery Orchestrator: Starting scheduled run
Found X cities with discovery enabled
Processing discovery for [City Name]
  → Y sources due to run for [City Name]
  ✅ Queued [source] sync for [City] (job #123)
✅ City Discovery Orchestrator: Queued Z discovery jobs
```

---

## Conclusion

Both issues were implemented well with clean, maintainable code. The core functionality works correctly. However, there is one **critical bug** that must be fixed before production use: `next_run_at` is never updated after queueing jobs, causing daily duplicate jobs.

**Grade Breakdown:**
- **Code Quality**: A (95%) - Clean, well-documented, maintainable
- **Feature Completeness**: A- (91%) - All requirements met with minor gaps
- **Production Readiness**: C (70%) - Critical bug prevents safe production use
- **Overall**: B+ (87%) - Excellent work with one critical fix needed

**Recommendation:** Fix the `next_run_at` update issue immediately, then the system will be production-ready with an A grade.
