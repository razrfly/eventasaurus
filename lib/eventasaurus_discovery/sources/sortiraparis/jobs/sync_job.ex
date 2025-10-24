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
    # Get sitemap configs (list of %{url: ..., language: ...})
    sitemap_configs = args["sitemap_urls"] || Config.sitemap_urls()
    limit = args["limit"]
    # Optional: :en, :fr, or :all (default)
    language_filter = args["language"]

    # Apply language filter if specified
    filtered_sitemaps =
      if language_filter do
        Enum.filter(sitemap_configs, fn config ->
          config.language == to_string(language_filter)
        end)
      else
        sitemap_configs
      end

    Logger.info("""
    🗺️ Starting Sortiraparis bilingual sitemap sync
    Sitemaps: #{length(filtered_sitemaps)} (#{Enum.map_join(filtered_sitemaps, ", ", & &1.language)})
    Limit: #{limit || "unlimited"}
    """)

    # TODO Phase 3: Implement full sitemap discovery workflow
    # For now, return skeleton structure

    with {:ok, event_urls_with_metadata} <- fetch_event_urls_from_sitemaps(filtered_sitemaps),
         {:ok, grouped_articles} <- group_urls_by_article(event_urls_with_metadata),
         {:ok, fresh_articles} <- filter_fresh_events(grouped_articles, limit),
         {:ok, scheduled_count} <- schedule_event_detail_jobs(fresh_articles) do
      total_urls = length(event_urls_with_metadata)
      unique_articles = map_size(grouped_articles)

      Logger.info("""
      ✅ Sortiraparis bilingual sync completed
      Total URLs found: #{total_urls}
      Unique articles: #{unique_articles}
      Fresh articles: #{length(fresh_articles)}
      Detail jobs scheduled: #{scheduled_count}
      """)

      {:ok,
       %{
         sitemaps_processed: length(filtered_sitemaps),
         urls_found: total_urls,
         unique_articles: unique_articles,
         fresh_articles: length(fresh_articles),
         jobs_scheduled: scheduled_count,
         mode: "bilingual_sitemap"
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

  defp fetch_event_urls_from_sitemaps(sitemap_configs) do
    Logger.info("🌐 Fetching event URLs from #{length(sitemap_configs)} sitemaps")

    # Fetch and extract URLs with metadata from each sitemap
    all_url_entries =
      sitemap_configs
      |> Enum.flat_map(fn %{url: sitemap_url, language: language} ->
        Logger.debug("📄 Fetching #{language} sitemap: #{sitemap_url}")

        case Client.fetch_sitemap(sitemap_url, language: language) do
          {:ok, url_entries} ->
            Logger.debug(
              "✅ Found #{length(url_entries)} URLs in #{language} sitemap: #{sitemap_url}"
            )

            url_entries

          {:error, :bot_protection} ->
            Logger.warning("🚫 Bot protection 401 on sitemap: #{sitemap_url}")
            []

          {:error, reason} ->
            Logger.warning("⚠️ Failed to fetch sitemap #{sitemap_url}: #{inspect(reason)}")
            []
        end
      end)

    Logger.info("📊 Total URL entries extracted from sitemaps: #{length(all_url_entries)}")

    # Filter to only event URLs (extract just URLs for filtering)
    just_urls = Enum.map(all_url_entries, & &1.url)

    case UrlFilter.filter_event_urls(just_urls) do
      {:ok, event_urls, stats} ->
        Logger.info("""
        🎯 URL Filtering Results:
        - Total URLs: #{stats.total}
        - Duplicates removed: #{stats.duplicates_removed}
        - Event URLs: #{stats.filtered}
        - Excluded (non-events): #{stats.excluded}
        """)

        # Keep only entries whose URLs passed the filter
        event_url_set = MapSet.new(event_urls)

        event_entries =
          Enum.filter(all_url_entries, fn entry ->
            MapSet.member?(event_url_set, entry.url)
          end)

        # DON'T apply limit here - we need ALL URLs to ensure complete language pairs
        # Limit will be applied to ARTICLES (not URL entries) in filter_fresh_events/1
        Logger.info("📊 Event URL entries to process: #{length(event_entries)}")

        {:ok, event_entries}

      {:error, reason} = error ->
        Logger.error("❌ Failed to filter URLs: #{inspect(reason)}")
        error
    end
  end

  defp group_urls_by_article(url_entries) do
    Logger.info("🔗 Grouping #{length(url_entries)} URLs by article_id")

    # Group URLs by article_id: %{article_id => %{"en" => url, "fr" => url}}
    grouped =
      url_entries
      |> Enum.group_by(& &1.article_id)
      |> Enum.into(%{}, fn {article_id, entries} ->
        # Create map of language => URL
        language_urls =
          entries
          |> Enum.into(%{}, fn entry ->
            {entry.language, entry.url}
          end)

        {article_id, language_urls}
      end)
      |> Enum.reject(fn {article_id, _} -> is_nil(article_id) end)
      |> Enum.into(%{})

    # Log statistics
    en_count = Enum.count(grouped, fn {_, langs} -> Map.has_key?(langs, "en") end)
    fr_count = Enum.count(grouped, fn {_, langs} -> Map.has_key?(langs, "fr") end)

    both_count =
      Enum.count(grouped, fn {_, langs} ->
        Map.has_key?(langs, "en") && Map.has_key?(langs, "fr")
      end)

    Logger.info("""
    📊 Article Grouping Results:
    - Unique articles: #{map_size(grouped)}
    - With English: #{en_count}
    - With French: #{fr_count}
    - With both languages: #{both_count}
    """)

    {:ok, grouped}
  end

  defp filter_fresh_events(grouped_articles, limit) do
    article_count = map_size(grouped_articles)
    Logger.info("🔍 Processing #{article_count} unique articles")

    # Process all articles - database-level deduplication will handle existing events
    # via unique constraint on (source, external_id)
    # Convert grouped map to list of {article_id, language_urls} tuples
    articles_list = Enum.to_list(grouped_articles)

    # Apply limit to ARTICLES (not URL entries)
    # This ensures we get complete language pairs for each article
    limited_articles =
      if limit do
        Enum.take(articles_list, limit)
      else
        articles_list
      end

    if limit && length(limited_articles) < length(articles_list) do
      Logger.info(
        "🔢 Applying limit: #{length(limited_articles)}/#{length(articles_list)} articles"
      )
    end

    Logger.info("""
    ✨ Article Processing:
    - Total articles available: #{article_count}
    - Articles to process (after limit): #{length(limited_articles)}
    - Deduplication: Handled by database constraints
    """)

    {:ok, limited_articles}
  end

  defp schedule_event_detail_jobs(articles_list) do
    Logger.info("📅 Scheduling #{length(articles_list)} bilingual event detail jobs")

    if length(articles_list) == 0 do
      Logger.info("ℹ️ No jobs to schedule")
      {:ok, 0}
    else
      # Schedule EventDetailJob for each article with staggered delays
      # Each job will receive both language URLs (if available)
      scheduled_jobs =
        articles_list
        |> Enum.with_index()
        |> Enum.map(fn {{article_id, language_urls}, idx} ->
          # Stagger jobs to respect rate limiting (5 seconds per request)
          # Note: bilingual fetching will take 2x time per article
          delay_seconds = idx * Config.rate_limit() * 2
          scheduled_at = DateTime.add(DateTime.utc_now(), delay_seconds, :second)

          # Use English URL as primary, French as secondary
          primary_url = Map.get(language_urls, "en") || Map.get(language_urls, "fr")

          secondary_url =
            if Map.has_key?(language_urls, "en") && Map.has_key?(language_urls, "fr") do
              Map.get(language_urls, "fr")
            else
              nil
            end

          job_args = %{
            "source" => "sortiraparis",
            "url" => primary_url,
            "secondary_url" => secondary_url,
            "event_metadata" => %{
              "article_id" => article_id,
              "external_id_base" => Config.generate_external_id(article_id),
              "languages" => Map.keys(language_urls),
              "bilingual" => !is_nil(secondary_url)
            }
          }

          Logger.debug(
            "📋 Scheduling article #{article_id}: EN=#{!is_nil(Map.get(language_urls, "en"))}, FR=#{!is_nil(Map.get(language_urls, "fr"))}"
          )

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
      bilingual_count = Enum.count(articles_list, fn {_, langs} -> map_size(langs) > 1 end)

      if failed_count > 0 do
        Logger.warning("⚠️ Failed to schedule #{failed_count} detail jobs")
      end

      Logger.info("""
      ✅ Successfully scheduled #{successful_count}/#{length(articles_list)} detail jobs
      🌐 Bilingual articles: #{bilingual_count}
      """)

      {:ok, successful_count}
    end
  end
end
