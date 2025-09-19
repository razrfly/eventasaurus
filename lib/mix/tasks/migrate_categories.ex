defmodule Mix.Tasks.MigrateCategories do
  @moduledoc """
  One-time migration task to assign categories to existing events using the new multi-category system.

  Usage:
    mix migrate_categories        # Migrate all events
    mix migrate_categories --dry  # Dry run to see what would happen
  """

  use Mix.Task
  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Categories.CategoryExtractor

  @shortdoc "Migrate existing events to use the new multi-category system"

  def run(args) do
    Mix.Task.run("app.start")

    dry_run = "--dry" in args

    IO.puts("\n🔄 Starting category migration#{if dry_run, do: " (DRY RUN)", else: ""}...")

    # Get all events
    events = Repo.all(
      from pe in PublicEvent,
      where: not is_nil(pe.external_id),
      preload: [:categories]
    )

    IO.puts("Found #{length(events)} events to process\n")

    stats = %{
      ticketmaster: 0,
      karnet: 0,
      bandsintown: 0,
      migrated: 0,
      already_has_categories: 0,
      failed: 0
    }

    updated_stats = Enum.reduce(events, stats, fn event, acc ->
      # Check if event already has categories
      if length(event.categories) > 0 do
        IO.puts("⏭️  Event #{event.id} already has categories, skipping...")
        %{acc | already_has_categories: acc.already_has_categories + 1}
      else
        # Determine source and process
        source = determine_source(event.external_id)

        if dry_run do
          IO.puts("🔍 Would migrate event #{event.id} (#{source}): #{event.title}")
          update_stats(acc, source)
        else
          case migrate_event(event, source) do
            :ok ->
              IO.puts("✅ Migrated event #{event.id} (#{source}): #{event.title}")
              acc
              |> update_stats(source)
              |> Map.update!(:migrated, &(&1 + 1))

            {:error, reason} ->
              IO.puts("❌ Failed to migrate event #{event.id}: #{inspect(reason)}")
              Map.update!(acc, :failed, &(&1 + 1))
          end
        end
      end
    end)

    # Print summary
    IO.puts("\n📊 Migration Summary:")
    IO.puts("  Total events: #{length(events)}")
    IO.puts("  Already had categories: #{updated_stats.already_has_categories}")
    IO.puts("  Ticketmaster events: #{updated_stats.ticketmaster}")
    IO.puts("  Karnet events: #{updated_stats.karnet}")
    IO.puts("  Bandsintown events: #{updated_stats.bandsintown}")

    if not dry_run do
      IO.puts("  Successfully migrated: #{updated_stats.migrated}")
      IO.puts("  Failed: #{updated_stats.failed}")
    end

    IO.puts("\n✨ Migration complete!")
  end

  defp determine_source(external_id) when is_binary(external_id) do
    cond do
      String.starts_with?(external_id, "tm_") -> "ticketmaster"
      String.starts_with?(external_id, "karnet") -> "karnet"
      String.starts_with?(external_id, "bit_") -> "bandsintown"
      true -> "unknown"
    end
  end
  defp determine_source(_), do: "unknown"

  defp update_stats(stats, "ticketmaster"), do: Map.update!(stats, :ticketmaster, &(&1 + 1))
  defp update_stats(stats, "karnet"), do: Map.update!(stats, :karnet, &(&1 + 1))
  defp update_stats(stats, "bandsintown"), do: Map.update!(stats, :bandsintown, &(&1 + 1))
  defp update_stats(stats, _), do: stats

  defp migrate_event(event, "ticketmaster") do
    # For Ticketmaster, we need to use the old category_id as a fallback
    # since we don't have the raw event data anymore
    if event.category_id do
      # Map old category_id to new category
      category_slug = case event.category_id do
        1 -> "conferences"
        2 -> "concerts"
        3 -> "performances"
        4 -> "exhibitions"
        5 -> "film"
        6 -> "festivals"
        _ -> nil
      end

      if category_slug do
        CategoryExtractor.assign_categories_to_event(
          event.id,
          "ticketmaster",
          %{classifications: [%{"segment" => %{"name" => category_slug}}]}
        )
        :ok
      else
        {:error, "Unknown category_id: #{event.category_id}"}
      end
    else
      # Try to infer from title/metadata
      CategoryExtractor.assign_categories_to_event(
        event.id,
        "ticketmaster",
        %{classifications: [%{"segment" => %{"name" => "Music"}}]}
      )
      :ok
    end
  end

  defp migrate_event(event, "karnet") do
    # For Karnet, check metadata or use default
    category = cond do
      String.contains?(String.downcase(event.title || ""), "festiwal") -> "festival"
      String.contains?(String.downcase(event.title || ""), "koncert") -> "koncerty"
      true -> "koncerty"  # Default to concerts
    end

    CategoryExtractor.assign_categories_to_event(
      event.id,
      "karnet",
      %{category: category}
    )
    :ok
  end

  defp migrate_event(event, "bandsintown") do
    # Bandsintown is always concerts
    CategoryExtractor.assign_categories_to_event(
      event.id,
      "bandsintown",
      %{genre: "concert"}
    )
    :ok
  end

  defp migrate_event(_event, _source) do
    {:error, "Unknown source"}
  end
end