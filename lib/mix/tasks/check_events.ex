defmodule Mix.Tasks.CheckEvents do
  @moduledoc """
  Checks the current state of Question One events.

  Shows event dates, last_seen_at, and whether they're in the future.
  Useful for verifying RecurringEventUpdater after running scraper.

  Usage:
    # Check all Question One events
    mix check_events

    # Check specific events
    mix check_events 54,192,193,194,195

    # Check with detailed pattern info
    mix check_events --verbose
  """

  use Mix.Task
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource}
  alias EventasaurusDiscovery.Sources.Source
  import Ecto.Query
  require Logger

  @shortdoc "Checks current state of Question One events"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, event_ids_args, _} =
      OptionParser.parse(args,
        switches: [verbose: :boolean],
        aliases: [v: :verbose]
      )

    verbose = opts[:verbose] || false

    # Parse event IDs from args
    event_ids =
      if length(event_ids_args) > 0 do
        event_ids_args
        |> Enum.flat_map(&String.split(&1, ","))
        |> Enum.map(&String.to_integer/1)
      else
        nil
      end

    IO.puts("\n" <> IO.ANSI.cyan() <> "🔍 Checking Question One Events" <> IO.ANSI.reset())
    IO.puts(String.duplicate("=", 60))

    # Get Question One source
    source = Repo.get_by(Source, slug: "question-one")

    if is_nil(source) do
      IO.puts(IO.ANSI.red() <> "❌ Question One source not found!" <> IO.ANSI.reset())
      exit(:normal)
    end

    # Build query
    base_query =
      from(pe in PublicEvent,
        join: pes in PublicEventSource, on: pes.event_id == pe.id,
        where: pes.source_id == ^source.id,
        order_by: [asc: pe.id]
      )

    query =
      if event_ids do
        from(pe in base_query, where: pe.id in ^event_ids)
      else
        from(pe in base_query, limit: 20)
      end

    # Get events
    events =
      query
      |> select([pe, pes], %{
        id: pe.id,
        title: pe.title,
        starts_at: pe.starts_at,
        ends_at: pe.ends_at,
        last_seen_at: pes.last_seen_at,
        updated_at: pe.updated_at,
        occurrences: pe.occurrences
      })
      |> Repo.all()

    if Enum.empty?(events) do
      IO.puts(IO.ANSI.yellow() <> "⚠️  No events found!" <> IO.ANSI.reset())
      exit(:normal)
    end

    now = DateTime.utc_now()

    IO.puts("\n📊 Found #{length(events)} events:\n")

    # Summary counts
    future_count = Enum.count(events, fn e -> DateTime.compare(e.starts_at, now) == :gt end)
    expired_count = Enum.count(events, fn e -> DateTime.compare(e.starts_at, now) != :gt end)

    IO.puts("   Future events: #{future_count}")
    IO.puts("   Expired events: #{expired_count}\n")

    # Show each event
    Enum.each(events, fn event ->
      is_future = DateTime.compare(event.starts_at, now) == :gt
      status_icon = if is_future, do: "✅", else: "❌"

      IO.puts("#{status_icon} Event ##{event.id}: #{String.slice(event.title, 0, 50)}")
      IO.puts("   starts_at: #{event.starts_at} " <> if(is_future, do: "(FUTURE)", else: "(EXPIRED)"))
      IO.puts("   ends_at: #{event.ends_at}")
      IO.puts("   last_seen_at: #{event.last_seen_at}")

      if verbose && event.occurrences do
        pattern = event.occurrences["pattern"]

        if pattern do
          IO.puts("   Pattern:")
          IO.puts("     - frequency: #{pattern["frequency"]}")
          IO.puts("     - days_of_week: #{inspect(pattern["days_of_week"])}")
          IO.puts("     - time: #{pattern["time"]}")
          IO.puts("     - timezone: #{pattern["timezone"]}")
        end
      end

      IO.puts("")
    end)

    IO.puts(String.duplicate("=", 60))

    if expired_count > 0 do
      IO.puts(
        IO.ANSI.yellow() <>
          "\n⚠️  #{expired_count} events have expired dates!" <> IO.ANSI.reset()
      )

      IO.puts("\n💡 To regenerate dates:")
      IO.puts("   1. Run scraper: " <> IO.ANSI.cyan() <> "mix run /tmp/trigger_qo_scraper.exs" <> IO.ANSI.reset())
      IO.puts("   2. Wait ~30 seconds")
      IO.puts("   3. Check again: " <> IO.ANSI.cyan() <> "mix check_events" <> IO.ANSI.reset())
    else
      IO.puts(IO.ANSI.green() <> "\n✅ All events have future dates!" <> IO.ANSI.reset())
    end

    IO.puts("")
  end
end
