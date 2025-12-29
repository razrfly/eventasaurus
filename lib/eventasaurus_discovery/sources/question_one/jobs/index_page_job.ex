defmodule EventasaurusDiscovery.Sources.QuestionOne.Jobs.IndexPageJob do
  @moduledoc """
  Parses Question One RSS feed and schedules venue detail jobs.

  CRITICAL: Uses EventFreshnessChecker to avoid re-scraping fresh venues.

  ## Workflow
  1. Fetch RSS feed page
  2. Parse venue list from feed
  3. Generate external_ids for venues
  4. Filter using EventFreshnessChecker (skip fresh venues)
  5. Schedule detail jobs for stale venues only
  6. Enqueue next page job (if not limited and venues found)

  ## Pagination
  - Page 1: https://questionone.com/venues/feed/
  - Page N: https://questionone.com/venues/feed/?paged=N
  - Stops when 404 or empty results
  """

  use Oban.Worker,
    queue: :scraper_index,
    max_attempts: 3,
    priority: 1

  require Logger

  alias EventasaurusDiscovery.Sources.QuestionOne.{
    Client,
    Jobs.VenueDetailJob,
    Extractors.VenueExtractor,
    Helpers.TextHelper
  }

  alias EventasaurusDiscovery.Services.EventFreshnessChecker
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    page = args["page"] || 1
    source_id = args["source_id"]
    limit = args["limit"]
    force = args["force"] || false
    external_id = "question_one_index_page_#{page}"

    Logger.info("🔄 Processing Question One RSS feed page #{page}")

    case Client.fetch_feed_page(page) do
      {:ok, :no_more_pages} ->
        Logger.info("✅ Reached end of feed at page #{page}")
        MetricsTracker.record_success(job, external_id)
        {:ok, :complete}

      {:ok, body} ->
        venues = parse_rss_feed(body)

        if Enum.empty?(venues) do
          Logger.info("✅ No more venues found at page #{page}")
          MetricsTracker.record_success(job, external_id)
          {:ok, :complete}
        else
          Logger.info("📋 Found #{length(venues)} venues on page #{page}")

          # CRITICAL: EventFreshnessChecker filters out fresh venues (unless force=true)
          scheduled_count = schedule_detail_jobs(venues, source_id, limit, force)

          if force do
            Logger.info("📤 Scheduled #{scheduled_count} detail jobs (force mode - no filtering)")
          else
            Logger.info("""
            📤 Scheduled #{scheduled_count} detail jobs
            (#{length(venues) - scheduled_count} venues skipped - recently updated)
            """)
          end

          # Enqueue next page if not limited
          should_continue = is_nil(limit) || scheduled_count > 0
          if should_continue, do: enqueue_next_page(page + 1, source_id, limit, force)

          MetricsTracker.record_success(job, external_id)
          {:ok, %{venues_found: length(venues), jobs_scheduled: scheduled_count}}
        end

      # Use standard categories for ErrorCategories.categorize_error/1
      # See docs/error-handling-guide.md for category definitions
      {:error, %HTTPoison.Error{reason: :timeout}} = error ->
        Logger.error("❌ Network timeout fetching feed page #{page}")
        MetricsTracker.record_failure(job, :network_error, external_id)
        error

      {:error, %HTTPoison.Error{reason: _reason}} = error ->
        Logger.error("❌ Network error fetching feed page #{page}")
        MetricsTracker.record_failure(job, :network_error, external_id)
        error

      {:error, _reason} = error ->
        Logger.error("❌ Failed to fetch feed page #{page}")
        MetricsTracker.record_failure(job, :network_error, external_id)
        error
    end
  end

  # Parse RSS XML feed to extract venue URLs and titles
  defp parse_rss_feed(xml_body) do
    # Simple RSS parser - extract <item> elements
    # Question One RSS has: <item><link>venue_url</link><title>Venue Name</title></item>

    xml_body
    |> String.split("<item>")
    |> Enum.drop(1)
    |> Enum.map(&parse_rss_item/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_rss_item(item_xml) do
    with link when not is_nil(link) <- extract_xml_tag(item_xml, "link"),
         title when not is_nil(title) <- extract_xml_tag(item_xml, "title") do
      %{url: link, title: title}
    else
      _ -> nil
    end
  end

  defp extract_xml_tag(xml, tag) do
    case Regex.run(~r/<#{tag}>(.*?)<\/#{tag}>/s, xml) do
      [_, content] -> String.trim(content)
      _ -> nil
    end
  end

  # CRITICAL: EventFreshnessChecker integration
  defp schedule_detail_jobs(venues, source_id, limit, force) do
    # Generate external_ids for freshness checking
    # For pattern-based scrapers, venue is the unique identifier
    # Day of week is metadata, not part of the external_id
    #
    # IMPORTANT: Must match Transformer's external_id generation:
    # 1. Clean RSS title using VenueExtractor.clean_title/1
    # 2. Slugify cleaned title using TextHelper.slugify/1
    #
    # IMPORTANT: Mark as recurring so EventFreshnessChecker bypasses freshness check
    # All Question One venues are weekly recurring trivia events
    venues_with_ids =
      Enum.map(venues, fn venue ->
        cleaned_title = VenueExtractor.clean_title(venue.title)
        venue_slug = TextHelper.slugify(cleaned_title)

        venue
        |> Map.put(:external_id, "question_one_#{venue_slug}")
        # Mark as recurring - triggers bypass in EventFreshnessChecker
        # The actual recurrence_rule is added later by Transformer
        |> Map.put(:recurrence_rule, %{"frequency" => "weekly"})
      end)

    # Filter out venues that were recently updated (default: 7 days)
    # In force mode, skip filtering to process all venues
    venues_to_process =
      if force do
        venues_with_ids
      else
        EventFreshnessChecker.filter_events_needing_processing(venues_with_ids, source_id)
      end

    # Apply limit if provided
    venues_to_process =
      if limit do
        Enum.take(venues_to_process, limit)
      else
        venues_to_process
      end

    # Schedule detail jobs for stale venues
    venues_to_process
    |> Enum.with_index()
    |> Enum.each(fn {venue, index} ->
      # Stagger jobs to respect rate limit (2 seconds between requests)
      delay_seconds = index * 3

      %{
        "venue_url" => venue.url,
        "venue_title" => venue.title,
        "source_id" => source_id
      }
      |> VenueDetailJob.new(schedule_in: delay_seconds)
      |> Oban.insert()
    end)

    length(venues_to_process)
  end

  defp enqueue_next_page(next_page, source_id, limit, force) do
    %{
      "page" => next_page,
      "source_id" => source_id,
      "limit" => limit,
      "force" => force
    }
    |> __MODULE__.new(schedule_in: 5)
    |> Oban.insert()
  end
end
