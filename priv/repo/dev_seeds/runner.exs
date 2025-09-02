# Development Seeds Runner
# This script generates comprehensive test data for development
# Run with: mix run priv/repo/dev_seeds/runner.exs

# Ensure we're in dev environment
unless Mix.env() == :dev do
  raise "This script should only be run in development environment!"
end

# Load the factory and helpers
Code.require_file("#{__DIR__}/../../../test/support/factory.ex")
Code.require_file("#{__DIR__}/helpers.exs")
Code.require_file("#{__DIR__}/users.exs")
Code.require_file("#{__DIR__}/groups.exs")
Code.require_file("#{__DIR__}/events.exs")

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

# Create polls for events (Phase 5 - to be implemented)
polls = []

# Create activities for completed events (Phase 6 - to be implemented)
activities = []

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