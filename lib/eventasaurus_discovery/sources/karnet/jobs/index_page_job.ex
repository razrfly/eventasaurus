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

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    # Validate and normalize input arguments
    with {:ok, page_number} <- validate_integer(args["page_number"], "page_number"),
         {:ok, source_id} <- validate_integer(args["source_id"], "source_id"),
         true <- page_number >= 1 || {:error, "page_number", "must be >= 1"},
         true <- source_id > 0 || {:error, "source_id", "must be > 0"} do

      # Optional arguments with defaults
      chunk_budget = validate_optional_integer(args["chunk_budget"])
      total_pages = validate_optional_integer(args["total_pages"])
      skip_in_first = validate_optional_integer(args["skip_in_first"]) || 0

      Logger.info("""
      📄 Processing Karnet index page
      Page: #{page_number}/#{total_pages || "unknown"}
      Source ID: #{source_id}
      Skip: #{skip_in_first} events
      Budget: #{chunk_budget || "unlimited"}
      """)

      process_page(page_number, source_id, chunk_budget, total_pages, skip_in_first)
    else
      {:error, field, reason} ->
        Logger.error("❌ Invalid job arguments - #{field}: #{reason}")
        {:error, "invalid_args_#{field}"}
    end
  end

  defp process_page(page_number, source_id, chunk_budget, _total_pages, skip_in_first) do

    # Build URL for this specific page
    url = Config.build_events_url(page_number)

    # Fetch the page
    case Client.fetch_page(url) do
      {:ok, html} ->
        process_index_page(html, page_number, source_id, chunk_budget, skip_in_first)

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
  defp validate_integer(value, field), do: {:error, field, "expected integer, got: #{inspect(value)}"}

  defp validate_optional_integer(nil), do: nil
  defp validate_optional_integer(value) when is_integer(value) and value > 0, do: value
  defp validate_optional_integer(value) when is_integer(value), do: nil  # Reject non-positive
  defp validate_optional_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end
  defp validate_optional_integer(_), do: nil

  defp process_index_page(html, page_number, source_id, chunk_budget, skip_in_first) do
    # Check if page has events
    if has_events?(html) do
      # Extract ALL events from this page
      events = IndexExtractor.extract_events_from_page({page_number, html})

      Logger.info("📋 Extracted #{length(events)} events from page #{page_number}")

      # OPTIMIZATION: Check freshness FIRST on all events (same query cost as checking subset)
      # Add external_id to events for freshness checking
      events_with_ids = Enum.map(events, fn event ->
        external_id = extract_external_id_from_url(event.url)
        Map.put(event, :external_id, external_id)
      end)

      # Filter to events needing processing based on freshness
      alias EventasaurusDiscovery.Services.EventFreshnessChecker
      events_needing_processing = EventFreshnessChecker.filter_events_needing_processing(
        events_with_ids,
        source_id
      )

      stale_count = length(events_needing_processing)
      fresh_count = length(events) - stale_count
      threshold = EventFreshnessChecker.get_threshold()

      Logger.info("🔍 Freshness check: #{stale_count} stale, #{fresh_count} fresh (threshold: #{threshold}h)")

      # Apply skip_in_first to STALE events only
      events_after_skip = if skip_in_first > 0 do
        remaining = max(0, stale_count - skip_in_first)
        Logger.info("⏭️ Skip offset: #{skip_in_first} events → #{remaining} stale candidates")
        Enum.drop(events_needing_processing, skip_in_first)
      else
        events_needing_processing
      end

      # Apply chunk budget to STALE events only
      events_to_process = if chunk_budget do
        taken = min(chunk_budget, length(events_after_skip))
        Logger.info("💰 Chunk budget: #{chunk_budget} → processing #{taken} stale events")
        Enum.take(events_after_skip, chunk_budget)
      else
        # No budget limit - process all stale events
        events_after_skip
      end

      # Schedule detail jobs for each event (already filtered for freshness)
      scheduled_count = schedule_detail_jobs(events_to_process, source_id, page_number)

      # Calculate budget efficiency
      efficiency = if chunk_budget && chunk_budget > 0 do
        Float.round(scheduled_count / chunk_budget * 100, 1)
      else
        100.0
      end

      Logger.info("""
      ✅ Page #{page_number}: #{scheduled_count} jobs scheduled
      Total: #{length(events)} events (#{stale_count} stale, #{fresh_count} fresh)
      Budget: #{chunk_budget || "unlimited"} → #{scheduled_count} jobs (#{efficiency}% efficiency)
      """)

      {:ok, %{
        page: page_number,
        events_found: length(events),
        stale_events: stale_count,
        fresh_events: fresh_count,
        jobs_scheduled: scheduled_count,
        chunk_budget: chunk_budget,
        budget_efficiency: efficiency
      }}
    else
      Logger.info("📭 No events on page #{page_number}")
      {:ok, :no_events}
    end
  end

  defp schedule_detail_jobs(events, source_id, page_number) do
    # Events are already filtered for freshness in process_index_page
    # Just ensure they have external_id set (should already be set from process_index_page)
    events_with_ids = Enum.map(events, fn event ->
      if Map.has_key?(event, :external_id) do
        event
      else
        external_id = extract_external_id_from_url(event.url)
        Map.put(event, :external_id, external_id)
      end
    end)

    Logger.info("📋 Scheduling #{length(events_with_ids)} detail jobs for page #{page_number}")

    # Calculate base delay for this page to distribute load
    # Use consistent page offset (30s per page) to prevent scheduling collisions
    # Then stagger individual jobs within the page based on rate limiting
    base_delay = (page_number - 1) * 30

    scheduled_jobs =
      events_with_ids
      |> Enum.with_index()
      |> Enum.map(fn {event, index} ->
        # Stagger job execution with rate limiting
        delay_seconds = base_delay + (index * Config.rate_limit())
        scheduled_at = DateTime.add(DateTime.utc_now(), delay_seconds, :second)

        # Clean UTF-8 before storing in database
        job_args = %{
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
          scheduled_at: scheduled_at
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