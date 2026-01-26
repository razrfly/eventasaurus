# Development Seeds

## Purpose

This directory contains **development and testing seed data** for creating rich, realistic test scenarios. These seeds are designed for development and testing environments only and should **never** run in production.

## Quick Start

```bash
# Seed development database with defaults (50 users, 15 groups, 100 events)
mix seed.dev

# Seed with custom amounts
mix seed.dev --users 100 --events 200

# Add more data without cleaning first
mix seed.dev --append

# Seed only specific entities
mix seed.dev --only users,events,polls

# Clean development data
mix seed.clean
mix seed.clean --only events  # Clean specific types
```

## Mix Tasks

### `mix seed.dev`

**Purpose**: Seeds development database with comprehensive, realistic test data

**Options**:
- `--append` - Don't clean existing data before seeding (default: false)
- `--users N` - Number of users to create (default: 50)
- `--groups N` - Number of groups to create (default: 15)
- `--events N` - Number of events to create (default: 100)
- `--polls N` - Number of polls to create (default: 40)
- `--only` - Comma-separated list of entities to seed
- `--quiet` - Suppress output

**Examples**:
```bash
# Full reset and seed with defaults
mix seed.dev

# Add data without resetting
mix seed.dev --append --users 50

# Large dataset for performance testing
mix seed.dev --users 200 --groups 30 --events 500

# Seed specific entities only
mix seed.dev --only users,events

# Quick re-seed during development
mix seed.dev --quiet
```

**What It Does**:
1. Optionally cleans existing development data
2. Runs production seeds (`priv/repo/seeds.exs`) for essential reference data
3. Creates test users with Clerk authentication
4. Creates persona users (admin, demo, organizer, participant, movie_buff, foodie_friend)
5. Creates groups with various privacy settings
6. Creates events (past, upcoming, future) with realistic data
7. Creates polls with options and votes
8. Creates activities for completed events
9. Creates ticketing scenarios
10. Validates data consistency

**Execution Time**: 30-90 seconds depending on quantities

### `mix seed.clean`

**Purpose**: Cleans specific types of development data

**Options**:
- `--only` - Comma-separated list of entities to clean
- `--force` - Don't ask for confirmation

**Available Entity Types**:
- `users` - All users except system users (holden@gmail.com)
- `events` - All events and related data (cascades to polls, activities, participants)
- `groups` - All groups and memberships
- `polls` - All polls, options, and votes
- `activities` - All event activities
- `venues` - All venues

**Examples**:
```bash
# Clean everything (with confirmation)
mix seed.clean

# Clean specific types
mix seed.clean --only events,polls

# Clean without confirmation (dangerous!)
mix seed.clean --force

# Clean just polls to re-seed poll data
mix seed.clean --only polls
```

**Note**: Cleaning is **permanent** and cannot be undone. Always have a database backup if needed.

## Seed Files Overview

### Core Entity Seeds

These create the foundational data that other seeds depend on.

#### `users.exs` (via `DevSeeds.Users` module)
- **Purpose**: Creates test users with realistic profiles
- **Features**:
  - Clerk authentication for test users
  - Persona users for specific testing scenarios
  - Configurable quantity via `--users` flag
- **Default**: 50 users + 4 personas
- **Personas Created**:
  - `admin@example.com` - Admin persona
  - `demo@example.com` - Demo account
  - `organizer@example.com` - Event organizer
  - `participant@example.com` - Event participant
  - `movie_buff@example.com` - Creates movie-related events
  - `foodie_friend@example.com` - Creates food-related events
- **Dependencies**: None
- **Password**: All test accounts use `testpass123`

#### `groups.exs` (via `DevSeeds.Groups` module)
- **Purpose**: Creates groups with members and various privacy settings
- **Features**:
  - Regular groups (5-20 members each)
  - Themed groups (The Dinner Club, Movie Nights, Tech Talks, etc.)
  - Various privacy levels (public, private, secret)
- **Default**: 15 groups + themed groups
- **Dependencies**: `users.exs`

#### `events.exs` (via `DevSeeds.Events` module)
- **Purpose**: Creates events with various states and times
- **Features**:
  - Past events (confirmed or cancelled)
  - Upcoming events (polling or confirmed)
  - Future events (draft state)
  - Some events at maximum capacity
  - Realistic cover images from default image collection
- **Default**: ~100 events (split across past/upcoming/future)
- **Dependencies**: `users.exs`, `groups.exs`
- **Uses**: Event service modules for complex event creation

