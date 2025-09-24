defmodule Mix.Tasks.Seed.Clean do
  @moduledoc """
  Cleans specific types of data from the development database.

  ## Usage

      mix seed.clean                  # Clean all seeded data
      mix seed.clean --only events    # Clean only events
      mix seed.clean --only polls,activities

  ## Options

    * `--only` - Comma-separated list of entities to clean
    * `--force` - Don't ask for confirmation

  ## Available entity types

    * `users` - All users except system users
    * `events` - All events and related data
    * `groups` - All groups and memberships
    * `polls` - All polls, options, and votes
    * `activities` - All event activities
    * `venues` - All venues

  ## Examples

      # Clean everything
      mix seed.clean

      # Clean only events and related data
      mix seed.clean --only events

      # Clean polls and activities without confirmation
      mix seed.clean --only polls,activities --force
  """

  use Mix.Task
  alias EventasaurusApp.Repo
  import Ecto.Query

  @shortdoc "Clean seeded data from development database"

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
          only: :string,
          force: :boolean
        ]
      )

    # Start the app
    Mix.Task.run("app.start")

    # Determine what to clean
    entities =
      if opts[:only] do
        String.split(opts[:only], ",")
      else
        ["all"]
      end

    # Confirm unless --force
    unless opts[:force] do
      IO.puts(
        IO.ANSI.format([
          :bright,
          :yellow,
          "\n⚠️  This will DELETE data from your development database!",
          :reset
        ])
      )

      IO.puts("Entities to clean: #{inspect(entities)}")

      unless Mix.shell().yes?("\nAre you sure you want to continue?") do
        IO.puts(IO.ANSI.format([:yellow, "\n❌ Cleaning cancelled.", :reset]))
        exit(:normal)
      end
    end

    IO.puts("\n🧹 Cleaning development data...\n")

    # Clean entities
    clean_entities(entities)

    IO.puts(IO.ANSI.format([:green, "\n✅ Development data cleaned successfully!", :reset]))
  end

  defp clean_entities(["all"]) do
    clean_entities(["activities", "polls", "events", "groups", "venues", "users"])
  end

  defp clean_entities(entities) do
    Enum.each(entities, &clean_entity/1)
  end

  defp clean_entity("users") do
    IO.write("Cleaning users... ")

    # Keep system users
    system_emails = ["admin@example.com", "demo@example.com"]

    deleted =
      Repo.delete_all(
        from(u in EventasaurusApp.Accounts.User,
          where: u.email not in ^system_emails
        )
      )

    IO.puts("✓ Deleted #{elem(deleted, 0)} users")
  end

  defp clean_entity("events") do
    IO.write("Cleaning events... ")

    # This will cascade to participants, polls, activities via foreign keys
    {count, _} = Repo.delete_all(EventasaurusApp.Events.Event)

    IO.puts("✓ Deleted #{count} events")
  end

  defp clean_entity("groups") do
    IO.write("Cleaning groups... ")

    # Delete group memberships first
    Repo.delete_all(EventasaurusApp.Groups.GroupUser)
    {count, _} = Repo.delete_all(EventasaurusApp.Groups.Group)

    IO.puts("✓ Deleted #{count} groups")
  end

  defp clean_entity("polls") do
    IO.write("Cleaning polls... ")

    # Delete in order of dependencies
    Repo.delete_all(EventasaurusApp.Events.PollVote)
    Repo.delete_all(EventasaurusApp.Events.PollOption)
    {count, _} = Repo.delete_all(EventasaurusApp.Events.Poll)

    IO.puts("✓ Deleted #{count} polls")
  end

  defp clean_entity("activities") do
    IO.write("Cleaning activities... ")

    {count, _} = Repo.delete_all(EventasaurusApp.Events.EventActivity)

    IO.puts("✓ Deleted #{count} activities")
  end

  defp clean_entity("venues") do
    IO.write("Cleaning venues... ")

    {count, _} = Repo.delete_all(EventasaurusApp.Venues.Venue)

    IO.puts("✓ Deleted #{count} venues")
  end

  defp clean_entity(entity) do
    IO.puts(IO.ANSI.format([:yellow, "⚠️  Unknown entity type: #{entity}", :reset]))
  end
end
