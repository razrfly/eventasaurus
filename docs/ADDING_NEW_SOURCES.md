# Adding New Event Sources

This guide explains how to add a new event source to Eventasaurus Discovery system.

## Overview

Event sources are managed through a unified system that combines:
- **Database table** (`sources`) - Runtime source of truth
- **Seeds file** - Ensures sources persist across database rebuilds
- **Config modules** - Provide default values and API configuration
- **Scraper implementations** - Fetch and transform event data

## Quick Start (5 minutes)

### 1. Add Source to Seeds File

Edit `priv/repo/seeds/sources.exs` and add your source to the list:

```elixir
sources = [
  # ... existing sources ...
  %{
    name: "Your Source Name",
    slug: "your-source-slug",
    website_url: "https://example.com",
    priority: 50,  # 0-100, higher = more authoritative
    metadata: %{
      "rate_limit_seconds" => 2,
      "max_requests_per_hour" => 1000,
      "language" => "en",
      "supports_pagination" => true
    }
  }
]
```

**Priority Guidelines:**
- **90-100**: Official APIs (Ticketmaster)
- **70-89**: Major aggregators (Bandsintown, Resident Advisor)
- **50-69**: Regional platforms (Karnet)
- **20-49**: Specialized sources (PubQuiz)
- **1-19**: Cinema/movie sources (Cinema City, Kino Krakow)

### 2. Create Config Module

Create `lib/eventasaurus_discovery/sources/your_source/config.ex`:

```elixir
defmodule EventasaurusDiscovery.Sources.YourSource.Config do
  @moduledoc """
  Configuration for Your Source scraper.
  """

  @behaviour EventasaurusDiscovery.Sources.SourceConfig

  @base_url "https://api.example.com"
  @rate_limit 2  # requests per second

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def source_config do
    EventasaurusDiscovery.Sources.SourceConfig.merge_config(%{
      name: "Your Source Name",
      slug: "your-source-slug",
      priority: 50,
      rate_limit: @rate_limit,
      timeout: 10_000,
      max_retries: 3,
      queue: :discovery,
      base_url: @base_url,
      api_key: api_key(),
      metadata: %{
        "language" => "en",
        "supports_pagination" => true
      }
    })
  end

  def base_url, do: @base_url
  def rate_limit, do: @rate_limit

  defp api_key do
    System.get_env("YOUR_SOURCE_API_KEY") ||
      Application.get_env(:eventasaurus, :your_source)[:api_key]
  end
end
```

### 3. Implement Sync Job with get_or_create Pattern

Create `lib/eventasaurus_discovery/sources/your_source/jobs/sync_job.ex`:

```elixir
defmodule EventasaurusDiscovery.Sources.YourSource.Jobs.SyncJob do
  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :discovery,
    max_attempts: 3

  require Logger
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Sources.YourSource.{Config, Client, Transformer}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    city_id = args["city_id"]
    limit = args["limit"] || 100

    with {:ok, city} <- get_city(city_id),
         {:ok, source} <- get_or_create_source(),
         {:ok, raw_events} <- fetch_events(city, limit, %{}),
         transformed_events <- transform_events(raw_events) do

      process_events(transformed_events, source)

      {:ok, %{city: city.name, events: length(transformed_events)}}
    end
  end

  # REQUIRED: Table-first get_or_create pattern
  defp get_or_create_source do
    case Repo.get_by(Source, slug: "your-source-slug") do
      nil ->
        Logger.warning("⚠️ Source not found, creating from config")
        config = source_config()

        %Source{}
        |> Source.changeset(config)
        |> Repo.insert!()
        |> then(&{:ok, &1})

      source ->
        {:ok, source}
    end
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(city, limit, _options) do
    # Your fetching logic here
    {:ok, []}
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(raw_events) do
    # Your transformation logic here
    []
  end

  def source_config do
    Config.source_config()
  end
end
```

## Architecture Principles

### 1. Table-First Pattern

**Always query the database first, fall back to Config:**

```elixir
defp get_or_create_source do
  case Repo.get_by(Source, slug: "your-slug") do
    nil ->
      # Only create if not found
      SourceStore.get_or_create_source(source_config())
    source ->
      # Use existing table record (runtime truth)
      {:ok, source}
  end
end
```

**Why?** This allows runtime changes to source configuration without code deployment.

### 2. Priority Consistency

**Config priority MUST match seeds priority:**

```elixir
# Config module
priority: 50

# Seeds file
priority: 50  # Must match!
```

