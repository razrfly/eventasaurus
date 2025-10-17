defmodule EventasaurusDiscovery.Sources.Sortiraparis.Jobs.SyncJob do
  @moduledoc """
  Oban job for syncing Sortiraparis events via sitemap discovery.

  Uses the standardized BaseJob behaviour for consistent processing across all sources.

  ## Discovery Strategy

  Unlike pagination-based scrapers, Sortiraparis uses **sitemap-based discovery**:
  1. Fetch sitemap XML files (sitemap-en-1.xml through sitemap-en-4.xml)
  2. Extract event URLs using `Config.is_event_url?/1` filter
  3. Schedule EventDetailJob for each event URL
  4. Database-level deduplication handles existing events via unique constraints

  ## Bot Protection

  ~30% of requests return 401 errors even with browser-like headers.
  - Current: Conservative rate limiting, browser headers, retries
  - Future (Phase 3+): Playwright fallback for persistent 401s

  ## Multi-Date Events

  Events with multiple dates are split into separate instances:
  - External ID format: `sortiraparis_{article_id}_{YYYY-MM-DD}`
  - Each date becomes a distinct event occurrence

  ## Phase Status

  **Phase 2**: Skeleton implementation (structure only)
  **Phase 3**: Complete sitemap discovery logic
  **Phase 5**: Comprehensive testing and integration
  """

  use EventasaurusDiscovery.Sources.BaseJob,
    queue: :scraper_index,
    max_attempts: 3

  require Logger

  alias EventasaurusDiscovery.Sources.Sortiraparis.{
    Client,
    Config
  }

  alias EventasaurusDiscovery.Sources.Sortiraparis.Helpers.UrlFilter

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    sitemap_urls = args["sitemap_urls"] || Config.sitemap_urls()
    limit = args["limit"]

    Logger.info("""
    🗺️ Starting Sortiraparis sitemap sync
    Sitemaps: #{length(sitemap_urls)}
    Limit: #{limit || "unlimited"}
    """)

    # TODO Phase 3: Implement full sitemap discovery workflow
    # For now, return skeleton structure

    with {:ok, event_urls} <- fetch_event_urls_from_sitemaps(sitemap_urls, limit),
         {:ok, fresh_urls} <- filter_fresh_events(event_urls),
         {:ok, scheduled_count} <- schedule_event_detail_jobs(fresh_urls) do
      Logger.info("""
      ✅ Sortiraparis sync completed
      Total URLs found: #{length(event_urls)}
      Fresh URLs: #{length(fresh_urls)}
      Detail jobs scheduled: #{scheduled_count}
      """)

      {:ok,
       %{
         sitemaps_processed: length(sitemap_urls),
         urls_found: length(event_urls),
         fresh_urls: length(fresh_urls),
         jobs_scheduled: scheduled_count,
         mode: "sitemap"
       }}
    else
      {:error, reason} = error ->
        Logger.error("❌ Failed to sync Sortiraparis: #{inspect(reason)}")
        error
    end
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def fetch_events(_city, _limit, _options) do
    # Sortiraparis uses sitemap-based discovery instead of direct fetch
    # This callback is not used for sitemap sources
    Logger.warning("⚠️ fetch_events called on sitemap-based source - this should not happen")
    {:ok, []}
  end

  @impl EventasaurusDiscovery.Sources.BaseJob
  def transform_events(raw_events) do
    # TODO Phase 4: Implement full transformation
    # For now, return empty list (no events fetched in Phase 2)
    Logger.debug("🔄 Transform called with #{length(raw_events)} events (skeleton)")
    []
  end

  @doc """
  Source configuration for BaseJob.
  """
  def source_config do
    %{
      name: "Sortiraparis",
      slug: "sortiraparis",
      website_url: Config.base_url(),
      priority: 65,
      config: %{
        "rate_limit_seconds" => Config.rate_limit(),
        "timeout" => Config.timeout(),
        "language" => "en",
        "supports_pagination" => false,
        "discovery_method" => "sitemap",
        "requires_geocoding" => true,
        "geocoding_strategy" => "multi_provider"
      }
    }
  end

  # Private functions

  defp fetch_event_urls_from_sitemaps(sitemap_urls, limit) do
    Logger.info("🌐 Fetching event URLs from #{length(sitemap_urls)} sitemaps")

    # Fetch and extract URLs from each sitemap
    all_urls =
      sitemap_urls
      |> Enum.flat_map(fn sitemap_url ->
        Logger.debug("📄 Fetching sitemap: #{sitemap_url}")

        case Client.fetch_sitemap(sitemap_url) do
          {:ok, urls} ->
            Logger.debug("✅ Found #{length(urls)} URLs in #{sitemap_url}")
            urls

          {:error, :bot_protection} ->
            Logger.warning("🚫 Bot protection 401 on sitemap: #{sitemap_url}")
            []

          {:error, reason} ->
            Logger.warning("⚠️ Failed to fetch sitemap #{sitemap_url}: #{inspect(reason)}")
            []
        end
      end)

    Logger.info("📊 Total URLs extracted from sitemaps: #{length(all_urls)}")

    # Filter to only event URLs
    case UrlFilter.filter_event_urls(all_urls) do
      {:ok, event_urls, stats} ->
        Logger.info("""
        🎯 URL Filtering Results:
        - Total URLs: #{stats.total}
        - Duplicates removed: #{stats.duplicates_removed}
        - Event URLs: #{stats.filtered}
        - Excluded (non-events): #{stats.excluded}
        """)

        # Apply limit if specified
        limited_urls =
          if limit do
            Enum.take(event_urls, limit)
          else
            event_urls
          end

        if limit && length(limited_urls) < length(event_urls) do
          Logger.info("🔢 Applying limit: #{length(limited_urls)}/#{length(event_urls)} URLs")
        end

        {:ok, limited_urls}

      {:error, reason} = error ->
        Logger.error("❌ Failed to filter URLs: #{inspect(reason)}")
        error
    end
  end

  defp filter_fresh_events(event_urls) do
    Logger.info("🔍 Processing #{length(event_urls)} event URLs")

    # Process all URLs - database-level deduplication will handle existing events
    # via unique constraint on (source, external_id)
    Logger.info("""
    ✨ URL Processing:
    - Total URLs to process: #{length(event_urls)}
    - Deduplication: Handled by database constraints
    """)

    {:ok, event_urls}
  end

  defp schedule_event_detail_jobs(event_urls) do
    Logger.info("📅 Scheduling #{length(event_urls)} event detail jobs")

    if length(event_urls) == 0 do
      Logger.info("ℹ️ No jobs to schedule")
      {:ok, 0}
    else
      # Schedule EventDetailJob for each URL with staggered delays
      scheduled_jobs =
        event_urls
        |> Enum.with_index()
        |> Enum.map(fn {url, idx} ->
          # Stagger jobs to respect rate limiting (5 seconds per request)
          delay_seconds = idx * Config.rate_limit()
          scheduled_at = DateTime.add(DateTime.utc_now(), delay_seconds, :second)

          article_id = Config.extract_article_id(url)

          job_args = %{
            "source" => "sortiraparis",
            "url" => url,
            "event_metadata" => %{
              "article_id" => article_id,
              "external_id_base" => Config.generate_external_id(article_id)
            }
          }

          EventasaurusDiscovery.Sources.Sortiraparis.Jobs.EventDetailJob.new(
            job_args,
            queue: :scraper_detail,
            scheduled_at: scheduled_at
          )
          |> Oban.insert()
        end)

      # Count successful insertions
      successful_count =
        Enum.count(scheduled_jobs, fn
          {:ok, _} -> true
          _ -> false
        end)

      failed_count = length(scheduled_jobs) - successful_count

      if failed_count > 0 do
        Logger.warning("⚠️ Failed to schedule #{failed_count} detail jobs")
      end

      Logger.info("✅ Successfully scheduled #{successful_count}/#{length(event_urls)} detail jobs")
      {:ok, successful_count}
    end
  end
end