### Feature-Specific Seeds

These add feature-specific data and scenarios.

#### `poll_seed.exs`
- **Purpose**: Creates polls with options and votes for events
- **Features**:
  - 1-3 polls per eligible event (polling or confirmed status)
  - 3-8 options per poll
  - Realistic voting patterns (30-70% participation)
  - Various voting systems (ranked, star rating, binary)
- **Dependencies**: `events.exs`, `users.exs`
- **Called By**: `runner.exs`

#### `diverse_polling_events.exs` (Phase I)
- **Purpose**: Creates specific polling scenarios for date selection and movie rating
- **Features**:
  - Date selection polls (binary voting)
  - Movie star rating polls
  - Realistic user engagement patterns
- **Dependencies**: `events.exs`, `users.exs`
- **Called By**: `runner.exs`

#### `enhanced_variety_polls.exs` (Phase IV)
- **Purpose**: Creates enhanced variety of poll types and scenarios
- **Features**:
  - Multiple poll types (date, location, activity, food, movie)
  - Complex voting patterns
  - Edge cases for testing
- **Dependencies**: `events.exs`, `users.exs`
- **Called By**: `runner.exs`

#### `activity_seed.exs`
- **Purpose**: Creates activities for completed events
- **Features**:
  - 1-5 activities per completed event
  - Realistic activity types (photos, reviews, check-ins)
  - Timestamps aligned with event times
- **Dependencies**: `events.exs`, `users.exs`
- **Called By**: `runner.exs`

#### `extended_ticket_scenarios.exs` (Phase 1 - Issue #2233)
- **Purpose**: Creates extended ticketing scenarios for testing
- **Features**:
  - Free and paid ticketed events
  - Various ticket price points
  - Sold out scenarios
  - Early bird pricing
- **Dependencies**: `events.exs`, `users.exs`
- **Called By**: `runner.exs`

#### `ticketed_event_organizers.exs`
- **Purpose**: Creates organizer personas specifically for ticketed events
- **Features**:
  - Professional event organizers
  - Ticketing-specific event scenarios
- **Dependencies**: `users.exs`
- **Called By**: `runner.exs`

#### `add_interest_to_ticketed_events.exs`
- **Purpose**: Adds interested participants to ticketed events
- **Features**:
  - Realistic interest patterns
  - Waitlist scenarios
- **Dependencies**: `events.exs`, `users.exs`, `ticketed_event_organizers.exs`
- **Called By**: `runner.exs`

#### `ensure_key_organizers.exs`
- **Purpose**: Ensures movie_buff and foodie_friend personas have appropriate events
- **Features**:
  - Movie-related events for movie_buff
  - Food-related events for foodie_friend
- **Dependencies**: `users.exs`, `events.exs`
- **Called By**: `runner.exs`

#### `diverse_privacy_groups.exs`
- **Purpose**: Creates groups with various privacy settings for testing
- **Features**:
  - Public, private, and secret groups
  - Different membership approval workflows
- **Dependencies**: `users.exs`
- **Called By**: `runner.exs` (if exists)

### Service Modules (`services/`)

Reusable service modules for complex seed data creation.

#### `event_builder.ex`
- **Purpose**: Complex event creation logic with realistic attributes
- **Features**:
  - Event type selection
  - Venue assignment
  - Capacity management
  - Status workflows

#### `event_types.ex`
- **Purpose**: Defines event type factories and configurations
- **Features**:
  - Event type definitions (concert, sports, theater, etc.)
  - Type-specific default attributes

#### `image_service.ex`
- **Purpose**: Image handling for seeded data
- **Features**:
  - Default image selection
  - Image URL generation
  - Fallback images

#### `validator.ex`
- **Purpose**: Validation helpers for seed data
- **Features**:
  - Data consistency checks
  - Relationship validation

#### `venue_service.ex`
- **Purpose**: Venue creation and management
- **Features**:
  - Realistic venue data
  - Coordinate generation
  - Venue type assignment

### Support Files

#### `helpers.exs` (via `DevSeeds.Helpers` module)
- **Purpose**: Shared helper functions for seeding
- **Features**:
  - Colorful logging (`log`, `success`, `error`, `section`)
  - User creation with Clerk auth (`get_or_create_user`, `create_users`)
  - Batch user creation for performance
  - Random image selection (`get_random_image_attrs`)
  - Event state helpers
  - Participant management
  - Poll creation with votes