The `get_or_create` pattern uses Config values when creating sources, so mismatches cause inconsistency.

### 3. Single Source of Truth

**Runtime:** Database table (can be modified via admin UI)
**Bootstrap:** Seeds file (preserves sources on database rebuild)
**Defaults:** Config module (provides fallback values)

## Current Sources (Priority Order)

| Source | Priority | Type | Location |
|--------|----------|------|----------|
| Ticketmaster | 100 | Official API | Global |
| Bandsintown | 80 | Aggregator | Global |
| Resident Advisor | 75 | Aggregator | Global |
| Karnet Kraków | 70 | Regional Platform | Kraków, PL |
| PubQuiz Poland | 25 | Specialized | Poland |
| Cinema City | 15 | Cinema | Poland |
| Kino Krakow | 15 | Cinema | Kraków, PL |

## Testing Your Source

### 1. Run Seeds

```bash
# Drop and recreate database
mix ecto.drop && mix ecto.create && mix ecto.migrate

# Run seeds (creates all sources)
mix run priv/repo/seeds.exs
```

### 2. Verify in Admin UI

```bash
# Start server
mix phx.server

# Navigate to: http://localhost:4000
# Login → Click "Manage Sources" in navigation
# Verify your source appears with correct priority
```

### 3. Test Scraper

```bash
# Enqueue a sync job
mix run -e "
  alias EventasaurusDiscovery.Sources.YourSource.Jobs.SyncJob
  city = EventasaurusApp.Repo.get_by!(EventasaurusDiscovery.Locations.City, slug: \"krakow\")
  SyncJob.new(%{\"city_id\" => city.id, \"limit\" => 10})
  |> Oban.insert!()
"

# Watch logs
tail -f log/dev.log | grep -i "your source"
```

### 4. Verify Source Creation

Your scraper should:
1. Query database for source
2. Find it (from seeds)
3. Use it to tag events
4. Log something like: "✅ Using source: Your Source Name (id: 123)"

If source isn't in database, scraper will create it from Config (warning logged).

## Common Issues

### Priority Mismatch

**Symptom:** Seeds show priority 50, but Config shows priority 60

**Fix:** Update Config module to match seeds (Config is used when creating, seeds is used when seeding)

```elixir
# In config.ex
priority: 50  # Match seeds value
```

### Source Not Found After Seeds

**Symptom:** Scraper creates source even after running seeds

**Possible causes:**
1. Slug mismatch between Config and seeds
2. Seeds file not run
3. Database not migrated

**Fix:** Verify slug consistency:

```elixir
# Config module
slug: "your-source-slug"

# Seeds file
slug: "your-source-slug"  # Must match exactly!

# Sync job
Repo.get_by(Source, slug: "your-source-slug")  # Must match exactly!
```

### Missing get_or_create Pattern

**Symptom:** Scraper fails if source not in database

**Fix:** Implement the get_or_create pattern (see example above)

## Admin UI

Sources can be managed at `/admin/sources`:

- **List**: View all sources with priority, status, metadata
- **Add**: Create new source without code changes
- **Edit**: Update priority, metadata, active status
- **Deactivate**: Disable source without deleting

Changes take effect immediately (no code deployment needed).

## Rate Limiting

Add source-specific rate limits to `scraping/rate_limiter.ex` if needed:

```elixir
def source_config(source_slug) do
  configs = %{
    "your-source-slug" => %{
      max_per_hour: 1000,
      max_per_minute: 50,
      delay_seconds: 2,
      max_attempts: 5
    }
  }
  # ...
end
```

## Best Practices

1. **Use Descriptive Names**: "Karnet Kraków" not "Karnet"
2. **Consistent Slugs**: Use kebab-case, match everywhere
3. **Set Realistic Priorities**: Don't over-inflate your source
4. **Document Metadata**: Explain custom metadata fields
5. **Test Thoroughly**: Drop/seed/test before committing
6. **Follow Patterns**: Use existing sources as templates

## Migration Path for Existing Sources

If you have an existing scraper without proper source integration:

1. Add to seeds file
2. Add `get_or_create_source()` to sync job
3. Update Config to use `SourceConfig` behavior
4. Test with database rebuild
5. Verify scraper finds/creates source correctly

## Further Reading

- `docs/SCRAPER_MANIFESTO.md` - Scraper architecture principles
- `lib/eventasaurus_discovery/sources/source.ex` - Source schema
- `lib/eventasaurus_discovery/sources/source_store.ex` - Helper functions
- Issue #1629 - Sources management standardization
