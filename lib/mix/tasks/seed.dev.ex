defmodule Mix.Tasks.Seed.Dev do
  @moduledoc """
  Seeds the development database with realistic test data for testing and development.

  This task orchestrates the development seeding system, executing seed scripts in the
  correct dependency order to create comprehensive test data including users, groups,
  events, polls, activities, and feature-specific scenarios.

  ## What This Task Does

  1. **Runs Production Seeds First**: Ensures essential reference data exists
     (categories, countries, cities, sources)
  2. **Cleans Existing Data** (unless `--append` is used): Removes all test data
     while preserving production reference data
  3. **Creates Core Entities**: Users, groups, venues in correct dependency order
  4. **Creates Events**: Past, upcoming, and future events with realistic scenarios
  5. **Adds Feature Data**: Polls, activities, tickets, and other feature-specific data
  6. **Runs Test Scenarios**: Executes special test scenarios and persona setups

  ## Important Notes

  - **Development Only**: This task only runs in the development environment
  - **Venue Validation**: All events must comply with venue validation rules
    (physical events require `venue_id`, virtual events must not have `venue_id`)
  - **Execution Time**: Full seeding typically takes 3-5 minutes depending on quantities
  - **Idempotent**: Safe to run multiple times with `--append` flag

  ## Usage

      mix seed.dev                    # Clean and seed with defaults
      mix seed.dev --append           # Seed without cleaning first
      mix seed.dev --users 100        # Custom user count
      mix seed.dev --events 200       # Custom event count
      mix seed.dev --only users       # Seed only specific entities
      mix seed.dev --only users,events,polls

  ## Options

    * `--append` - Don't clean existing data before seeding (adds to existing data)
    * `--users N` - Number of users to create (default: 50)
    * `--groups N` - Number of groups to create (default: 15)
    * `--events N` - Number of events to create (default: 100, distributed across time periods)
    * `--polls N` - Number of polls to create (default: 40)
    * `--activities N` - Number of activities to create (default: based on events)
    * `--only` - Comma-separated list of entities to seed (users, groups, events, polls, activities)
    * `--quiet` - Suppress output messages

  ## Common Workflows

      # Full reset and seed (typical development workflow)
      mix seed.clean && mix seed.dev

      # Quick reset with minimal data (faster for testing)
      mix seed.dev --users 10 --events 20 --polls 10

      # Add more users to existing database
      mix seed.dev --append --only users --users 50

      # Seed everything except polls
      mix seed.dev --only users,groups,events,activities

      # Full seed with custom quantities
      mix seed.dev --users 100 --groups 30 --events 300 --polls 80

  ## Event Distribution

  Events are distributed across three time periods automatically:

  - **Past Events** (1/3): Already completed, useful for historical data and activities
  - **Upcoming Events** (1/2): Near future, most relevant for current testing
  - **Future Events** (1/5): Distant future, useful for scheduling features

  Example with `--events 100`:
  - Past: 33 events
  - Upcoming: 50 events
  - Future: 20 events

  ## Seeding Order (Important for Dependencies)

  The runner executes seeds in this order:

  1. **Production Seeds** (`priv/repo/seeds.exs`)
     - Reference data: categories, countries, cities, sources
     - Essential for all other seeds
  2. **Core Users** (`dev_seeds/core/users.exs`)
     - Base users and test personas
  3. **Core Groups** (`dev_seeds/core/groups.exs`)
     - Groups and memberships
  4. **Venues** (created by event seeds)
     - Physical locations for events
  5. **Core Events** (`dev_seeds/core/events.exs`)
     - Past, upcoming, and future events
  6. **Feature Seeds** (polls, activities, tickets)
     - Feature-specific data attached to events
  7. **Test Scenarios** (special test cases)
     - Scenario-specific seeds

  ## Test Accounts Created

  Every seed run creates standard test accounts:

  - `admin@example.com` - Admin user
  - `demo@example.com` - Demo user
  - `organizer@example.com` - Event organizer
  - `participant@example.com` - Regular participant

  Plus 10 themed personas:
  - `movie_buff@example.com` - Movie enthusiast
  - `foodie_friend@example.com` - Restaurant explorer
  - `fitness_fan@example.com` - Fitness enthusiast
  - (and 7 more...)

  All test accounts use password: `testpass123`

  ## Validation and Data Quality

  All seeded data passes validation rules enforced at the changeset level:

  - Physical events (is_virtual: false) **must** have venue_id
  - Virtual events (is_virtual: true) **must not** have venue_id
  - All required fields must be present
  - Datetimes must be valid and properly ordered

  To verify data quality after seeding:

      mix run priv/repo/dev_seeds/validation_proof.exs

  ## Troubleshooting

  ### Seeding Takes Too Long

  Use smaller quantities during development:

      mix seed.dev --users 10 --events 20

  ### Validation Errors

  If you see venue validation errors, check:

  - Physical events must have `venue_id` set
  - Virtual events must have `is_virtual: true` and `virtual_venue_url`
  - See `priv/repo/dev_seeds/BEST_PRACTICES.md` for venue handling patterns

  ### Memory Issues

  Seed smaller batches and use `--only` for selective seeding:

      mix seed.dev --only users --users 50
      mix seed.dev --append --only events --events 100

  ### Clean State Required

  If data seems inconsistent, do a full reset:

      mix seed.clean --force && mix seed.dev

  ## Related Commands

  - `mix seed.clean` - Clean seeded development data
  - `mix run priv/repo/seeds.exs` - Run production seeds only
  - `mix run priv/repo/dev_seeds/validation_proof.exs` - Verify data quality

  ## Documentation

  - **Best Practices Guide**: `priv/repo/dev_seeds/BEST_PRACTICES.md`
  - **Seeding Overview**: `priv/repo/dev_seeds/README.md`
  - **Validation Changes**: `priv/repo/PHASE_4_SUMMARY.md`
  - **Audit Report**: `priv/repo/PHASE_4_AUDIT_REPORT.md`

  ## Implementation Details

  This task:

  1. Validates environment is `:dev`
  2. Parses command-line options
  3. Starts the application
  4. Builds configuration from options
  5. Passes configuration to `priv/repo/dev_seeds/runner.exs` via environment variable
  6. Runner orchestrates all seed scripts in correct order

  ## Examples

      # Standard development reset
      mix seed.dev

      # Quick minimal seed for rapid iteration
      mix seed.dev --users 5 --events 10

      # Add more data without resetting
      mix seed.dev --append

      # Large dataset for load testing
      mix seed.dev --users 500 --events 2000 --polls 500

      # Seed specific entities only
      mix seed.dev --only users,groups

      # Silent mode (no output)
      mix seed.dev --quiet

      # Incremental seeding workflow
      mix seed.dev --only users --users 50
      mix seed.dev --append --only groups --groups 20
      mix seed.dev --append --only events --events 100

  ## Performance Tips

  - Use `--append` to avoid cleaning overhead
  - Use `--only` to seed specific entities
  - Reduce quantities during development
  - Use `--quiet` in automated scripts
  - Run production seeds separately if unchanged: `mix run priv/repo/seeds.exs`

  ## See Also

  - Mix task source code at `lib/mix/tasks/seed.dev.ex`
  - Runner source code at `priv/repo/dev_seeds/runner.exs`
  - Issue #2239 for full seeding system documentation
  """

  use Mix.Task

  @shortdoc "Seeds development database with test data"

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    # Ensure we're in dev environment
    unless Mix.env() == :dev do
      Mix.raise("This task should only be run in development environment!")
    end

    # Parse arguments
    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          append: :boolean,
          users: :integer,
          groups: :integer,
          events: :integer,
          polls: :integer,
          activities: :integer,
          only: :string,
          quiet: :boolean
        ]
      )

    # Start the app
    Mix.Task.run("app.start")

    # Load the runner script with configuration
    config = build_config(opts)

    # Set environment variable for the runner to use
    System.put_env("DEV_SEED_CONFIG", Jason.encode!(config))

    # Run the seeder
    Code.eval_file("priv/repo/dev_seeds/runner.exs")

    unless opts[:quiet] do
      IO.puts("\n✅ Development seeding complete!")
    end
  end

  defp build_config(opts) do
    base_config = %{
      users: opts[:users] || 50,
      groups: opts[:groups] || 15,
      events: %{
        past: div(opts[:events] || 100, 3),
        upcoming: div(opts[:events] || 100, 2),
        future: div(opts[:events] || 100, 5)
      },
      participation_rate: 0.3,
      clean_first: !opts[:append]
    }

    # Handle --only option
    if opts[:only] do
      entities = String.split(opts[:only], ",")
      Map.put(base_config, :only, entities)
    else
      base_config
    end
  end
end