- **Used By**: All other seed files
- **Key Functions**:
  - `create_users(count, attrs_fn)` - Batch create users with auth
  - `get_or_create_user(attrs)` - Idempotent user creation
  - `create_events_with_states(users, counts)` - Create events in various states
  - `add_participants_to_events(events, users, rate)` - Add event participants
  - `create_polls_for_events(events, users)` - Create polls with votes

#### `curated_data.exs`
- **Purpose**: Hand-picked realistic test data
- **Features**:
  - Realistic event names
  - Curated descriptions
  - Real-world scenarios

#### `runner.exs`
- **Purpose**: Main orchestration script for development seeding
- **Features**:
  - Configuration management from environment
  - Execution order management
  - Progress tracking
  - Consistency validation
  - Summary output with test account credentials
- **Flow**:
  1. Load configuration (from `DEV_SEED_CONFIG` env or defaults)
  2. Optionally clean database
  3. Run production seeds (`priv/repo/seeds.exs`)
  4. Create users (base + personas)
  5. Create groups (regular + themed)
  6. Create events (various states)
  7. Run feature-specific seeds (polls, tickets, activities)
  8. Validate consistency
  9. Display summary

#### `comprehensive_seed.exs`
- **Purpose**: Alternative comprehensive seeding approach
- **Features**: Monolithic seeding script (alternative to modular approach)
- **Status**: May be deprecated in favor of modular approach

### Legacy Files ⚠️

~~These files have been removed in favor of proper changeset validation:~~

#### ~~`fix_venue_events.exs`~~ (REMOVED in Phase 4)
- **Previous Purpose**: Band-aid fix for physical events without venues
- **Resolution**: Added validation to Event changeset requiring `venue_id` for physical events (`is_virtual=false`)
- **Status**: ✅ Removed - validation now prevents this issue at creation time

#### ~~`fix_virtual_events_with_venues.exs`~~ (REMOVED in Phase 4)
- **Previous Purpose**: Fixed virtual events that incorrectly had venues
- **Resolution**: Enhanced Event changeset validation to prevent `venue_id` for virtual events (`is_virtual=true`)
- **Status**: ✅ Removed - validation now prevents this issue at creation time

**Note**: Venue consistency is now enforced in `lib/eventasaurus_app/events/event.ex` via `validate_virtual_event_venue/1` function.

## Seeding Flow & Dependencies

### Execution Order

When `mix seed.dev` runs, seeds execute in this order:

```
1. Clean Database (if --append not used)
   ↓
2. Production Seeds (priv/repo/seeds.exs)
   - Essential users (Holden)
   - Reference data (locations, categories, sources)
   ↓
3. Dev Seed Runner (runner.exs)
   ↓
4. Core Entities
   ├─ Users (base + personas)
   ├─ Groups (regular + themed)
   └─ Events (past + upcoming + future)
   ↓
5. Feature Seeds (order matters!)
   ├─ ensure_key_organizers (depends on: users, events)
   ├─ ticketed_event_organizers (depends on: users)
   ├─ add_interest_to_ticketed_events (depends on: events, users)
   ├─ extended_ticket_scenarios (depends on: users)
   ├─ diverse_polling_events (depends on: events, users)
   ├─ poll_seed (depends on: events, users)
   ├─ activity_seed (depends on: events, users)
   └─ enhanced_variety_polls (depends on: events, users)
   ↓
6. Validation
   - Check events with polls have participants
   - Report any inconsistencies
   ↓
7. Summary
   - Display counts and test account credentials
```

### Dependency Graph

```
Production Seeds (locations, categories, sources, etc.)
    ↓
users.exs
    ↓
    ├─→ groups.exs ────┐
    │                   ↓
    └─→ events.exs ←───┘
            ↓
            ├─→ ensure_key_organizers.exs
            ├─→ ticketed_event_organizers.exs
            ├─→ extended_ticket_scenarios.exs
            ├─→ poll_seed.exs
            ├─→ diverse_polling_events.exs
            ├─→ enhanced_variety_polls.exs
            ├─→ activity_seed.exs
            └─→ add_interest_to_ticketed_events.exs
```

**Critical Dependencies**:
- Everything depends on `users.exs` (need users to assign as creators/participants)
- `events.exs` depends on `users.exs` and `groups.exs`
- All feature seeds depend on `events.exs` and `users.exs`
- Production seeds must run before dev seeds (provides reference data)

## Adding New Development Seeds

