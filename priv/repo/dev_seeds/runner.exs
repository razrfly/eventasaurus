# Development Seeds Runner
# This script generates comprehensive test data for development
# Run with: mix run priv/repo/dev_seeds/runner.exs

# Ensure we're in dev environment
unless Mix.env() == :dev do
  raise "This script should only be run in development environment!"
end

# Load the factory and helpers
Code.require_file("#{__DIR__}/../../../test/support/factory.ex")
Code.require_file("#{__DIR__}/support/helpers.exs")
Code.require_file("#{__DIR__}/core/users.exs")
Code.require_file("#{__DIR__}/core/groups.exs")
Code.require_file("#{__DIR__}/core/events.exs")

alias DevSeeds.{Helpers, Users, Groups, Events}
alias EventasaurusApp.Repo

# Configuration - Check environment variable or use defaults
config = if System.get_env("DEV_SEED_CONFIG") do
  Jason.decode!(System.get_env("DEV_SEED_CONFIG"), keys: :atoms)
else
  %{
    users: 50,     # Updated to match issue requirement
    groups: 15,    # Updated to match issue requirement
    events: 100,   # Updated to match issue requirement
    clean_first: true
  }
end

# Print configuration
Helpers.section("Development Seeding Configuration")
IO.inspect(config, label: "Config")

# Optionally clean existing data
if config.clean_first do
  Helpers.section("Cleaning Existing Data")
  
  # Clean in reverse order of dependencies
  Repo.delete_all(EventasaurusApp.Events.PollVote)
  Repo.delete_all(EventasaurusApp.Events.PollOption)
  Repo.delete_all(EventasaurusApp.Events.Poll)
  Repo.delete_all(EventasaurusApp.Events.EventActivity)
  Repo.delete_all(EventasaurusApp.Events.EventParticipant)
  Repo.delete_all(EventasaurusApp.Events.EventUser)
  Repo.delete_all(EventasaurusApp.Groups.GroupUser)
  Repo.delete_all(EventasaurusApp.Events.Order)  # Clean orders before events
  Repo.delete_all(EventasaurusApp.Events.Ticket) # Clean tickets before events
  Repo.delete_all(EventasaurusApp.Events.Event)
  Repo.delete_all(EventasaurusApp.Venues.Venue)
  # Delete groups before users (groups reference users via created_by_id)
  # Force delete all groups including soft-deleted ones
  Repo.query!("DELETE FROM groups")
  # Delete Stripe Connect accounts before users
  Repo.delete_all(EventasaurusApp.Stripe.StripeConnectAccount)
  # Delete all users (we'll recreate test users)
  Repo.delete_all(EventasaurusApp.Accounts.User)
  
  Helpers.success("Cleaned existing data")
end

# Run general seeds first (creates holden@gmail.com)
Helpers.section("Running General Seeds")
Code.eval_file("priv/repo/seeds.exs")

# Start development seeding
Helpers.section("Starting Development Seed Process")
start_time = System.monotonic_time(:second)

# Create users using the new Users module
users = Users.seed(count: config.users, with_auth: true)

# Create personas for specific testing scenarios
personas = Users.create_personas()
all_users = users ++ personas

# Create groups using the new Groups module
groups = Groups.seed(count: config.groups, users: all_users)

# Create themed groups for specific scenarios
themed_groups = Groups.create_themed_groups(all_users)
all_groups = groups ++ themed_groups

# Create events using the new Events module
events = Events.seed(count: config.events, users: all_users, groups: all_groups)

# Create some events at maximum capacity
full_events = Events.create_full_events(all_users)
all_events = events ++ full_events

# Ensure key organizers have appropriate events (movie_buff, foodie_friend)
Code.require_file("scenarios/key_organizers.exs", __DIR__)
DevSeeds.EnsureKeyOrganizers.ensure_key_organizers()

# Ensure Holden (the only Clerk-authenticated user) has events for iOS testing
Code.require_file("scenarios/ensure_holden_events.exs", __DIR__)
DevSeeds.EnsureHoldenEvents.run()

# Create ticketed event organizer personas (Phase 1 from issue #1036)
Code.require_file("features/ticketing/ticketed_events.exs", __DIR__)
DevSeeds.TicketedEventOrganizers.ensure_ticketed_event_organizers()

# Add interested participants to ticketed events
Code.require_file("features/ticketing/ticketed_events_interest.exs", __DIR__)
DevSeeds.AddInterestToTicketedEvents.add_interest_to_organizer_events()

# Create Phase 1 extended ticket scenarios (Issue #2233)
Helpers.section("Creating Phase 1: Extended Ticket Scenarios")
Code.require_file("features/ticketing/ticket_scenarios.exs", __DIR__)
DevSeeds.ExtendedTicketScenarios.seed_phase_1()

# Create Phase 2 Kickstarter/Threshold event scenarios (Issue #2243)
Helpers.section("Creating Phase 2: Kickstarter/Threshold Event Scenarios")
DevSeeds.ExtendedTicketScenarios.seed_phase_2()

