# Sources Management Integration & Dashboard Access

## Overview
We have a sources table and management UI (`/admin/sources`, form at `/admin/source_form_live.ex`), but there are several integration gaps:
1. **No dashboard link** - The source management UI isn't accessible from the main dashboard
2. **Mixed source handling** - Some scrapers query the table, others use hardcoded config
3. **Seeds synchronization** - Seeds file may not match all active sources
4. **Configuration drift** - Priority and metadata split between table and hardcoded Config modules

## Current State Analysis

### Sources Table Schema
```elixir
- name: string (required)
- slug: string (required, unique)
- website_url: string
- priority: integer (0-100, default: 50)
- is_active: boolean (default: true)
- metadata: map (rate limits, etc.)
- domains: array of strings
- aggregate_on_index: boolean
- aggregation_type: string
```

### Existing Infrastructure
- ✅ **Admin UI**: `/admin/sources` (index) and `/admin/source_form_live` (form)
- ✅ **Source Schema**: `EventasaurusDiscovery.Sources.Source`
- ✅ **SourceStore**: Helper module for get/create operations
- ✅ **Seeds File**: `priv/repo/seeds/sources.exs` (9 sources)
- ✅ **Join Table**: `public_event_sources` links events to sources

### Seeds File Sources
Current seeds define (9 sources):
1. Ticketmaster (priority: 100)
2. Bandsintown (priority: 80)
3. Resident Advisor (priority: 75)
4. Karnet Kraków (priority: 70)
5. Question One (priority: 35)
6. Geeks Who Drink (priority: 35)
7. PubQuiz Poland (priority: 25)
8. Cinema City (priority: 15)
9. Kino Krakow (priority: 15)

## Scraper Integration Audit

### 🟢 Grade A: Fully Integrated

#### Resident Advisor
**Integration Score: 95/100**
- ✅ Uses `get_or_create_ra_source()` in sync job
- ✅ Queries table by slug: `resident-advisor`
- ✅ Falls back to creating from hardcoded config if missing
- ✅ Passes source_id throughout pipeline
- ⚠️ Priority hardcoded in Config module (75) AND seeds (75) - **DUPLICATION**

```elixir
# lib/eventasaurus_discovery/sources/resident_advisor/jobs/sync_job.ex:327
defp get_or_create_ra_source do
  case Repo.get_by(Source, slug: "resident-advisor") do
    nil -> # Creates from config
    source -> source
  end
end
```

#### Karnet Kraków
**Integration Score: 90/100**
- ✅ Uses `get_or_create_karnet_source()` pattern
- ✅ Queries table by slug: `karnet`
- ✅ Falls back to creating from config
- ❌ **NOT IN SEEDS** - Missing from seeds file
- ⚠️ Priority hardcoded in Config (70) - needs table migration

```elixir
# lib/eventasaurus_discovery/sources/karnet/jobs/sync_job.ex:445
defp get_or_create_karnet_source do
  case Repo.get_by(Source, slug: "karnet") do
    nil -> # Creates from source_config()
    source -> source
  end
end
```

### 🟡 Grade B: Partially Integrated

#### Bandsintown
**Integration Score: 70/100**
- ⚠️ **DUPLICATE IMPLEMENTATIONS** - Split between `scraping/` and `sources/`
- ❌ No clear get_or_create pattern visible
- ✅ In seeds file (priority: 80)
- ⚠️ Priority in Config (80) matches seeds but duplication exists
- ❓ Unclear which implementation is canonical

**Action Required**: Consolidate implementations first, then verify table integration

#### Ticketmaster
**Integration Score: 75/100**
- ❓ Uses different job structure (`apis/ticketmaster/` instead of `sources/`)
- ✅ In seeds file (priority: 70 in seeds, but Config says 100!)
- ⚠️ **PRIORITY MISMATCH**: Config=100, Seeds=70
- ❌ No visible get_or_create pattern in sync job
- ✅ Source_id used in EventProcessor

**Critical Issue**: Priority conflict between config and seeds

### 🔴 Grade C: Minimal Integration

#### Cinema City
**Integration Score: 60/100**
- ❌ No get_or_create pattern found
- ✅ In seeds (priority: 15)
- ⚠️ Likely relies on seeds being run
- ❓ Config priority unknown (needs investigation)

#### Kino Krakow
**Integration Score: 60/100**
- ❌ No get_or_create pattern found
- ✅ In seeds (priority: 15)
- ⚠️ Likely relies on seeds being run
- ❓ Config priority unknown

#### PubQuiz
**Integration Score: 55/100**
- ❌ No get_or_create pattern found
- ✅ In seeds (priority: 25)
- ⚠️ Likely relies on seeds being run
- ❓ Config priority unknown

### ❓ Not Audited

#### Question One
**Integration Score: TBD**
- ✅ In seeds (priority: 35)
- ✅ Regional trivia source for UK
- ❓ Integration pattern needs verification

#### Geeks Who Drink
**Integration Score: TBD**
- ✅ In seeds (priority: 35)
- ✅ Regional trivia source for US/Canada
- ❓ Integration pattern needs verification

## Issues Identified

### 🚨 Critical Issues (P0)

1. **No Dashboard Link**
   - Source management UI exists but not linked from dashboard
   - Users/admins can't easily access source configuration
   - **Impact**: Hidden functionality, no visibility into sources

2. **Priority Conflicts**
   - Ticketmaster: Config says 100, seeds say 70
   - Which is correct? Config used at runtime or seeds used at creation?
   - **Impact**: Unclear which priority is actually used

