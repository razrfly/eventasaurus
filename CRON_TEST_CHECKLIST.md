# Discovery Cron Job Test Checklist
*For testing tonight at 16:00 UTC (11 AM CDT)*

## Critical Fixes Implemented ✅

1. **Added `update_source_next_run/3`** to `DiscoveryConfigManager`
   - Updates `next_run_at` in `discovery_config` after queueing
   - Prevents duplicate job queueing on subsequent runs

2. **Updated `CityDiscoveryOrchestrator`**
   - Now updates `next_run_at` immediately after successful job queueing
   - Calculates: `DateTime.utc_now() + (frequency_hours * 3600 seconds)`
   - Logs the update with debug level

3. **Added Oban Unique Constraint** to `DiscoverySyncJob`
   - Period: 3600 seconds (1 hour)
   - Fields: `[:args]` (prevents duplicate jobs with same arguments)
   - States: `[:available, :scheduled, :executing]`
   - Prevents accidental duplicate queueing

## Before Cron Runs (Pre-Check)

### 1. Verify Configuration
```bash
# In IEx
iex> cities = EventasaurusDiscovery.Admin.DiscoveryConfigManager.list_discovery_enabled_cities()
iex> Enum.each(cities, fn city ->
...>   IO.puts("\n#{city.name}:")
...>   IO.puts("  Discovery enabled: #{city.discovery_enabled}")
...>   config = city.discovery_config || %{}
...>   sources = config["sources"] || []
...>   Enum.each(sources, fn source ->
...>     IO.puts("    - #{source["name"]}: enabled=#{source["enabled"]}, next_run=#{source["next_run_at"]}")
...>   end)
...> end)
```

**Expected:**
- At least one city with `discovery_enabled = true`
- At least one source with `enabled = true`
- `next_run_at` should be `nil` or a past date for sources that should run

### 2. Check Cron Schedule
```bash
# Verify the cron is set correctly
grep -A 5 "CityDiscoveryOrchestrator" config/config.exs
```

**Expected:**
```elixir
{"0 16 * * *", EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator}
```

### 3. Manual Test (Optional but Recommended)
```bash
# In IEx - manually trigger the orchestrator to verify it works
iex> EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator.perform(%Oban.Job{args: %{}})
```

**Expected Output:**
```
🌍 City Discovery Orchestrator: Starting scheduled run
Found X cities with discovery enabled
Processing discovery for [City Name]
  → Y sources due to run for [City Name]
  ✅ Queued [source] sync for [City] (job #123)
  📅 Updated next_run_at for [source] to 2025-10-08T16:00:00Z
✅ City Discovery Orchestrator: Queued Z discovery jobs
```

## During Cron Run (16:00 UTC)

### Watch the Logs
```bash
# Tail the Phoenix logs
tail -f /path/to/phoenix.log

# Or in production
fly logs
```

**Expected Log Sequence:**
1. `🌍 City Discovery Orchestrator: Starting scheduled run`
2. `Found X cities with discovery enabled`
3. For each city:
   - `Processing discovery for [City Name]`
   - `→ Y sources due to run for [City Name]`
   - For each due source:
     - `✅ Queued [source] sync for [City] (job #123)`
     - `📅 Updated next_run_at for [source] to [timestamp]`
4. `✅ City Discovery Orchestrator: Queued Z discovery jobs`

### Check Oban Dashboard
Navigate to: `/oban`

**Expected:**
- New jobs in `discovery_sync` queue
- Number of jobs = number of enabled sources across all enabled cities
- Each job should have unique arguments (city_id + source combination)
- No duplicate jobs (thanks to unique constraint)

## After Cron Run (Validation)

### 1. Verify Jobs Were Queued
```bash
# In IEx
iex> alias EventasaurusApp.Repo
iex> import Ecto.Query
iex>
iex> # Get jobs queued by the orchestrator
iex> from(j in "oban_jobs",
...>   where: j.queue == "discovery_sync",
...>   where: j.inserted_at > ago(5, "minute"),
...>   select: {j.id, j.state, fragment("? ->> 'source'", j.args), fragment("? ->> 'city_id'", j.args)}
...> ) |> Repo.all()
```

**Expected:**
- List of jobs with state `available` or `executing`
- One job per enabled source per enabled city
- No duplicate (city_id, source) combinations

### 2. Verify next_run_at Was Updated
```bash
# In IEx
iex> cities = EventasaurusDiscovery.Admin.DiscoveryConfigManager.list_discovery_enabled_cities()
iex> Enum.each(cities, fn city ->
...>   IO.puts("\n#{city.name}:")
...>   config = city.discovery_config || %{}
...>   sources = config["sources"] || []
...>   Enum.each(sources, fn source ->
...>     if source["enabled"] do
...>       case DateTime.from_iso8601(source["next_run_at"] || "") do
...>         {:ok, dt, _} ->
...>           hours_from_now = DateTime.diff(dt, DateTime.utc_now()) / 3600
...>           IO.puts("  #{source["name"]}: next_run in #{Float.round(hours_from_now, 1)} hours")
...>         _ ->
...>           IO.puts("  #{source["name"]}: next_run_at not set or invalid")
...>       end
...>     end
...>   end)
...> end)
```

