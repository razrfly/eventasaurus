defmodule EventasaurusDiscovery.Sources.GeeksWhoDrink.Jobs.VenueDetailJob do
  @moduledoc """
  Scrapes individual venue detail pages and creates events.

  ## Workflow
  1. Fetch venue detail page HTML
  2. Extract additional venue details (website, phone, description, etc.)
  3. Extract quizmaster data from AJAX API endpoint
  4. Parse time_text to generate next event occurrence
  5. Transform to unified format with quizmaster in description + metadata
  6. Process through Processor.process_source_data/2

  ## Critical Features
  - Uses Processor.process_source_data/2 (NOT manual VenueStore/EventStore)
  - GPS coordinates already provided (no geocoding needed)
  - Quizmaster stored in description AND metadata (hybrid approach)
  - EventProcessor updates last_seen_at timestamp
  - Stable external_ids for deduplication
  - Weekly recurring events with recurrence_rule

  ## Quizmaster Handling (Hybrid Approach)
  - Extract from AJAX endpoint: mb_display_venue_events
  - Store in description: "Weekly trivia at [Venue] with Quizmaster [Name]"
  - Store in metadata: {"quizmaster": {"name": "...", "profile_image": "..."}}
  - NOT stored in performers table (venue-specific hosts, not shareable)
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3,
    priority: 2

  require Logger

  alias EventasaurusDiscovery.Sources.GeeksWhoDrink.{
    Extractors.VenueDetailsExtractor,
    Transformer
  }

  alias EventasaurusDiscovery.Sources.Shared.RecurringEventParser

  alias EventasaurusDiscovery.Sources.Processor
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    venue_id = args["venue_id"]
    venue_url = args["venue_url"]
    venue_title = args["venue_title"]
    venue_data = string_keys_to_atoms(args["venue_data"])
    source_id = args["source_id"]

    # Use venue_id as external_id for metrics tracking
    external_id = "geeks_who_drink_venue_#{venue_id}"

    Logger.info("🔍 Processing Geeks Who Drink venue: #{venue_title} (ID: #{venue_id})")
    Logger.info("📋 PHASE 1 DEBUG: Initial venue_data keys: #{inspect(Map.keys(venue_data))}")

    result =
      with {:ok, additional_details} <- fetch_additional_details(venue_url),
           _ <- log_additional_details(additional_details),
           # CRITICAL FIX: Determine timezone BEFORE calculating next_occurrence
           # Previously hardcoded to "America/New_York", causing 1-3 hour errors for non-Eastern venues
           venue_timezone <- determine_timezone(venue_data),
           {:ok, {day_of_week, time}} <-
             parse_time_from_sources(venue_data.time_text, additional_details),
           {:ok, next_occurrence} <- calculate_next_occurrence(day_of_week, time, venue_timezone),
           enriched_venue_data <-
             enrich_venue_data(venue_data, additional_details, next_occurrence),
           _ <- log_enriched_data(enriched_venue_data),
           {:ok, transformed} <- transform_and_validate(enriched_venue_data),
           _ <- log_transformed_data(transformed),
           {:ok, events} <- process_event(transformed, source_id) do
        Logger.info("✅ Successfully processed venue: #{venue_title}")

        # Log quizmaster from metadata (hybrid approach - not stored in performers table)
        quizmaster_name = get_in(transformed, [:metadata, :quizmaster, :name])

        if quizmaster_name do
          Logger.info("🎭 Quizmaster: #{quizmaster_name} (stored in description + metadata)")
        end

        log_results(events)
        {:ok, %{events: length(events)}}
      else
        {:error, reason} = error ->
          Logger.error("❌ Failed to process venue #{venue_url}: #{inspect(reason)}")
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

  # Convert string keys to atoms for venue_data map
  # Only convert keys that are already existing atoms, keep others as strings
  defp string_keys_to_atoms(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) ->
        try do
          {String.to_existing_atom(key), value}
        rescue
          ArgumentError ->
            # Key doesn't exist as atom, keep as string
            {key, value}
        end

      {key, value} ->
        {key, value}
    end)
  end

  defp fetch_additional_details(venue_url) do
    case VenueDetailsExtractor.extract_additional_details(venue_url) do
      {:ok, details} ->
        {:ok, details}

      {:error, reason} ->
        Logger.warning("⚠️ Failed to fetch additional details, using defaults: #{inspect(reason)}")
        # Return empty map as fallback - transformer will handle missing fields
        {:ok, %{}}
    end
  end

  # Parse time from two sources:
  # 1. Day of week from time_text (e.g., "Thursdays at")
  # 2. Time from additional_details.start_time (e.g., "20:00")
  #
  # Special case: time_text="at" (no day) indicates special one-time events
  defp parse_time_from_sources(nil, _additional_details), do: {:error, "Missing time_text"}

  defp parse_time_from_sources("at", _additional_details) do
    Logger.info("ℹ️ Special event with no recurring schedule (time_text='at') - skipping")
    {:error, "Special event with no recurring schedule"}
  end

  defp parse_time_from_sources(time_text, additional_details) do
    with {:ok, day_of_week} <- RecurringEventParser.parse_day_of_week(time_text),
         time_string <- get_time_string(additional_details),
         {:ok, time} <- RecurringEventParser.parse_time(time_string) do
      {:ok, {day_of_week, time}}
    else
      {:error, reason} ->
        Logger.warning("⚠️ Failed to parse time from '#{time_text}': #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Get time string from additional_details or use default
  defp get_time_string(additional_details) do
    case additional_details[:start_time] do
      time when is_binary(time) and time != "" -> time
      # Default fallback matching trivia_advisor
      _ -> "20:00"
    end
  end

  defp calculate_next_occurrence(day_of_week, time, timezone) do
    # Calculate next occurrence in venue's actual timezone (not hardcoded!)
    # This fixes the bug where all venues were calculated in Eastern timezone
    Logger.info("🕐 Calculating next occurrence for #{day_of_week} at #{time} in #{timezone}")
    next_dt = RecurringEventParser.next_occurrence(day_of_week, time, timezone)
    {:ok, next_dt}
  rescue
    error ->
      Logger.error("❌ Failed to calculate next occurrence: #{inspect(error)}")
      {:error, "Failed to calculate next occurrence"}
  end

  # Process performer data through PerformerStore
  # Enrich venue data with additional details and event occurrence
  defp enrich_venue_data(venue_data, additional_details, next_occurrence) do
    venue_data
    |> normalize_coordinates()
    |> Map.merge(additional_details)
    |> Map.put(:starts_at, next_occurrence)
    # Add timezone dynamically from venue coordinates
    |> add_timezone()
  end

  # Determine timezone from venue coordinates using TzWorld
  defp add_timezone(venue_data) do
    timezone = determine_timezone(venue_data)
    Map.put(venue_data, :timezone, timezone)
  end

  defp determine_timezone(venue_data) do
    cond do
      # Priority 1: Use timezone if already provided by source
      is_binary(venue_data[:timezone]) ->
        venue_data[:timezone]

      # Priority 2: Use state-based fallback from address
      # TzWorld runtime lookups disabled (Issue #3334 Phase 2) - OOM prevention
      venue_data[:latitude] && venue_data[:longitude] ->
        Logger.debug(
          "TzWorld lookup skipped for venue #{venue_data[:venue_id]} at (#{venue_data[:latitude]}, #{venue_data[:longitude]}), using state-based fallback"
        )

        fallback_timezone_from_address(venue_data)

      # Priority 3: Fallback to Eastern (most common, but log warning)
      true ->
        Logger.warning(
          "Could not determine timezone for venue #{venue_data[:venue_id]} (no coordinates), using America/New_York fallback"
        )

        "America/New_York"
    end
  end

  # State-based fallback if TzWorld lookup fails
  defp fallback_timezone_from_address(venue_data) do
    case get_state_from_address(venue_data[:address]) do
      # West Coast
      state when state in ["CA", "WA", "OR", "NV"] ->
        "America/Los_Angeles"

      # Arizona (no DST)
      "AZ" ->
        "America/Phoenix"

      # Mountain Time
      state when state in ["MT", "CO", "UT", "NM", "WY", "ID"] ->
        "America/Denver"

      # Central Time
      state
      when state in [
             "IL",
             "TX",
             "MN",
             "MO",
             "WI",
             "IA",
             "KS",
             "OK",
             "AR",
             "LA",
             "MS",
             "AL",
             "TN",
             "KY",
             "IN",
             "MI",
             "ND",
             "SD",
             "NE"
           ] ->
        "America/Chicago"

      # Eastern Time (default)
      _ ->
        "America/New_York"
    end
  end

  # Extract state abbreviation from address string
  defp get_state_from_address(address) when is_binary(address) do
    # Example: "1898 S. Flatiron Court Boulder, CO 80301" → "CO"
    case Regex.run(~r/\b([A-Z]{2})\s+\d{5}/, address) do
      [_, state] -> state
      _ -> nil
    end
  end

  defp get_state_from_address(_), do: nil

  # Normalize lat/lon to latitude/longitude for transformer compatibility
  defp normalize_coordinates(venue_data) do
    venue_data
    |> Map.put(:latitude, venue_data[:lat] || venue_data[:latitude])
    |> Map.put(:longitude, venue_data[:lon] || venue_data[:longitude])
  end

  defp transform_and_validate(venue_data) do
    case Transformer.transform_event(venue_data) do
      transformed when is_map(transformed) ->
        {:ok, transformed}

      _ ->
        {:error, "Transformation failed"}
    end
  end

  # CRITICAL: Use Processor.process_source_data/3
  # This handles:
  # - VenueProcessor (no geocoding needed - GPS provided)
  # - EventProcessor creation/update
  # - last_seen_at timestamps
  # - Deduplication via external_id
  # - Scraper attribution via explicit scraper name
  defp process_event(transformed, source_id) do
    case Processor.process_source_data([transformed], source_id, "geeks_who_drink") do
      {:ok, events} -> {:ok, events}
      error -> error
    end
  end

  defp log_results(events) do
    count = length(events)

    Logger.info("""
    📊 Processing results:
    - Events processed: #{count}
    """)
  end

  # Phase 1 Debug Logging Functions
  defp log_additional_details(additional_details) do
    Logger.info("""
    📋 PHASE 1 DEBUG: Additional details extracted:
    - Keys present: #{inspect(Map.keys(additional_details))}
    - Description present: #{!is_nil(additional_details[:description])}
    - Description length: #{if additional_details[:description], do: String.length(additional_details[:description]), else: 0}
    - Description value: #{inspect(String.slice(additional_details[:description] || "", 0..100))}
    - Performer present: #{!is_nil(additional_details[:performer])}
    - Performer data: #{inspect(additional_details[:performer])}
    - Start time: #{inspect(additional_details[:start_time])}
    - Fee text: #{inspect(additional_details[:fee_text])}
    """)

    :ok
  end

  defp log_enriched_data(enriched_venue_data) do
    Logger.info("""
    📋 PHASE 1 DEBUG: Enriched venue data:
    - Keys present: #{inspect(Map.keys(enriched_venue_data))}
    - Description present: #{!is_nil(enriched_venue_data[:description])}
    - Description value: #{inspect(String.slice(enriched_venue_data[:description] || "", 0..100))}
    - Performer present: #{!is_nil(enriched_venue_data[:performer])}
    - Start time: #{inspect(enriched_venue_data[:start_time])}
    - Starts at: #{inspect(enriched_venue_data[:starts_at])}
    """)

    :ok
  end

  defp log_transformed_data(transformed) do
    Logger.info("""
    📋 PHASE 1 DEBUG: Transformed data:
    - Keys present: #{inspect(Map.keys(transformed))}
    - External ID: #{transformed[:external_id]}
    - Description present: #{!is_nil(transformed[:description])}
    - Description length: #{if transformed[:description], do: String.length(transformed[:description]), else: 0}
    - Description value: #{inspect(String.slice(transformed[:description] || "", 0..100))}
    - Recurrence rule present: #{!is_nil(transformed[:recurrence_rule])}
    - Recurrence rule: #{inspect(transformed[:recurrence_rule])}
    - Venue data keys: #{inspect(Map.keys(transformed[:venue_data] || %{}))}
    - Metadata keys: #{inspect(Map.keys(transformed[:metadata] || %{}))}
    """)

    :ok
  end
end
