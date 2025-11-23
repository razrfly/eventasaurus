# Monitoring Tools Quick Reference

## Mix Tasks (CLI)

### Baseline
```bash
# Create and save baseline
mix monitor.baseline <source> --hours=24 --limit=100 --save

# Examples
mix monitor.baseline cinema_city --hours=24 --save
mix monitor.baseline kino_krakow --hours=48 --limit=200
```

### Errors
```bash
# Analyze all errors
mix monitor.errors <source> --hours=24

# Filter by category
mix monitor.errors <source> --category=network_error

# Examples
mix monitor.errors cinema_city --hours=48
mix monitor.errors week_pl --category=validation_error --hours=24
```

### Health
```bash
# Check health with default threshold (90%)
mix monitor.health <source> --hours=24

# Custom threshold
mix monitor.health <source> --hours=24 --threshold=85

# Examples
mix monitor.health cinema_city --hours=24
mix monitor.health inquizition --hours=48 --threshold=95
```

### Chain
```bash
# Get recent chains
mix monitor.chain <source> --limit=5

# Only failed chains
mix monitor.chain <source> --limit=10 --failed-only

# Examples
mix monitor.chain cinema_city --limit=5
mix monitor.chain kino_krakow --limit=3 --failed-only
```

### Compare
```bash
# Compare two baseline files
mix monitor.compare --before=<path> --after=<path>

# Example
mix monitor.compare \
  --before=.taskmaster/baselines/cinema_city_20241122.json \
  --after=.taskmaster/baselines/cinema_city_20241123.json
```

## Programmatic API (Elixir)

### Baseline

```elixir
alias EventasaurusDiscovery.Monitoring.Baseline

# Create baseline
{:ok, baseline} = Baseline.create("cinema_city", hours: 24, limit: 100)

# Save to file
{:ok, filepath} = Baseline.save(baseline, "cinema_city")

# Load from file
{:ok, baseline} = Baseline.load(".taskmaster/baselines/cinema_city_20241123.json")

# Access metrics
baseline.success_rate      # => 91.8
baseline.avg_duration      # => 1238.5
baseline.p95               # => 2100.0
baseline.sample_size       # => 98
```

### Errors

```elixir
alias EventasaurusDiscovery.Monitoring.Errors

# Analyze errors
{:ok, analysis} = Errors.analyze("cinema_city", hours: 24, limit: 20)

# Get summary
summary = Errors.summary(analysis)
# => %{total_failures: 14, error_rate: 11.0, top_category: "network_error"}

# Get top error messages
top_errors = Errors.top_messages(analysis, 5)

# Get recommendations
recommendations = Errors.recommendations(analysis)
# => %{"network_error" => "Consider implementing retry logic..."}
```

### Health

```elixir
alias EventasaurusDiscovery.Monitoring.Health

# Check health
{:ok, health} = Health.check("cinema_city", hours: 24)

# Calculate score
score = Health.score(health)  # => 95.7 (0-100 scale)

# Check SLO compliance
meeting_slos? = Health.meeting_slos?(health)  # => true

# Find degraded workers
degraded = Health.degraded_workers(health, threshold: 90.0)
# => [{"MovieDetailJob", 85.2}]

# Get recent failures
failures = Health.recent_failures(health, limit: 5)
```

### Chain

```elixir
alias EventasaurusDiscovery.Monitoring.Chain

# Analyze specific job
{:ok, chain} = Chain.analyze_job(12345)

# Get recent chains
{:ok, chains} = Chain.recent_chains("cinema_city", limit: 5, failed_only: true)

# Calculate statistics
stats = Chain.statistics(chain)
# => %{total: 10, completed: 8, failed: 2, success_rate: 80.0}

# Find cascade failures
cascades = Chain.cascade_failures(chain)

# Calculate impact
impact = Chain.cascade_impact(chain)  # => 15
```

### Compare