**Expected:**
- Each queued source should have `next_run_at` set to ~24 hours from now (or whatever `frequency_hours` is set to)
- Format: ISO8601 timestamp (e.g., `2025-10-08T16:00:00Z`)

### 3. Monitor Job Execution
```bash
# Watch job completion over the next few minutes
# In IEx
iex> :timer.sleep(60_000)  # Wait 1 minute
iex> from(j in "oban_jobs",
...>   where: j.queue == "discovery_sync",
...>   where: j.inserted_at > ago(10, "minute"),
...>   select: {j.state, count(j.id)}
...> ) |> Repo.all() |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
```

**Expected Progress:**
- Initial: All jobs in `available` or `executing`
- After ~5 min: Some jobs moving to `completed`
- After ~15 min: Most/all jobs in `completed` state
- Check for any jobs in `discarded` state (errors)

### 4. Verify Stats Update
Navigate to: `/admin/cities/[city-slug]/discovery/config`

**Expected:**
- Stats show updated run counts
- Last run time updated to recent timestamp
- Success/error counts reflect job outcomes
- Next run shows ~24 hours from now

## Troubleshooting

### Issue: No Jobs Queued

**Check:**
```bash
iex> cities = EventasaurusDiscovery.Admin.DiscoveryConfigManager.list_discovery_enabled_cities()
iex> length(cities)  # Should be > 0
```

**If 0 cities:**
- Enable discovery for at least one city via admin UI

**If cities exist but no jobs:**
```bash
iex> city = hd(cities)
iex> EventasaurusDiscovery.Admin.DiscoveryConfigManager.get_due_sources(city)
```

**If empty list:**
- Check `schedule.enabled` is not `false`
- Check at least one source has `enabled = true`
- Check `next_run_at` is `nil` or in the past

### Issue: Duplicate Jobs Queued

**This should NOT happen with our fixes, but if it does:**

1. Check Oban unique constraint is active:
```bash
grep -A 5 "use Oban.Worker" lib/eventasaurus_discovery/admin/discovery_sync_job.ex
```

2. Check for race condition (multiple orchestrators running):
```bash
# Check how many orchestrator jobs ran
from(j in "oban_jobs",
  where: j.worker == "EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator",
  where: j.inserted_at > ago(10, "minute"),
  select: count(j.id)
) |> Repo.one()
```

Should be exactly 1.

### Issue: next_run_at Not Updated

**Check the logs for warnings:**
```bash
grep "Failed to update next_run_at" /path/to/phoenix.log
```

**Manual verification:**
```bash
iex> EventasaurusDiscovery.Admin.DiscoveryConfigManager.update_source_next_run(
...>   1,  # city_id
...>   "bandsintown",  # source_name
...>   DateTime.add(DateTime.utc_now(), 24 * 3600, :second)
...> )
```

Should return `{:ok, %City{}}`

### Issue: Jobs Failing

**Check Oban dashboard for error messages:**
- Navigate to `/oban`
- Click on `discarded` tab
- View error details

**Common issues:**
- City not found: Check city_id is valid
- Source not configured: Check source settings
- API errors: Check API keys and rate limits

## Success Criteria

✅ At least one job queued per enabled source per enabled city
✅ Each source's `next_run_at` updated to future timestamp
✅ No duplicate jobs in queue
✅ Jobs completing successfully (state = `completed`)
✅ Stats updating correctly in admin UI
✅ No errors in logs

## Next Steps After Successful Test

1. **Monitor for 24 hours** - Verify no issues over time
2. **Check tomorrow at 16:00 UTC** - Verify it runs again and doesn't queue duplicates
3. **Review job completion rates** - Check success/error ratios
4. **Update cron schedule** - Change back to `{"0 0 * * *"}` if desired
5. **Create GitHub issue** - Document any remaining improvements needed

## Quick Reference Commands

```bash
# Manual trigger (testing)
iex -S mix
EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator.perform(%Oban.Job{args: %{}})

# Check enabled cities
EventasaurusDiscovery.Admin.DiscoveryConfigManager.list_discovery_enabled_cities()

# Check due sources for a city
EventasaurusDiscovery.Admin.DiscoveryConfigManager.get_due_sources(city)

# Check recent jobs
from(j in "oban_jobs", where: j.inserted_at > ago(1, "hour"), select: {j.queue, j.state, j.worker}) |> Repo.all()

# View Oban dashboard
# Navigate to: http://localhost:4000/oban (dev) or https://eventasaur.us/oban (prod)
```
