# City-Based Venue Slug Regeneration

## Problem Statement

When adding new cities to the scraping system, venue slugs are sometimes generated incorrectly or sub-optimally. Currently, there's no easy way to regenerate slugs for all venues in a specific city without running a database migration.

**Example**: London has many venues with poorly-formatted slugs that need to be regenerated using the current slug generation logic.

## Current State

### Existing Infrastructure

1. **Slug Generation Logic**: `EventasaurusApp.Venues.Venue.Slug` module
   - Located in: `lib/eventasaurus_app/venues/venue.ex`
   - Strategy: Progressive disambiguation (name → name-city → name-timestamp)
   - Handles UTF-8 safety and uniqueness

2. **Historical Precedent**: Migration `20251024071752_regenerate_venue_slugs.exs`
   - Batch-processes all venues to regenerate slugs
   - Provides pattern for forcing slug regeneration
   - Key technique: `force_change(:name, venue.name)` triggers `Venue.Slug.maybe_generate_slug/1`

3. **Similar Operations Pages**:
   - **Venue Image Operations** (`/admin/venue-images/operations`): Shows enrichment job history, allows retry operations
   - **Geocoding Operations** (`/admin/geocoding/cities/:city_slug/operations`): City-specific operations with job tracking
   - **Sitemap Page** (`/admin/sitemap`): Simple regeneration button pattern

## Requirements

### Functional Requirements

1. **City-Specific Regeneration**: Ability to regenerate venue slugs for a single city
2. **Job Tracking**: Track progress and results of slug regeneration operations
3. **Error Handling**: Gracefully handle failures, report problematic venues
4. **History**: View past slug regeneration operations per city
5. **Batch Processing**: Process venues in batches to avoid memory/lock issues
6. **Idempotent**: Safe to run multiple times (skips unchanged slugs)

### Non-Functional Requirements

1. **Performance**: Process ~100 venues in reasonable time (<5 minutes)
2. **Reliability**: Use Oban for background processing with retry logic
3. **Observability**: Clear progress indicators and detailed result metadata
4. **Safety**: No data loss, proper transaction handling

## Proposed Solution

### Option 1: Add to Geocoding Operations Page (Recommended)

**Location**: Extend `/admin/geocoding/cities/:city_slug/operations`

**Rationale**:
- Already city-specific (takes city_slug parameter)
- Already displays venue operation history
- Has infrastructure for job tracking
- Consistent with existing venue operations pattern

**UI Addition**:
```text
[Existing geocoding operations display]

Venue Operations
└─ [Regenerate Venue Slugs] button
   "Regenerate slugs for all venues in {city_name}"
```

### Option 2: Add to City Index Page

**Location**: Add action button to `/admin/cities`

**Rationale**:
- Quick access without navigating to separate page
- Simple, direct action per city
- Less overhead for single operation

**UI Addition**:
```text
Cities Table
│ Name     │ Country │ Venues │ Actions                        │
├──────────┼─────────┼────────┼───────────────────────────────┤
│ London   │ UK      │ 234    │ [Edit] [Delete] [⚡ Regen Slugs]│
```

### Option 3: New Venue Operations Dashboard

**Location**: Create `/admin/venues/operations`

**Rationale**:
- Centralized location for all venue maintenance operations
- Room for future venue-related bulk operations
- Consistent with venue image operations pattern

## Implementation Components

### 1. Oban Worker

**Name**: `EventasaurusApp.Venues.RegenerateSlugsByCityJob`

**Parameters**:
```elixir
%{
  "city_id" => integer,
  "city_slug" => string,  # For display purposes
  "force_all" => boolean  # If true, regenerate even unchanged slugs
}
```

**Logic** (based on migration pattern):
1. Load all venues for city_id with preloaded city_ref
2. Process in batches of 100 venues
3. For each venue:
   - Create changeset with `force_change(:name, venue.name)`
   - Call `Venue.Slug.maybe_generate_slug/1`
   - Update if slug changed
   - Track result (updated/skipped/error)
4. Store metadata with results