### For New Feature Scenarios

**Step 1**: Create the seed file in `dev_seeds/`

```elixir
# dev_seeds/my_feature_seed.exs

alias EventasaurusApp.Repo
alias EventasaurusApp.Events.Event
alias DevSeeds.Helpers
import Ecto.Query

# Get all events that need this feature data
events = Repo.all(from e in Event, where: e.status == :confirmed)

Enum.each(events, fn event ->
  # Create feature-specific data for this event
  # Use helpers for logging
  Helpers.log("Creating feature data for event: #{event.title}")

  # Your logic here
end)

Helpers.success("Created feature data for #{length(events)} events")
```

**Step 2**: Add to `runner.exs`

```elixir
# In runner.exs, add after similar seeds
Helpers.section("Creating My Feature Data")
Code.require_file("my_feature_seed.exs", __DIR__)
```

**Step 3**: Add cleanup to `seed.clean.ex` (if needed)

```elixir
defp clean_entity("my_feature") do
  IO.write("Cleaning my feature data... ")
  {count, _} = Repo.delete_all(EventasaurusApp.MyContext.MySchema)
  IO.puts("✓ Deleted #{count} records")
end
```

### For New Service Modules

**Step 1**: Create service in `services/`

```elixir
# dev_seeds/services/my_service.ex

defmodule DevSeeds.Services.MyService do
  @moduledoc """
  Service for creating complex my_feature data.
  """

  alias EventasaurusApp.Repo

  def create_feature_data(event, options \\ []) do
    # Complex logic here
  end
end
```

**Step 2**: Use in seed files

```elixir
# Load the service
Code.require_file("services/my_service.ex", __DIR__)
alias DevSeeds.Services.MyService

# Use it
MyService.create_feature_data(event)
```

## Best Practices

### DO ✅

- **Use Faker for realistic data** - Names, emails, addresses, dates
- **Use helpers for logging** - `Helpers.log`, `Helpers.success`, `Helpers.error`
- **Make seeds rerunnable** - Check if data exists before creating
- **Add progress indicators** - For long-running operations
- **Use factory traits** - Leverage ExMachina factories in test/support/factory.ex
- **Respect dependencies** - Ensure required data exists before creating dependent data
- **Use realistic quantities** - Balance between comprehensive testing and speed
- **Add validation** - Check data consistency after seeding
- **Document complex logic** - Add comments explaining "why" not just "what"

### DON'T ❌

- **Don't use production data** - Keep dev seeds separate from production
- **Don't create slow seeds** - Aim for <2 minutes total seed time
- **Don't hardcode IDs** - Use associations and references
- **Don't skip cleanup** - Add cleanup logic to `seed.clean.ex`
- **Don't ignore errors** - Handle and log errors gracefully
- **Don't create duplicate personas** - Check if persona exists first
- **Don't forget --append mode** - Test that seeds work without cleaning

## Testing Your Seeds

### Basic Testing

```bash
# Clean and reseed
mix ecto.reset

# Test append mode
mix seed.dev --append

# Test selective seeding
mix seed.dev --only users,events

# Test custom quantities
mix seed.dev --users 10 --events 20
```

### Validation

```bash
# Check user count
mix ecto.query -r EventasaurusApp.Repo "SELECT COUNT(*) FROM users"

# Check events with polls
mix ecto.query -r EventasaurusApp.Repo "SELECT COUNT(*) FROM events e JOIN polls p ON e.id = p.event_id"

# Check for orphaned records
mix ecto.query -r EventasaurusApp.Repo "SELECT * FROM events WHERE user_id NOT IN (SELECT id FROM users)"
```

### Performance Testing

```bash
# Time the seeding
time mix seed.dev

# Profile memory usage
mix profile.eprof priv/repo/dev_seeds/runner.exs

# Large dataset test
mix seed.dev --users 500 --events 1000
```

## Common Issues & Solutions

### Seeding is Slow

**Problem**: `mix seed.dev` takes >2 minutes

**Solutions**:
- Reduce default quantities in runner.exs
- Use `Repo.insert_all` for bulk inserts instead of individual `insert!`
- Disable unnecessary callbacks during seeding
- Profile with `mix profile.eprof` to find bottlenecks

### Consistency Validation Fails

**Problem**: "Events with polls but no participants" error

**Solution**:
- Ensure `add_participants_to_events` runs before poll creation
- Check that participant creation isn't failing silently
- Review seed execution order in runner.exs

### Authentication Creation Fails

