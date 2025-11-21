# Week.pl Deployment Guide

## Overview

Week.pl source integration for Restaurant Week, Fine Dining Week, and Breakfast Week festivals across 13 Polish cities.

## Phased Deployment Strategy

### Phase 1: Pilot (Kraków Only)
**Duration**: 1-2 weeks
**Cities**: Kraków (region_id: "1")
**Goal**: Validate integration in production with limited scope

```bash
# Enable pilot phase
export WEEK_PL_DEPLOYMENT_PHASE=pilot

# Or in application config
config :eventasaurus, week_pl_deployment_phase: :pilot
```

**Success Criteria**:
- ✅ Jobs run successfully during festival period
- ✅ Events created with correct consolidation (44 slots → 1 daily event)
- ✅ Category mapping works correctly (all map to food-drink)
- ✅ No rate limiting issues (2s delay maintained)
- ✅ Build ID cache functions properly (1-hour TTL)
- ✅ Venue data geocoded successfully

### Phase 2: Expansion (Major Cities)
**Duration**: 1-2 weeks
**Cities**: Kraków, Warszawa, Wrocław, Gdańsk (4 cities)
**Goal**: Scale to major metropolitan areas

```bash
export WEEK_PL_DEPLOYMENT_PHASE=expansion
```

**Success Criteria**:
- ✅ All 4 cities processing successfully
- ✅ No performance degradation
- ✅ Oban queue handling load appropriately
- ✅ Event quality maintained across cities

### Phase 3: Full Rollout (All Cities)
**Duration**: Ongoing
**Cities**: All 13 supported cities
**Goal**: Complete nationwide coverage

```bash
export WEEK_PL_DEPLOYMENT_PHASE=full
```

**Monitored Cities**:
1. Kraków (1)
2. Gdańsk (2)
3. Wrocław (4)
4. Warszawa (5)
5. Poznań (6)
6. Katowice (7)
7. Łódź (9)
8. Sopot (10)
9. Trójmiasto (11)
10. Szczecin (12)
11. Lublin (14)
12. Bydgoszcz (15)
13. Białystok (21)

## Festival Calendar

Week.pl operates on a festival schedule. Sync only occurs during active festival periods:

### RestaurantWeek Spring 2026
- Dates: March 4 - April 22, 2026
- Menu Price: 63 PLN
- Code: RWP26W

### FineDiningWeek Fall 2026
- Dates: September 17 - November 1, 2026
- Menu Price: 99 PLN
- Code: FDWJ26

### BreakfastWeek Winter 2026
- Dates: November 30 - December 28, 2026
- Menu Price: 49 PLN
- Code: BWZ26

**Note**: Update festival dates annually in `source.ex`

## Job Architecture

### 3-Level Job Hierarchy

```
SyncJob (Priority 1, Queue: week_pl_sync)
  ├─ Checks: Festival active? Deployment enabled?
  └─ Queues: RegionSyncJob for each active city

RegionSyncJob (Priority 2, Queue: week_pl_region_sync)
  ├─ Fetches: Restaurant listings for city
  ├─ Rate Limit: 2s delay before API call
  └─ Queues: RestaurantDetailJob for each restaurant

RestaurantDetailJob (Priority 3, Queue: week_pl_detail)
  ├─ Fetches: Restaurant details with time slots (14-28 days ahead)
  ├─ Processes: 44 time slots per restaurant per date range
  ├─ Rate Limit: 2s delay before API call
  └─ Creates: Events via EventProcessor (consolidation happens here)
```

### Rate Limiting
- **Request Delay**: 2 seconds between API calls
- **Daily Volume**: ~500 restaurants × 15 days = ~7,500 events per city per sync
- **Full Rollout**: 13 cities × 7,500 = ~97,500 events per festival period
- **Consolidation**: 44 slots → 1 daily event = ~90% reduction

### Expected Load
- **Pilot**: ~500 restaurants in Kraków
- **Expansion**: ~2,000 restaurants across 4 cities
- **Full**: ~6,500 restaurants across 13 cities

## Oban Configuration

Ensure queues are configured in Oban:

```elixir
# config/config.exs
config :eventasaurus, Oban,
  queues: [
    week_pl_sync: 1,          # 1 concurrent (festival check)
    week_pl_region_sync: 2,   # 2 concurrent (city fetching)
    week_pl_detail: 5         # 5 concurrent (restaurant details)
  ]
```

## Monitoring

### Key Metrics
- **Job Success Rate**: Should be >95%
- **Event Creation Rate**: ~7,500 per city per sync
- **Consolidation Rate**: ~90% reduction (44 slots → 1 event)
- **API Response Time**: <2s per request
- **Build ID Cache Hits**: Should be >99% after initial fetch

