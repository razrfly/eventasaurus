# Phase 2: Rename Kino Krakow Source to Repertuary

## Overview

Rename the "Kino Krakow" source to "Repertuary" to support multi-city scraping from the Repertuary.pl network (similar to Cinema City's multi-city architecture). This enables scraping movie showtimes from 29+ Polish cities using a single, properly-named source.

## Current State

### Database Records
- **Source ID**: 7
- **Current Slug**: `kino-krakow`
- **Current Name**: `Kino Krakow`
- **Website URL**: `https://www.kino.krakow.pl` (should be `https://krakow.repertuary.pl`)
- **Linked Records**: 61 `public_event_sources` records
- **Movies with Metadata**: 17 movies with `kino_krakow_slug` or `repertuary_slug` in metadata

### External IDs
- **Old format**: `kino_krakow_movie_{id}_{date}` (existing events)
- **New format**: `repertuary_{city}_movie_{id}_{date}` (introduced in Phase 1)
- The code already supports both formats via `EventFreshnessChecker`

### Active Jobs
- **Pending Oban Jobs**: 0 (safe to rename)

## Files to Rename/Update

### 1. Directory & Module Renames (18 files)

**Rename directory**:
```
lib/eventasaurus_discovery/sources/kino_krakow/ → lib/eventasaurus_discovery/sources/repertuary/
```

**Files to rename** (16 files in directory + 1 parent module):
| Current Path | New Path |
|-------------|----------|
| `lib/eventasaurus_discovery/sources/kino_krakow.ex` | `lib/eventasaurus_discovery/sources/repertuary.ex` |
| `lib/eventasaurus_discovery/sources/kino_krakow/config.ex` | `lib/eventasaurus_discovery/sources/repertuary/config.ex` |
| `lib/eventasaurus_discovery/sources/kino_krakow/cities.ex` | `lib/eventasaurus_discovery/sources/repertuary/cities.ex` |
| `lib/eventasaurus_discovery/sources/kino_krakow/source.ex` | `lib/eventasaurus_discovery/sources/repertuary/source.ex` |
| `lib/eventasaurus_discovery/sources/kino_krakow/transformer.ex` | `lib/eventasaurus_discovery/sources/repertuary/transformer.ex` |
| `lib/eventasaurus_discovery/sources/kino_krakow/dedup_handler.ex` | `lib/eventasaurus_discovery/sources/repertuary/dedup_handler.ex` |
| `lib/eventasaurus_discovery/sources/kino_krakow/tmdb_matcher.ex` | `lib/eventasaurus_discovery/sources/repertuary/tmdb_matcher.ex` |
| `lib/eventasaurus_discovery/sources/kino_krakow/jobs/sync_job.ex` | `lib/eventasaurus_discovery/sources/repertuary/jobs/sync_job.ex` |
| `lib/eventasaurus_discovery/sources/kino_krakow/jobs/movie_page_job.ex` | `lib/eventasaurus_discovery/sources/repertuary/jobs/movie_page_job.ex` |
| `lib/eventasaurus_discovery/sources/kino_krakow/jobs/movie_detail_job.ex` | `lib/eventasaurus_discovery/sources/repertuary/jobs/movie_detail_job.ex` |
| `lib/eventasaurus_discovery/sources/kino_krakow/jobs/showtime_process_job.ex` | `lib/eventasaurus_discovery/sources/repertuary/jobs/showtime_process_job.ex` |
| `lib/eventasaurus_discovery/sources/kino_krakow/jobs/day_page_job.ex` | `lib/eventasaurus_discovery/sources/repertuary/jobs/day_page_job.ex` |
| `lib/eventasaurus_discovery/sources/kino_krakow/extractors/showtime_extractor.ex` | `lib/eventasaurus_discovery/sources/repertuary/extractors/showtime_extractor.ex` |
| `lib/eventasaurus_discovery/sources/kino_krakow/extractors/cinema_extractor.ex` | `lib/eventasaurus_discovery/sources/repertuary/extractors/cinema_extractor.ex` |
| `lib/eventasaurus_discovery/sources/kino_krakow/extractors/movie_extractor.ex` | `lib/eventasaurus_discovery/sources/repertuary/extractors/movie_extractor.ex` |
| `lib/eventasaurus_discovery/sources/kino_krakow/extractors/movie_list_extractor.ex` | `lib/eventasaurus_discovery/sources/repertuary/extractors/movie_list_extractor.ex` |
| `lib/eventasaurus_discovery/sources/kino_krakow/extractors/movie_page_extractor.ex` | `lib/eventasaurus_discovery/sources/repertuary/extractors/movie_page_extractor.ex` |

**Module name changes inside each file**:
- `EventasaurusDiscovery.Sources.KinoKrakow` → `EventasaurusDiscovery.Sources.Repertuary`
- All nested modules follow the same pattern

### 2. Test Files to Rename (2 files)

```
test/eventasaurus_discovery/sources/kino_krakow/ → test/eventasaurus_discovery/sources/repertuary/
```

| Current Path | New Path |
|-------------|----------|
| `test/eventasaurus_discovery/sources/kino_krakow/integration_test.exs` | `test/eventasaurus_discovery/sources/repertuary/integration_test.exs` |
| `test/eventasaurus_discovery/sources/kino_krakow/transformer_test.exs` | `test/eventasaurus_discovery/sources/repertuary/transformer_test.exs` |

### 3. Registry & Configuration Updates

**`lib/eventasaurus_discovery/sources/source_registry.ex`**:
```elixir
# Change:
"kino-krakow" => EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob,
# To:
"repertuary" => EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob,
```

**`lib/eventasaurus_app/monitoring/job_registry.ex`**:
```elixir
# Change:
defp get_parent_worker_for_source("kino-krakow"),
  do: "EventasaurusDiscovery.Sources.KinoKrakow.Jobs.DayPageJob"
# To:
defp get_parent_worker_for_source("repertuary"),
  do: "EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob"
```

**`lib/mix/tasks/discovery.sync.ex`**:
```elixir
# Change @sources map:
"kino-krakow" => EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob,
# To:
"repertuary" => EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob,

# Change @country_wide_sources:
@country_wide_sources ["pubquiz-pl", "cinema-city", "kino-krakow"]
# To:
@country_wide_sources ["pubquiz-pl", "cinema-city", "repertuary"]
```

### 4. Seeds Update

**`priv/repo/seeds/reference_data/sources.exs`**:
```elixir
# Change:
%{
  name: "Kino Krakow",
  slug: "kino-krakow",
  website_url: "https://www.kino.krakow.pl",
  ...
}
# To:
%{
  name: "Repertuary",
  slug: "repertuary",
  website_url: "https://repertuary.pl",
  ...
}
```

### 5. Config File Updates

**`config/runtime.exs`** (2 references):
```elixir
# Line ~194 - Change:
kino_krakow: [:direct]
# To:
repertuary: [:direct]

# Line ~871 - Change source mapping if present
```

**`config/dev.exs`** (line 234):
```elixir
# Change:
"kino-krakow" => 24
# To:
"repertuary" => 24
```

**`config/test.exs`** (line 122):
```elixir
# Change:
"kino-krakow" => 24
# To:
"repertuary" => 24
```

### 6. Monitoring & Metrics Updates

**`lib/eventasaurus_discovery/metrics/scraper_slos.ex`** (5 worker entries):
```elixir
# Change all worker names from KinoKrakow to Repertuary:
"EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob" => %{...}
# To:
"EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob" => %{...}

# And similarly for:
# - MoviePageJob
# - MovieDetailJob
# - ShowtimeProcessJob
# - DayPageJob
```

**Monitoring modules** (1 reference each):
- `lib/eventasaurus_discovery/monitoring/baseline.ex`
- `lib/eventasaurus_discovery/monitoring/health.ex`
- `lib/eventasaurus_discovery/monitoring/errors.ex`
- `lib/eventasaurus_discovery/monitoring/chain.ex`

### 7. Service Layer Updates

**`lib/eventasaurus_discovery/services/event_freshness_checker.ex`** (4 references):
- Update worker name patterns used for job matching

**`lib/eventasaurus_discovery/job_execution_summaries.ex`** (3 references):
- Update any hardcoded source slug references

### 8. Database Migration

Create migration to update the source record:

```elixir
defmodule EventasaurusApp.Repo.Migrations.RenameKinoKrakowToRepertuary do
  use Ecto.Migration

  def up do
    execute """
    UPDATE sources
    SET name = 'Repertuary',
        slug = 'repertuary',
        website_url = 'https://repertuary.pl'
    WHERE slug = 'kino-krakow'
    """
  end

  def down do
    execute """
    UPDATE sources
    SET name = 'Kino Krakow',
        slug = 'kino-krakow',
        website_url = 'https://www.kino.krakow.pl'
    WHERE slug = 'repertuary'
    """
  end
end
```

### 9. Oban Job Migration

Update existing Oban job records to use new worker names:

```elixir
defmodule EventasaurusApp.Repo.Migrations.UpdateObanJobWorkerNames do
  use Ecto.Migration

  @worker_mappings [
    {"EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob",
     "EventasaurusDiscovery.Sources.Repertuary.Jobs.SyncJob"},
    {"EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MoviePageJob",
     "EventasaurusDiscovery.Sources.Repertuary.Jobs.MoviePageJob"},
    {"EventasaurusDiscovery.Sources.KinoKrakow.Jobs.MovieDetailJob",
     "EventasaurusDiscovery.Sources.Repertuary.Jobs.MovieDetailJob"},
    {"EventasaurusDiscovery.Sources.KinoKrakow.Jobs.ShowtimeProcessJob",
     "EventasaurusDiscovery.Sources.Repertuary.Jobs.ShowtimeProcessJob"},
    {"EventasaurusDiscovery.Sources.KinoKrakow.Jobs.DayPageJob",
     "EventasaurusDiscovery.Sources.Repertuary.Jobs.DayPageJob"}
  ]

  def up do
    for {old_worker, new_worker} <- @worker_mappings do
      execute """
      UPDATE oban_jobs
      SET worker = '#{new_worker}'
      WHERE worker = '#{old_worker}'
      """
    end
  end

  def down do
    for {old_worker, new_worker} <- @worker_mappings do
      execute """
      UPDATE oban_jobs
      SET worker = '#{old_worker}'
      WHERE worker = '#{new_worker}'
      """
    end
  end
end
```

### 10. Job Execution Summaries Migration

Update historical execution records:

```elixir
defmodule EventasaurusApp.Repo.Migrations.UpdateJobExecutionSummaryWorkers do
  use Ecto.Migration

  def up do
    # Update worker names in job_execution_summaries
    execute """
    UPDATE job_execution_summaries
    SET worker = REPLACE(worker, 'KinoKrakow', 'Repertuary')
    WHERE worker LIKE '%KinoKrakow%'
    """

    # Update source slug references
    execute """
    UPDATE job_execution_summaries
    SET results = jsonb_set(results, '{source}', '"repertuary"')
    WHERE results->>'source' = 'kino-krakow'
    """
  end

  def down do
    execute """
    UPDATE job_execution_summaries
    SET worker = REPLACE(worker, 'Repertuary', 'KinoKrakow')
    WHERE worker LIKE '%Repertuary%'
    """

    execute """
    UPDATE job_execution_summaries
    SET results = jsonb_set(results, '{source}', '"kino-krakow"')
    WHERE results->>'source' = 'repertuary'
    """
  end
end
```

## Files to Archive/Document (no code changes needed)

These files contain historical references and documentation. They should NOT be modified but noted:

- `docs/kino-krakow/*.md` (13 documentation files) - Historical documentation
- `scripts/archive/test_kino_krakow*.exs` (3 files) - Archived test scripts
- `.taskmaster/baselines/kino_krakow_*.json` (1 file) - Historical baseline data
- Various analysis/report markdown files (7 files)

## Backward Compatibility Considerations

### External ID Handling
The code already handles both old and new external ID formats:
- Old: `kino_krakow_movie_{id}_{date}`
- New: `repertuary_{city}_movie_{id}_{date}`

The `EventFreshnessChecker` checks for both `repertuary_slug` and `kino_krakow_slug` in movie metadata.

### Movie Metadata
17 movies have `kino_krakow_slug` in their metadata. Options:
1. **Keep as-is**: The code already handles both key names
2. **Migrate**: Update metadata keys from `kino_krakow_slug` to `repertuary_slug`

Recommendation: Keep as-is since the code already supports both.

### Linked Events
61 `public_event_sources` records link to source ID 7. These will automatically update when the source record is migrated since they reference by ID, not slug.

## Implementation Order

1. **Create database migrations** (source, oban_jobs, job_execution_summaries)
2. **Rename directory and files** (git mv for proper history)
3. **Update module names** in all renamed files
4. **Update registry files** (source_registry.ex, job_registry.ex, discovery.sync.ex)
5. **Update config files** (runtime.exs, dev.exs, test.exs)
6. **Update monitoring/metrics files** (scraper_slos.ex, monitoring modules)
7. **Update service files** (event_freshness_checker.ex, job_execution_summaries.ex)
8. **Update seeds** (sources.exs)
9. **Run migrations**
10. **Run tests** to verify everything works
11. **Deploy** with coordinated database migration

## Testing Checklist

- [ ] All tests pass after rename
- [ ] `mix compile --warnings-as-errors` succeeds
- [ ] `mix format` passes
- [ ] Can trigger sync job via `mix discovery.sync repertuary`
- [ ] Jobs appear correctly in Oban dashboard
- [ ] Monitoring dashboards work correctly
- [ ] Historical metrics still accessible
- [ ] New events created with correct external IDs

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Missed reference causing runtime error | Medium | High | Comprehensive grep + test suite |
| Historical data becomes inaccessible | Low | Medium | Migration handles worker name updates |
| External ID conflicts | Low | Low | Code already handles both formats |
| Monitoring gaps during transition | Low | Medium | Deploy during low-traffic period |

## Related Issues

- Phase 1: Multi-city support (completed) - Added city parameter throughout job chain
- Phase 3: Add Warsaw city configuration (pending) - After this rename

## Estimated Effort

- **File renames**: 20 files
- **Module updates**: ~50 module name changes across 18 source files
- **Registry/config updates**: 8 files
- **Monitoring updates**: 5 files
- **Database migrations**: 3 migrations
- **Testing**: Full test suite run

**Total estimated time**: 2-3 hours for implementation, 1 hour for testing and validation