3. **Bandsintown Consolidation**
   - Duplicate implementations in `scraping/` and `sources/`
   - Can't audit table integration until consolidated
   - **Impact**: Confusion, potential bugs from using wrong version

### ⚠️ High Priority Issues (P1)

4. **Inconsistent Integration Patterns**
   - RA/Karnet: Full get_or_create with table queries ✅
   - Cinema City/Kino/PubQuiz: Rely on seeds ⚠️
   - Question One/Geeks Who Drink: Integration needs verification ❓
   - **Impact**: Fragile, requires seeds to run, can't add sources via UI

5. **Config/Table Duplication**
   - Priority defined in BOTH Config modules AND seeds
   - Metadata (rate limits, etc.) duplicated
   - **Impact**: Changes in one place don't reflect in other

### 📋 Medium Priority Issues (P2)

7. **Seeds File Maintenance**
   - No automatic sync between scrapers and seeds
   - Easy to forget updating seeds when adding scrapers
   - **Impact**: Database rebuild loses sources

## Recommended Solutions

### Phase 1: Dashboard Integration & Consolidation (Week 1)

**Tasks:**
1. Add "Manage Sources" link to dashboard navigation
   - Add to `lib/eventasaurus_web/live/dashboard_live.ex`
   - Link to route for `/admin/sources`
   - Consider permissions (admin only?)

2. Consolidate Bandsintown implementation
   - Determine canonical version
   - Remove duplicate
   - Add get_or_create pattern

3. Resolve Ticketmaster priority conflict
   - Determine correct priority (90? 100? 70?)
   - Update Config OR seeds to match
   - Document decision

### Phase 2: Standardize Source Integration (Week 2)

**Goal: Every scraper uses table-first approach**

**Pattern to Implement:**
```elixir
defp get_or_create_source do
  # Query table first
  case Repo.get_by(Source, slug: "scraper-slug") do
    nil ->
      # Fallback: create from config
      SourceStore.get_or_create_source(source_config())
    source ->
      source
  end
end
```

**Apply to:**
1. ✅ Resident Advisor (already has pattern)
2. ✅ Karnet (already has pattern)
3. ❌ Bandsintown (after consolidation)
4. ❌ Ticketmaster
5. ❌ Cinema City
6. ❌ Kino Krakow
7. ❌ PubQuiz
8. ❓ Question One (needs verification)
9. ❓ Geeks Who Drink (needs verification)

### Phase 3: Seeds & Configuration (Week 3)

1. **Update Seeds File**
   - ✅ Karnet added
   - ✅ Question One added
   - ✅ Geeks Who Drink added
   - Ensure all active scrapers represented
   - Match priorities with Config modules

2. **Deprecate Hardcoded Config**
   - Move priority to table
   - Move metadata to table
   - Keep only API URLs/endpoints in Config
   - Config becomes source of defaults, table is runtime truth

3. **Migration Strategy**
   - Create migration to sync existing sources with Config priorities
   - Add validation: Config priority should match table on startup
   - Add dev warning if mismatch detected

### Phase 4: Documentation & Testing (Week 4)

1. Document new source addition process
2. Add tests for source management
3. Add tests for get_or_create patterns
4. Update scraper docs with table-first approach

## Acceptance Criteria

- [ ] Dashboard has visible link to `/admin/sources`
- [ ] All active scrapers use get_or_create pattern
- [x] Seeds file includes all active sources (9 sources)
- [ ] No priority conflicts between Config and seeds
- [ ] Bandsintown consolidation complete
- [x] Karnet added to seeds
- [x] Question One added to seeds
- [x] Geeks Who Drink added to seeds
- [ ] Documentation updated for adding new sources
- [ ] All sources created via table are visible in UI

## Success Metrics

- **Developer Experience**: New scraper takes <5 minutes to add source
- **Operational**: Can add/edit sources without code deployment
- **Consistency**: Single source of truth for all source metadata
- **Reliability**: Database rebuild preserves all sources via seeds

## Related Files

### Source Management
- `lib/eventasaurus_discovery/sources/source.ex` - Schema
- `lib/eventasaurus_web/live/admin/source_index_live.ex` - List UI
- `lib/eventasaurus_web/live/admin/source_form_live.ex` - Form UI
- `lib/eventasaurus_discovery/sources/source_store.ex` - Helpers
- `priv/repo/seeds/sources.exs` - Seeds

### Scraper Configs (Hardcoded Values)
- `lib/eventasaurus_discovery/sources/resident_advisor/config.ex`
- `lib/eventasaurus_discovery/sources/ticketmaster/config.ex`
- `lib/eventasaurus_discovery/sources/bandsintown/config.ex`
- `lib/eventasaurus_discovery/sources/karnet/config.ex`
- `lib/eventasaurus_discovery/sources/cinema_city/config.ex`
- `lib/eventasaurus_discovery/sources/kino_krakow/config.ex`
- `lib/eventasaurus_discovery/sources/pubquiz/config.ex`

### Scraper Jobs (Integration Points)
- `lib/eventasaurus_discovery/sources/resident_advisor/jobs/sync_job.ex:327`
- `lib/eventasaurus_discovery/sources/karnet/jobs/sync_job.ex:445`
- (Others need investigation)

---

**Labels**: enhancement, refactoring, p0
**Milestone**: Sources Management Standardization
**Estimate**: 4 weeks (1 week per phase)