**Metadata Structure**:
```elixir
%{
  "total_venues" => 234,
  "updated" => 198,
  "skipped" => 34,
  "failed" => 2,
  "duration_seconds" => 45,
  "failed_venues" => [
    %{"venue_id" => 123, "venue_name" => "Example", "error" => "..."}
  ]
}
```

### 2. LiveView Updates

#### If using Geocoding Operations Page:

**File**: `lib/eventasaurus_web/live/admin/geocoding_operations_live.ex`

**Changes**:
1. Add `handle_event("regenerate_venue_slugs", ...)` handler
2. Enqueue `RegenerateSlugsByCityJob` with city_id
3. Display flash message confirming job queued
4. Update operations query to include slug regeneration jobs

**Template**: `geocoding_operations_live.html.heex`
- Add "Regenerate Venue Slugs" button in operations section
- Display slug regeneration job history in operations list

#### If using City Index Page:

**File**: `lib/eventasaurus_web/live/admin/city_index_live.ex`

**Changes**:
1. Add `handle_event("regenerate_slugs", %{"city_id" => city_id}, ...)` handler
2. Enqueue job, display flash confirmation
3. No history display needed (simple trigger)

**Template**: `city_index_live.html.heex`
- Add button in actions column per city row

### 3. Router Updates (if needed)

No changes needed if using existing pages.

## Testing Strategy

### Unit Tests

1. **Worker Tests**: `test/eventasaurus_app/venues/regenerate_slugs_by_city_job_test.exs`
   - Test successful regeneration
   - Test error handling
   - Test batch processing
   - Test metadata generation

### Integration Tests

1. **LiveView Tests**: Test button triggers job correctly
2. **End-to-End**: Verify slugs actually change after job completes

### Manual Testing Checklist

- [ ] Create test city with venues having bad slugs
- [ ] Trigger regeneration from UI
- [ ] Verify job appears in operations history
- [ ] Confirm slugs updated correctly in database
- [ ] Test with city having 0 venues
- [ ] Test with city having 500+ venues
- [ ] Verify error handling with problematic venue data

## Migration Path

1. **Phase 1**: Create Oban worker with full logic
2. **Phase 2**: Add UI button to chosen page
3. **Phase 3**: Test with London (known problem city)
4. **Phase 4**: Document usage in admin guide

## Success Criteria

- [ ] Admin can trigger slug regeneration for any city from UI
- [ ] Job processes all venues in city correctly
- [ ] Results visible in operations history with clear metadata
- [ ] Failed venues reported with actionable error messages
- [ ] London venue slugs successfully regenerated
- [ ] Operation completes in <5 minutes for cities with <1000 venues

## Related Files

### Core Logic
- `lib/eventasaurus_app/venues/venue.ex` - Venue.Slug module
- `priv/repo/migrations/20251024071752_regenerate_venue_slugs.exs` - Reference implementation

### Potential UI Locations
- `lib/eventasaurus_web/live/admin/geocoding_operations_live.ex` - Option 1
- `lib/eventasaurus_web/live/admin/city_index_live.ex` - Option 2

### Similar Patterns
- `lib/eventasaurus_web/live/admin/venue_image_operations_live.ex` - Job tracking pattern
- `lib/eventasaurus_web/live/admin/sitemap_live.ex` - Simple button pattern
- `lib/eventasaurus_discovery/venue_images/backfill_orchestrator_job.ex` - City-wide operation pattern

## Questions for Discussion

1. **UI Location**: Which page should host this functionality? (Geocoding Operations vs City Index vs New Page)
2. **Scope Control**: Should we support:
   - Regenerate all venues (even with unchanged slugs)?
   - Regenerate only venues matching certain patterns?
   - Dry-run mode to preview changes?
3. **Notifications**: Should we notify when job completes (email/Slack)?
4. **Frequency Limits**: Should we rate-limit to prevent abuse?

## Implementation Estimate

- **Worker Development**: 2-3 hours
- **UI Integration**: 1-2 hours (depending on chosen option)
- **Testing**: 2-3 hours
- **Documentation**: 1 hour

**Total**: ~6-9 hours

## Priority

**Medium-High**: Currently blocking ability to fix London venue slugs without manual SQL or new migration.