```elixir
alias EventasaurusDiscovery.Monitoring.Compare

# Compare two baseline files
{:ok, comparison} = Compare.from_files(
  ".taskmaster/baselines/cinema_city_before.json",
  ".taskmaster/baselines/cinema_city_after.json"
)

# Or compare baseline maps
comparison = Compare.baselines(before_baseline, after_baseline)

# Get summary
summary = Compare.summary(comparison)
# => %{
#   success_rate_change: 2.3,
#   avg_duration_change: -150.0,
#   improved: true,
#   regression_count: 0
# }

# Check status
improved? = Compare.improved?(comparison)
has_regressions? = Compare.has_regressions?(comparison)

# Get job-level changes
improved_jobs = Compare.improved_jobs(comparison)
regressed_jobs = Compare.regressed_jobs(comparison)
```

## Supported Sources

- `cinema_city`
- `kino_krakow`
- `karnet`
- `week_pl`
- `bandsintown`
- `resident_advisor`
- `sortiraparis`
- `inquizition`
- `waw4free`

## SLO Targets

- **Success Rate**: 95%
- **P95 Duration**: 3000ms

## Error Categories

1. `validation_error` - Missing/invalid fields
2. `geocoding_error` - Address resolution failures
3. `venue_error` - Venue lookup issues
4. `performer_error` - Artist matching problems
5. `category_error` - Event categorization failures
6. `duplicate_error` - Duplicate detection
7. `network_error` - HTTP timeouts, API failures
8. `data_quality_error` - Parsing issues, format changes
9. `unknown_error` - Uncategorized

## Common Workflows

### Debug Performance Issue

```elixir
# 1. Check health
{:ok, health} = Health.check("cinema_city", hours: 24)
score = Health.score(health)

# 2. Find degraded workers
degraded = Health.degraded_workers(health, threshold: 85.0)

# 3. Analyze errors
{:ok, analysis} = Errors.analyze("cinema_city", hours: 24)
top_errors = Errors.top_messages(analysis, 10)

# 4. Check cascade failures
{:ok, chains} = Chain.recent_chains("cinema_city", limit: 10, failed_only: true)
Enum.each(chains, &IO.inspect(Chain.cascade_failures(&1)))
```

### Measure Performance Improvement

```bash
# Before changes
mix monitor.baseline cinema_city --save

# After changes
mix monitor.baseline cinema_city --save

# Compare
mix monitor.compare \
  --before=.taskmaster/baselines/cinema_city_<date1>.json \
  --after=.taskmaster/baselines/cinema_city_<date2>.json
```

### Monitor All Sources

```elixir
sources = ["cinema_city", "kino_krakow", "week_pl"]

Enum.each(sources, fn source ->
  case Health.check(source, hours: 24) do
    {:ok, health} ->
      score = Health.score(health)
      status = if Health.meeting_slos?(health), do: "✅", else: "⚠️"
      IO.puts("#{status} #{source}: #{Float.round(score, 1)}/100")

    {:error, reason} ->
      IO.puts("❌ #{source}: #{inspect(reason)}")
  end
end)
```

## File Locations

### Code
- Mix Tasks: `lib/mix/tasks/monitor.*.ex`
- API Modules: `lib/eventasaurus_discovery/monitoring/*.ex`
- MetricsTracker: `lib/eventasaurus_discovery/metrics/metrics_tracker.ex`
- Error Categories: `lib/eventasaurus_discovery/metrics/error_categories.ex`

### Documentation
- Implementation Guide: `docs/scraper-monitoring-guide.md`
- Quick Reference: `docs/monitoring-quick-reference.md` (this file)
- Main Guide: `CLAUDE.md`

### Data
- Baselines: `.taskmaster/baselines/`
- Database: `job_execution_summaries` table

## Testing

```bash
# Run monitoring API tests
mix test test/eventasaurus_discovery/monitoring/

# Test script
mix run test_monitoring_api.exs

# Test specific module
mix test test/eventasaurus_discovery/monitoring/baseline_test.exs
```

---

**Last Updated**: 2025-11-23
