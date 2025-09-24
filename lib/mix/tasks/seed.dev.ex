defmodule Mix.Tasks.Seed.Dev do
  @moduledoc """
  Seeds the development database with realistic test data using Faker and ExMachina.

  ## Usage

      mix seed.dev                    # Clean and seed with defaults
      mix seed.dev --append           # Seed without cleaning first
      mix seed.dev --users 100        # Custom user count
      mix seed.dev --events 200       # Custom event count
      mix seed.dev --only users       # Seed only specific entities
      mix seed.dev --only users,events,polls

  ## Options

    * `--append` - Don't clean existing data before seeding
    * `--users N` - Number of users to create (default: 50)
    * `--groups N` - Number of groups to create (default: 15)
    * `--events N` - Number of events to create (default: 100)
    * `--polls N` - Number of polls to create (default: 40)
    * `--only` - Comma-separated list of entities to seed
    * `--quiet` - Suppress output

  ## Examples

      # Reset and seed everything
      mix seed.dev

      # Add more data without resetting
      mix seed.dev --append

      # Create specific amounts
      mix seed.dev --users 100 --events 200

      # Seed only certain entities
      mix seed.dev --only users,events
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
