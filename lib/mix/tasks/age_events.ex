defmodule Mix.Tasks.AgeEvents do
  @moduledoc """
  Ages Question One events to expired state for testing RecurringEventUpdater.

  This allows you to repeatedly test the scraper integration by:
  1. Aging events to expired state
  2. Running the scraper manually
  3. Observing automatic date regeneration

  Usage:
    # Age all Question One events
    mix age_events

    # Age specific number of events
    mix age_events --limit 5

    # Age specific event IDs
    mix age_events --ids 54,192,193

    # Age to different days ago
    mix age_events --days-ago 10
  """

  use Mix.Task
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource}
  alias EventasaurusDiscovery.Sources.Source
  import Ecto.Query
  require Logger

  @shortdoc "Ages events to expired state for testing"

  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)
    limit = opts[:limit]
    days_ago = opts[:days_ago] || 8
    event_ids = opts[:ids]

    IO.puts("\n" <> IO.ANSI.cyan() <> "⏰ Aging Question One Events" <> IO.ANSI.reset())
    IO.puts(String.duplicate("=", 60))

    # Get Question One source
    source = Repo.get_by(Source, slug: "question-one")

    if is_nil(source) do
      IO.puts(IO.ANSI.red() <> "❌ Question One source not found!" <> IO.ANSI.reset())
      exit(:normal)
    end

    # Build base query
    base_query =
      from(pe in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == pe.id,
        where: pes.source_id == ^source.id,
        order_by: [asc: pe.id]
      )

    # Apply filters
    query =
      cond do
        event_ids ->
          from(pe in base_query, where: pe.id in ^event_ids)

        limit ->
          from(pe in base_query, limit: ^limit)

        true ->
          base_query
      end

    # Get events to age
    events =
      query
      |> select([pe], %{id: pe.id, title: pe.title, starts_at: pe.starts_at})
      |> Repo.all()

    if Enum.empty?(events) do
      IO.puts(IO.ANSI.yellow() <> "⚠️  No events found to age!" <> IO.ANSI.reset())
      exit(:normal)
    end

    IO.puts("\n📊 Will age #{length(events)} events to #{days_ago} days ago:")

    Enum.each(events, fn event ->
      IO.puts("   - Event ##{event.id}: #{String.slice(event.title, 0, 50)}")
    end)

    IO.puts("\nProceed? [y/N]: ")
    response = IO.gets("") |> String.trim() |> String.downcase()

    if response != "y" do
      IO.puts("❌ Cancelled")
      exit(:normal)
    end

    # Calculate dates
    n_days_ago = DateTime.utc_now() |> DateTime.add(-days_ago, :day)
    expired_date = DateTime.utc_now() |> DateTime.add(-2, :day)

    event_ids = Enum.map(events, & &1.id)

    # Age last_seen_at
    {aged_sources, _} =
      from(pes in PublicEventSource,
        join: pe in PublicEvent,
        on: pes.event_id == pe.id,
        where: pe.id in ^event_ids
      )
      |> Repo.update_all(
        set: [
          last_seen_at: n_days_ago,
          updated_at: DateTime.utc_now()
        ]
      )

    # Age event dates
    {aged_events, _} =
      from(pe in PublicEvent,
        where: pe.id in ^event_ids
      )
      |> Repo.update_all(
        set: [
          starts_at: expired_date,
          ends_at: expired_date,
          updated_at: DateTime.utc_now()
        ]
      )

    IO.puts("\n✅ Aged #{aged_sources} event sources to #{days_ago} days ago")
    IO.puts("✅ Aged #{aged_events} event dates to 2 days ago (EXPIRED)")

    # Show results
    IO.puts("\n📊 Current state:")

    current =
      from(pe in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == pe.id,
        where: pe.id in ^event_ids,
        select: %{
          id: pe.id,
          title: pe.title,
          starts_at: pe.starts_at,
          last_seen_at: pes.last_seen_at
        },
        order_by: [asc: pe.id]
      )
      |> Repo.all()

    Enum.each(current, fn event ->
      IO.puts("   - Event ##{event.id}: #{String.slice(event.title, 0, 50)}")
      IO.puts("     starts_at: #{event.starts_at} (EXPIRED)")
      IO.puts("     last_seen_at: #{event.last_seen_at} (#{days_ago} days ago)")
    end)

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts(IO.ANSI.yellow() <> "🔄 Next Steps:" <> IO.ANSI.reset())
    IO.puts("\n1. Trigger Question One scraper:")
    IO.puts("   " <> IO.ANSI.cyan() <> "mix run /tmp/trigger_qo_scraper.exs" <> IO.ANSI.reset())
    IO.puts("\n2. Wait ~30 seconds, then check results:")

    IO.puts(
      "   " <>
        IO.ANSI.cyan() <> "mix check_events #{Enum.join(event_ids, ",")}" <> IO.ANSI.reset()
    )

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts(IO.ANSI.green() <> "\n✅ Events aged successfully!" <> IO.ANSI.reset())
    IO.puts("")
  end

  defp parse_args(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [limit: :integer, days_ago: :integer, ids: :string],
        aliases: [l: :limit, d: :days_ago, i: :ids]
      )

    # Parse comma-separated IDs
    opts =
      if ids_str = opts[:ids] do
        ids = String.split(ids_str, ",") |> Enum.map(&String.to_integer/1)
        Keyword.put(opts, :ids, ids)
      else
        opts
      end

    opts
  end
end
