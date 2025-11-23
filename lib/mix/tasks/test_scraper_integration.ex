defmodule Mix.Tasks.TestScraperIntegration do
  @moduledoc """
  Tests the RecurringEventUpdater integration with the scraper.

  This script:
  1. Ages a sample of events to 8 days old (expired)
  2. Provides instructions to run the scraper
  3. Verifies events get regenerated during scraper processing

  Usage:
    mix test_scraper_integration
  """

  use Mix.Task
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource}
  alias EventasaurusDiscovery.Sources.Source
  import Ecto.Query
  require Logger

  @shortdoc "Tests RecurringEventUpdater integration with scraper"

  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("\n" <> IO.ANSI.cyan() <> "🧪 Testing Scraper Integration" <> IO.ANSI.reset())
    IO.puts(String.duplicate("=", 60))

    # Get Question One source
    source = Repo.get_by(Source, slug: "question-one")

    if is_nil(source) do
      IO.puts(IO.ANSI.red() <> "❌ Question One source not found!" <> IO.ANSI.reset())
      exit(:normal)
    end

    # Select 5 sample events to age
    sample_events =
      from(pe in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == pe.id,
        where: pes.source_id == ^source.id,
        order_by: [asc: pe.id],
        limit: 5,
        select: %{id: pe.id, title: pe.title, starts_at: pe.starts_at, ends_at: pe.ends_at}
      )
      |> Repo.all()

    IO.puts("\n📊 Selected #{length(sample_events)} events for testing:")

    Enum.each(sample_events, fn event ->
      IO.puts("   - Event ##{event.id}: #{event.title}")
      IO.puts("     Current: #{event.starts_at}")
    end)

    # Age the events to 8 days old
    eight_days_ago = DateTime.utc_now() |> DateTime.add(-8, :day)
    two_days_ago = DateTime.utc_now() |> DateTime.add(-2, :day)

    event_ids = Enum.map(sample_events, & &1.id)

    # Age last_seen_at
    {aged_count, _} =
      from(pes in PublicEventSource,
        join: pe in PublicEvent,
        on: pes.event_id == pe.id,
        where: pe.id in ^event_ids
      )
      |> Repo.update_all(
        set: [
          last_seen_at: eight_days_ago,
          updated_at: DateTime.utc_now()
        ]
      )

    # Age event dates
    {dated_count, _} =
      from(pe in PublicEvent,
        where: pe.id in ^event_ids
      )
      |> Repo.update_all(
        set: [
          starts_at: two_days_ago,
          ends_at: two_days_ago,
          updated_at: DateTime.utc_now()
        ]
      )

    IO.puts("\n✅ Aged #{aged_count} event sources to 8 days old")
    IO.puts("✅ Aged #{dated_count} event dates to 2 days ago")

    # Show current state
    IO.puts("\n📊 Current state of sample events:")

    current_state =
      from(pe in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == pe.id,
        where: pe.id in ^event_ids,
        select: %{
          id: pe.id,
          title: pe.title,
          starts_at: pe.starts_at,
          last_seen_at: pes.last_seen_at
        }
      )
      |> Repo.all()

    Enum.each(current_state, fn event ->
      IO.puts("   - Event ##{event.id}: #{String.slice(event.title, 0, 50)}")
      IO.puts("     starts_at: #{event.starts_at} (EXPIRED)")
      IO.puts("     last_seen_at: #{event.last_seen_at} (8 days ago)")
    end)

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts(IO.ANSI.yellow() <> "🔄 Next Steps:" <> IO.ANSI.reset())
    IO.puts("\n1. Run the Question One scraper:")
    IO.puts("   " <> IO.ANSI.cyan() <> "mix scraper.run question-one" <> IO.ANSI.reset())
    IO.puts("\n2. After scraper completes, verify integration:")
    IO.puts("   " <> IO.ANSI.cyan() <> "mix verify_scraper_integration" <> IO.ANSI.reset())
    IO.puts("\n" <> String.duplicate("=", 60))

    # Store event IDs for verification later
    File.write!(
      ".test_integration_events.json",
      Jason.encode!(%{event_ids: event_ids, timestamp: DateTime.utc_now()})
    )

    IO.puts(IO.ANSI.green() <> "\n✅ Test setup complete!" <> IO.ANSI.reset())
    IO.puts("")
  end
end
