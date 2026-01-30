defmodule Mix.Tasks.Discovery.TestRecurring do
  @moduledoc """
  Test recurring event date regeneration for pattern-based scrapers.

  This task helps test the RecurringEventUpdater integration by:
  1. Aging events to expired state (last_seen_at and event dates)
  2. Providing instructions to trigger scraper
  3. Verifying automatic date regeneration

  ## Usage

      # Test Question One scraper (default: 5 events)
      mix discovery.test_recurring question-one

      # Test with specific number of events
      mix discovery.test_recurring question-one --limit 10

      # Test with specific event IDs
      mix discovery.test_recurring question-one --ids 54,192,193

      # Age events more days back
      mix discovery.test_recurring question-one --days-ago 10

      # Just verify without aging (after scraper runs)
      mix discovery.test_recurring question-one --verify-only

  ## Supported Scrapers

  Pattern-based scrapers with weekly/monthly recurring events:
    * question-one - Question One trivia nights
    * inquizition - Inquizition trivia events
    * speed-quizzing - Speed Quizzing events
    * pubquiz - PubQuiz events
    * quizmeisters - Quizmeisters trivia
    * geeks-who-drink - Geeks Who Drink pub quizzes

  ## Options

    * `--limit` - Number of events to age (default: 5)
    * `--ids` - Comma-separated event IDs to age
    * `--days-ago` - How many days to age last_seen_at (default: 8)
    * `--verify-only` - Skip aging, just verify current state
    * `--auto-scrape` - Automatically trigger scraper after aging

  ## Examples

      # Basic test
      mix discovery.test_recurring question-one

      # Test with auto-scrape
      mix discovery.test_recurring question-one --auto-scrape

      # Verify results after manual scraper run
      mix discovery.test_recurring question-one --verify-only

      # Test specific events
      mix discovery.test_recurring inquizition --ids 100,101,102
  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource}
  alias EventasaurusDiscovery.Sources.Source
  import Ecto.Query

  @shortdoc "Test recurring event date regeneration"

  @supported_scrapers [
    "question-one",
    "inquizition",
    "speed-quizzing",
    "pubquiz-pl",
    "quizmeisters",
    "geeks-who-drink"
  ]

  def run(args) do
    Application.ensure_all_started(:eventasaurus)

    {scraper_slug, opts} = parse_args(args)

    if scraper_slug not in @supported_scrapers do
      exit_with_error(
        "Unsupported scraper: #{scraper_slug}\nSupported: #{Enum.join(@supported_scrapers, ", ")}"
      )
    end

    if opts[:verify_only] do
      verify_events(scraper_slug, opts)
    else
      age_and_test(scraper_slug, opts)
    end
  end

  defp age_and_test(scraper_slug, opts) do
    limit = opts[:limit] || 5
    days_ago = opts[:days_ago] || 8
    event_ids = opts[:ids]
    auto_scrape = opts[:auto_scrape] || false

    IO.puts(
      "\n" <>
        IO.ANSI.cyan() <> "🧪 Testing RecurringEventUpdater: #{scraper_slug}" <> IO.ANSI.reset()
    )

    IO.puts(String.duplicate("=", 70))

    # Get source
    source = Repo.get_by(Source, slug: scraper_slug)

    if is_nil(source) do
      exit_with_error("Source '#{scraper_slug}' not found in database")
    end

    # Build query
    base_query =
      from(pe in PublicEvent,
        join: pes in PublicEventSource,
        on: pes.event_id == pe.id,
        where: pes.source_id == ^source.id,
        where: fragment("?->>'type' = 'pattern'", pe.occurrences),
        order_by: [asc: pe.id]
      )

    query =
      cond do
        event_ids ->
          from(pe in base_query, where: pe.id in ^event_ids)

        limit ->
          from(pe in base_query, limit: ^limit)

        true ->
          base_query
      end

    # Get events
    events =
      query
      |> select([pe], %{id: pe.id, title: pe.title, starts_at: pe.starts_at})
      |> Repo.all()

    if Enum.empty?(events) do
      exit_with_error("No pattern-based events found for #{scraper_slug}")
    end

    IO.puts("\n📊 Selected #{length(events)} events to age (#{days_ago} days):\n")

    Enum.each(events, fn event ->
      IO.puts("   • Event ##{event.id}: #{String.slice(event.title, 0, 60)}")
      IO.puts("     Current: #{event.starts_at}")
    end)

    IO.puts("")

    # Age events
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

    IO.puts("✅ Aged #{aged_sources} event sources (last_seen_at → #{days_ago} days ago)")
    IO.puts("✅ Aged #{aged_events} event dates (starts_at/ends_at → EXPIRED)\n")

    # Store test metadata
    test_file = ".test_recurring_#{scraper_slug}.json"

    File.write!(
      test_file,
      Jason.encode!(%{
        scraper: scraper_slug,
        event_ids: event_ids,
        timestamp: DateTime.utc_now(),
        days_ago: days_ago
      })
    )

    IO.puts(String.duplicate("=", 70))
    IO.puts(IO.ANSI.yellow() <> "🔄 Next Steps:" <> IO.ANSI.reset() <> "\n")

    if auto_scrape do
      IO.puts("⏳ Auto-triggering scraper...")
      trigger_scraper(scraper_slug, source.id)
      IO.puts("⏳ Waiting 30 seconds for processing...\n")
      Process.sleep(30_000)
      verify_events(scraper_slug, %{event_ids: event_ids, test_file: test_file})
    else
      IO.puts("1. Trigger the #{scraper_slug} scraper manually or via:")
      IO.puts("   " <> IO.ANSI.cyan() <> "mix discovery.sync #{scraper_slug}" <> IO.ANSI.reset())
      IO.puts("")
      IO.puts("2. Wait ~30 seconds for scraper to process events\n")
      IO.puts("3. Verify automatic date regeneration:")

      IO.puts(
        "   " <>
          IO.ANSI.cyan() <>
          "mix discovery.test_recurring #{scraper_slug} --verify-only" <>
          IO.ANSI.reset()
      )

      IO.puts("")
      IO.puts(String.duplicate("=", 70))
      IO.puts(IO.ANSI.green() <> "✅ Events aged! Ready for testing." <> IO.ANSI.reset())
      IO.puts("")
    end
  end

  defp verify_events(scraper_slug, opts) do
    # Read test metadata
    test_file = opts[:test_file] || ".test_recurring_#{scraper_slug}.json"

    case File.read(test_file) do
      {:ok, content} ->
        %{"event_ids" => event_ids, "timestamp" => test_timestamp} = Jason.decode!(content)

        IO.puts(
          "\n" <>
            IO.ANSI.cyan() <>
            "🔍 Verifying RecurringEventUpdater: #{scraper_slug}" <> IO.ANSI.reset()
        )

        IO.puts(String.duplicate("=", 70))
        IO.puts("📊 Test started: #{test_timestamp}")
        IO.puts("📊 Checking #{length(event_ids)} events...\n")

        # Query events
        results =
          from(pe in PublicEvent,
            join: pes in PublicEventSource,
            on: pes.event_id == pe.id,
            join: s in Source,
            on: pes.source_id == s.id,
            where: pe.id in ^event_ids and s.slug == ^scraper_slug,
            select: %{
              id: pe.id,
              title: pe.title,
              starts_at: pe.starts_at,
              ends_at: pe.ends_at,
              last_seen_at: pes.last_seen_at,
              updated_at: pe.updated_at,
              occurrences: pe.occurrences
            },
            order_by: [asc: pe.id]
          )
          |> Repo.all()

        # Parse test timestamp
        {:ok, test_dt, _} = DateTime.from_iso8601(test_timestamp)
        now = DateTime.utc_now()

        # Verify each event
        {successes, failures} =
          Enum.reduce(results, {0, 0}, fn event, {succ, fail} ->
            is_future = event.starts_at && DateTime.compare(event.starts_at, now) == :gt

            was_updated =
              event.last_seen_at && DateTime.compare(event.last_seen_at, test_dt) == :gt

            success = is_future && was_updated

            if success do
              IO.puts("✅ Event ##{event.id}: #{String.slice(event.title, 0, 55)}")
              IO.puts("   starts_at: #{event.starts_at} (FUTURE)")
              IO.puts("   last_seen_at: #{event.last_seen_at} (UPDATED)")

              # Show pattern info
              if pattern = event.occurrences["pattern"] do
                day = hd(pattern["days_of_week"] || ["unknown"])
                time = pattern["time"] || "unknown"
                IO.puts("   pattern: #{pattern["frequency"]} on #{day} at #{time}")
              end

              IO.puts("")
              {succ + 1, fail}
            else
              IO.puts("❌ Event ##{event.id}: #{String.slice(event.title, 0, 55)}")

              IO.puts(
                "   starts_at: #{event.starts_at} " <>
                  if(is_future, do: "(FUTURE)", else: "(EXPIRED)")
              )

              IO.puts(
                "   last_seen_at: #{event.last_seen_at} " <>
                  if(was_updated, do: "(UPDATED)", else: "(NOT UPDATED)")
              )

              unless is_future do
                IO.puts("   ⚠️  dates NOT regenerated")
              end

              unless was_updated do
                IO.puts("   ⚠️  scraper did NOT process event")
              end

              IO.puts("")
              {succ, fail + 1}
            end
          end)

        # Summary
        IO.puts(String.duplicate("=", 70))
        total = successes + failures

        if failures == 0 do
          IO.puts(
            IO.ANSI.green() <>
              "🎉 SUCCESS: All #{successes}/#{total} events passed!" <> IO.ANSI.reset()
          )

          IO.puts("\n✅ RecurringEventUpdater is working correctly!")
          IO.puts("✅ Scraper processed aged events")
          IO.puts("✅ Dates automatically regenerated from patterns")
          IO.puts("✅ All events now have future dates\n")

          # Clean up test file
          File.rm(test_file)
        else
          IO.puts(
            IO.ANSI.red() <> "❌ FAILURE: #{failures}/#{total} events failed" <> IO.ANSI.reset()
          )

          IO.puts("\n⚠️  Some events were not regenerated correctly")
          IO.puts("⚠️  Check EventProcessor integration")
          IO.puts("⚠️  Review logs for errors\n")
        end

      {:error, :enoent} ->
        # No test file - just show current state
        IO.puts("\n" <> IO.ANSI.cyan() <> "📊 Current State: #{scraper_slug}" <> IO.ANSI.reset())
        IO.puts(String.duplicate("=", 70))

        event_ids = opts[:event_ids] || []

        query =
          from(pe in PublicEvent,
            join: pes in PublicEventSource,
            on: pes.event_id == pe.id,
            join: s in Source,
            on: pes.source_id == s.id,
            where: s.slug == ^scraper_slug,
            order_by: [asc: pe.id]
          )

        query =
          if length(event_ids) > 0 do
            from(pe in query, where: pe.id in ^event_ids)
          else
            from(pe in query, limit: 10)
          end

        events =
          query
          |> select([pe, pes], %{id: pe.id, title: pe.title, starts_at: pe.starts_at})
          |> Repo.all()

        now = DateTime.utc_now()
        future_count = Enum.count(events, fn e -> DateTime.compare(e.starts_at, now) == :gt end)
        expired_count = length(events) - future_count

        IO.puts("\n📊 Found #{length(events)} events:")
        IO.puts("   Future: #{future_count}")
        IO.puts("   Expired: #{expired_count}\n")

        if expired_count > 0 do
          IO.puts(IO.ANSI.yellow() <> "⚠️  Some events have expired dates" <> IO.ANSI.reset())
          IO.puts("\nRun scraper to regenerate dates:")

          IO.puts(
            "   " <> IO.ANSI.cyan() <> "mix discovery.sync #{scraper_slug}" <> IO.ANSI.reset()
          )
        else
          IO.puts(IO.ANSI.green() <> "✅ All events have future dates!" <> IO.ANSI.reset())
        end

        IO.puts("")
    end
  end

  defp trigger_scraper(scraper_slug, _source_id) do
    # Map scraper slugs to their sync job modules
    sync_jobs = %{
      "question-one" => EventasaurusDiscovery.Sources.QuestionOne.Jobs.SyncJob,
      "inquizition" => EventasaurusDiscovery.Sources.Inquizition.Jobs.SyncJob,
      "speed-quizzing" => EventasaurusDiscovery.Sources.SpeedQuizzing.Jobs.SyncJob,
      "pubquiz-pl" => EventasaurusDiscovery.Sources.PubquizPl.Jobs.SyncJob,
      "quizmeisters" => EventasaurusDiscovery.Sources.Quizmeisters.Jobs.SyncJob,
      "geeks-who-drink" => EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.SyncJob
    }

    if job_module = sync_jobs[scraper_slug] do
      %{} |> job_module.new() |> Oban.insert()
    end
  end

  defp parse_args([]) do
    exit_with_error("Scraper name required\n\nUsage: mix discovery.test_recurring <scraper-name>")
  end

  defp parse_args([scraper_slug | rest]) do
    {opts, _, _} =
      OptionParser.parse(rest,
        switches: [
          limit: :integer,
          days_ago: :integer,
          ids: :string,
          verify_only: :boolean,
          auto_scrape: :boolean
        ],
        aliases: [l: :limit, d: :days_ago, i: :ids, v: :verify_only, a: :auto_scrape]
      )

    # Parse comma-separated IDs
    opts =
      if ids_str = opts[:ids] do
        ids = String.split(ids_str, ",") |> Enum.map(&String.to_integer/1)
        Keyword.put(opts, :ids, ids)
      else
        opts
      end

    {scraper_slug, opts}
  end

  defp exit_with_error(message) do
    IO.puts(IO.ANSI.red() <> "\n❌ #{message}\n" <> IO.ANSI.reset())
    System.halt(1)
  end
end