### Logs to Watch
```bash
# Festival check
grep "WeekPl.SyncJob" production.log

# Deployment status
grep "Deployment:" production.log | grep "cities active"

# Rate limiting warnings
grep "Rate limited" production.log | grep WeekPl

# Build ID cache
grep "BuildIdCache" production.log
```

### Error Scenarios

#### Build ID Stale (404 Errors)
```
[WeekPl.Client] Got 404, build ID may be stale. Refreshing...
```
**Resolution**: Automatic - client refreshes build ID and retries

#### Rate Limited
```
[WeekPl.RegionSync] Rate limited for Kraków, retrying...
```
**Resolution**: Automatic - job retries with Oban backoff

#### Festival Inactive
```
[WeekPl.SyncJob] No active festival, skipping sync
```
**Resolution**: Expected behavior outside festival periods

#### Source Disabled
```
[WeekPl.SyncJob] Source disabled via deployment config
```
**Resolution**: Expected behavior when `WEEK_PL_DEPLOYMENT_PHASE=disabled`

## Quality Assessment

Run the quality assessment script before advancing deployment phases:

```bash
# Run quality assessment
mix run lib/eventasaurus_discovery/sources/week_pl/quality_assessment.exs

# Expected output:
# ✅ Phase validation passed
# ✅ Event quality checks passed
# ✅ Category mapping working
# ✅ Consolidation working (90%+ reduction)
# ✅ Venue geocoding successful
```

## Rollback Procedure

If issues are detected:

```bash
# 1. Disable source immediately
export WEEK_PL_DEPLOYMENT_PHASE=disabled

# 2. Cancel pending Oban jobs
mix run -e "Oban.cancel_all_jobs(:week_pl_sync)"
mix run -e "Oban.cancel_all_jobs(:week_pl_region_sync)"
mix run -e "Oban.cancel_all_jobs(:week_pl_detail)"

# 3. Investigate logs
grep ERROR production.log | grep WeekPl

# 4. Fix issues, then re-enable at previous phase
export WEEK_PL_DEPLOYMENT_PHASE=pilot  # or expansion
```

## Testing

### Unit Tests
```bash
mix test test/eventasaurus_discovery/sources/week_pl/
```

### Integration Tests (Requires Network)
```bash
mix test test/eventasaurus_discovery/sources/week_pl/ --only integration
```

### Manual Testing

#### 1. Test Pilot Phase (Kraków)
```bash
export WEEK_PL_DEPLOYMENT_PHASE=pilot

# Verify configuration
iex -S mix
> EventasaurusDiscovery.Sources.WeekPl.DeploymentConfig.status()
# Should show: %{phase: :pilot, active_cities: 1, ...}

# Queue sync job manually
> source_id = EventasaurusApp.Repo.get_by(EventasaurusDiscovery.Sources.Source, slug: "week_pl").id
> Oban.insert(EventasaurusDiscovery.Sources.WeekPl.Jobs.SyncJob.new(%{source_id: source_id}))
```

#### 2. Monitor Job Progress
```bash
# Watch Oban dashboard
# Or query job counts:
iex> Oban.check_queue(queue: :week_pl_detail)
```

#### 3. Verify Events Created
```sql
-- Check events created
SELECT COUNT(*)
FROM public_event_sources
WHERE source_id = <week_pl_source_id>
AND external_id LIKE 'week_pl_%';

-- Check consolidation working (should see restaurant_date_id in metadata)
SELECT metadata->'restaurant_date_id', COUNT(*)
FROM public_event_sources
WHERE source_id = <week_pl_source_id>
GROUP BY 1
ORDER BY 2 DESC
LIMIT 10;

-- Should see multiple external_ids grouped under same restaurant_date_id
```

## Category Mapping

All week.pl events map to the `food-drink` category. The mapping file supports:
- Cuisine types (Italian, Polish, French, etc.)
- Dining styles (Fine Dining, Bistro, Casual, etc.)
- Food types (Pizza, Sushi, Steakhouse, etc.)
- Beverage focus (Wine Bar, Cocktail Bar - also tagged with nightlife)

Mapping file: `priv/category_mappings/week_pl.yml`

## Support & Troubleshooting

### Common Issues

**Issue**: No events created
**Check**:
1. Is festival currently active? `Source.festival_active?()`
2. Is deployment enabled? `DeploymentConfig.enabled?()`
3. Check Oban job failures in dashboard

**Issue**: Too many events (not consolidating)
**Check**:
1. Verify `restaurant_date_id` in metadata
2. Check EventProcessor logs for consolidation
3. Verify external_id pattern: `week_pl_{restaurant_id}_{date}_{slot}`

**Issue**: Rate limiting errors
**Check**:
1. Verify 2s delay between requests in Config
2. Reduce concurrent workers in Oban queue config
3. Check `Process.sleep(Config.request_delay_ms())` in jobs

### Contact

For issues, create a GitHub issue with:
- Deployment phase
- Error logs
- Job IDs
- Expected vs actual behavior
