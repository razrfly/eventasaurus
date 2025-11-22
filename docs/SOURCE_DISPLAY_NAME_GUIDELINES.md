# Source Display Name Guidelines

## Overview

This document provides guidelines for managing source display names in Eventasaurus. Following these guidelines ensures consistency, maintainability, and prevents hardcoded source names from proliferating across the codebase.

## Problem Background

**Issue:** #2344 - Centralize source display names from database

Prior to this implementation, source display names were hardcoded in multiple locations throughout the codebase:

- `AggregatedContentLive.get_source_name/1` - 2 hardcoded sources
- `JobRegistry.humanize_source_name/1` - 13 hardcoded sources
- `GeocodingDashboardLive.format_scraper_name/1` - 5 hardcoded sources

This approach created several problems:

1. **Inconsistency** - Same source could have different display names in different parts of the app
2. **Maintenance Burden** - Adding a new source required code changes in multiple files
3. **Risk of Outdated Names** - If a source rebrands, names might not update uniformly
4. **Code Duplication** - Pattern matching logic repeated across modules

## Solution: Single Source of Truth

All source display names now come from the **database** via the `sources` table.

### Database Schema

```elixir
# priv/repo/seeds/reference_data/sources.exs
%{
  slug: "week_pl",
  name: "Restaurant Week",  # ← Single source of truth
  category: "food_and_dining",
  countries: ["PL"]
}
```

### Helper Function

Use `Source.get_display_name/1` for all display name needs:

```elixir
alias EventasaurusDiscovery.Sources.Source

# Get display name from database
Source.get_display_name("week_pl")
# => "Restaurant Week"

# Unknown sources get automatic title-casing from slug
Source.get_display_name("unknown-source")
# => "Unknown Source"
```

## Usage Guidelines

### ✅ DO: Use Source.get_display_name/1

```elixir
# Good - pulls from database
defp get_source_name(slug) do
  Source.get_display_name(slug)
end

# Good - with additional formatting
defp humanize_source_name(slug) do
  Source.get_display_name(slug) <> " Sync"
end

# Good - normalize underscore to hyphen first
defp format_scraper_name(name) do
  normalized = String.replace(name, "_", "-")
  Source.get_display_name(normalized)
end
```

### ❌ DON'T: Hardcode Source Names

```elixir
# Bad - hardcoded display names
defp get_source_name("week_pl"), do: "Restaurant Week"
defp get_source_name("bandsintown"), do: "Bandsintown"
defp get_source_name(slug), do: slug

# Bad - multiple pattern matches for different sources
defp humanize_source_name("karnet"), do: "Karnet Sync"
defp humanize_source_name("resident-advisor"), do: "Resident Advisor Sync"
```

### Special Cases

#### 1. Handling nil/Unknown Sources

```elixir
defp format_name(nil), do: "Unknown"
defp format_name(slug), do: Source.get_display_name(slug)
```

#### 2. Normalizing Slug Formats

Some systems use underscores, others use hyphens. Normalize before lookup:

```elixir
# Scrapers often use underscores, sources use hyphens
defp format_scraper_name(name) do
  normalized = String.replace(name, "_", "-")
  Source.get_display_name(normalized)
end
```

## Adding New Sources

### Step 1: Add to Seeds

Edit `priv/repo/seeds/reference_data/sources.exs`:

```elixir
%{
  slug: "new-source",
  name: "New Source Display Name",
  category: "nightlife",
  countries: ["US"]
}
```

### Step 2: Run Seeds

```bash
mix run priv/repo/seeds.exs
```

### Step 3: Verify

```elixir
Source.get_display_name("new-source")
# => "New Source Display Name"
```

**That's it!** The display name is automatically available throughout the application via `Source.get_display_name/1`. No code changes required.

## Safeguards

A comprehensive test suite prevents regression to hardcoded names:

### Test File

`test/eventasaurus_discovery/sources/no_hardcoded_names_test.exs`

### What It Checks

1. **Pattern Matching on Slugs** - Detects functions that pattern match on known source slugs and return hardcoded display names
2. **High-Risk Files** - Specifically checks files that previously had hardcoded names (AggregatedContentLive, JobRegistry)
3. **Helper Function Exists** - Verifies `Source.get_display_name/1` is available and working

### Running the Test

```bash
MIX_ENV=test mix test test/eventasaurus_discovery/sources/no_hardcoded_names_test.exs
```

### When Tests Fail

If the safeguard test fails, you've likely added hardcoded source names. Follow these steps:

1. Review the test output to identify the file and line number
2. Replace hardcoded pattern matching with `Source.get_display_name/1`
3. Run the test again to verify the fix
4. Ensure the source exists in `priv/repo/seeds/reference_data/sources.exs`

## Implementation References

For detailed examples of how this pattern was implemented, see:

- **Issue:** #2344 - Centralize source display names from database
- **Phase 1:** Created `Source.get_display_name/1` helper with fallback logic
- **Phase 2:** Replaced all hardcoded references in:
  - `lib/eventasaurus_web/live/aggregated_content_live.ex` (lines 283)
  - `lib/eventasaurus_app/monitoring/job_registry.ex` (lines 227-229)
  - `lib/eventasaurus_web/live/admin/geocoding_dashboard_live.ex` (lines 127-133)
- **Phase 3:** Added safeguard tests to prevent future hardcoding

## Benefits

Following these guidelines provides:

1. ✅ **Single Source of Truth** - Database is authoritative for all display names
2. ✅ **Consistency** - Same source shows identical name everywhere
3. ✅ **Zero Code Changes** - Adding sources requires only seed data updates
4. ✅ **Automatic Updates** - Name changes in database propagate instantly
5. ✅ **Safeguards** - Tests prevent accidental hardcoding
6. ✅ **Maintainability** - Centralized logic is easier to understand and modify

## Related Documentation

- `lib/eventasaurus_discovery/sources/source.ex` - Implementation of `get_display_name/1`
- `priv/repo/seeds/reference_data/sources.exs` - Source definitions
- `test/eventasaurus_discovery/sources/no_hardcoded_names_test.exs` - Safeguard tests
- Issue #2344 - Original implementation tracking

---

**Questions?** See issue #2344 or contact the development team.
