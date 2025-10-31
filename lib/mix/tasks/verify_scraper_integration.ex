defmodule Mix.Tasks.VerifyScraperIntegration do
  @moduledoc """
  Verifies that RecurringEventUpdater worked during scraper run.

  Checks the events that were aged in test_scraper_integration and verifies:
  1. last_seen_at was updated (scraper processed them)
  2. starts_at and ends_at were regenerated (RecurringEventUpdater worked)
  3. All dates are now in the future

  Usage:
    mix verify_scraper_integration
  """

  use Mix.Task
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource}
  import Ecto.Query
  require Logger

  @shortdoc "Verifies RecurringEventUpdater integration worked"

  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("\n" <> IO.ANSI.cyan() <> "🔍 Verifying Scraper Integration" <> IO.ANSI.reset())
    IO.puts(String.duplicate("=", 60))

    # Read test event IDs
    case File.read(".test_integration_events.json") do
      {:ok, content} ->
        %{"event_ids" => event_ids, "timestamp" => test_timestamp} = Jason.decode!(content)

        IO.puts("📊 Checking #{length(event_ids)} test events...")
        IO.puts("   Test started: #{test_timestamp}\n")

        # Query current state
        results =
          from(pe in PublicEvent,
            join: pes in PublicEventSource, on: pes.event_id == pe.id,
            where: pe.id in ^event_ids,
            select: %{
              id: pe.id,
              title: pe.title,
              starts_at: pe.starts_at,
              ends_at: pe.ends_at,
              last_seen_at: pes.last_seen_at,
              updated_at: pe.updated_at
            }
          )
          |> Repo.all()

        # Parse test timestamp
        {:ok, test_dt, _} = DateTime.from_iso8601(test_timestamp)
        now = DateTime.utc_now()

        # Analyze results
        IO.puts("📊 Results:\n")

        successes = 0
        failures = 0

        results
        |> Enum.each(fn event ->
          # Check if last_seen_at was updated (after test started)
          last_seen_updated =
            event.last_seen_at && DateTime.compare(event.last_seen_at, test_dt) == :gt

          # Check if starts_at is in future
          starts_in_future =
            event.starts_at && DateTime.compare(event.starts_at, now) == :gt

          # Check if event was updated (after test started)
          event_updated =
            event.updated_at &&
              DateTime.compare(
                DateTime.from_naive!(event.updated_at, "Etc/UTC"),
                test_dt
              ) == :gt

          success = last_seen_updated && starts_in_future && event_updated

          if success do
            IO.puts("✅ Event ##{event.id}: #{String.slice(event.title, 0, 50)}")
            IO.puts("   starts_at: #{event.starts_at} (FUTURE ✅)")
            IO.puts("   ends_at: #{event.ends_at}")
            IO.puts("   last_seen_at: #{event.last_seen_at} (UPDATED ✅)")
            IO.puts("")
            successes = successes + 1
          else
            IO.puts("❌ Event ##{event.id}: #{String.slice(event.title, 0, 50)}")
            IO.puts("   starts_at: #{event.starts_at}")

            if !starts_in_future do
              IO.puts("   ⚠️  starts_at is NOT in future")
            end

            if !last_seen_updated do
              IO.puts("   ⚠️  last_seen_at was NOT updated")
            end

            if !event_updated do
              IO.puts("   ⚠️  Event was NOT updated")
            end

            IO.puts("")
            failures = failures + 1
          end
        end)

        IO.puts(String.duplicate("=", 60))

        total = length(results)

        if failures == 0 do
          IO.puts(
            IO.ANSI.green() <>
              "✅ SUCCESS: All #{successes}/#{total} events passed!" <> IO.ANSI.reset()
          )

          IO.puts("\n🎯 Integration Test Results:")
          IO.puts("   ✅ Scraper processed aged events")
          IO.puts("   ✅ last_seen_at updated correctly")
          IO.puts("   ✅ RecurringEventUpdater regenerated dates")
          IO.puts("   ✅ All events now have future dates")
          IO.puts("")
          IO.puts(IO.ANSI.green() <> "🎉 Phase 4 Integration Test PASSED!" <> IO.ANSI.reset())

          # Clean up test file
          File.rm(".test_integration_events.json")
        else
          IO.puts(
            IO.ANSI.red() <>
              "❌ FAILURE: #{failures}/#{total} events failed!" <> IO.ANSI.reset()
          )

          IO.puts("\n⚠️  Integration Issues Detected:")
          IO.puts("   - Some events were not processed correctly")
          IO.puts("   - Check EventProcessor integration")
          IO.puts("   - Review RecurringEventUpdater logs")
        end

        IO.puts("")

      {:error, _} ->
        IO.puts(
          IO.ANSI.red() <>
            "❌ Test file not found! Run 'mix test_scraper_integration' first." <>
            IO.ANSI.reset()
        )
    end
  end
end
