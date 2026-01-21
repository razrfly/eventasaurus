defmodule EventasaurusDiscovery.Sources.Sortiraparis.Jobs.EventDetailJob do
  @moduledoc """
  Oban job for fetching and processing individual Sortiraparis event details.

  Scheduled by SyncJob for each fresh event URL discovered in sitemaps.

  ## Responsibilities

  1. Fetch event HTML page
  2. Extract event data (title, dates, venue, description, etc.)
  3. **Date-based expiration filtering** (Phase 1 - NEW)
  4. Transform to unified format using Transformer
  5. Process through VenueProcessor (geocoding, deduplication)
  6. Store in database

  ## Date-Based Expiration Filtering (Phase 1)

  Sortiraparis keeps expired events in sitemap forever as archived content.
  To prevent re-creating expired events, we filter based on parsed end dates:

  - Extract end date from raw event data (if available)
  - Skip events with `ends_at < NOW() - 7 days` (grace period)
  - Events with unparseable dates continue to transformer (unknown occurrence handling)

  **Benefits:**
  - Prevents expired events from being created/updated in database
  - Primary expiration mechanism for sortiraparis (sitemap removal doesn't occur)
  - Reduces database churn from re-processing expired content

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

  **Phase 1**: Date-based expiration filtering (IMPLEMENTED)
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
  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, id: job_id} = job) do
    url = args["url"]
    secondary_url = args["secondary_url"]
    event_metadata = args["event_metadata"] || %{}
    is_bilingual = event_metadata["bilingual"] || false

    # Extract external_id for metrics tracking with fallback to job.id
    # Ensures external_id is always a string
    external_id =
      to_string(
        event_metadata["external_id_base"] || event_metadata["article_id"] || url || job_id
      )

    if is_bilingual do
      Logger.info("🌐 Fetching bilingual Sortiraparis event: #{url} + #{secondary_url}")
    else
      Logger.info("🔍 Fetching Sortiraparis event details: #{url}")
    end

    result =
      with {:ok, raw_event} <- fetch_and_extract_event(url, secondary_url, event_metadata),
           :ok <- check_event_not_expired(raw_event, url),
           {:ok, transformed_events} <- transform_events(raw_event),
           {:ok, processed_count} <- process_events(transformed_events) do
        Logger.info("""
        ✅ Sortiraparis event detail job completed
        Primary URL: #{url}
        Secondary URL: #{secondary_url || "none"}
        Bilingual: #{is_bilingual}
        Events created: #{processed_count}
        """)

        {:ok,
         %{
           url: url,
           secondary_url: secondary_url,
           bilingual: is_bilingual,
           events_created: processed_count,
           article_id: event_metadata["article_id"]
         }}
      else
        {:error, :expired} ->
          Logger.info("⏭️ Skipping expired event: #{url}")
          {:ok, :skipped_expired}

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

    # Track metrics in job metadata
    case result do
      {:ok, _} ->
        MetricsTracker.record_success(job, external_id)
        result

      {:error, reason} ->
        MetricsTracker.record_failure(job, reason, external_id)
        result

      _other ->
        result
    end
  end

  # Private functions

  defp fetch_and_extract_event(primary_url, nil = _secondary_url, event_metadata) do
    # Single language mode (backwards compatible)
    Logger.debug("📄 Single language mode: fetching #{primary_url}")

    with {:ok, html} <- fetch_page(primary_url),
         {:ok, raw_event} <- extract_single_language(html, primary_url, event_metadata) do
      {:ok, raw_event}
    end
  end

  defp fetch_and_extract_event(primary_url, secondary_url, event_metadata) do
    # Bilingual mode: fetch both language versions with retry logic for secondary URL
    Logger.debug("🌐 Bilingual mode: fetching #{primary_url} + #{secondary_url}")

    with {:ok, primary_html} <- fetch_page(primary_url),
         {:ok, secondary_html} <- fetch_secondary_with_retry(secondary_url),
         {:ok, primary_data} <-
           extract_single_language(primary_html, primary_url, event_metadata),
         {:ok, secondary_data} <-
           extract_single_language(secondary_html, secondary_url, event_metadata),
         {:ok, merged_event} <-
           merge_translations(primary_data, secondary_data, primary_url, secondary_url) do
      Logger.info("✅ Successfully merged bilingual event data")
      {:ok, merged_event}
    else
      {:error, reason} ->
        Logger.warning(
          "⚠️ Bilingual fetch failed after retries (#{inspect(reason)}), attempting fallback to primary URL only: #{primary_url}"
        )

        Logger.warning("   Secondary URL that failed: #{secondary_url}")

        # Fallback: fetch primary language only, but track the failure
        case fetch_and_extract_event(primary_url, nil, event_metadata) do
          {:ok, raw_event} ->
            # Add metadata to track that bilingual fetch failed
            tracked_event =
              Map.merge(raw_event, %{
                "bilingual_fetch_attempted" => true,
                "bilingual_fetch_failed" => true,
                "bilingual_fetch_failure_reason" => inspect(reason),
                "attempted_secondary_url" => secondary_url
              })

            {:ok, tracked_event}

          {:error, _} = error ->
            error
        end
    end
  end

  defp fetch_page(url) do
    Logger.debug("📄 Fetching page: #{url}")

    case Client.fetch_page(url) do
      {:ok, html} ->
        Logger.debug("✅ Fetched #{byte_size(html)} bytes from #{url}")
        {:ok, html}

      {:error, reason} = error ->
        Logger.warning("⚠️ Failed to fetch #{url}: #{inspect(reason)}")
        error
    end
  end

  defp fetch_secondary_with_retry(secondary_url, attempt \\ 1, max_attempts \\ 3) do
    case fetch_page(secondary_url) do
      {:ok, html} ->
        if attempt > 1 do
          Logger.info("🎉 Secondary URL fetch succeeded on attempt #{attempt}/#{max_attempts}")
        end

        {:ok, html}

      {:error, :bot_protection} when attempt < max_attempts ->
        # Exponential backoff for bot protection (2^attempt seconds)
        delay = round(:math.pow(2, attempt) * 1000)

        Logger.info(
          "🔄 Bot protection detected, retrying secondary URL after #{delay}ms (attempt #{attempt + 1}/#{max_attempts})"
        )

        Process.sleep(delay)
        fetch_secondary_with_retry(secondary_url, attempt + 1, max_attempts)

      {:error, :timeout} when attempt < max_attempts ->
        # Linear backoff for timeouts (attempt * 2 seconds)
        delay = attempt * 2000

        Logger.info(
          "🔄 Timeout detected, retrying secondary URL after #{delay}ms (attempt #{attempt + 1}/#{max_attempts})"
        )

        Process.sleep(delay)
        fetch_secondary_with_retry(secondary_url, attempt + 1, max_attempts)

      {:error, _reason} = error ->
        # Other errors don't retry (404, network errors, etc.)
        if attempt > 1 do
          Logger.warning("❌ Secondary URL fetch failed after #{attempt} attempts")
        end

        error
    end
  end

  defp extract_single_language(html, url, event_metadata) do
    Logger.debug("📄 Extracting event data from #{url}")

    case EventExtractor.extract(html, url) do
      {:ok, event_data} ->
        # Try to extract venue data, but don't fail if it's missing
        # Some events (outdoor exhibitions, walking tours) don't have specific venues
        venue_data =
          case VenueExtractor.extract(html) do
            {:ok, venue} ->
              Logger.debug("✅ Venue extracted: #{venue["name"]}")
              venue

            {:error, :venue_name_not_found} ->
              Logger.debug("ℹ️ No venue data (outdoor/district event)")
              nil

            {:error, :address_not_found} ->
              Logger.debug("ℹ️ No venue address found")
              nil

            {:error, reason} ->
              Logger.warning("⚠️ Venue extraction failed: #{inspect(reason)}")
              nil
          end

        raw_event =
          Map.merge(event_data, %{
            "url" => url,
            "venue" => venue_data,
            "article_id" => event_metadata["article_id"]
          })

        Logger.debug("✅ Extracted event data from #{url}")
        {:ok, raw_event}

      {:error, reason} = error ->
        Logger.warning("⚠️ Failed to extract event data from #{url}: #{inspect(reason)}")
        error
    end
  end

  defp merge_translations(primary_data, secondary_data, primary_url, secondary_url) do
    Logger.debug("🔄 Merging translations from #{primary_url} + #{secondary_url}")

    # Detect languages from URLs
    primary_lang = detect_language(primary_url)
    secondary_lang = detect_language(secondary_url)

    Logger.debug("🌐 Detected languages: primary=#{primary_lang}, secondary=#{secondary_lang}")

    # Merge description translations
    description_translations = %{
      primary_lang => primary_data["description"] || "",
      secondary_lang => secondary_data["description"] || ""
    }

    # Use primary data as base, add translation map and success tracking
    merged =
      primary_data
      |> Map.put("description_translations", description_translations)
      |> Map.put("source_language", primary_lang)
      |> Map.put("bilingual_fetch_attempted", true)
      |> Map.put("bilingual_fetch_succeeded", true)

    Logger.debug("✅ Merged translations: #{map_size(description_translations)} languages")
    {:ok, merged}
  end

  defp detect_language(url) when is_binary(url) do
    if String.contains?(url, "/en/") do
      "en"
    else
      "fr"
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
    source = JobRepo.one(from(s in Source, where: s.slug == "sortiraparis"))

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

      Logger.info(
        "📊 Successfully processed #{processed_count}/#{length(transformed_events)} events"
      )

      {:ok, processed_count}
    end
  end

  # Check if event is expired based on parsed end date.
  #
  # Uses 7-day grace period to avoid filtering events that might be updated.
  #
  # Returns:
  # - `:ok` if event is not expired or has no parseable end date
  # - `{:error, :expired}` if event ended more than 7 days ago
  #
  # Expiration Logic:
  # 1. Extract dates from raw_event["dates"] or raw_event["date_string"]
  # 2. Try to find latest date (end date)
  # 3. If ends_at < NOW() - 7 days → expired
  # 4. If can't parse dates → not expired (will fall into unknown occurrence handling)
  defp check_event_not_expired(raw_event, url) do
    grace_period_days = 7
    cutoff = DateTime.add(DateTime.utc_now(), -grace_period_days * 86400, :second)

    case extract_end_date_from_raw_event(raw_event) do
      {:ok, ends_at} ->
        if DateTime.compare(ends_at, cutoff) == :lt do
          Logger.info("""
          ⏭️ Skipping expired event (date-based filtering)
          URL: #{url}
          End date: #{Calendar.strftime(ends_at, "%Y-%m-%d")}
          Cutoff: #{Calendar.strftime(cutoff, "%Y-%m-%d")}
          Grace period: #{grace_period_days} days
          """)

          {:error, :expired}
        else
          Logger.debug("✅ Event not expired (ends_at: #{Calendar.strftime(ends_at, "%Y-%m-%d")})")
          :ok
        end

      {:error, :no_end_date} ->
        # No parseable end date - let it continue to transformer
        # Will be handled by unknown occurrence fallback if needed
        Logger.debug("ℹ️ No parseable end date, continuing to transformation")
        :ok
    end
  end

  # Extract end date from raw event data for expiration checking.
  #
  # Tries multiple strategies:
  # 1. Look for pre-parsed dates list (from EventExtractor)
  # 2. Look for date_string field
  #
  # Returns the LATEST date found (end date for exhibitions/multi-date events).
  defp extract_end_date_from_raw_event(raw_event) do
    cond do
      # Strategy 1: Pre-parsed dates list
      is_list(raw_event["dates"]) && length(raw_event["dates"]) > 0 ->
        dates = raw_event["dates"]
        # Dates could be DateTime structs or ISO8601 strings
        parsed_dates =
          Enum.flat_map(dates, fn
            %DateTime{} = dt ->
              [dt]

            date_string when is_binary(date_string) ->
              case DateTime.from_iso8601(date_string) do
                {:ok, dt, _offset} -> [dt]
                _ -> []
              end

            _ ->
              []
          end)

        if Enum.empty?(parsed_dates) do
          {:error, :no_end_date}
        else
          # Return latest date (end date)
          latest = Enum.max_by(parsed_dates, &DateTime.to_unix/1)
          {:ok, latest}
        end

      # Strategy 2: date_string field (would need parsing - complex)
      is_binary(raw_event["date_string"]) ->
        # Date string parsing is complex (French dates, ranges, etc.)
        # The transformer handles this via MultilingualDateParser
        # For now, if we only have unparsed date_string, we can't determine expiration
        # Let it continue to transformer which will handle it
        {:error, :no_end_date}

      # No dates found
      true ->
        {:error, :no_end_date}
    end
  end
end