**Problem**: "Could not create auth for email" errors

**Solutions**:
- Verify Clerk keys are set correctly in `.env`
- Check Clerk dashboard settings
- Ensure test mode is enabled for dev environment
- Verify API keys have correct permissions

### Seeds Fail on Fresh Database

**Problem**: Reference constraint violations

**Solution**:
- Ensure production seeds run first (`priv/repo/seeds.exs`)
- Check that `runner.exs` calls production seeds
- Verify migrations are up to date: `mix ecto.migrate`

## Environment Variables

### Required (for full functionality)

- `CLERK_SECRET_KEY` - For creating authenticated test users
- `CLERK_PUBLISHABLE_KEY` - Clerk frontend key

### Optional

- `DEV_SEED_CONFIG` - JSON config for runner.exs (usually set by Mix task)

### Test Accounts

All development seeds create these test accounts (password: `testpass123`):

- `holden@gmail.com` - Personal account (from production seeds)
- `admin@example.com` - Admin persona
- `demo@example.com` - Demo account
- `organizer@example.com` - Event organizer
- `participant@example.com` - Event participant
- `movie_buff@example.com` - Movie event organizer
- `foodie_friend@example.com` - Food event organizer

## Documentation

### Essential Guides

- **📘 [Best Practices Guide](BEST_PRACTICES.md)** - **START HERE** - Comprehensive guide for adding new seeds
  - Quick start template
  - Venue handling patterns (required for Phase 4 compliance)
  - Service usage and common patterns
  - Testing and troubleshooting
  - Anti-patterns to avoid

### Mix Task Reference

- **[`mix seed.dev`](../../lib/mix/tasks/seed.dev.ex)** - Complete module documentation with:
  - All options and flags
  - Common workflows
  - Event distribution
  - Seeding order
  - Troubleshooting guide

- **[`mix seed.clean`](../../lib/mix/tasks/seed.clean.ex)** - Complete module documentation with:
  - Entity types and cleaning order
  - Safety mechanisms
  - Common workflows
  - Troubleshooting guide

### Phase 4 Changes (Validation Enhancement)

- **[Phase 4 Summary](../PHASE_4_SUMMARY.md)** - What changed in Phase 4:
  - Venue validation implementation
  - Fix scripts removal
  - Seed script updates
  - Before/after comparison

- **[Phase 4 Audit Report](../PHASE_4_AUDIT_REPORT.md)** - Validation proof and statistics:
  - 4 validation tests (all passing)
  - Database statistics (100% venue consistency)
  - Evidence of success
  - Risk assessment

### Other Documentation

- **Production Seeds**: See `priv/repo/seeds/README.md`
- **Factory Definitions**: See `test/support/factory.ex`
- **Reorganization Plan**: See [Issue #2239](https://github.com/razrfly/eventasaurus/issues/2239)

## Completed Improvements ✅

See [Issue #2239](https://github.com/razrfly/eventasaurus/issues/2239) for details on completed reorganization:

- ✅ **Phase 1-2**: Planning and analysis (COMPLETE)
- ✅ **Phase 3**: Organized seeds into subdirectories (core/, features/, scenarios/, support/) (COMPLETE)
- ✅ **Phase 3.5**: Fixed all Code.require_file dependencies (COMPLETE)
- ✅ **Phase 4**: Removed fix scripts, added proper changeset validation (COMPLETE)

### Potential Future Improvements

- Consolidate similar seeds (multiple poll seeds) - Optional Phase 5
- Add more inline documentation
- Create visual dependency diagram
- Improve selective seeding (--only flag)

## Questions?

**Where should I add my seed?**
- Test scenario? → `dev_seeds/scenarios/`
- Core entity? → `dev_seeds/core/`
- Feature-specific? → `dev_seeds/features/<feature_name>/`
- Shared logic? → `dev_seeds/services/` or `dev_seeds/support/` (for helpers)

**Should I make a separate seed file?**
- Yes, if it's >100 lines or a distinct feature scenario
- Yes, if it might be run independently
- No, if it's just a few lines - add to existing seed
- No, if it's helper logic - add to helpers.exs or services/

**How do I test Clerk auth locally?**
1. Set `CLERK_SECRET_KEY` and `CLERK_PUBLISHABLE_KEY` in `.env`
2. Run `mix seed.dev`
3. Seeds will create users with authentication
4. Login with test accounts to verify

Need more help? Check the team wiki or ask in #engineering.
