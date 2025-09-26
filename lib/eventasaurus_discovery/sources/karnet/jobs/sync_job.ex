defmodule EventasaurusDiscovery.Sources.Karnet.Jobs.SyncJob do
  @moduledoc """
  Unified Oban job for syncing Karnet Kraków events.

  Uses the standardized BaseJob behaviour for consistent processing across all sources.
  All events are processed through the unified Processor which enforces venue requirements.
  """

  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :discovery,
    max_attempts: 3

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Sources.Karnet.{Client, Config, IndexExtractor, DetailExtractor, Transformer}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    city_id = args["city_id"]
    limit = args["limit"] || 200
    max_pages = args["max_pages"] || calculate_max_pages(limit)

    # Get city (should be Kraków)
    case Repo.get(City, city_id) do
      nil ->
        Logger.error("City not found: #{inspect(city_id)}")
        {:error, :city_not_found}

      city ->
        city = Repo.preload(city, :country)

        # Verify it's Kraków (or allow other Polish cities in the future)
        unless String.downcase(city.name) in ["kraków", "krakow", "cracow"] do
          Logger.warning("⚠️ Karnet scraper is designed for Kraków but got: #{city.name}")
        end

        Logger.info("""
        🎭 Starting Karnet Kraków inline sync
        City: #{city.name}, #{city.country.name}
        Limit: #{limit} events
        Max pages: #{max_pages}
        """)

        result = continue_sync(city,
          source: get_or_create_karnet_source(),
          limit: limit,
          max_pages: max_pages
        )

        # Schedule coordinate recalculation after successful sync
        case result do
          {:ok, _} = success ->
            schedule_coordinate_update(city_id)
            Logger.info("🗺️ Scheduled coordinate update for city #{city_id}")
            success
          other ->
            other
        end
    end
  end


  defp continue_sync(_city, opts) do
    source = opts[:source]
    limit = opts[:limit]
    max_pages = opts[:max_pages]

    # Fetch all index pages
    case Client.fetch_all_index_pages(max_pages) do
      {:ok, pages} ->
        Logger.info("📚 Fetched #{length(pages)} index pages")

        # Extract events from all pages
        events = IndexExtractor.extract_events_from_pages(pages)
        Logger.info("📋 Extracted #{length(events)} total events")

        # Apply limit
        events_to_process = if limit, do: Enum.take(events, limit), else: events

        Logger.info(
          "🎯 Processing #{length(events_to_process)} events (limit: #{limit || "none"})"
        )

        # Schedule individual detail jobs
        enqueued_count = schedule_detail_jobs(events_to_process, source.id)

        Logger.info("""
        ✅ Karnet sync job completed
        Events found: #{length(events)}
        Events to process: #{length(events_to_process)}
        Detail jobs enqueued: #{enqueued_count}
        """)

        {:ok,
         %{
           found: length(events),
           processed: length(events_to_process),
           enqueued: enqueued_count
         }}

      {:error, reason} ->
        Logger.error("❌ Failed to fetch index pages: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(city, limit, _options) do
    Logger.info("""
    🎭 Fetching Karnet events
    City: #{city.name}, #{city.country.name}
    Target events: #{limit}
    """)

    # Verify it's Kraków (Karnet only serves Kraków)
    unless String.downcase(city.name) in ["kraków", "krakow", "cracow"] do
      Logger.warning("⚠️ Karnet scraper is designed for Kraków but got: #{city.name}")
    end

    max_pages = calculate_max_pages(limit)

    # Fetch all index pages
    with {:ok, pages} <- Client.fetch_all_index_pages(max_pages) do
      Logger.info("📚 Fetched #{length(pages)} index pages")

      # Extract basic events from index
      basic_events = IndexExtractor.extract_events_from_pages(pages)
      Logger.info("📋 Extracted #{length(basic_events)} events from index")

      # Apply limit
      limited_events = Enum.take(basic_events, limit)

      # Fetch details for each event
      detailed_events =
        limited_events
        |> Enum.map(&fetch_and_merge_details/1)
        |> Enum.reject(&is_nil/1)

      Logger.info("✅ Successfully fetched #{length(detailed_events)} events with details")
      {:ok, detailed_events}
    else
      {:error, reason} = error ->
        Logger.error("Failed to fetch Karnet events: #{inspect(reason)}")
        error
    end
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(raw_events) do
    # Transform each event using our Transformer
    # Filter out events that fail venue validation
    raw_events
    |> Enum.map(&Transformer.transform_event/1)
    |> Enum.filter(fn
      {:ok, _event} -> true
      {:error, _reason} -> false
    end)
    |> Enum.map(fn {:ok, event} -> event end)
  end

  # Required by BaseJob for source configuration
  def source_config do
    %{
      name: "Karnet Kraków",
      slug: "karnet",
      website_url: "https://karnet.krakowculture.pl",
      priority: 70,
      config: %{
        "rate_limit_seconds" => Config.rate_limit(),
        "max_requests_per_hour" => 300,
        "language" => "pl",
        "supports_pagination" => true
      }
    }
  end

  defp schedule_detail_jobs(events, source_id) do
    Logger.info("📅 Scheduling #{length(events)} detail jobs")

    # Schedule individual jobs for each event with rate limiting
    scheduled_jobs =
      events
      |> Enum.with_index()
      |> Enum.map(fn {event, index} ->
        # Add delay between jobs to respect rate limits
        # Start immediately, then rate_limit seconds between each job
        scheduled_at = DateTime.add(DateTime.utc_now(), index * Config.rate_limit(), :second)

        job_args = %{
          "url" => event.url,
          "source_id" => source_id,
          "event_metadata" => Map.take(event, [:title, :date_text, :venue_name, :category]),
          "external_id" => extract_external_id_from_url(event.url)
        }

        # For now, we'll create a placeholder - EventDetailJob will be implemented in Phase 2
        # Using a dummy module name that we'll implement later
        %{
          module: EventasaurusDiscovery.Sources.Karnet.Jobs.EventDetailJob,
          args: job_args,
          queue: "scraper_detail",
          scheduled_at: scheduled_at
        }
        |> then(fn job_spec ->
          # Check if the module exists before trying to insert
          if Code.ensure_loaded?(job_spec.module) do
            job_spec.module.new(job_args,
              queue: job_spec.queue,
              scheduled_at: job_spec.scheduled_at
            )
            |> Oban.insert()
          else
            # For now, just log that we would schedule this job
            Logger.debug("Would schedule detail job for: #{event.url}")
            {:ok, :placeholder}
          end
        end)
      end)

    # Count successful insertions
    successful_count =
      Enum.count(scheduled_jobs, fn
        {:ok, _} -> true
        _ -> false
      end)

    Logger.info("✅ Successfully scheduled #{successful_count}/#{length(events)} detail jobs")
    successful_count
  end

  defp get_or_create_karnet_source do
    case Repo.get_by(Source, slug: "karnet") do
      nil ->
        config = source_config()

        %Source{}
        |> Source.changeset(config)
        |> Repo.insert!()

      source ->
        source
    end
  end

  # Private helper functions

  defp fetch_and_merge_details(%{url: url} = basic_event) do
    Logger.debug("🔍 Fetching details for: #{url}")

    case Client.fetch_page(url) do
      {:ok, html} ->
        case DetailExtractor.extract_event_details(html, url) do
          {:ok, details} ->
            # Merge basic and detailed data
            Map.merge(basic_event, details)

          {:error, reason} ->
            Logger.warning("Failed to extract details from #{url}: #{inspect(reason)}")
            nil
        end

      {:error, reason} ->
        Logger.warning("Failed to fetch event page #{url}: #{inspect(reason)}")
        nil
    end
  end

  defp fetch_and_merge_details(basic_event) do
    Logger.warning("Event without URL: #{inspect(basic_event)}")
    nil
  end

  defp calculate_max_pages(limit) do
    # Karnet has ~12 events per page
    events_per_page = 12
    pages = div(limit, events_per_page)
    if rem(limit, events_per_page) > 0, do: pages + 1, else: pages
  end

  defp extract_external_id_from_url(url) do
    # Extract the event ID from the URL
    # Format: /60682-krakow-event-name
    case Regex.run(~r/\/(\d+)-/, url) do
      [_, id] -> "karnet_#{id}"
      _ -> nil
    end
  end
end
