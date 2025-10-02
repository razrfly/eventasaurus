# Kino Krakow Oban Job Fix

## Issue

Oban jobs for Kino Krakow scraper were failing with:
```
** (Oban.PerformError) EventasaurusDiscovery.Sources.KinoKrakow.Jobs.SyncJob failed with {:error, :invalid_config_slug}
```

## Root Cause

The `BaseJob` behavior calls `SourceStore.get_or_create_source(source_config())` which requires the config to include:
- `slug` - Source identifier (e.g., "kino-krakow")
- `name` - Human-readable name (e.g., "Kino Krakow")
- `priority` - Priority number for source ordering
- `website_url` - Source website URL

The Kino Krakow `Source.config/0` function was missing these required fields.

## Fix

Added required fields to `Source.config/0`:

```elixir
def config do
  %{
    # Source identification (required by SourceStore)
    slug: key(),              # "kino-krakow"
    name: name(),             # "Kino Krakow"
    priority: priority(),     # 15
    website_url: Config.base_url(),

    # ... rest of config
  }
end
```

Also added:
- `rate_limit` - For SourceStore metadata
- `max_retries` - For SourceStore metadata

## Files Modified

- `lib/eventasaurus_discovery/sources/kino_krakow/source.ex`
  - Added `slug`, `name`, `priority`, `website_url` fields
  - Added `rate_limit` and `max_retries` for metadata

## Testing

The job should now successfully:
1. Create/fetch the source record in the database
2. Fetch movie showtimes from Kino Krakow
3. Match movies to TMDB with the improved algorithm
4. Create enriched public events

## Status

✅ **FIXED** - Oban job should now run successfully from the admin dashboard.

---

**Date**: October 2, 2025
**Issue**: Oban job failing with :invalid_config_slug
**Fix**: Added required source identification fields to config
