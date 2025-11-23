defmodule EventasaurusDiscovery.Sources.Karnet.Jobs.IndexPageJob do
  @moduledoc """
  Oban job for processing individual Karnet index pages.

  This job is part of a distributed scraping strategy that prevents timeouts
  by breaking up the index scraping into smaller, concurrent units of work.

  Each IndexPageJob:
  1. Fetches a single index page
  2. Extracts events from that page
  3. Schedules EventDetailJobs for each event found

  This allows for:
  - Better failure isolation (one page failing doesn't affect others)
  - Concurrent processing of multiple index pages
  - More granular progress tracking
  - Ability to resume from partial failures
  """

  use Oban.Worker,
    queue: :scraper_index,
    max_attempts: 3

  require Logger

  alias EventasaurusDiscovery.Sources.Karnet.{Client, Config, IndexExtractor}
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    # Validate and normalize input arguments
    with {:ok, page_number} <- validate_integer(args["page_number"], "page_number"),
         {:ok, source_id} <- validate_integer(args["source_id"], "source_id"),
         true <- page_number >= 1 || {:error, "page_number", "must be >= 1"},
         true <- source_id > 0 || {:error, "source_id", "must be > 0"} do
      # Optional arguments with defaults
      chunk_budget = validate_optional_integer(args["chunk_budget"])
      total_pages = validate_optional_integer(args["total_pages"])
      skip_in_first = validate_optional_integer(args["skip_in_first"]) || 0
      force = args["force"] || false

      external_id = "karnet_indexpage_page#{page_number}_#{Date.utc_today()}"

      Logger.info("""
      📄 Processing Karnet index page
      Page: #{page_number}/#{total_pages || "unknown"}
      Source ID: #{source_id}
      Skip: #{skip_in_first} events
      Budget: #{chunk_budget || "unlimited"}
      """)

      case process_page(page_number, source_id, chunk_budget, total_pages, skip_in_first, force) do
        {:ok, _result} = success ->
          MetricsTracker.record_success(job, external_id)
          success

        {:error, reason} = error ->
          MetricsTracker.record_failure(job, "Page processing failed: #{inspect(reason)}", external_id)
          error
      end
    else
      {:error, field, reason} ->
        Logger.error("❌ Invalid job arguments - #{field}: #{reason}")
        external_id = "karnet_indexpage_invalid_#{Date.utc_today()}"
        MetricsTracker.record_failure(job, "Invalid arguments - #{field}: #{reason}", external_id)
        {:error, "invalid_args_#{field}"}
    end
  end

  defp process_page(page_number, source_id, chunk_budget, _total_pages, skip_in_first, force) do
    # Build URL for this specific page
    url = Config.build_events_url(page_number)

    # Fetch the page
    case Client.fetch_page(url) do
      {:ok, html} ->
        process_index_page(html, page_number, source_id, chunk_budget, skip_in_first, force)

      {:error, :not_found} ->
        Logger.info("📭 Page #{page_number} not found - likely past last page")
        {:ok, :no_more_pages}

      {:error, reason} ->
        Logger.error("❌ Failed to fetch page #{page_number}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Validation helpers
  defp validate_integer(nil, field), do: {:error, field, "is required"}
  defp validate_integer(value, _field) when is_integer(value), do: {:ok, value}

  defp validate_integer(value, field) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, field, "invalid integer: #{inspect(value)}"}
    end
  end

  defp validate_integer(value, field),
    do: {:error, field, "expected integer, got: #{inspect(value)}"}

  defp validate_optional_integer(nil), do: nil
  defp validate_optional_integer(value) when is_integer(value) and value > 0, do: value
  # Reject non-positive
  defp validate_optional_integer(value) when is_integer(value), do: nil

  defp validate_optional_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  defp validate_optional_integer(_), do: nil

  defp process_index_page(html, page_number, source_id, chunk_budget, skip_in_first, force) do
    # Check if page has events
    if has_events?(html) do
      # Extract events from this page
      events = IndexExtractor.extract_events_from_page({page_number, html})

      # Apply skip_in_first for chunked processing
      events_after_skip =
        if skip_in_first > 0 do
          Logger.info("⏭️ Skipping first #{skip_in_first} events for chunk offset")
          Enum.drop(events, skip_in_first)
        else
          events
        end

      Logger.info(
        "📋 Extracted #{length(events)} events from page #{page_number} (#{length(events_after_skip)} after skip)"
      )

      # Apply chunk budget to prevent overshooting
      events_to_process =
        if chunk_budget do
          Logger.info("💰 Applying chunk budget: #{chunk_budget} events")
          Enum.take(events_after_skip, chunk_budget)
        else
          # No budget limit - process all events (for backward compatibility)
          events_after_skip
        end

      # Schedule detail jobs for each event
      scheduled_count = schedule_detail_jobs(events_to_process, source_id, page_number, force)

      Logger.info("""
      ✅ Index page #{page_number} processed
      Events found: #{length(events)} (#{length(events_after_skip)} after skip, #{length(events_to_process)} final)
      Detail jobs scheduled: #{scheduled_count}
      """)

      {:ok,
       %{
         page: page_number,
         events_found: length(events),
         jobs_scheduled: scheduled_count
       }}
    else
      Logger.info("📭 No events on page #{page_number}")
      {:ok, :no_events}
    end
  end

  defp schedule_detail_jobs(events, source_id, page_number, force) do
    alias EventasaurusDiscovery.Services.EventFreshnessChecker

    # Extract external_ids for all events (adds "karnet_" prefix automatically)
    # This allows us to check freshness before scheduling detail jobs
    events_with_ids =
      Enum.map(events, fn event ->
        external_id = extract_external_id_from_url(event.url)
        Map.put(event, :external_id, external_id)
      end)

    # Filter to events needing processing based on freshness (unless force=true)
    events_to_process =
      if force do
        events_with_ids
      else
        EventFreshnessChecker.filter_events_needing_processing(
          events_with_ids,
          source_id
        )
      end

    skipped = length(events) - length(events_to_process)
    threshold = EventFreshnessChecker.get_threshold()

    Logger.info(
      "📋 Karnet page #{page_number}: Processing #{length(events_to_process)}/#{length(events)} events #{if force, do: "(Force mode)", else: "(#{skipped} skipped, threshold: #{threshold}h)"}"
    )

    # Calculate base delay for this page to distribute load
    # Use consistent page offset (30s per page) to prevent scheduling collisions
    # Then stagger individual jobs within the page based on rate limiting
    base_delay = (page_number - 1) * 30

    scheduled_jobs =
      events_to_process
      |> Enum.with_index()
      |> Enum.map(fn {event, index} ->
        # Stagger job execution with rate limiting
        delay_seconds = base_delay + index * Config.rate_limit()

        # Clean UTF-8 before storing in database
        job_args =
          %{
            "url" => event.url,
            "source_id" => source_id,
            "event_metadata" => Map.take(event, [:title, :date_text, :venue_name, :category]),
            # Reuse the external_id we already extracted (already has "karnet_" prefix)
            "external_id" => event.external_id,
            "from_page" => page_number
          }
          |> EventasaurusDiscovery.Utils.UTF8.validate_map_strings()

        # Schedule the detail job
        EventasaurusDiscovery.Sources.Karnet.Jobs.EventDetailJob.new(
          job_args,
          queue: :scraper_detail,
          schedule_in: delay_seconds
        )
        |> Oban.insert()
      end)

    # Count successful insertions
    Enum.count(scheduled_jobs, fn
      {:ok, _} -> true
      _ -> false
    end)
  end

  defp has_events?(html) do
    # Check if the HTML contains event listings
    String.contains?(html, "class=\"event-item\"") ||
      String.contains?(html, "class=\"wydarzenie\"") ||
      String.contains?(html, "data-event-id") ||
      (String.contains?(html, "href") && String.contains?(html, "/wydarzenia/"))
  end

  defp extract_external_id_from_url(nil), do: nil

  defp extract_external_id_from_url(url) when is_binary(url) do
    # Extract the event ID from the URL
    # Format: /60682-krakow-event-name
    case Regex.run(~r/\/(\d+)-/, url) do
      [_, id] -> "karnet_#{id}"
      _ -> nil
    end
  end

  defp extract_external_id_from_url(_), do: nil
end
