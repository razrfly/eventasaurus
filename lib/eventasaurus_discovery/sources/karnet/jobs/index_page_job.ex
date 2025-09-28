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
    page_number = args["page_number"]
    source_id = args["source_id"]
    limit = args["limit"]
    total_pages = args["total_pages"]

    Logger.info("""
    📄 Processing Karnet index page
    Page: #{page_number}/#{total_pages || "unknown"}
    Source ID: #{source_id}
    """)

    # Build URL for this specific page
    url = Config.build_events_url(page_number)

    # Fetch the page
    case Client.fetch_page(url) do
      {:ok, html} ->
        process_index_page(html, page_number, source_id, limit)

      {:error, :not_found} ->
        Logger.info("📭 Page #{page_number} not found - likely past last page")
        {:ok, :no_more_pages}

      {:error, reason} ->
        Logger.error("❌ Failed to fetch page #{page_number}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_index_page(html, page_number, source_id, limit) do
    # Check if page has events
    if has_events?(html) do
      # Extract events from this page
      events = IndexExtractor.extract_events_from_page({page_number, html})

      Logger.info("📋 Extracted #{length(events)} events from page #{page_number}")

      # Apply limit if this is the first page and we have a limit
      events_to_process =
        if page_number == 1 && limit do
          Enum.take(events, limit)
        else
          events
        end

      # Schedule detail jobs for each event
      scheduled_count = schedule_detail_jobs(events_to_process, source_id, page_number)

      Logger.info("""
      ✅ Index page #{page_number} processed
      Events found: #{length(events)}
      Detail jobs scheduled: #{scheduled_count}
      """)

      {:ok, %{
        page: page_number,
        events_found: length(events),
        jobs_scheduled: scheduled_count
      }}
    else
      Logger.info("📭 No events on page #{page_number}")
      {:ok, :no_events}
    end
  end

  defp schedule_detail_jobs(events, source_id, page_number) do
    Logger.debug("📅 Scheduling #{length(events)} detail jobs from page #{page_number}")

    # Calculate base delay for this page to distribute load
    # Add staggered delays to respect rate limits
    base_delay = (page_number - 1) * length(events) * Config.rate_limit()

    scheduled_jobs =
      events
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
          "external_id" => extract_external_id_from_url(event.url),
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

  defp extract_external_id_from_url(url) do
    # Extract the event ID from the URL
    # Format: /60682-krakow-event-name
    case Regex.run(~r/\/(\d+)-/, url) do
      [_, id] -> "karnet_#{id}"
      _ -> nil
    end
  end
end