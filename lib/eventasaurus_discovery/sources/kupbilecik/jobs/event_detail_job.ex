defmodule EventasaurusDiscovery.Sources.Kupbilecik.Jobs.EventDetailJob do
  @moduledoc """
  Fetches and processes individual Kupbilecik event details.

  Scheduled by SyncJob for each event URL discovered in sitemaps.

  ## Responsibilities

  1. Fetch event HTML page via Zyte (JS rendering required)
  2. Extract event data using EventExtractor (Floki-based)
  3. Transform to unified format using Transformer
  4. Process through EventProcessor (geocoding, deduplication)
  5. Store in database

  ## Bot Protection

  Kupbilecik is a React SPA that requires JavaScript execution.
  Uses Zyte API with browserHtml mode for full content rendering.

  ## Usage

  Jobs are automatically scheduled by SyncJob:

      EventDetailJob.new(%{
        "source" => "kupbilecik",
        "url" => "https://www.kupbilecik.pl/imprezy/186000/",
        "event_metadata" => %{
          "event_id" => "186000",
          "external_id_base" => "kupbilecik_article_186000"
        }
      })
      |> Oban.insert()
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3,
    priority: 2

  require Logger

  alias EventasaurusDiscovery.Sources.Kupbilecik.{
    Client,
    Transformer
  }

  alias EventasaurusDiscovery.Sources.Kupbilecik.Extractors.EventExtractor
  alias EventasaurusDiscovery.Scraping.Processors.EventProcessor
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, id: job_id} = job) do
    url = args["url"]
    event_metadata = args["event_metadata"] || %{}

    # Extract external_id for metrics tracking
    external_id =
      to_string(
        event_metadata["external_id_base"] || event_metadata["event_id"] || url || job_id
      )

    Logger.info("🔍 Fetching Kupbilecik event details: #{url}")

    result =
      with {:ok, html} <- Client.fetch_event_page(url),
           {:ok, raw_event} <- extract_event_data(html, url, event_metadata),
           :ok <- check_event_not_expired(raw_event, url),
           {:ok, transformed_events} <- transform_events(raw_event),
           {:ok, processed_count} <- process_events(transformed_events) do
        Logger.info("""
        ✅ Kupbilecik event detail job completed
        URL: #{url}
        Events created: #{processed_count}
        """)

        {:ok,
         %{
           url: url,
           events_created: processed_count,
           event_id: event_metadata["event_id"]
         }}
      else
        {:error, :expired} ->
          Logger.info("⏭️ Skipping expired event: #{url}")
          {:ok, :skipped_expired}

        {:error, :max_retries_exceeded} = error ->
          Logger.warning("🚫 Max retries exceeded for event page: #{url}")
          error

        {:error, :not_found} = error ->
          Logger.warning("❌ Event page not found: #{url}")
          error

        {:error, reason} = error ->
          Logger.error("❌ Failed to process event #{url}: #{inspect(reason)}")
          error
      end

    # Track metrics
    case result do
      {:ok, _} ->
        MetricsTracker.record_success(job, external_id)
        result

      {:error, reason} ->
        MetricsTracker.record_failure(job, reason, external_id)
        result
    end
  end

  # Private functions

  defp extract_event_data(html, url, event_metadata) do
    Logger.debug("📄 Extracting event data from #{url}")

    case EventExtractor.extract(html, url) do
      {:ok, event_data} ->
        # Merge with metadata from SyncJob
        raw_event =
          Map.merge(event_data, %{
            "url" => url,
            "event_id" => event_metadata["event_id"],
            "external_id_base" => event_metadata["external_id_base"]
          })

        Logger.debug("✅ Extracted event data: #{raw_event["title"]}")
        {:ok, raw_event}

      {:error, reason} = error ->
        Logger.warning("⚠️ Failed to extract event data from #{url}: #{inspect(reason)}")
        error
    end
  end

  defp check_event_not_expired(raw_event, url) do
    grace_period_days = 7
    cutoff = DateTime.add(DateTime.utc_now(), -grace_period_days * 86400, :second)

    case extract_end_date(raw_event) do
      {:ok, ends_at} ->
        if DateTime.compare(ends_at, cutoff) == :lt do
          Logger.info("""
          ⏭️ Skipping expired event (date-based filtering)
          URL: #{url}
          End date: #{Calendar.strftime(ends_at, "%Y-%m-%d")}
          Cutoff: #{Calendar.strftime(cutoff, "%Y-%m-%d")}
          """)

          {:error, :expired}
        else
          Logger.debug("✅ Event not expired (ends_at: #{Calendar.strftime(ends_at, "%Y-%m-%d")})")
          :ok
        end

      {:error, :no_end_date} ->
        # No parseable end date - let it continue
        Logger.debug("ℹ️ No parseable end date, continuing to transformation")
        :ok
    end
  end

  defp extract_end_date(raw_event) do
    cond do
      is_struct(raw_event["ends_at"], DateTime) ->
        {:ok, raw_event["ends_at"]}

      is_struct(raw_event["starts_at"], DateTime) ->
        # Use starts_at if no ends_at
        {:ok, raw_event["starts_at"]}

      is_binary(raw_event["date_string"]) ->
        case Transformer.parse_polish_date(raw_event["date_string"]) do
          {:ok, datetime} -> {:ok, datetime}
          _ -> {:error, :no_end_date}
        end

      true ->
        {:error, :no_end_date}
    end
  end

  defp transform_events(raw_event) do
    Logger.debug("🔄 Transforming raw event data")

    case Transformer.transform_events([raw_event]) do
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

    # Look up Kupbilecik source by slug
    source = Repo.one(from(s in Source, where: s.slug == "kupbilecik"))

    if is_nil(source) do
      Logger.error("❌ Kupbilecik source not found in database")
      {:error, :source_not_found}
    else
      processed_count =
        transformed_events
        |> Enum.map(fn event ->
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

      Logger.info(
        "📊 Successfully processed #{processed_count}/#{length(transformed_events)} events"
      )

      {:ok, processed_count}
    end
  end
end
