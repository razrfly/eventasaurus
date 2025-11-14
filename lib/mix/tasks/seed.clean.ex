defmodule Mix.Tasks.Seed.Clean do
  @moduledoc """
  Cleans development seed data from the database with intelligent dependency ordering
  and safety mechanisms to prevent data loss.

  This task provides selective or complete removal of development test data while
  preserving essential reference data and system accounts. All deletions are performed
  in correct dependency order to prevent foreign key violations.

  ## What This Task Does

  1. **Environment Check**: Ensures task only runs in development (safety check)
  2. **Parse Options**: Determines which entities to clean (`--only` or all)
  3. **Safety Confirmation**: Prompts for confirmation unless `--force` is used
  4. **Dependency Ordering**: Deletes data in correct order (children before parents)
  5. **Cascade Handling**: Leverages foreign key cascades for related data
  6. **System Preservation**: Keeps essential system accounts and reference data

  ## Important Notes

  - **Development Only**: This task only runs in the development environment
  - **Destructive Operation**: All cleaning operations are PERMANENT and cannot be undone
  - **Dependency Order**: Entities are cleaned in reverse dependency order automatically
  - **Cascade Deletions**: Some entities trigger cascading deletes (e.g., events → participants)
  - **System Preservation**: System accounts (admin@example.com, demo@example.com) are preserved
  - **Foreign Key Safety**: Deletion order prevents foreign key constraint violations
  - **No Backup**: Data is permanently deleted - use `mix seed.dev --append` to rebuild

  ## Usage

      mix seed.clean                           # Clean all seeded data (with confirmation)
      mix seed.clean --force                   # Clean all without confirmation
      mix seed.clean --only events             # Clean only events
      mix seed.clean --only polls,activities   # Clean specific entities
      mix seed.clean --only users --force      # Clean users without confirmation

  ## Options

    * `--only ENTITIES` - Comma-separated list of entities to clean (see Available Entities)
    * `--force` - Skip confirmation prompt (use with caution in scripts)

  ## Available Entity Types

    * `users` - All users **except** system accounts (admin@example.com, demo@example.com)
    * `events` - All events (cascades to participants, event_users, event_tags automatically)
    * `groups` - All groups and their memberships
    * `polls` - All polls, options, and votes (deleted in dependency order)
    * `activities` - All event activities
    * `venues` - All physical venue locations

  ## Common Workflows

      # Full reset workflow (most common during development)
      mix seed.clean --force && mix seed.dev

      # Clean and reseed with specific quantities
      mix seed.clean --force && mix seed.dev --users 10 --events 20

      # Clean only events to test event seeding
      mix seed.clean --only events --force && mix seed.dev --only events

      # Clean polls to test poll generation
      mix seed.clean --only polls --force

      # Selective cleanup before adding more data
      mix seed.clean --only activities,polls --force
      mix seed.dev --append --only polls,activities

      # Interactive cleanup (confirms before deleting)
      mix seed.clean

      # Script-friendly cleanup (no prompts)
      mix seed.clean --force

  ## Cleaning Order (Automatic Dependency Management)

  When cleaning "all" entities, deletion happens in this order:

  1. **Activities** - No dependencies, can be deleted first
  2. **Polls** - Votes → Options → Polls (sub-dependency order handled automatically)
  3. **Events** - Triggers cascading deletion of participants, event_users, event_tags
  4. **Groups** - Group memberships deleted first, then groups
  5. **Venues** - Can be deleted after events are removed
  6. **Users** - Deleted last (preserves system accounts: admin@, demo@)

  This order ensures no foreign key constraint violations occur during cleanup.

  ## Safety Mechanisms

  ### 1. Environment Restriction
  Task will **fail immediately** if run outside development environment:
  ```
  ** (Mix.Error) This task should only be run in development environment!
  ```

  ### 2. Confirmation Prompt (unless --force)
  Interactive confirmation prevents accidental data loss:
  ```
  ⚠️  This will DELETE data from your development database!
  Entities to clean: ["all"]

  Are you sure you want to continue? [Yn]
  ```

  ### 3. System Account Preservation
  System accounts are **always preserved** during user cleanup:
  - `admin@example.com` - Admin test account
  - `demo@example.com` - Demo test account

  ### 4. Cascade Awareness
  The task leverages database foreign key cascades for efficiency:
  - Deleting events automatically removes: participants, event_users, event_tags
  - No need to manually clean child records

  ## Troubleshooting

  ### "This task should only be run in development environment!"

  **Cause**: Trying to run in production or test environment

  **Solution**: Ensure you're in development:
  ```bash
  MIX_ENV=dev mix seed.clean
  ```

  ### Foreign Key Constraint Violations

  **Cause**: Manual entity deletion in wrong order

  **Solution**: Use `mix seed.clean` without `--only` to clean in correct order, or
  specify entities in reverse dependency order:
  ```bash
  mix seed.clean --only activities,polls,events,groups,venues,users
  ```

  ### "Unknown entity type" Warning

  **Cause**: Typo in `--only` parameter

  **Solution**: Check spelling against Available Entity Types list above

  ### Need to Keep Specific Data

  **Cause**: Want to clean some data but keep others

  **Solution**: Use `--only` to selectively clean:
  ```bash
  # Keep users and groups, clean events and polls
  mix seed.clean --only events,polls,activities --force
  ```

  ## Related Commands

  - `mix seed.dev` - Seed development data (use `--append` to add without cleaning)
  - `mix seed.dev --append` - Add more seed data without cleaning first
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
  2. Parses command-line options (`--only`, `--force`)
  3. Starts the application
  4. Determines entity list (specific or all)
  5. Prompts for confirmation (unless `--force`)
  6. Deletes entities in dependency order
  7. Reports deletion counts per entity

  ## Examples

      # Standard development reset
      mix seed.clean --force && mix seed.dev

      # Quick event testing iteration
      mix seed.clean --only events --force && mix seed.dev --only events --events 10

      # Clean polls to regenerate with different parameters
      mix seed.clean --only polls --force

      # Interactive cleanup (confirm before deletion)
      mix seed.clean

      # Automated script cleanup
      mix seed.clean --force

      # Clean specific entities for targeted testing
      mix seed.clean --only activities,polls --force

      # Full reset with specific seed quantities
      mix seed.clean --force && mix seed.dev --users 50 --events 100

      # Clean everything except users (preserve test accounts)
      mix seed.clean --only activities,polls,events,groups,venues --force

  ## Performance Tips

  - Use `--force` in automated scripts to avoid prompts
  - Use `--only` to clean only what you need (faster than full cleanup)
  - Combine with `mix seed.dev --only` for targeted testing
  - Leverage cascade deletions - no need to manually clean child records
  - Delete in dependency order when using `--only` with multiple entities

  ## See Also

  - Mix task source code at `lib/mix/tasks/seed.clean.ex`
  - Issue #2239 for full seeding system documentation
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