# Seed Stripe Connect test accounts for ticketed event organizers
Helpers.section("Seeding Stripe Connect Test Accounts")
Code.require_file("features/ticketing/stripe_connect.exs", __DIR__)
DevSeeds.StripeConnect.seed()

# Create Phase I diverse polling events (date + movie star rating)
Helpers.section("Creating Phase I: Date + Movie Star Rating Polls")
Code.require_file("features/polls/polling_events.exs", __DIR__)
if Code.ensure_loaded?(DiversePollingEvents) and function_exported?(DiversePollingEvents, :run, 0) do
  DiversePollingEvents.run()
else
  Helpers.error("DiversePollingEvents module not properly loaded")
end

# Create polls and activities in parallel (they operate on existing events independently)
Helpers.section("Creating Polls and Activities (Parallel)")

poll_task = Task.async(fn ->
  Code.require_file("features/polls/polls.exs", __DIR__)
  # PollSeed.run() is called within the file
  Repo.all(EventasaurusApp.Events.Poll)
end)

activity_task = Task.async(fn ->
  Code.require_file("features/activities/activities.exs", __DIR__)
  ActivitySeed.run()
  Repo.all(EventasaurusApp.Events.EventActivity)
end)

# Wait for both to complete
[polls, activities] = Task.await_many([poll_task, activity_task], :infinity)

Helpers.success("✓ Polls created: #{length(polls)}")
Helpers.success("✓ Activities created: #{length(activities)}")

# Create Phase IV: Enhanced Variety Polls
Helpers.section("Creating Phase IV: Enhanced Variety Polls")
Code.require_file("features/polls/variety_polls.exs", __DIR__)
if Code.ensure_loaded?(EnhancedVarietyPolls) and function_exported?(EnhancedVarietyPolls, :run, 0) do
  EnhancedVarietyPolls.run()
else
  Helpers.error("EnhancedVarietyPolls module not properly loaded")
end

# Create Phase V: Mobile Testing Comprehensive Polls
Helpers.section("Creating Phase V: Mobile Testing Comprehensive Polls")
# Force recompile to avoid stale module cache
if Code.ensure_loaded?(MobileTestingPolls) do
  :code.purge(MobileTestingPolls)
  :code.delete(MobileTestingPolls)
end
Code.compile_file("features/polls/mobile_testing_polls.exs", __DIR__)
if Code.ensure_loaded?(MobileTestingPolls) and function_exported?(MobileTestingPolls, :run, 0) do
  MobileTestingPolls.run()
else
  Helpers.error("MobileTestingPolls module not properly loaded")
end

# Validate seeding consistency
Helpers.section("Validating Seeding Consistency")
import Ecto.Query
alias EventasaurusApp.Events.{Event, Poll, EventParticipant}

events_with_polls_count =
  from(e in Event,
    join: p in Poll, on: p.event_id == e.id,
    where: is_nil(e.deleted_at),
    select: count(fragment("distinct ?", e.id))
  )
  |> Repo.one()

inconsistent =
  from(e in Event,
    join: p in Poll, on: p.event_id == e.id,
    left_join: ep in EventParticipant, on: ep.event_id == e.id,
    where: is_nil(e.deleted_at),
    group_by: [e.id, e.title],
    having: count(ep.id) == 0,
    select: %{id: e.id, title: e.title}
  )
  |> Repo.all()

if inconsistent != [] do
  Helpers.error("❌ Found #{length(inconsistent)} events with polls but no participants!")
  Enum.each(inconsistent, fn e ->
    IO.puts("   - #{e.title} (ID: #{e.id})")
  end)
  IO.puts("\nThis indicates a seeding coordination issue.")
else
  Helpers.success("✅ All #{events_with_polls_count} events with polls have participants")
end

# Summary
elapsed_time = System.monotonic_time(:second) - start_time
Helpers.section("Seeding Complete!")

IO.puts("""
Summary:
--------
✓ Users created: #{length(all_users)}
  - Base users: #{length(users)}
  - Personas: #{length(personas)}
✓ Groups created: #{length(all_groups)}
  - Regular groups: #{length(groups)}
  - Themed groups: #{length(themed_groups)}
✓ Events created: #{length(all_events)}
  - Regular events: #{length(events)}
  - Full capacity events: #{length(full_events)}
✓ Polls created: #{length(polls)}
✓ Activities created: #{length(activities)}

Time elapsed: #{elapsed_time} seconds

Test Accounts:
--------------
- Email: admin@example.com / Password: testpass123
- Email: demo@example.com / Password: testpass123
- Email: organizer@example.com / Password: testpass123
- Email: participant@example.com / Password: testpass123

Personal Account:
----------------
- Email: holden@gmail.com / Password: sawyer1234
""")


Helpers.success("Development database seeded successfully! 🎉")