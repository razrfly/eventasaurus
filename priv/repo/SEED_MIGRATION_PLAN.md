# Seed Migration Plan - Phase 2 & 3

**Status**: Phase 2 Complete, Ready for Phase 3 Execution
**Created**: 2025
**Issue**: [#2239](https://github.com/razrfly/eventasaurus/issues/2239)

## Overview

This document provides the complete categorization of all seed files and the detailed migration plan for reorganizing them. Phase 2 created the directory structure; Phase 3 will execute the migrations.

## Directory Structure Created (Phase 2 ✅)

```
priv/repo/
├── seeds/
│   ├── reference_data/     # NEW - For reference lookup data
│   │   └── .gitkeep
│   └── ... (existing files)
│
└── dev_seeds/
    ├── core/               # NEW - Core entity seeds
    │   └── .gitkeep
    ├── features/           # NEW - Feature-specific seeds
    │   ├── polls/
    │   │   └── .gitkeep
    │   ├── ticketing/
    │   │   └── .gitkeep
    │   ├── groups/
    │   │   └── .gitkeep
    │   └── activities/
    │       └── .gitkeep
    ├── scenarios/          # NEW - Test scenarios
    │   └── .gitkeep
    ├── support/            # NEW - Support utilities
    │   └── .gitkeep
    ├── services/           # EXISTS - Service modules
    └── ... (existing files)
```

## Complete File Categorization

### Production Seeds (priv/repo/seeds/)

| Current File | Category | New Location | Action | Priority |
|-------------|----------|--------------|--------|----------|
| `categories.exs` | Reference Data | `reference_data/categories.exs` | **MOVE** | P1 |
| `locations.exs` | Reference Data | `reference_data/locations.exs` | **MOVE** | P1 |
| `sources.exs` | Reference Data | `reference_data/sources.exs` | **MOVE** | P1 |
| `discovery_cities.exs` | Reference Data | `reference_data/discovery_cities.exs` | **MOVE** | P1 |
| `discovery_config_krakow.exs` | Reference Data | `reference_data/discovery_config_krakow.exs` | **MOVE** | P1 |
| `city_alternate_names.exs` | Reference Data | `reference_data/city_alternate_names.exs` | **MOVE** | P1 |
| `poll_suggestions_test_data.exs` | **TEST DATA** | `../dev_seeds/scenarios/poll_suggestions_test.exs` | **MOVE + RENAME** | P2 |
| `cocktail_poll_test.exs` | **TEST DATA** | `../dev_seeds/scenarios/cocktail_poll_test.exs` | **MOVE + RENAME** | P2 |

**Notes**:
- P1 = High priority (pure organization, no semantic change)
- P2 = Medium priority (moving test data out of production)
- All reference data moves together for consistency
- Test data moves fix a category violation

### Development Seeds (priv/repo/dev_seeds/)

#### Core Entity Seeds

| Current File | Category | New Location | Action | Priority |
|-------------|----------|--------------|--------|----------|
| `users.exs` | Core Entity | `core/users.exs` | **MOVE** | P1 |
| `groups.exs` | Core Entity | `core/groups.exs` | **MOVE** | P1 |
| `events.exs` | Core Entity | `core/events.exs` | **MOVE** | P1 |

#### Feature-Specific Seeds - Polls

| Current File | Category | New Location | Action | Priority | Notes |
|-------------|----------|--------------|--------|----------|-------|
| `poll_seed.exs` | Poll Feature | `features/polls/poll_seed.exs` | **MOVE** | P1 | General poll creation |
| `diverse_polling_events.exs` | Poll Feature | `features/polls/date_movie_polls.exs` | **MOVE + RENAME** | P2 | Phase I specific |
| `enhanced_variety_polls.exs` | Poll Feature | `features/polls/variety_polls.exs` | **MOVE + RENAME** | P2 | Phase IV specific |

**Consolidation Opportunity**: Consider merging poll seeds in future, but keeping separate for now maintains clarity about which phase/feature each supports.

#### Feature-Specific Seeds - Ticketing

| Current File | Category | New Location | Action | Priority |
|-------------|----------|--------------|--------|----------|
| `extended_ticket_scenarios.exs` | Ticketing | `features/ticketing/ticket_scenarios.exs` | **MOVE + RENAME** | P1 |
| `ticketed_event_organizers.exs` | Ticketing | `features/ticketing/organizer_personas.exs` | **MOVE + RENAME** | P2 |
| `add_interest_to_ticketed_events.exs` | Ticketing | `features/ticketing/add_interest.exs` | **MOVE + RENAME** | P2 |

**Consolidation Opportunity**: Three closely related ticketing seeds could potentially be merged into one `ticketing_scenarios.exs` file in the future.

#### Feature-Specific Seeds - Groups

| Current File | Category | New Location | Action | Priority |
|-------------|----------|--------------|--------|----------|
| `diverse_privacy_groups.exs` | Groups | `features/groups/privacy_scenarios.exs` | **MOVE + RENAME** | P1 |

#### Feature-Specific Seeds - Activities

| Current File | Category | New Location | Action | Priority |
|-------------|----------|--------------|--------|----------|
| `activity_seed.exs` | Activities | `features/activities/activity_seed.exs` | **MOVE** | P1 |

#### Scenario Seeds

| Current File | Category | New Location | Action | Priority |
|-------------|----------|--------------|--------|----------|
| `ensure_key_organizers.exs` | Scenario | `scenarios/key_organizer_personas.exs` | **MOVE + RENAME** | P2 |

#### Support Files

| Current File | Category | New Location | Action | Priority |
|-------------|----------|--------------|--------|----------|
| `helpers.exs` | Support | `support/helpers.exs` | **MOVE** | P1 |
| `curated_data.exs` | Support | `support/curated_data.exs` | **MOVE** | P1 |
| `comprehensive_seed.exs` | Support | `support/comprehensive_seed.exs` | **MOVE** | P3 |

**Note**: `comprehensive_seed.exs` is an alternative seeding approach, low priority to move.

#### Orchestration Files (Root Level - DON'T MOVE)

| File | Category | Location | Action |
|------|----------|----------|--------|
| `runner.exs` | Orchestrator | **KEEP IN ROOT** | Update imports only |
| `README.md` | Documentation | **KEEP IN ROOT** | Update references |

#### Service Modules (Already Organized)

| File | Category | Location | Action |
|------|----------|----------|--------|
| `services/event_builder.ex` | Service | **NO CHANGE** | None |
| `services/event_types.ex` | Service | **NO CHANGE** | None |
| `services/image_service.ex` | Service | **NO CHANGE** | None |
| `services/validator.ex` | Service | **NO CHANGE** | None |
| `services/venue_service.ex` | Service | **NO CHANGE** | None |

Services are already well-organized in their own directory.

#### Fix Scripts (TO BE REMOVED)

| File | Issue | Recommendation | Action |
|------|-------|----------------|--------|
| `fix_venue_events.exs` | Band-aid fix | Incorporate into event creation validation | **REMOVE** in Phase 4 |
| `fix_virtual_events_with_venues.exs` | Band-aid fix | Add changeset validation | **REMOVE** in Phase 4 |

## Fix Scripts Analysis

### `fix_venue_events.exs`

**What it does**:
- Finds physical events (`is_virtual=false`) with `NULL venue_id`
- Creates a pool of venues (theaters, restaurants, general venues)
- Assigns venues to these events in a round-robin fashion

**Root cause**:
- Event creation logic doesn't always assign venues to physical events
- Validation allows physical events without venues

**Proper solution**:
1. Add changeset validation: `validate_required(:venue_id)` when `is_virtual == false`
2. Update event creation logic to ensure physical events get venues
3. Update event builder service to handle this automatically

**Implementation location**:
- `lib/eventasaurus_app/events/event.ex` - Add validation
- `priv/repo/dev_seeds/services/event_builder.ex` - Ensure venue assignment
- `priv/repo/dev_seeds/core/events.exs` - Check for validation before creation

### `fix_virtual_events_with_venues.exs`

**What it does**:
- Finds events marked as virtual (`is_virtual=true`) with `venue_id` assigned
- Sets them to `is_virtual=false` and clears `virtual_venue_url`
- Contradictory state: virtual events shouldn't have physical venues

**Root cause**:
- Event update logic allows setting both `is_virtual=true` and `venue_id`
- Missing mutual exclusivity validation

**Proper solution**:
1. Add changeset validation: When `is_virtual == true`, `venue_id` must be `nil`
2. Add changeset validation: When `venue_id` is present, `is_virtual` must be `false`
3. Clear opposite field when setting one (if virtual, clear venue_id; if physical, clear virtual_url)

**Implementation location**:
- `lib/eventasaurus_app/events/event.ex` - Add mutual exclusivity validation
- Consider custom validation function: `validate_venue_consistency/1`

## Migration Priority Groups

### Priority 1 (P1) - Pure Organization
**Goal**: Improve organization without semantic changes
**Risk**: Low (just moving files, updating imports)
**Files**: 14 files

Production:
- All 6 reference data files → `reference_data/`

Development:
- 3 core entity files → `core/`
- Poll, activity, group feature files → `features/`
- Helper files → `support/`

### Priority 2 (P2) - Organization + Renaming
**Goal**: Improve naming clarity while organizing
**Risk**: Low-Medium (renaming + moving)
**Files**: 8 files

- Test data files (2) from production → dev scenarios
- Poll feature renames (2) for clarity
- Ticketing renames (2) for consistency
- Scenario renames (1) for clarity
- Group feature rename (1) for consistency

### Priority 3 (P3) - Low Priority / Future
**Goal**: Nice-to-have improvements
**Risk**: Low (optional)
**Files**: 1 file

- `comprehensive_seed.exs` (alternative approach, rarely used)

## File Rename Mappings

| Old Name | New Name | Reason |
|----------|----------|--------|
| `poll_suggestions_test_data.exs` | `poll_suggestions_test.exs` | Consistency: all test scenarios use `_test` suffix |
| `cocktail_poll_test.exs` | `cocktail_poll_test.exs` | No change (already has good name) |
| `diverse_polling_events.exs` | `date_movie_polls.exs` | Clarity: describes what it actually creates |
| `enhanced_variety_polls.exs` | `variety_polls.exs` | Brevity: "enhanced" is redundant |
| `extended_ticket_scenarios.exs` | `ticket_scenarios.exs` | Brevity: "extended" is redundant |
| `ticketed_event_organizers.exs` | `organizer_personas.exs` | Brevity: context clear from directory |
| `add_interest_to_ticketed_events.exs` | `add_interest.exs` | Brevity: context clear from directory |
| `ensure_key_organizers.exs` | `key_organizer_personas.exs` | Clarity: better describes purpose |
| `diverse_privacy_groups.exs` | `privacy_scenarios.exs` | Consistency: matches other scenario naming |

## Import Path Updates Required

### `priv/repo/seeds.exs` (Main Production Orchestrator)

**Current**:
```elixir
Code.eval_file("priv/repo/seeds/locations.exs")
Code.eval_file("priv/repo/seeds/categories.exs")
Code.eval_file("priv/repo/seeds/sources.exs")
Code.eval_file("priv/repo/seeds/discovery_cities.exs")
```

**Updated**:
```elixir
Code.eval_file("priv/repo/seeds/reference_data/locations.exs")
Code.eval_file("priv/repo/seeds/reference_data/categories.exs")
Code.eval_file("priv/repo/seeds/reference_data/sources.exs")
Code.eval_file("priv/repo/seeds/reference_data/discovery_cities.exs")
```

**Test** with: `mix run priv/repo/seeds.exs`

### `priv/repo/dev_seeds/runner.exs` (Main Dev Orchestrator)

**Current**:
```elixir
Code.require_file("helpers.exs", __DIR__)
Code.require_file("users.exs", __DIR__)
Code.require_file("groups.exs", __DIR__)
Code.require_file("events.exs", __DIR__)
Code.require_file("ensure_key_organizers.exs", __DIR__)
Code.require_file("ticketed_event_organizers.exs", __DIR__)
Code.require_file("add_interest_to_ticketed_events.exs", __DIR__)
Code.require_file("extended_ticket_scenarios.exs", __DIR__)
Code.require_file("diverse_polling_events.exs", __DIR__)
Code.require_file("poll_seed.exs", __DIR__)
Code.require_file("activity_seed.exs", __DIR__)
Code.require_file("enhanced_variety_polls.exs", __DIR__)
```

**Updated**:
```elixir
# Load support first
Code.require_file("support/helpers.exs", __DIR__)

# Load core entities
Code.require_file("core/users.exs", __DIR__)
Code.require_file("core/groups.exs", __DIR__)
Code.require_file("core/events.exs", __DIR__)

# Load scenarios
Code.require_file("scenarios/key_organizer_personas.exs", __DIR__)

# Load ticketing features
Code.require_file("features/ticketing/organizer_personas.exs", __DIR__)
Code.require_file("features/ticketing/add_interest.exs", __DIR__)
Code.require_file("features/ticketing/ticket_scenarios.exs", __DIR__)

# Load polling features
Code.require_file("features/polls/date_movie_polls.exs", __DIR__)
Code.require_file("features/polls/poll_seed.exs", __DIR__)
Code.require_file("features/polls/variety_polls.exs", __DIR__)

# Load activities
Code.require_file("features/activities/activity_seed.exs", __DIR__)
```

**Test** with: `mix seed.dev`

## Module Name Updates

Some seed files define modules that will need updates:

| File | Old Module | New Module (if needed) |
|------|-----------|------------------------|
| `fix_venue_events.exs` | `FixVenueEvents` | **REMOVE** (Phase 4) |
| `fix_virtual_events_with_venues.exs` | `FixVirtualEventsWithVenues` | **REMOVE** (Phase 4) |
| `diverse_polling_events.exs` | `DiversePollingEvents` | `DateMoviePolls` (if renamed) |
| `enhanced_variety_polls.exs` | `EnhancedVarietyPolls` | `VarietyPolls` (if renamed) |

**Note**: Most seed files don't define modules, so renaming is safe.

## Testing Strategy for Each Migration

### Before Each File Move

1. **Document current behavior**:
   ```bash
   # Record what the seed creates
   mix run priv/repo/dev_seeds/[file].exs
   # Take screenshot or database snapshot
   ```

2. **Check dependencies**:
   ```bash
   # Search for references to this file
   grep -r "[filename]" priv/repo/
   ```

### After Each File Move

1. **Update imports** in calling files (seeds.exs or runner.exs)

2. **Test the seed runs**:
   ```bash
   # For production seeds
   mix run priv/repo/seeds.exs

   # For dev seeds
   mix seed.dev
   ```

3. **Verify data creation**:
   ```bash
   # Check database records created
   mix ecto.query -r EventasaurusApp.Repo "SELECT COUNT(*) FROM [table]"
   ```

4. **Test idempotency**:
   ```bash
   # Run twice, should not error
   mix run priv/repo/seeds.exs
   mix run priv/repo/seeds.exs
   ```

### Full Regression Test After All Moves

```bash
# Clean slate
mix ecto.reset

# Should complete without errors
# Check output for all success messages

# Verify comprehensive data
mix ecto.query -r EventasaurusApp.Repo "
  SELECT
    (SELECT COUNT(*) FROM users) as users,
    (SELECT COUNT(*) FROM groups) as groups,
    (SELECT COUNT(*) FROM events) as events,
    (SELECT COUNT(*) FROM polls) as polls,
    (SELECT COUNT(*) FROM venues) as venues
"
```

## Backward Compatibility Strategy

### Option 1: No Backward Compatibility (Recommended)
- Clean break, better long-term
- Update all imports in one commit
- Phase 3 is single atomic change
- **Advantage**: Simpler, clearer
- **Risk**: Developers need to pull latest code

### Option 2: Symbolic Links (Not Recommended)
- Create symlinks from old → new locations
- Maintain for 1-2 weeks
- **Advantage**: Gradual transition
- **Disadvantage**: Can mask issues, Git complexity

### Option 3: Deprecation Warnings (Overkill)
- Keep old files with warning messages
- **Advantage**: Very safe transition
- **Disadvantage**: Complexity not warranted for internal tool

**Recommendation**: Option 1 - Clean break with communication to team.

## Consolidation Opportunities (Future Phases)

### Polls Seeds (3 files → 1 file?)

**Current**:
- `poll_seed.exs` - General poll creation
- `date_movie_polls.exs` (formerly diverse_polling_events) - Phase I specific
- `variety_polls.exs` (formerly enhanced_variety_polls) - Phase IV specific

**Potential consolidation**:
```elixir
# features/polls/comprehensive_poll_scenarios.exs
defmodule DevSeeds.Features.Polls.ComprehensiveScenarios do
  def general_polls(events, users), do: ...
  def date_movie_polls(events, users), do: ...
  def variety_polls(events, users), do: ...
end
```

**Recommendation**: Keep separate for now, consider consolidation in Phase 5 (future).

### Ticketing Seeds (3 files → 1 file?)

**Current**:
- `ticket_scenarios.exs` - Extended scenarios
- `organizer_personas.exs` - Organizer creation
- `add_interest.exs` - Add interest to events

**Potential consolidation**:
```elixir
# features/ticketing/ticketing_scenarios.exs
defmodule DevSeeds.Features.Ticketing.Scenarios do
  def create_organizers(), do: ...
  def create_scenarios(users), do: ...
  def add_interest(events, users), do: ...
end
```

**Recommendation**: Consider in Phase 5, after seeing usage patterns.

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Broken imports | Medium | High | Test after each move, update immediately |
| Database issues | Low | Medium | Test with `mix ecto.reset` |
| Module conflicts | Low | Low | Few modules defined in seeds |
| Lost git history | Medium | Low | Use `git mv` commands |
| Team coordination | Medium | Medium | Communication, single PR |

## Communication Plan

### Before Phase 3

1. **Team announcement**: "Seed reorganization PR incoming"
2. **Timeline**: "Will merge on [date]"
3. **Impact**: "Will need to pull latest after merge, may affect open branches"

### During Phase 3

1. **Single PR**: All moves in one atomic PR
2. **Clear description**: Link to this plan and issue #2239
3. **Testing checklist**: Mark off each test in PR description

### After Phase 3

1. **Announcement**: "Seed reorganization complete, please pull latest"
2. **Documentation**: Point to new READMEs
3. **Support**: Answer questions about new structure

## Success Criteria

Phase 3 is successful when:

- [ ] All files moved to new locations
- [ ] All imports updated and working
- [ ] `mix run priv/repo/seeds.exs` succeeds
- [ ] `mix seed.dev` succeeds
- [ ] `mix ecto.reset` completes without errors
- [ ] All tests pass
- [ ] Documentation updated (README references)
- [ ] Git history preserved (`git log --follow` works)
- [ ] No broken references in codebase
- [ ] Team successfully uses new structure

## Next Steps

1. **Complete Phase 2** ✅
   - [x] Create directory structure
   - [x] Categorize all files
   - [x] Analyze fix scripts
   - [x] Create migration plan (this document)

2. **Execute Phase 3** (Next)
   - [ ] Implement fix script logic in proper locations (see recommendations below)
   - [ ] Test fix logic works in event creation
   - [ ] Move Priority 1 files (pure organization)
   - [ ] Update imports for P1 files
   - [ ] Test P1 migrations
   - [ ] Move Priority 2 files (renames + moves)
   - [ ] Update imports for P2 files
   - [ ] Test P2 migrations
   - [ ] Full regression test
   - [ ] Update documentation references
   - [ ] Create PR

3. **Execute Phase 4** (After Phase 3)
   - [ ] Remove fix scripts
   - [ ] Final validation
   - [ ] Update best practices guide

## Fix Script Removal Plan (Phase 4 Preview)

### Implementation Tasks

1. **Add Event Validation** (`lib/eventasaurus_app/events/event.ex`):
   ```elixir
   # Add to changeset/2
   |> validate_venue_consistency()

   defp validate_venue_consistency(changeset) do
     is_virtual = get_field(changeset, :is_virtual)
     venue_id = get_field(changeset, :venue_id)

     cond do
       is_virtual == true && venue_id != nil ->
         add_error(changeset, :venue_id, "virtual events cannot have a physical venue")

       is_virtual == false && venue_id == nil ->
         add_error(changeset, :venue_id, "physical events must have a venue")

       true ->
         changeset
     end
   end
   ```

2. **Update Event Builder Service** (`dev_seeds/services/event_builder.ex`):
   - Ensure physical events always get venue_id
   - Validate before insert

3. **Update Event Seeds** (`dev_seeds/core/events.exs`):
   - Add validation check
   - Handle errors gracefully

4. **Test Validation**:
   ```bash
   # Try to create invalid events, should fail
   # Should prevent the issues fix scripts were solving
   ```

5. **Remove Fix Scripts**:
   - Delete `fix_venue_events.exs`
   - Delete `fix_virtual_events_with_venues.exs`

---

**Document Status**: ✅ Phase 2 Complete
**Next Action**: Begin Phase 3 execution
**Last Updated**: 2025
