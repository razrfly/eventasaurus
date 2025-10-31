defmodule Mix.Tasks.RegenerateRecurringDates do
  @moduledoc """
  Regenerates dates for all expired pattern-based recurring events.

  This is a one-time fix to update all Question One (and other pattern-based)
  events that currently have expired dates but valid recurring patterns.

  Usage:
    mix regenerate_recurring_dates
    mix regenerate_recurring_dates --source=question-one
    mix regenerate_recurring_dates --dry-run
  """

  use Mix.Task
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource}
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Services.RecurringEventUpdater
  import Ecto.Query
  require Logger

  @shortdoc "Regenerates expired recurring event dates from patterns"

  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)
    dry_run = opts[:dry_run]
    source_slug = opts[:source]

    IO.puts("\n" <> IO.ANSI.cyan() <> "🔄 Regenerating Recurring Event Dates" <> IO.ANSI.reset())
    IO.puts(String.duplicate("=", 60))

    if dry_run do
      IO.puts(IO.ANSI.yellow() <> "DRY RUN MODE - No changes will be made" <> IO.ANSI.reset())
    end

    # Build query for expired pattern-based events
    query =
      from pe in PublicEvent,
        where: fragment("?->>'type' = 'pattern'", pe.occurrences),
        where: pe.starts_at < ^DateTime.utc_now()

    # Filter by source if specified
    query =
      if source_slug do
        from pe in query,
          join: pes in PublicEventSource, on: pes.event_id == pe.id,
          join: s in Source, on: pes.source_id == s.id,
          where: s.slug == ^source_slug,
          distinct: true
      else
        query
      end

    events = Repo.all(query)

    IO.puts("\n📊 Found #{length(events)} expired pattern-based events")

    if source_slug do
      IO.puts("   Source filter: #{source_slug}")
    else
      IO.puts("   Source filter: all sources")
    end

    if Enum.empty?(events) do
      IO.puts(IO.ANSI.green() <> "\n✅ No events need regeneration!" <> IO.ANSI.reset())
      exit(:normal)
    end

    IO.puts("\n🔄 Processing events...")

    results =
      events
      |> Enum.with_index(1)
      |> Enum.map(fn {event, index} ->
        IO.write("\r[#{index}/#{length(events)}] #{event.title |> String.slice(0, 50)}")

        if dry_run do
          # Just check what would happen
          case RecurringEventUpdater.calculate_next_occurrence(event.occurrences["pattern"]) do
            {:ok, next_date} ->
              {:ok, event, next_date}

            error ->
              {:error, event, error}
          end
        else
          # Actually regenerate
          case RecurringEventUpdater.maybe_regenerate_dates(event) do
            {:ok, updated} ->
              {:ok, event, updated.starts_at}

            error ->
              {:error, event, error}
          end
        end
      end)

    IO.puts("")

    # Count results
    successes = Enum.count(results, fn {status, _, _} -> status == :ok end)
    failures = Enum.count(results, fn {status, _, _} -> status == :error end)

    IO.puts("\n📊 Results:")
    IO.puts("   ✅ Successfully regenerated: #{successes}")

    if failures > 0 do
      IO.puts("   ❌ Failed: #{failures}")

      IO.puts("\n❌ Failed events:")

      results
      |> Enum.filter(fn {status, _, _} -> status == :error end)
      |> Enum.take(10)
      |> Enum.each(fn {:error, event, reason} ->
        IO.puts("   - Event ##{event.id}: #{event.title}")
        IO.puts("     Reason: #{inspect(reason)}")
      end)
    end

    # Show some examples
    if successes > 0 do
      IO.puts("\n✅ Sample regenerated events:")

      results
      |> Enum.filter(fn {status, _, _} -> status == :ok end)
      |> Enum.take(5)
      |> Enum.each(fn {:ok, event, new_date} ->
        IO.puts("   - #{event.title}")
        IO.puts("     Old: #{event.starts_at} → New: #{new_date}")
      end)
    end

    IO.puts("\n" <> String.duplicate("=", 60))

    if dry_run do
      IO.puts(
        IO.ANSI.yellow() <>
          "✅ Dry run complete - run without --dry-run to apply changes" <> IO.ANSI.reset()
      )
    else
      IO.puts(IO.ANSI.green() <> "✅ Regeneration complete!" <> IO.ANSI.reset())
    end

    IO.puts("")
  end

  defp parse_args(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [dry_run: :boolean, source: :string],
        aliases: [d: :dry_run, s: :source]
      )

    opts
  end
end
