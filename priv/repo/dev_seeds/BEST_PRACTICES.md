# Development Seeding Best Practices Guide

**Version**: 1.0
**Last Updated**: 2025-11-14
**Audience**: Developers, AI Agents, Future Contributors

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [When to Add Seeds](#when-to-add-seeds)
3. [Naming Conventions](#naming-conventions)
4. [Venue Handling (Critical)](#venue-handling-critical)
5. [Using Services and Helpers](#using-services-and-helpers)
6. [Testing Seed Scripts](#testing-seed-scripts)
7. [Common Patterns](#common-patterns)
8. [Anti-Patterns to Avoid](#anti-patterns-to-avoid)
9. [Troubleshooting](#troubleshooting)

---

## Quick Start

### Adding a New Development Seed

```bash
# 1. Create seed file in appropriate directory
touch priv/repo/dev_seeds/features/my_feature/my_feature_seed.exs

# 2. Follow the template structure
# 3. Test your seed
mix seed.dev --only my_feature

# 4. Test full seeding workflow
mix seed.clean && mix seed.dev
```

### Template Structure

```elixir
defmodule DevSeeds.MyFeature do
  @moduledoc """
  Seeds data for [feature description].

  Creates:
  - [List what this seed creates]
  - [Be specific about entities and quantities]

  Dependencies:
  - Requires [users/groups/events] to exist
  - Called by [runner.exs or other seeds]
  """

  alias EventasaurusApp.{Repo, MyContext}
  import Ecto.Query

  # Load helpers if needed
  Code.require_file("../../support/helpers.exs", __DIR__)
  alias DevSeeds.Helpers

  def seed_my_feature do
    Helpers.section("Seeding My Feature")

    # Your seeding logic here

    Helpers.success("My feature seeded successfully")
  end
end

# Allow direct execution
if __ENV__.file == Path.absname(__ENV__.file) do
  DevSeeds.MyFeature.seed_my_feature()
end
```

---

## When to Add Seeds

### Production Seeds (`priv/repo/seeds/`)

**Add production seeds when:**
- Data is **reference data** (categories, countries, cities)
- Data **must exist** in all environments (dev, staging, production)
- Data is **rarely changed** once created
- Data is **not test-specific**

**Examples:**
- Event categories (Concerts, Sports, Festivals)
- Countries and cities
- Discovery source configurations
- System-level configuration data

**Important:** Never add test-specific scenarios to production seeds.

---

### Development Seeds (`priv/repo/dev_seeds/`)

**Add development seeds when:**
- Data is for **testing and development only**
- Data needs **realistic scenarios** for feature testing
- Data includes **test user personas**
- Data is **regenerated frequently**

**Directory Structure:**

```
dev_seeds/
├── core/              # Core entities (users, groups, events)
├── features/          # Feature-specific seeds
│   ├── polls/
│   ├── ticketing/
│   ├── activities/
│   └── groups/
├── scenarios/         # Test scenarios and edge cases
├── services/          # Service modules (builders, validators)
└── support/           # Helpers and utilities
```

**Where to Add Your Seed:**

| Type | Directory | Example |
|------|-----------|---------|
| Core entity seed | `core/` | `users.exs`, `groups.exs`, `events.exs` |
| Feature-specific | `features/{feature}/` | `features/polls/poll_scenarios.exs` |
| Test scenario | `scenarios/` | `scenarios/cocktail_poll_test.exs` |
| Service module | `services/` | `services/venue_service.ex` |
| Helper utility | `support/` | `support/helpers.exs` |

---

## Naming Conventions

### File Naming Patterns

#### Core Entity Seeds
- **Pattern**: `{entity_plural}.exs`
- **Examples**: `users.exs`, `groups.exs`, `events.exs`
- **Rule**: Plural noun representing the entity

#### Feature Seeds
- **Pattern**: `{feature_name}_seed.exs` or `{feature_name}_scenarios.exs`
- **Examples**: `poll_seed.exs`, `ticketing_scenarios.exs`
- **Rule**: Feature name + purpose suffix

#### Test Scenarios
- **Pattern**: `{scenario_name}_test.exs`
- **Examples**: `cocktail_poll_test.exs`, `poll_suggestions_test.exs`
- **Rule**: Descriptive scenario name + `_test` suffix

#### Service Modules
- **Pattern**: `{domain}_service.ex` or `{domain}_builder.ex`
- **Examples**: `venue_service.ex`, `event_builder.ex`
- **Rule**: Domain + purpose suffix (`.ex` extension for compiled modules)

### Module Naming

```elixir
# Good: Matches file name and structure
defmodule DevSeeds.FeatureName do
  # in dev_seeds/features/feature_name/feature_seed.exs
end

# Good: Service modules
defmodule DevSeeds.Services.VenueService do
  # in dev_seeds/services/venue_service.ex
end

# Bad: Generic module name
defmodule Seed do
  # Too generic, unclear purpose
end
```

### Function Naming

```elixir
# Good: Descriptive verb + noun
def seed_poll_options
def create_diverse_events
def ensure_key_organizers

# Bad: Vague or unclear
def do_stuff
def run
def go
```

---

## Venue Handling (Critical)

**⚠️ CRITICAL**: All events MUST follow venue validation rules (enforced at changeset level since Phase 4).

### Validation Rules

```elixir
# Physical events (is_virtual: false) MUST have venue_id
# Virtual events (is_virtual: true) MUST NOT have venue_id
```

### Pattern 1: Physical Event with Venue

```elixir
# When you create venues for physical events
venue = create_or_get_venue()

event_params = %{
  title: "Concert in the Park",
  is_virtual: false,         # Physical event
  venue_id: venue.id,        # REQUIRED for physical events
  # ... other params
}

Events.create_event_with_organizer(event_params, user)
```

### Pattern 2: Virtual Event (No Venue)

```elixir
# When creating virtual events
event_params = %{
  title: "Online Workshop",
  is_virtual: true,                                        # Virtual event
  venue_id: nil,                                           # MUST be nil
  virtual_venue_url: "https://zoom.us/j/#{:rand.uniform(999999999)}",
  # ... other params
}

Events.create_event_with_organizer(event_params, user)
```

### Pattern 3: Automatic Fallback (Recommended)

```elixir
# If you don't create venues, automatically convert to virtual
venue_pool = create_venues_or_empty_list()

event_params =
  if Enum.empty?(venue_pool) do
    # No venues available - make it virtual
    %{
      title: "Event Title",
      is_virtual: true,
      virtual_venue_url: "https://zoom.us/j/#{:rand.uniform(999999999)}",
      # ... other params
    }
  else
    # Venues available - make it physical
    venue = Enum.random(venue_pool)
    %{
      title: "Event Title",
      is_virtual: false,
      venue_id: venue.id,
      # ... other params
    }
  end

Events.create_event_with_organizer(event_params, user)
```

### Anti-Pattern: Physical Event Without Venue ❌

```elixir
# ❌ THIS WILL FAIL VALIDATION
event_params = %{
  title: "Concert in the Park",
  is_virtual: false,  # Physical event
  venue_id: nil,      # ERROR: Physical events require venue_id
  # ... other params
}

# Result: {:error, changeset} with "must be present for physical events"
```

### Anti-Pattern: Virtual Event With Venue ❌

```elixir
# ❌ THIS WILL FAIL VALIDATION
event_params = %{
  title: "Online Workshop",
  is_virtual: true,   # Virtual event
  venue_id: venue.id, # ERROR: Virtual events cannot have venue_id
  # ... other params
}

# Result: {:error, changeset} with "must be nil for virtual events"
```

### Venue Service Usage

```elixir
# Use VenueService for consistent venue creation
alias DevSeeds.Services.VenueService

# Create a pool of venues
venue_pool = VenueService.create_venue_pool(%{
  count: 10,
  cities: cities,
  types: [:restaurant, :concert_hall, :park, :museum]
})

# Use venues in events
Enum.each(events_to_create, fn event_attrs ->
  venue = Enum.random(venue_pool)

  event_params = Map.merge(event_attrs, %{
    is_virtual: false,
    venue_id: venue.id
  })

  Events.create_event_with_organizer(event_params, user)
end)
```

---

## Using Services and Helpers

### Helpers Module

Located at: `priv/repo/dev_seeds/support/helpers.exs`

```elixir
Code.require_file("../../support/helpers.exs", __DIR__)
alias DevSeeds.Helpers

# Logging and output
Helpers.section("Seeding Users")        # Section header
Helpers.log("Created user: #{email}")   # Info message
Helpers.success("Seeding complete")     # Success message
Helpers.error("Seeding failed")         # Error message

# Random data generation
Helpers.get_random_image_attrs()        # Random image attributes
Helpers.random_datetime_forward(30)     # Random future datetime
Helpers.random_datetime_past(30)        # Random past datetime

# User creation
Helpers.create_user_with_auth(%{        # User with Clerk auth
  email: "test@example.com",
  name: "Test User"
})
```

### EventBuilder Service

Located at: `priv/repo/dev_seeds/services/event_builder.ex`

```elixir
alias DevSeeds.Services.EventBuilder

# Build complex event with all associations
event = EventBuilder.create_event(%{
  title: "Tech Conference",
  organizer: user,
  venue: venue,
  participants_count: 50,
  with_polls: true,
  with_activities: true
})
```

### VenueService

Located at: `priv/repo/dev_seeds/services/venue_service.ex`

```elixir
alias DevSeeds.Services.VenueService

# Create venue pool
venues = VenueService.create_venue_pool(%{
  count: 10,
  cities: cities,
  types: [:restaurant, :bar, :concert_hall]
})

# Create single venue
venue = VenueService.create_venue(%{
  name: "Blue Note Jazz Club",
  city: city,
  type: :music_venue
})
```

### CuratedData Module

Located at: `priv/repo/dev_seeds/support/curated_data.exs`

```elixir
Code.require_file("../../support/curated_data.exs", __DIR__)
alias DevSeeds.CuratedData

# Get realistic test data
movies = CuratedData.movies()           # Hand-picked movies
restaurants = CuratedData.restaurants() # Hand-picked restaurants
tagline = CuratedData.random_tagline()  # Random event tagline
```

---

## Testing Seed Scripts

### Test Directly

```bash
# Run single seed file
mix run priv/repo/dev_seeds/features/polls/poll_seed.exs

# Run with Elixir
elixir priv/repo/dev_seeds/features/polls/poll_seed.exs
```

### Test Through Mix Task

```bash
# Full seeding
mix seed.dev

# Selective seeding
mix seed.dev --only users,events

# Append mode (don't clean first)
mix seed.dev --append

# Custom quantities
mix seed.dev --users 100 --events 200 --polls 50
```

### Test Cleaning

```bash
# Clean all seeded data
mix seed.clean

# Clean specific entities
mix seed.clean --only events

# Force clean without confirmation
mix seed.clean --force
```

### Validation Testing

After adding new seeds, always verify venue consistency:

```bash
# Run validation proof script
mix run priv/repo/dev_seeds/validation_proof.exs
```

Query for venue inconsistencies:

```sql
-- Should return 0 rows
SELECT * FROM events
WHERE (is_virtual = false AND venue_id IS NULL)
   OR (is_virtual = true AND venue_id IS NOT NULL);
```

---

## Common Patterns

### Pattern 1: Create Entity with Associations

```elixir
# Good: Create event with organizer and participants
def create_event_with_associations(user, venue, participant_users) do
  event_params = %{
    title: "Tech Meetup",
    is_virtual: false,
    venue_id: venue.id,
    start_at: Faker.DateTime.forward(7),
    ends_at: Faker.DateTime.forward(7) |> DateTime.add(7200, :second),
    timezone: "America/New_York",
    status: :confirmed,
    visibility: :public
  }

  # Create event with organizer
  {:ok, event} = Events.create_event_with_organizer(event_params, user)

  # Add participants
  Enum.each(participant_users, fn participant ->
    Events.create_event_participant(%{
      event_id: event.id,
      user_id: participant.id,
      status: :accepted,
      role: :participant
    })
  end)

  event
end
```

### Pattern 2: Idempotent Seeding

```elixir
# Good: Check if data exists before creating
def ensure_category(name) do
  case Repo.get_by(Category, name: name) do
    nil ->
      Repo.insert!(%Category{name: name})
    category ->
      category
  end
end
```

### Pattern 3: Batch Creation

```elixir
# Good: Use Enum.map for multiple entities
users = Enum.map(1..10, fn i ->
  Helpers.create_user_with_auth(%{
    email: "user#{i}@example.com",
    name: "User #{i}"
  })
end)
```

### Pattern 4: Error Handling

```elixir
# Good: Handle errors gracefully
case Events.create_event_with_organizer(event_params, user) do
  {:ok, event} ->
    Helpers.success("Created event: #{event.title}")
    event

  {:error, changeset} ->
    Helpers.error("Failed to create event: #{inspect(changeset.errors)}")
    nil
end
```

### Pattern 5: Conditional Seeding

```elixir
# Good: Check environment or flags
if Mix.env() == :dev do
  seed_test_data()
end

# Or use module attributes for configuration
@seed_enabled Application.compile_env(:eventasaurus, :seed_feature_x, true)

if @seed_enabled do
  seed_feature_x()
end
```

---

## Anti-Patterns to Avoid

### ❌ Anti-Pattern 1: Hardcoded IDs

```elixir
# Bad: Hardcoded IDs break when database is reset
event = Repo.get!(Event, 123)

# Good: Query by attribute or create fresh
event = Repo.get_by!(Event, slug: "tech-meetup") ||
        create_event(params)
```

### ❌ Anti-Pattern 2: Missing Dependencies

```elixir
# Bad: Assumes users exist
users = Repo.all(User)
organizer = List.first(users)  # Might be nil!

# Good: Ensure dependencies exist
users = Repo.all(User)
organizer = case users do
  [] ->
    Helpers.error("No users found. Run user seeds first.")
    System.halt(1)
  [user | _] ->
    user
end
```

### ❌ Anti-Pattern 3: Silent Failures

```elixir
# Bad: Ignoring errors
{:error, _} = Events.create_event(params)
# Continue anyway...

# Good: Handle errors explicitly
case Events.create_event(params) do
  {:ok, event} -> event
  {:error, changeset} ->
    Helpers.error("Event creation failed: #{inspect(changeset.errors)}")
    nil
end
```

### ❌ Anti-Pattern 4: Duplicate Data

```elixir
# Bad: Creating duplicate data
Enum.each(1..10, fn _ ->
  Repo.insert!(%Category{name: "Music"})  # Creates 10 duplicate categories
end)

# Good: Use unique constraints or check existence
def ensure_category(name) do
  Repo.get_by(Category, name: name) ||
    Repo.insert!(%Category{name: name})
end
```

### ❌ Anti-Pattern 5: Ignoring Venue Validation

```elixir
# Bad: Physical event without venue (WILL FAIL)
%{
  title: "Concert",
  is_virtual: false,
  venue_id: nil  # ERROR!
}

# Good: Always provide venue for physical events
%{
  title: "Concert",
  is_virtual: false,
  venue_id: venue.id  # ✅
}
```

### ❌ Anti-Pattern 6: Complex Logic in Seed Files

```elixir
# Bad: Complex business logic in seed file
# (100+ lines of complex calculations and conditionals)

# Good: Extract to service module
alias DevSeeds.Services.EventBuilder
EventBuilder.create_complex_event(params)
```

---

## Troubleshooting

### Problem: Seed Fails with Venue Validation Error

**Error Message:**
```
{:error, #Ecto.Changeset<errors: [venue_id: {"must be present for physical events", []}]>}
```

**Solution:**
- Physical events (is_virtual: false) require venue_id
- Either create a venue and assign it, or set is_virtual: true

**Fix:**
```elixir
# Option 1: Create venue
venue = VenueService.create_venue(params)
event_params = %{is_virtual: false, venue_id: venue.id}

# Option 2: Make it virtual
event_params = %{
  is_virtual: true,
  virtual_venue_url: "https://zoom.us/j/#{:rand.uniform(999999999)}"
}
```

---

### Problem: Seed Fails with Missing Users

**Error Message:**
```
** (MatchError) no match of right hand side value: []
```

**Solution:**
Ensure dependencies are seeded first. The runner.exs orchestrates the correct order.

**Fix:**
```elixir
# In runner.exs, ensure order:
1. Users must be seeded before events
2. Groups must be seeded before group-specific events
3. Events must be seeded before polls/activities
```

---

### Problem: DateTime Type Error

**Error Message:**
```
** (FunctionClauseError) no function clause matching in DateTime.add/4
```

**Solution:**
DateTime.add expects integer seconds, not floats.

**Fix:**
```elixir
# Bad
ends_at = DateTime.add(start_at, duration_hours * 3600, :second)

# Good
ends_at = DateTime.add(start_at, round(duration_hours * 3600), :second)
```

---

### Problem: Circular Dependencies

**Error Message:**
```
** (ArgumentError) could not load module DevSeeds.Something due to a circular dependency
```

**Solution:**
Avoid circular requires. Use services module to break the cycle.

**Fix:**
```elixir
# Instead of:
# users.exs requires events.exs
# events.exs requires users.exs

# Use:
# users.exs and events.exs both require helpers.exs
# helpers.exs has shared utilities
```

---

### Problem: Seed Takes Too Long

**Symptoms:**
- Seed execution takes >5 minutes
- Database grows very large

**Solution:**
- Use smaller quantities during development
- Profile slow queries with query logging
- Consider pagination for large batch operations

**Fix:**
```bash
# Instead of:
mix seed.dev --users 1000 --events 5000

# Use:
mix seed.dev --users 50 --events 100
```

---

## Additional Resources

### Documentation Files
- **Main README**: `priv/repo/dev_seeds/README.md` - Overview and directory structure
- **Phase 4 Summary**: `priv/repo/PHASE_4_SUMMARY.md` - Venue validation changes
- **Phase 4 Audit**: `priv/repo/PHASE_4_AUDIT_REPORT.md` - Validation proof and testing

### Mix Tasks
- **Seed Development Data**: `lib/mix/tasks/seed.dev.ex`
- **Clean Development Data**: `lib/mix/tasks/seed.clean.ex`

### Key Modules
- **Helpers**: `priv/repo/dev_seeds/support/helpers.exs`
- **Curated Data**: `priv/repo/dev_seeds/support/curated_data.exs`
- **Event Builder**: `priv/repo/dev_seeds/services/event_builder.ex`
- **Venue Service**: `priv/repo/dev_seeds/services/venue_service.ex`

### Validation
- **Validation Proof Script**: `priv/repo/dev_seeds/validation_proof.exs`
- **Event Changeset**: `lib/eventasaurus_app/events/event.ex` (lines 283-296)

---

## Quick Reference Commands

```bash
# Full seeding workflow
mix seed.clean && mix seed.dev

# Selective seeding
mix seed.dev --only users,events,polls

# Append mode (keep existing data)
mix seed.dev --append

# Custom quantities
mix seed.dev --users 100 --events 200

# Clean specific data
mix seed.clean --only events --force

# Test validation
mix run priv/repo/dev_seeds/validation_proof.exs

# Direct seed execution
mix run priv/repo/dev_seeds/features/polls/poll_seed.exs
```

---

**Version History:**
- **1.0** (2025-11-14): Initial version - Phase 5 documentation
