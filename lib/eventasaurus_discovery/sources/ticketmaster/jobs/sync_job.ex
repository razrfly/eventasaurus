defmodule EventasaurusDiscovery.Sources.Ticketmaster.Jobs.SyncJob do
  @moduledoc """
  Unified Oban job for syncing Ticketmaster events.

  Uses the standardized BaseJob behaviour for consistent processing across all sources.
  Now schedules individual EventProcessorJob for each event instead of batch processing.
  """

  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :discovery,
    max_attempts: 3

  require Logger
  alias EventasaurusDiscovery.Sources.Ticketmaster.{Config, Client, Transformer}
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    city_id = args["city_id"]
    external_id = "ticketmaster_sync_city_#{city_id}_#{Date.utc_today()}"
    limit = args["limit"] || 100
    options = args["options"] || %{}
    force = args["force"] || false

    if force do
      Logger.info("⚡ Force mode enabled - bypassing EventFreshnessChecker")
    end

    with {:ok, city} <- get_city(city_id),
         {:ok, source} <- get_or_create_source(),
         {:ok, raw_events} <- fetch_events(city, limit, options),
         # Pass city context through transformation
         transformed_events <-
           transform_events_with_options(raw_events, Map.put(options, "city", city)) do
      # Schedule individual jobs for each transformed event
      %{enqueued: enqueued_count, stale: stale_count, fresh: fresh_count} =
        schedule_event_jobs(transformed_events, source.id, force)

      efficiency =
        if length(transformed_events) > 0 do
          Float.round(enqueued_count / length(transformed_events) * 100, 1)
        else
          0.0
        end

      Logger.info("""
      ✅ Ticketmaster sync completed
      City: #{city.name}
      Events found: #{length(raw_events)}
      Events transformed: #{length(transformed_events)}
      Stale events: #{stale_count}
      Fresh events: #{fresh_count}
      Jobs enqueued: #{enqueued_count}
      Efficiency: #{efficiency}%
      """)

      # Schedule coordinate recalculation after successful sync
      schedule_coordinate_update(city_id)

      MetricsTracker.record_success(job, external_id)

      {:ok,
       %{
         city: city.name,
         found: length(raw_events),
         transformed: length(transformed_events),
         enqueued: enqueued_count
       }}
    else
      {:discard, reason} ->
        Logger.error("Job discarded: #{reason}")
        MetricsTracker.record_failure(job, "Job discarded: #{reason}", external_id)
        {:discard, reason}

      {:error, reason} = error ->
        Logger.error("Failed to sync Ticketmaster events: #{inspect(reason)}")
        MetricsTracker.record_failure(job, "Failed to sync: #{inspect(reason)}", external_id)
        error
    end
  end

  defp schedule_event_jobs(events, source_id, force) do
    alias EventasaurusDiscovery.Services.EventFreshnessChecker

    # DEBUG: Check what external_ids we have
    sample_ids = events |> Enum.take(3) |> Enum.map(& &1[:external_id])
    Logger.info("🔍 DEBUG: Sample external_ids from events: #{inspect(sample_ids)}")
    Logger.info("🔍 DEBUG: Total events to check: #{length(events)}, source_id: #{source_id}")

    # Filter to events needing processing based on freshness (unless force=true)
    # EventFreshnessChecker already supports both string and atom keys
    events_needing_processing =
      if force do
        events
      else
        EventFreshnessChecker.filter_events_needing_processing(
          events,
          source_id
        )
      end

    Logger.info("🔍 DEBUG: Events after freshness filter: #{length(events_needing_processing)}")

    stale_count = length(events_needing_processing)
    fresh_count = length(events) - stale_count
    threshold = EventFreshnessChecker.get_threshold()

    Logger.info(
      "🔍 Freshness check: #{stale_count} stale, #{fresh_count} fresh #{if force, do: "(Force mode)", else: "(threshold: #{threshold}h)"}"
    )

    # Schedule individual EventProcessorJob for each event needing processing
    # Following the same pattern as Karnet's schedule_detail_jobs
    scheduled_jobs =
      events_needing_processing
      |> Enum.with_index()
      |> Enum.map(fn {event, index} ->
        # Stagger jobs slightly to avoid overwhelming the system
        delay_seconds = index * Config.rate_limit()

        # CRITICAL: Clean UTF-8 before storing in job args
        # This prevents PostgreSQL UTF-8 errors when the job is stored
        clean_event = EventasaurusDiscovery.Utils.UTF8.validate_map_strings(event)

        job_args = %{
          "event_data" => clean_event,
          "source_id" => source_id
        }

        EventasaurusDiscovery.Sources.Ticketmaster.Jobs.EventProcessorJob.new(job_args,
          queue: :scraper_detail,
          schedule_in: delay_seconds
        )
        |> Oban.insert()
      end)

    # Count successful insertions
    successful_count =
      Enum.count(scheduled_jobs, fn
        {:ok, _} -> true
        _ -> false
      end)

    Logger.info(
      "📋 Scheduled #{successful_count}/#{length(events)} Ticketmaster event processing jobs (#{fresh_count} skipped as fresh)"
    )

    %{
      enqueued: successful_count,
      stale: stale_count,
      fresh: fresh_count
    }
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(city, limit, options) do
    radius = options["radius"] || options[:radius] || Config.default_radius()
    max_pages = calculate_max_pages(limit)

    # Determine locales based on country
    locales = determine_locales(city, options)

    Logger.info("""
    🎫 Fetching Ticketmaster events
    City: #{city.name}, #{city.country.name}
    Coordinates: (#{city.latitude}, #{city.longitude})
    Radius: #{radius}km
    Locales: #{inspect(locales)}
    Max pages: #{max_pages}
    Target events: #{limit}
    """)

    # Fetch events for each locale and combine results
    # We need to keep all versions to get translations in different languages
    all_events =
      locales
      |> Enum.flat_map(fn locale ->
        Logger.info("🌐 Fetching events with locale: #{locale}")

        case fetch_all_pages(city, radius, max_pages, limit, locale) do
          {:ok, events} ->
            # Tag each event with its locale for transformation
            Enum.map(events, &Map.put(&1, "_locale", locale))

          {:error, reason} ->
            Logger.warning("Failed to fetch events for locale #{locale}: #{inspect(reason)}")
            []
        end
      end)
      # Don't deduplicate here - we want all language versions!
      # The EventProcessor will merge translations for the same external_id
      # Take more since we have duplicates
      |> Enum.take(limit * length(locales))

    {:ok, all_events}
  end

  defp determine_locales(city, options) do
    # Check if locale was explicitly provided
    case options["locale"] || options[:locale] do
      nil ->
        # No explicit locale, use country-based detection with safe fallback
        case Config.country_locales(city.country.code) do
          locales when is_list(locales) and locales != [] -> locales
          # safe fallback if country detection fails
          _ -> ["en-us"]
        end

      locale ->
        # Explicit locale provided, use only that one
        [locale]
    end
  end

  # Keep @impl on the 1-arity variant to satisfy BaseJob behaviour
  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(raw_events) do
    transform_events(raw_events, %{})
  end

  def transform_events(raw_events, options) do
    # Extract city context from options (passed by BaseJob)
    city = options["city"]

    # Transform each event using our Transformer
    # Each event has its locale tagged in "_locale" field
    raw_events
    |> Enum.flat_map(fn raw_event ->
      # Extract the locale that was tagged on this event
      locale = Map.get(raw_event, "_locale")
      # Remove the temporary locale tag before transformation
      event_data = Map.delete(raw_event, "_locale")

      case Transformer.transform_event(event_data, locale, city) do
        {:ok, event} ->
          [event]

        {:error, reason} ->
          Logger.debug("Ticketmaster event transformation failed: #{reason}")
          []
      end
    end)
  end

  # Override the helper from BaseJob to use our version with options
  defp transform_events_with_options(raw_events, options) do
    transform_events(raw_events, options)
  end

  def source_config do
    Config.source_config()
  end

  # Private functions

  defp calculate_max_pages(limit) do
    # Each page returns up to 100 events
    pages = div(limit, Config.default_page_size())
    if rem(limit, Config.default_page_size()) > 0, do: pages + 1, else: pages
  end

  defp fetch_all_pages(city, radius, max_pages, target_limit, locale) do
    fetch_pages_recursive(city, radius, 0, max_pages, [], target_limit, locale)
  end

  defp fetch_pages_recursive(_city, _radius, page, max_pages, events, _limit, _locale)
       when page >= max_pages do
    {:ok, events}
  end

  defp fetch_pages_recursive(_city, _radius, _page, _max_pages, events, limit, _locale)
       when length(events) >= limit do
    {:ok, Enum.take(events, limit)}
  end

  defp fetch_pages_recursive(city, radius, page, max_pages, accumulated_events, limit, locale) do
    case Client.fetch_events_by_location(city.latitude, city.longitude, radius, page, locale) do
      {:ok, %{"_embedded" => %{"events" => page_events}}} when is_list(page_events) ->
        all_events = accumulated_events ++ page_events

        if length(all_events) >= limit do
          {:ok, Enum.take(all_events, limit)}
        else
          # Rate limiting with safety checks
          rate_limit = max(Config.source_config().rate_limit, 1)
          # Minimum 100ms between requests
          sleep_ms = max(div(1000, rate_limit), 100)
          Process.sleep(sleep_ms)
          fetch_pages_recursive(city, radius, page + 1, max_pages, all_events, limit, locale)
        end

      {:ok, _} ->
        # No more events
        {:ok, accumulated_events}

      {:error, reason} = error ->
        if page == 0 do
          # First page failed, return error
          error
        else
          # Subsequent page failed, return what we have
          Logger.warning("Failed to fetch page #{page}: #{inspect(reason)}")
          {:ok, accumulated_events}
        end
    end
  end
end
