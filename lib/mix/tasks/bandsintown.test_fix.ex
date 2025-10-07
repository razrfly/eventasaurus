defmodule Mix.Tasks.Bandsintown.TestFix do
  @moduledoc """
  Test task to verify the Bandsintown scraper fix.

  Usage:
    mix bandsintown.test_fix
  """

  use Mix.Task
  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.{City, Country}

  @shortdoc "Test the Bandsintown scraper fix"

  def run(_args) do
    # Start the application
    Mix.Task.run("app.start")

    Logger.info("""

    ====================================
    🎵 Testing Bandsintown Scraper Fix
    ====================================
    """)

    # Get or create Poland and Kraków
    poland = get_or_create_poland()
    krakow = get_or_create_krakow(poland)

    # Test 1: Test API data transformation
    test_api_transformation()

    # Test 2: Test full sync job
    test_sync_job(krakow)
  end

  defp test_api_transformation do
    Logger.info("📝 Test 1: Testing API data transformation...")

    # Mock API event data (like what we get from the API)
    api_event = %{
      "eventUrl" => "https://www.bandsintown.com/e/107321108",
      "artistName" => "Test Artist",
      "venueName" => "Test Venue",
      "startsAt" => "2025-09-28T13:00:00",
      "title" => "Test Concert",
      "artistImageSrc" => "https://example.com/image.jpg"
    }

    # Transform using Client module
    alias EventasaurusDiscovery.Sources.Bandsintown.Client

    transformed =
      Client.__info__(:functions)
      |> Keyword.has_key?(:transform_api_event)
      |> case do
        true ->
          # Access private function through module
          apply(Client, :transform_api_event, [api_event])

        false ->
          # Call through fetch pipeline
          Logger.warning("Cannot access transform_api_event directly, testing through pipeline")
          nil
      end

    if transformed do
      Logger.info("✅ Transformed event data:")
      Logger.info("  artist_name: #{inspect(transformed["artist_name"])}")
      Logger.info("  venue_name: #{inspect(transformed["venue_name"])}")
      Logger.info("  date: #{inspect(transformed["date"])}")

      # Now test if Transformer can process it
      alias EventasaurusDiscovery.Sources.Bandsintown.Transformer

      case Transformer.transform_event(transformed) do
        {:ok, event} ->
          Logger.info("✅ Transformer successfully processed the event!")
          Logger.info("  Title: #{event.title}")
          Logger.info("  Venue: #{inspect(event.venue_data[:name])}")

        {:error, reason} ->
          Logger.error("❌ Transformer failed: #{reason}")
      end
    end
  end

  defp test_sync_job(krakow) do
    Logger.info("""

    📝 Test 2: Testing full sync job with limit of 5 events...
    """)

    # Create job args
    job_args = %{
      "city_id" => krakow.id,
      "limit" => 5,
      "options" => %{}
    }

    # Enqueue the sync job
    case EventasaurusDiscovery.Sources.Bandsintown.Jobs.SyncJob.new(job_args)
         |> Oban.insert() do
      {:ok, job} ->
        Logger.info("""

        ✅ Sync job enqueued successfully!
        Job ID: #{job.id}
        Queue: #{job.queue}

        The job will fetch up to 5 events from Bandsintown for Kraków.
        Check the logs to see if events are being processed correctly.
        """)

        # Wait a bit to see results
        Process.sleep(5000)

        # Check if any events were created recently
        check_recent_events()

      {:error, reason} ->
        Logger.error("❌ Failed to enqueue job: #{inspect(reason)}")
    end
  end

  defp get_or_create_poland do
    case Repo.get_by(Country, code: "PL") do
      nil ->
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
    case Repo.get_by(City, name: "Kraków", country_id: poland.id) do
      nil ->
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
      Check the logs above for any errors.
      """)
    end
  end
end
