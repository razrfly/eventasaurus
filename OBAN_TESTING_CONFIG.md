# Temporary Oban Configuration Change for Issue #1539

**Date:** October 7, 2025
**Time:** 5:50 PM CEST
**Issue:** https://github.com/razrfly/eventasaurus/issues/1539

## Changes Made

Changed the `CityDiscoveryOrchestrator` cron schedule from midnight UTC to 6 PM CEST (16:00 UTC) to test if Oban jobs execute correctly in production.

### File Modified
- `config/config.exs` (lines 134-136)

### Original Configuration
```elixir
# City discovery orchestration every 24 hours at midnight UTC
{"0 0 * * *", EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator}
```

### Temporary Configuration
```elixir
# City discovery orchestration - TEMPORARY: Set to 6 PM CEST (16:00 UTC) for testing
# TODO: Revert to {"0 0 * * *"} after verifying it works in production
{"0 16 * * *", EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator}
```

## Expected Execution Time
- **Next scheduled run:** 6:00 PM CEST / 4:00 PM UTC (approximately 10 minutes after change)
- **Date:** October 7, 2025

## How to Verify

After deployment to production:

1. **Check Oban Dashboard** (if available):
   - Navigate to `/admin/oban` or wherever Oban Web is mounted
   - Look for scheduled jobs under the "Cron" tab
   - Verify `CityDiscoveryOrchestrator` appears with schedule `0 23 * * *`

2. **Check Application Logs**:
   ```bash
   # Look for these log messages around 6 PM CEST (4 PM UTC):
   fly logs --app eventasaurus | grep "City Discovery Orchestrator"
   ```

   Expected log messages:
   ```
   🌍 City Discovery Orchestrator: Starting scheduled run
   Found X cities with discovery enabled
   Processing discovery for [City Name]
   ✅ City Discovery Orchestrator: Queued X discovery jobs
   ```

3. **Check Database Jobs**:
   ```sql
   -- Connect to production database
   SELECT * FROM oban_jobs
   WHERE worker = 'EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator'
   ORDER BY inserted_at DESC
   LIMIT 5;
   ```

4. **Verify Discovery Jobs Queued**:
   ```sql
   -- Check if discovery sync jobs were queued after the orchestrator ran
   SELECT * FROM oban_jobs
   WHERE worker LIKE '%DiscoverySyncJob%'
   AND inserted_at > NOW() - INTERVAL '10 minutes'
   ORDER BY inserted_at DESC;
   ```

## What the Job Does

The `CityDiscoveryOrchestrator` worker:
1. Finds all cities with `discovery_enabled = true`
2. Checks each city's `discovery_config` JSONB field for sources due to run
3. Queues `DiscoverySyncJob` jobs for each due source (Bandsintown, Resident Advisor, Karnet, etc.)
4. Updates run statistics in the city's config

## Deployment Steps

1. **Commit the change:**
   ```bash
   git add config/config.exs OBAN_TESTING_CONFIG.md
   git commit -m "temp: change CityDiscoveryOrchestrator to 6 PM CEST for testing (#1539)"
   git push origin main
   ```

2. **Deploy to production:**
   ```bash
   fly deploy
   ```

3. **Wait for 6 PM CDT** and monitor logs

4. **Verify execution** using steps above

## Revert Instructions

**IMPORTANT:** After verifying the job works correctly, revert to the original schedule:

```bash
# 1. Edit config/config.exs and change line 136 back to:
{"0 0 * * *", EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator}

# 2. Commit and deploy:
git add config/config.exs
git commit -m "revert: restore CityDiscoveryOrchestrator to midnight UTC (#1539)"
git push origin main
fly deploy

# 3. Delete this temporary file:
git rm OBAN_TESTING_CONFIG.md
git commit -m "chore: remove temporary testing documentation"
git push origin main
```

## Oban Configuration Summary

### Current Oban Setup
- **Repo:** `EventasaurusApp.Repo`
- **Queue:** `maintenance` (concurrency: 2)
- **Worker:** `EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator`
- **Max Attempts:** 3
- **Plugins Active:**
  - Pruner (7 days retention)
  - Reindexer (daily)
  - Lifeline (60s rescue)
  - Cron (scheduled jobs)

### All Queues
- `emails: 2` (Resend API rate limiting)
- `scraper: 5`
- `scraper_detail: 3`
- `scraper_index: 2`
- `discovery: 3` (where DiscoverySyncJob jobs run)
- `discovery_sync: 2`
- `google_lookup: 1`
- `default: 10`
- `maintenance: 2` (where CityDiscoveryOrchestrator runs)

### Configuration Files
- **Main config:** `config/config.exs` (lines 93-138)
- **No overrides in:** `config/prod.exs` or `config/runtime.exs`

## Related Code

- **Worker:** `lib/eventasaurus_discovery/workers/city_discovery_orchestrator.ex`
- **Config Manager:** `lib/eventasaurus_discovery/admin/discovery_config_manager.ex`
- **Sync Job:** `lib/eventasaurus_discovery/admin/discovery_sync_job.ex`
- **City Schema:** `lib/eventasaurus_discovery/locations/city.ex`

## Troubleshooting

### If the job doesn't run:

1. **Check Oban is running:**
   ```elixir
   # In IEx console on production:
   Oban.check_queue(queue: :maintenance)
   ```

2. **Check city configuration:**
   ```elixir
   # Verify cities have discovery enabled:
   alias EventasaurusDiscovery.Admin.DiscoveryConfigManager
   DiscoveryConfigManager.list_discovery_enabled_cities()
   ```

3. **Manually trigger the job:**
   ```elixir
   # Queue the job manually for immediate execution:
   %{}
   |> EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator.new()
   |> Oban.insert()
   ```

4. **Check for errors in logs:**
   ```bash
   fly logs --app eventasaurus | grep -i error
   ```

### If jobs are queued but not processing:

1. **Check maintenance queue is running:**
   ```sql
   SELECT * FROM oban_queues WHERE name = 'maintenance';
   ```

2. **Check for stuck jobs:**
   ```sql
   SELECT * FROM oban_jobs
   WHERE state = 'executing'
   AND queue = 'maintenance'
   AND attempted_at < NOW() - INTERVAL '5 minutes';
   ```

3. **Restart the app:**
   ```bash
   fly apps restart eventasaurus
   ```

## Success Criteria

✅ Job appears in Oban at 6 PM CDT
✅ Log message shows "Starting scheduled run"
✅ Discovery sync jobs are queued for enabled cities
✅ No errors in application logs
✅ City configs are updated with new `last_run_at` timestamps

## Notes

- This is a **temporary testing configuration** to verify issue #1539
- The cron schedule will run **once per day** at the configured time
- After successful verification, **must be reverted** to midnight UTC
- Changes require app restart/redeploy to take effect
