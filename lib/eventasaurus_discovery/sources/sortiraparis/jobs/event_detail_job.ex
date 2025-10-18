defmodule EventasaurusDiscovery.Sources.Sortiraparis.Jobs.EventDetailJob do
  @moduledoc """
  Oban job for fetching and processing individual Sortiraparis event details.

  Scheduled by SyncJob for each fresh event URL discovered in sitemaps.

  ## Responsibilities

  1. Fetch event HTML page
  2. Extract event data (title, dates, venue, description, etc.)
  3. Transform to unified format using Transformer
  4. Process through VenueProcessor (geocoding, deduplication)
  5. Store in database

  ## Bot Protection

  ~30% of requests return 401 errors. Handles:
  - Automatic retry with exponential backoff
  - Rate limiting (5 seconds per request via job scheduling)
  - Future: Playwright fallback for persistent 401s (Phase 4+)

  ## Multi-Date Events

  Events with multiple dates are split into separate DB records:
  - Each date becomes a distinct event instance
  - External ID format: `sortiraparis_{article_id}_{YYYY-MM-DD}`
  - Transformer handles the splitting logic

  ## Phase Status

  **Phase 3**: Skeleton structure (job args, error handling)
  **Phase 4**: Full implementation (HTML extraction, transformation, processing)

  ## Usage

  Jobs are automatically scheduled by SyncJob:

      EventDetailJob.new(%{
        "source" => "sortiraparis",
        "url" => "https://www.sortiraparis.com/articles/319282-indochine",
        "event_metadata" => %{
          "article_id" => "319282",
          "external_id_base" => "sortiraparis_319282"
        }
      })
      |> Oban.insert()
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3,
    priority: 2

  require Logger

  alias EventasaurusDiscovery.Sources.Sortiraparis.{
    Client,
    Transformer
  }

  alias EventasaurusDiscovery.Sources.Sortiraparis.Extractors.{
    EventExtractor,
    VenueExtractor
  }

  alias EventasaurusDiscovery.Scraping.Processors.EventProcessor
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusApp.Repo

  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    url = args["url"]
    event_metadata = args["event_metadata"] || %{}

    Logger.info("🔍 Fetching Sortiraparis event details: #{url}")

    with {:ok, html} <- fetch_event_page(url),
         {:ok, raw_event} <- extract_event_data(html, url, event_metadata),
         {:ok, transformed_events} <- transform_events(raw_event),
         {:ok, processed_count} <- process_events(transformed_events) do
      Logger.info("""
      ✅ Sortiraparis event detail job completed
      URL: #{url}
      Events created: #{processed_count}
      """)

      {:ok,
       %{
         url: url,
         events_created: processed_count,
         article_id: event_metadata["article_id"]
       }}
    else
      {:error, :bot_protection} = error ->
        Logger.warning("🚫 Bot protection 401 on event page: #{url}")
        # TODO Phase 4: Implement Playwright fallback
        error

      {:error, :not_found} = error ->
        Logger.warning("❌ Event page not found: #{url}")
        error

      {:error, reason} = error ->
        Logger.error("❌ Failed to process event #{url}: #{inspect(reason)}")
        error
    end
  end

  # Private functions

  defp fetch_event_page(url) do
    Logger.debug("📄 Fetching event page: #{url}")

    case Client.fetch_page(url) do
      {:ok, html} ->
        Logger.debug("✅ Successfully fetched #{byte_size(html)} bytes")
        {:ok, html}

      {:error, reason} = error ->
        Logger.warning("⚠️ Failed to fetch event page: #{inspect(reason)}")
        error
    end
  end

  defp extract_event_data(html, url, event_metadata) do
    Logger.debug("📄 Extracting event data from HTML page")

    with {:ok, event_data} <- EventExtractor.extract(html, url),
         {:ok, venue_data} <- VenueExtractor.extract(html) do
      # Merge event and venue data
      raw_event =
        Map.merge(event_data, %{
          "url" => url,
          "venue" => venue_data,
          "article_id" => event_metadata["article_id"]
        })

      Logger.debug("✅ Successfully extracted raw event data")
      {:ok, raw_event}
    else
      {:error, reason} = error ->
        Logger.warning("⚠️ Failed to extract event data: #{inspect(reason)}")
        error
    end
  end

  defp transform_events(raw_event) do
    Logger.debug("🔄 Transforming raw event data")

    case Transformer.transform_event(raw_event) do
      {:ok, events} when is_list(events) ->
        Logger.debug("✅ Transformed into #{length(events)} event instance(s)")
        {:ok, events}

      {:error, reason} = error ->
        Logger.warning("⚠️ Failed to transform event: #{inspect(reason)}")
        error
    end
  end

  defp process_events(transformed_events) do
    Logger.debug("💾 Processing #{length(transformed_events)} event(s)")

    # Look up Sortiraparis source by slug
    source = Repo.one(from s in Source, where: s.slug == "sortiraparis")

    if is_nil(source) do
      Logger.error("❌ Sortiraparis source not found in database")
      {:error, :source_not_found}
    else
      processed_count =
      transformed_events
      |> Enum.map(fn event ->
        # EventProcessor handles:
        # - Venue geocoding (via VenueProcessor with multi-provider)
        # - Venue GPS deduplication (50m tight, 200m broad)
        # - Event deduplication by external_id
        # - Database insertion
        case EventProcessor.process_event(event, source.id) do
          {:ok, db_event} ->
            Logger.debug("✅ Processed event: #{db_event.title} (ID: #{db_event.id})")
            true

          {:error, reason} ->
            Logger.warning("⚠️ Failed to process event: #{inspect(reason)}")
            false
        end
      end)
      |> Enum.count(& &1)

      Logger.info("📊 Successfully processed #{processed_count}/#{length(transformed_events)} events")
      {:ok, processed_count}
    end
  end
end
