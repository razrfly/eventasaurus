defmodule Mix.Tasks.Ecto.Reset.Dev do
  @moduledoc """
  Resets the development database and seeds it with test data.

  This is a convenience task that combines:
  1. `mix ecto.drop`
  2. `mix ecto.create`
  3. `mix ecto.migrate`
  4. `mix seed.dev`

  ## Usage

      mix ecto.reset.dev              # Reset and seed with defaults
      mix ecto.reset.dev --users 100  # Reset with custom user count
      mix ecto.reset.dev --quiet      # Suppress output

  ## Options

  Accepts all options from `mix seed.dev`:
    * `--users N` - Number of users to create
    * `--groups N` - Number of groups to create
    * `--events N` - Number of events to create
    * `--quiet` - Suppress output
  """

  use Mix.Task

  @shortdoc "Reset and seed the development database"

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    # Ensure we're in dev environment
    unless Mix.env() == :dev do
      Mix.raise("This task should only be run in development environment!")
    end

    IO.puts(
      IO.ANSI.format([:bright, :yellow, "\n⚠️  This will DROP your development database!", :reset])
    )

    if Mix.shell().yes?("Are you sure you want to continue?") do
      IO.puts("\n🔄 Resetting development database...\n")

      # Drop the database
      Mix.Task.run("ecto.drop")
      Mix.Task.reenable("ecto.drop")

      # Create the database
      Mix.Task.run("ecto.create")
      Mix.Task.reenable("ecto.create")

      # Run migrations
      Mix.Task.run("ecto.migrate")
      Mix.Task.reenable("ecto.migrate")

      # Run the dev seeder with passed arguments
      Mix.Task.run("seed.dev", args)

      IO.puts(
        IO.ANSI.format([
          :green,
          "\n✅ Development database reset and seeded successfully!",
          :reset
        ])
      )
    else
      IO.puts(IO.ANSI.format([:yellow, "\n❌ Database reset cancelled.", :reset]))
    end
  end
end
