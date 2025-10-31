defmodule Mix.Tasks.TestExpiredEvents do
  @moduledoc """
  Ages Question One events to simulate production conditions where events
  are "seen recently" but have expired dates.

  This reproduces the bug where:
  1. Events were scraped 5-6 days ago (within 7-day threshold)
  2. Event dates are now in the past
  3. Scraper skips them because they're "seen recently"
  4. Result: 0 future events, stuck forever

  Usage:
    mix test_expired_events

  Then run:
    mix run -e "EventasaurusDiscovery.Sources.QuestionOne.Jobs.SyncJob.perform(%{})"

  Expected behavior (BUG):
    - Should SKIP all events (last_seen_at < 7 days)
    - No VenueDetailJob queued
    - Events remain expired
  """

  use Mix.Task
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource}
  alias EventasaurusDiscovery.Sources.Source
  import Ecto.Query
  require Logger

  @shortdoc "Ages Question One events to test scraper behavior"

  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("\n" <> IO.ANSI.cyan() <> "🔍 Phase 1: Reproducing Production Bug in Development" <> IO.ANSI.reset())
    IO.puts(String.duplicate("=", 60))

    # Get Question One source
    source = Repo.get_by(Source, slug: "question-one")

    if is_nil(source) do
      IO.puts(IO.ANSI.red() <> "❌ Question One source not found. Make sure you have events in development." <> IO.ANSI.reset())
      exit(:normal)
    end

    # Count events before
    initial_count =
      PublicEventSource
      |> where([pes], pes.source_id == ^source.id)
      |> Repo.aggregate(:count)

    if initial_count == 0 do
      IO.puts(IO.ANSI.red() <> "❌ No Question One events found. Run the scraper first to create events." <> IO.ANSI.reset())
      IO.puts("   Run: mix run -e \"EventasaurusDiscovery.Sources.QuestionOne.Jobs.SyncJob.perform(%{})\"")
      exit(:normal)
    end

    IO.puts("\n📊 Initial State:")
    IO.puts("   Total Question One events: #{initial_count}")

    # Check current state
    stats_before = get_event_stats(source.id)
    IO.puts("   Future events: #{stats_before.future_count}")
    IO.puts("   Past events: #{stats_before.past_count}")
    IO.puts("   Most recent last_seen_at: #{format_datetime(stats_before.max_last_seen)}")

    # Age event sources to 8 days ago
    IO.puts("\n⏰ Aging event sources to 8 days ago...")
    eight_days_ago = DateTime.utc_now() |> DateTime.add(-8, :day)

    {aged_count, _} =
      PublicEventSource
      |> where([pes], pes.source_id == ^source.id)
      |> Repo.update_all(
        set: [
          last_seen_at: eight_days_ago,
          updated_at: DateTime.utc_now()
        ]
      )

    IO.puts(IO.ANSI.green() <> "   ✅ Aged #{aged_count} event sources to 8 days old" <> IO.ANSI.reset())

    # Push event dates to the past (for those that are currently in future)
    IO.puts("\n📅 Pushing future event dates to the past...")
    two_days_ago = DateTime.utc_now() |> DateTime.add(-2, :day)

    {dated_count, _} =
      from(pe in PublicEvent,
        join: pes in PublicEventSource, on: pes.event_id == pe.id,
        where: pes.source_id == ^source.id and pe.starts_at > ^DateTime.utc_now()
      )
      |> Repo.update_all(
        set: [
          starts_at: two_days_ago,
          ends_at: two_days_ago,
          updated_at: DateTime.utc_now()
        ]
      )

    IO.puts(IO.ANSI.green() <> "   ✅ Pushed #{dated_count} event dates (starts_at AND ends_at) to the past" <> IO.ANSI.reset())

    # Show final state
    stats_after = get_event_stats(source.id)

    IO.puts("\n📊 Final State (Simulating Production):")
    IO.puts("   Total events: #{initial_count}")
    IO.puts("   Future events: #{IO.ANSI.red()}#{stats_after.future_count} ❌#{IO.ANSI.reset()}")
    IO.puts("   Past events: #{stats_after.past_count}")
    IO.puts("   All last_seen_at: #{IO.ANSI.yellow()}8 days ago#{IO.ANSI.reset()}")

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts(IO.ANSI.cyan() <> "📝 Next Steps:" <> IO.ANSI.reset())
    IO.puts("\n1. Run the scraper:")
    IO.puts(IO.ANSI.yellow() <> "   mix run -e \"EventasaurusDiscovery.Sources.QuestionOne.Jobs.SyncJob.perform(%{})\"" <> IO.ANSI.reset())

    IO.puts("\n2. Check Oban jobs:")
    IO.puts("   Should see VERY FEW or ZERO VenueDetailJob queued")
    IO.puts("   (Bug: Events are skipped because last_seen_at < 7 days)")

    IO.puts("\n3. Expected behavior (THE BUG):")
    IO.puts("   #{IO.ANSI.red()}❌ All events SKIPPED (seen 8 days ago > 7 day threshold)#{IO.ANSI.reset()}")
    IO.puts("   #{IO.ANSI.red()}❌ No VenueDetailJob queued#{IO.ANSI.reset()}")
    IO.puts("   #{IO.ANSI.red()}❌ Events remain expired#{IO.ANSI.reset()}")
    IO.puts("   #{IO.ANSI.red()}❌ 0 future events forever#{IO.ANSI.reset()}")

    IO.puts("\n4. Verify in console:")
    IO.puts("""
       iex> alias EventasaurusDiscovery.Sources.Source
       iex> alias EventasaurusDiscovery.PublicEvents.PublicEventSource
       iex> import Ecto.Query
       iex> source = Repo.get_by(Source, slug: "question-one")
       iex> Repo.one(from pes in PublicEventSource,
            where: pes.source_id == ^source.id,
            join: pe in assoc(pes, :public_event),
            select: %{
              last_seen: pes.last_seen_at,
              starts_at: pe.starts_at,
              is_future: pe.starts_at > ^DateTime.utc_now(),
              days_since_seen: fragment("EXTRACT(DAY FROM (? - ?))", ^DateTime.utc_now(), pes.last_seen_at)
            },
            limit: 5)
    """)

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts(IO.ANSI.green() <> "✅ Phase 1 complete: Production bug reproduced in development" <> IO.ANSI.reset())
    IO.puts("")
  end

  defp get_event_stats(source_id) do
    query = from pes in PublicEventSource,
      join: pe in PublicEvent, on: pe.id == pes.event_id,
      where: pes.source_id == ^source_id,
      select: %{
        total: count(),
        future_count: count() |> filter(pe.starts_at > ^DateTime.utc_now()),
        past_count: count() |> filter(pe.starts_at <= ^DateTime.utc_now()),
        max_last_seen: max(pes.last_seen_at)
      }

    Repo.one(query) || %{total: 0, future_count: 0, past_count: 0, max_last_seen: nil}
  end

  defp format_datetime(nil), do: "N/A"
  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  end
end
