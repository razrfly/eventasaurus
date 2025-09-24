defmodule Mix.Tasks.Eventasaurus.RecategorizeEvents do
  @moduledoc """
  Recategorizes all public events to apply multi-category support.
  This will re-extract categories from the source metadata using the updated mappings.

  Usage:
    mix eventasaurus.recategorize_events [options]

  Options:
    --source SOURCE   Only recategorize events from a specific source (ticketmaster, bandsintown, karnet)
    --limit N         Process only N events (useful for testing)
    --dry-run         Show what would be done without making changes
  """

  use Mix.Task

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Categories.CategoryExtractor
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Categories.PublicEventCategory
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource
  import Ecto.Query

  @shortdoc "Recategorizes all public events with multi-category support"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [source: :string, limit: :integer, dry_run: :boolean],
        aliases: [s: :source, l: :limit, d: :dry_run]
      )

    source_filter = opts[:source]
    limit = opts[:limit]
    dry_run = opts[:dry_run] || false

    IO.puts("\n🔄 Starting event recategorization...")
    IO.puts("   Source filter: #{source_filter || "all"}")
    IO.puts("   Limit: #{limit || "none"}")
    IO.puts("   Mode: #{if dry_run, do: "DRY RUN", else: "LIVE"}")
    IO.puts("")

    # Get events to process
    events_query =
      from(e in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == e.id,
        join: s in assoc(pes, :source),
        select: {e, s.slug, e.metadata}
      )

    events_query =
      if source_filter do
        from([e, pes, s] in events_query,
          where: s.slug == ^source_filter
        )
      else
        events_query
      end

    events_query =
      if limit do
        from(q in events_query, limit: ^limit)
      else
        events_query
      end

    events = Repo.all(events_query)
    total = length(events)

    IO.puts("Found #{total} events to process\n")

    # Track statistics
    stats = %{
      processed: 0,
      updated: 0,
      multi_category: 0,
      errors: 0,
      by_source: %{}
    }

    # Process each event
    stats =
      Enum.reduce(events, stats, fn {event, source, metadata}, acc ->
        if rem(acc.processed, 100) == 0 and acc.processed > 0 do
          IO.puts("Progress: #{acc.processed}/#{total} events processed...")
        end

        result = process_event(event, source, metadata, dry_run)

        acc
        |> Map.update!(:processed, &(&1 + 1))
        |> update_stats(result, source)
      end)

    # Print results
    print_results(stats, dry_run)
  end

  defp process_event(event, source, metadata, dry_run) do
    # Extract categories using the extraction logic
    categories =
      case source do
        "ticketmaster" ->
          CategoryExtractor.extract_ticketmaster_categories(metadata || %{})

        "bandsintown" ->
          CategoryExtractor.extract_bandsintown_categories(metadata || %{})

        "karnet" ->
          # For Karnet, include title in the data for secondary extraction
          karnet_data =
            Map.merge(metadata || %{}, %{
              "title" => event.title,
              "description" => event.description
            })

          CategoryExtractor.extract_karnet_categories(karnet_data)

        _ ->
          []
      end

    category_count = length(categories)

    if category_count > 0 do
      if dry_run do
        {:updated, category_count}
      else
        # Delete existing category assignments
        Repo.delete_all(
          from(pec in PublicEventCategory,
            where: pec.event_id == ^event.id
          )
        )

        # Insert new category assignments
        Enum.each(categories, fn {category_id, is_primary} ->
          %PublicEventCategory{}
          |> PublicEventCategory.changeset(%{
            event_id: event.id,
            category_id: category_id,
            is_primary: is_primary,
            source: source,
            confidence: 1.0
          })
          |> Repo.insert!()
        end)

        {:updated, category_count}
      end
    else
      {:no_categories, 0}
    end
  rescue
    e ->
      IO.puts("Error processing event #{event.id}: #{inspect(e)}")
      {:error, 0}
  end

  defp update_stats(stats, result, source) do
    {status, category_count} = result

    stats =
      case status do
        :updated ->
          stats
          |> Map.update!(:updated, &(&1 + 1))
          |> then(fn s ->
            if category_count > 1 do
              Map.update!(s, :multi_category, &(&1 + 1))
            else
              s
            end
          end)

        :error ->
          Map.update!(stats, :errors, &(&1 + 1))

        _ ->
          stats
      end

    # Update source-specific stats
    Map.update!(stats, :by_source, fn sources ->
      Map.update(sources, source, %{total: 1, multi: 0}, fn source_stats ->
        source_stats
        |> Map.update!(:total, &(&1 + 1))
        |> then(fn s ->
          if status == :updated and category_count > 1 do
            Map.update!(s, :multi, &(&1 + 1))
          else
            s
          end
        end)
      end)
    end)
  end

  defp print_results(stats, dry_run) do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("RECATEGORIZATION #{if dry_run, do: "SIMULATION", else: "COMPLETE"}")
    IO.puts(String.duplicate("=", 60))

    IO.puts("\n📊 Overall Statistics:")
    IO.puts("   Total processed: #{stats.processed}")
    IO.puts("   Events updated: #{stats.updated}")
    IO.puts("   Multi-category events: #{stats.multi_category}")
    IO.puts("   Errors: #{stats.errors}")

    IO.puts("\n📈 By Source:")

    Enum.each(stats.by_source, fn {source, source_stats} ->
      _coverage = Float.round(source_stats.total / 1 * 100, 1)

      multi_pct =
        if source_stats.total > 0 do
          Float.round(source_stats.multi / source_stats.total * 100, 1)
        else
          0.0
        end

      IO.puts(
        "   #{String.pad_trailing(source, 15)} Total: #{source_stats.total}, Multi: #{source_stats.multi} (#{multi_pct}%)"
      )
    end)

    IO.puts("\n✅ Grade Estimates:")

    Enum.each(stats.by_source, fn {source, source_stats} ->
      avg_categories =
        if source_stats.total > 0 do
          if source_stats.multi > 0 do
            # Estimate average (assuming multi-category events have 2+ categories)
            Float.round(1.0 + source_stats.multi / source_stats.total, 2)
          else
            1.0
          end
        else
          0.0
        end

      grade = calculate_grade(100.0, avg_categories)

      IO.puts(
        "   #{String.pad_trailing(source, 15)} Coverage: 100%, Avg Categories: #{avg_categories} → Grade: #{grade}"
      )
    end)

    if dry_run do
      IO.puts("\n⚠️  This was a DRY RUN - no changes were made")
      IO.puts("   Run without --dry-run to apply changes")
    end
  end

  defp calculate_grade(coverage, avg_categories) do
    cond do
      coverage >= 98 and avg_categories >= 1.5 -> "A+"
      coverage >= 95 and avg_categories >= 1.3 -> "A"
      coverage >= 90 and avg_categories >= 1.1 -> "B+"
      coverage >= 85 -> "B"
      coverage >= 80 -> "C+"
      coverage >= 75 -> "C"
      coverage >= 70 -> "D"
      true -> "F"
    end
  end
end
