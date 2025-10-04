defmodule Mix.Tasks.Bandsintown.TestAsync do
  @moduledoc """
  Test task for the new asynchronous Bandsintown scraping architecture.

  Usage:
    mix bandsintown.test_async [--limit 10] [--max-pages 2]
  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.{City, Country}

  @shortdoc "Test the asynchronous Bandsintown scraping architecture"

  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    # Parse arguments
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [limit: :integer, max_pages: :integer],
        aliases: [l: :limit, p: :max_pages]
      )

    limit = opts[:limit] || 10
    max_pages = opts[:max_pages] || 2

    Logger.info("""

    ====================================
    🎵 Testing Asynchronous Bandsintown Scraping
    ====================================
    Limit: #{limit} events
    Max pages: #{max_pages}
    """)

    # Get or create Poland and Kraków
    poland = get_or_create_poland()
    krakow = get_or_create_krakow(poland)

    # Create job args
    job_args = %{
      "city_id" => krakow.id,
      "limit" => limit,
      "max_pages" => max_pages
    }

    Logger.info("📋 Job args: #{inspect(job_args)}")

    # Enqueue the sync job
    case EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob.new(job_args)
         |> Oban.insert() do
      {:ok, job} ->
        Logger.info("""

        ✅ Sync job enqueued successfully!
        Job ID: #{job.id}
        Queue: #{job.queue}

        The job will:
        1. Determine total page count from API (max: #{max_pages})
        2. Schedule IndexPageJobs for each page
        3. Each IndexPageJob will schedule EventDetailJobs
        4. EventDetailJobs process events through unified Processor

        Monitor the logs to see the asynchronous processing in action.
        """)

        # Wait a moment to see if job starts
        Process.sleep(2000)

        # Check Oban job counts
        check_job_counts()

        # Wait a bit more to check for events
        Process.sleep(10000)

        # Check for recently created events
        check_recent_events()

      {:error, reason} ->
        Logger.error("❌ Failed to enqueue job: #{inspect(reason)}")
    end
  end

  defp get_or_create_poland do
    # First try to get existing
    case Repo.get_by(Country, code: "PL") do
      nil ->
        # Create new if doesn't exist
        %Country{}
        |> Country.changeset(%{
          name: "Poland",
          code: "PL",
          slug: "poland"
        })
        |> Repo.insert!()

      country ->
        country
    end
  end

  defp get_or_create_krakow(poland) do
    # First try to get existing
    case Repo.get_by(City, name: "Kraków", country_id: poland.id) do
      nil ->
        # Create new if doesn't exist
        %City{}
        |> City.changeset(%{
          name: "Kraków",
          country_id: poland.id,
          latitude: Decimal.new("50.0647"),
          longitude: Decimal.new("19.9450")
        })
        |> Repo.insert!()

      city ->
        city
    end
  end

  defp check_job_counts do
    import Ecto.Query

    # Count jobs by state and queue
    query =
      from(j in Oban.Job,
        group_by: [j.state, j.queue],
        select: {j.state, j.queue, count(j.id)}
      )

    results = Repo.all(query)

    Logger.info("""

    📊 Current Oban Job Status:
    ================================
    """)

    results
    |> Enum.group_by(fn {state, _, _} -> state end)
    |> Enum.each(fn {state, jobs} ->
      Logger.info("#{String.upcase(to_string(state))}:")

      Enum.each(jobs, fn {_, queue, count} ->
        Logger.info("  #{queue}: #{count} jobs")
      end)
    end)

    # Specifically check for our new queues
    scraper_index_count =
      results
      |> Enum.filter(fn {_, queue, _} -> queue == "scraper_index" end)
      |> Enum.map(fn {_, _, count} -> count end)
      |> Enum.sum()

    scraper_detail_count =
      results
      |> Enum.filter(fn {_, queue, _} -> queue == "scraper_detail" end)
      |> Enum.map(fn {_, _, count} -> count end)
      |> Enum.sum()

    Logger.info("""

    🎯 Target Queues:
    - scraper_index: #{scraper_index_count} jobs
    - scraper_detail: #{scraper_detail_count} jobs

    If you see jobs in scraper_index queue, the async architecture is working!
    """)
  end

  defp check_recent_events do
    import Ecto.Query

    # Check for recently created events from Bandsintown
    recent_cutoff = DateTime.utc_now() |> DateTime.add(-60, :second)

    query =
      from(pes in EventasaurusDiscovery.PublicEvents.PublicEventSource,
        join: s in EventasaurusDiscovery.Sources.Source,
        on: s.id == pes.source_id,
        where: s.slug == "bandsintown",
        where: pes.inserted_at > ^recent_cutoff,
        select: {pes.external_id, pes.inserted_at}
      )

    results = Repo.all(query)

    if length(results) > 0 do
      Logger.info("""

      🎉 SUCCESS! Found #{length(results)} recently created Bandsintown events:
      """)

      Enum.each(results, fn {external_id, inserted_at} ->
        Logger.info("  - #{external_id} (created #{inserted_at})")
      end)
    else
      Logger.warning("""

      ⚠️ No new Bandsintown events found in the last 60 seconds.
      This is normal if jobs are still processing.
      Check the logs above for any errors.
      """)
    end
  end
end
