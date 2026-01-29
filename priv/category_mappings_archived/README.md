# Archived Category Mappings (YAML)

These YAML files are **archived** and no longer used by the application.

## History

- **Original Purpose**: Category mappings for event scrapers
- **Migration Date**: January 2025
- **Migrated To**: Database-backed mappings with ETS caching
- **Migration Task**: `EventasaurusApp.ReleaseTasks.migrate_yaml_mappings/0`

## Why Archived?

As part of Phase 2.3 (Issue #3469), we deprecated the YAML-based category mappings in favor of:

1. **Database storage** (`category_mappings` table) - Allows runtime updates without redeployment
2. **ETS caching** - Fast in-memory lookups with automatic refresh
3. **Admin UI** - Category mappings can be managed via `/admin/category-mappings`

## Restoring (Emergency Only)

If you need to restore YAML mappings for emergency debugging:

1. Copy files back to `priv/category_mappings/`
2. Set `use_db_mappings: false` in config (requires code changes to re-add)
3. This is NOT recommended - prefer fixing the DB/ETS system instead

## Files

- `_defaults.yml` - Default fallback mappings
- `bandsintown.yml` - Bandsintown source mappings
- `karnet.yml` - Karnet source mappings
- `resident-advisor.yml` - Resident Advisor source mappings
- `sortiraparis.yml` - Sortir à Paris source mappings
- `ticketmaster.yml` - Ticketmaster source mappings
- `waw4free.yml` - Waw4Free source mappings
- `week_pl.yml` - Week.pl source mappings
