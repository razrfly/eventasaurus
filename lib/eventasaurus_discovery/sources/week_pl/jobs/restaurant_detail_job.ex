defmodule EventasaurusDiscovery.Sources.WeekPl.Jobs.RestaurantDetailJob do
  @moduledoc """
  Time slot extraction and event creation job for week.pl restaurants.

  ## Responsibilities
  - Fetch restaurant details with available time slots
  - Transform restaurant slots into event occurrences
  - Process events through EventProcessor (handles consolidation)

  ## Optimization Strategy
  - EventProcessor handles consolidation by restaurant_date_id
  - last_seen_at tracking prevents duplicate event creation
  - Consolidation groups 44 slots into single daily event per restaurant
  - Provides 80-90% reduction in events through daily consolidation

  ## Data Flow
  1. Fetch detail endpoint with time slots
  2. Transform slots to event data (Transformer)
  3. Process through EventProcessor (consolidation happens here)
  4. Mark as seen (EventProcessor handles this via last_seen_at)

  ## Job Arguments
  - source_id: Source database ID
  - restaurant_id: week.pl restaurant ID
  - restaurant_slug: URL-friendly restaurant identifier
  - restaurant_name: Display name
  - region_id: City ID
  - region_name: City name
  - country: "Poland"
  - festival_code: Current festival code
  - festival_name: Festival display name
  - festival_price: Menu price
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3,
    priority: 3

  require Logger
  alias EventasaurusDiscovery.Sources.WeekPl.{Client, Config, Transformer, FestivalManager}
  alias EventasaurusDiscovery.Scraping.Processors.EventProcessor
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args:
            %{
              "source_id" => source_id,
              "restaurant_slug" => slug
            } = args,
          meta: meta
        } = job
      ) do
    external_id = "week_pl_restaurant_#{slug}"
    Logger.info("🍽️  [WeekPl.DetailJob] Processing restaurant: #{args["restaurant_name"]}")

    # Note: EventFreshnessChecker optimization happens at event level in EventProcessor
    # through consolidation logic and last_seen_at tracking
    result = fetch_and_process(args, source_id, meta)

    # Track success/failure based on processing outcome
    # Error messages use standard categories for ErrorCategories.categorize_error/1
    # See docs/error-handling-guide.md for category definitions
    case result do
      {:ok, %{"status" => "matched", "items_processed" => items}} when items > 0 ->
        MetricsTracker.record_success(job, external_id)
        result

      {:ok, %{"status" => "no_slots"}} ->
        MetricsTracker.record_success(job, external_id)
        result

      {:ok, %{"status" => "no_restaurant"}} ->
        MetricsTracker.record_failure(job, :venue_error, external_id)
        result

      {:ok, %{"status" => "matched", "items_processed" => 0}} ->
        # Silent failure - found restaurant but created 0 events
        MetricsTracker.record_failure(job, :data_quality_error, external_id)
        result

      # Transient errors - allow Oban to retry (don't track metrics yet)
      {:error, :api_error} = error ->
        Logger.warning("[WeekPl.DetailJob] API error, will retry")
        error

      {:error, :invalid_response} = error ->
        Logger.warning("[WeekPl.DetailJob] Invalid response structure, will retry")
        error

      {:error, :rate_limited} = error ->
        Logger.warning("[WeekPl.DetailJob] Rate limited, will retry")
        error

      {:error, reason} = error ->
        MetricsTracker.record_failure(job, reason, external_id)
        error

      unknown ->
        Logger.warning("[WeekPl.DetailJob] Unknown result status: #{inspect(unknown)}")
        MetricsTracker.record_failure(job, :uncategorized_error, external_id)
        {:ok, unknown}
    end
  end

  # Fetch restaurant details and process events
  defp fetch_and_process(args, source_id, meta) do
    %{
      "restaurant_id" => restaurant_id,
      "restaurant_slug" => slug,
      "region_name" => region_name
    } = args

    # Use current and near-future date range for availability (today through 2 weeks)
    dates = generate_date_range(0, 14)

    # Use popular dinner time slot (7:00 PM = 1140 minutes) - for logging only
    slot = 1140
    people_count = 2

    # Build query params for observability (Phase 2: #2332)
    query_params = %{
      "restaurant_id" => restaurant_id,
      "restaurant_slug" => slug,
      "region_name" => region_name,
      "date_range" => %{
        "start" => hd(dates),
        "end" => List.last(dates),
        "days" => length(dates)
      },
      "slot" => slot,
      "people_count" => people_count
    }

    # Rate limiting: 2 seconds between requests
    Process.sleep(Config.request_delay_ms())

    # Fetch restaurant details by ID (GraphQL API requires ID, not slug)
    case Client.fetch_restaurant_detail(
           restaurant_id,
           slug,
           region_name,
           hd(dates),
           slot,
           people_count
         ) do
      {:ok, response} ->
        process_restaurant_detail(response, args, source_id, dates, meta, query_params)

      {:error, :rate_limited} ->
        Logger.warning("[WeekPl.DetailJob] Rate limited for #{slug}, retrying...")
        {:error, :rate_limited}

      {:error, reason} ->
        Logger.error("[WeekPl.DetailJob] Failed to fetch #{slug}: #{inspect(reason)}")
        # Return error tuple to allow Oban retry for transient API failures
        {:error, :api_error}
    end
  end

  # Process restaurant detail response (Apollo GraphQL state format)
  defp process_restaurant_detail(
         %{"pageProps" => %{"apolloState" => apollo_state}},
         args,
         source_id,
         dates,
         meta,
         query_params
       )
       when is_map(apollo_state) do
    # Extract restaurant from Apollo state (keys like "Restaurant:3525")
    restaurant =
      apollo_state
      |> Enum.find(fn {key, _value} -> String.starts_with?(key, "Restaurant:") end)
      |> case do
        {_key, restaurant_data} -> restaurant_data
        nil -> nil
      end

    pipeline_id = Map.get(meta, "pipeline_id") || "week_pl_#{Date.utc_today()}"
    parent_job_id = Map.get(meta, "parent_job_id")

    case restaurant do
      nil ->
        Logger.warning(
          "[WeekPl.DetailJob] ❌ No restaurant found in Apollo state for #{args["restaurant_slug"]}"
        )

        {:ok,
         %{
           "job_role" => "detail_fetcher",
           "pipeline_id" => pipeline_id,
           "parent_job_id" => parent_job_id,
           "entity_id" => args["restaurant_slug"],
           "entity_type" => "restaurant",
           "status" => "no_restaurant",
           "items_processed" => 0,
           # Phase 2 observability enhancements (#2332)
           "query_params" => query_params,
           "api_response" => %{
             "has_apollo_state" => true,
             "restaurant_found" => false
           },
           "decision_context" => %{
             "error_type" => "no_restaurant_in_apollo_state",
             "apollo_keys_checked" => "Restaurant:*"
           }
         }}

      restaurant_data ->
        # Extract slots from Daily objects referenced by restaurant
        api_slots = extract_slots_from_apollo_state(restaurant_data, apollo_state, args)

        # Phase 3: Pattern-based fallback (#2333)
        # If API doesn't return time slots, generate standard restaurant booking times
        slots =
          if Enum.empty?(api_slots) do
            Logger.info(
              "[WeekPl.DetailJob] 📅 API returned 0 slots for #{args["restaurant_name"]}, using pattern-based generation"
            )

            generate_standard_time_slots()
          else
            api_slots
          end

        process_restaurant_slots(
          restaurant_data,
          slots,
          args,
          source_id,
          dates,
          meta,
          query_params,
          Enum.empty?(api_slots)
        )
    end
  end

  # Fallback for unexpected response structure
  defp process_restaurant_detail(response, args, _source_id, _dates, _meta, _query_params) do
    Logger.error("""
    [WeekPl.DetailJob] ❌ Unexpected response structure for #{args["restaurant_slug"]}
    Response keys: #{inspect(Map.keys(response))}
    Expected: %{"pageProps" => %{"apolloState" => %{"Restaurant:XXX" => {...}}}}
    Full response sample: #{inspect(response, pretty: true, limit: 50)}
    """)

    # Return error tuple to allow Oban retry for transient response parsing issues
    {:error, :invalid_response}
  end

  # Extract slots from Apollo GraphQL state
  # Slots are stored in Daily objects that are referenced by restaurant.reservables
  defp extract_slots_from_apollo_state(restaurant, apollo_state, args) do
    # Get reservables array (contains references like {"__ref" => "Daily:5450"})
    reservables = restaurant["reservables"] || []

    # Extract slot data from each Daily reference
    slots =
      reservables
      |> Enum.flat_map(fn
        %{"__ref" => daily_ref} ->
          # Get the Daily object from apollo_state
          case apollo_state[daily_ref] do
            nil ->
              Logger.warning(
                "[WeekPl.DetailJob] Daily reference #{daily_ref} not found in Apollo state"
              )

              []

            daily ->
              # Extract possibleSlots from Daily object
              possible_slots = daily["possibleSlots"] || []

              Logger.debug(
                "[WeekPl.DetailJob] Found #{length(possible_slots)} slots in #{daily_ref}"
              )

              possible_slots
          end

        _other ->
          []
      end)
      |> Enum.uniq()

    Logger.info(
      "[WeekPl.DetailJob] 🎯 Extracted #{length(slots)} unique slots for #{args["restaurant_name"]}"
    )

    slots
  end

  # Generate standard restaurant booking time slots (Phase 3: #2333)
  # Pattern: 18:00-22:00 in 30-minute intervals (matches observed website pattern)
  defp generate_standard_time_slots do
    # Time slots in minutes from midnight
    # 18:00 = 1080, 18:30 = 1110, 19:00 = 1140, 19:30 = 1170, 20:00 = 1200,
    # 20:30 = 1230, 21:00 = 1260, 21:30 = 1290, 22:00 = 1320
    [1080, 1110, 1140, 1170, 1200, 1230, 1260, 1290, 1320]
  end

  # Process restaurant slots and create events
  defp process_restaurant_slots(
         restaurant,
         slots,
         args,
         source_id,
         dates,
         meta,
         query_params,
         pattern_based
       ) do
    # Build festival data for transformer
    festival = %{
      name: args["festival_name"],
      code: args["festival_code"],
      price: args["festival_price"]
    }

    pipeline_id = Map.get(meta, "pipeline_id") || "week_pl_#{Date.utc_today()}"
    parent_job_id = Map.get(meta, "parent_job_id")

    if Enum.empty?(slots) do
      Logger.warning(
        "[WeekPl.DetailJob] ⚠️  Pattern generation returned 0 slots for #{args["restaurant_name"]} - this should not happen!"
      )

      {:ok,
       %{
         "job_role" => "detail_fetcher",
         "pipeline_id" => pipeline_id,
         "parent_job_id" => parent_job_id,
         "entity_id" => args["restaurant_slug"],
         "entity_type" => "restaurant",
         "status" => "no_slots",
         "items_processed" => 0,
         # Phase 2 observability enhancements (#2332)
         "query_params" => query_params,
         "api_response" => %{
           "restaurant_found" => true,
           "slots_extracted" => 0,
           "daily_references_found" => 0,
           "pattern_based" => pattern_based
         },
         "decision_context" => %{
           "slots_empty" => true,
           "pattern_generation_failed" => pattern_based,
           "possible_reasons" =>
             if(pattern_based,
               do: ["pattern generation bug"],
               else: ["no availability", "fully booked", "date out of range"]
             )
         }
       }}
    else
      # Phase 4: Get festival container ID for linking events (#2334)
      festival_container_id = args["festival_container_id"]

      # Process each date with available slots
      results =
        dates
        |> Enum.flat_map(fn date ->
          # Transform each slot into an event
          Enum.map(slots, fn slot ->
            event_data =
              Transformer.transform_restaurant_slot(
                restaurant,
                slot,
                date,
                festival,
                args["region_name"]
              )

            process_event(event_data, source_id, festival_container_id)
          end)
        end)

      succeeded = Enum.count(results, fn {status, _} -> status == :ok end)
      failed = length(results) - succeeded

      Logger.info(
        "[WeekPl.DetailJob] ✅ Processed #{succeeded} events, #{failed} failed for #{args["restaurant_name"]}"
      )

      {:ok,
       %{
         "job_role" => "detail_fetcher",
         "pipeline_id" => pipeline_id,
         "parent_job_id" => parent_job_id,
         "entity_id" => args["restaurant_slug"],
         "entity_type" => "restaurant",
         "status" => "matched",
         "items_processed" => succeeded,
         "items_failed" => failed,
         # Phase 2 observability enhancements (#2332)
         "query_params" => query_params,
         "api_response" => %{
           "restaurant_found" => true,
           "slots_extracted" => length(slots),
           "dates_processed" => length(dates),
           "total_attempts" => length(slots) * length(dates),
           # Phase 3: #2333
           "pattern_based" => pattern_based
         },
         "decision_context" => %{
           "slots_available" => true,
           "slot_source" => if(pattern_based, do: "pattern_based_generation", else: "api_data"),
           "consolidation" => "EventProcessor handles daily consolidation",
           "transformer_used" => "Transformer.transform_restaurant_slot/5",
           "pattern" => if(pattern_based, do: "18:00-22:00, 30min intervals", else: "from API")
         }
       }}
    end
  end

  # Process individual event through EventProcessor
  # Phase 4: Link events to festival container (#2334)
  defp process_event(event_data, source_id, festival_container_id) do
    # Convert atom keys to string keys and add occurrence_type
    normalized_data = %{
      external_id: event_data.external_id,
      title: event_data.title,
      description: event_data.description,
      source_url: event_data.url,
      # Include image_url from transformer
      image_url: event_data.image_url,
      starts_at: event_data.starts_at,
      ends_at: event_data.ends_at,
      venue_data: event_data.venue_attributes,
      metadata: event_data.metadata,
      # Phase 4: Include category_id
      category_id: event_data.category_id,
      # Add occurrence_type for proper event initialization
      occurrence_type: :explicit
    }

    case EventProcessor.process_event(normalized_data, source_id) do
      {:ok, event} ->
        # Phase 4: Link event to festival container if container_id provided
        if festival_container_id do
          case FestivalManager.link_event_to_festival(event, festival_container_id) do
            {:ok, _membership} ->
              Logger.debug(
                "[WeekPl.DetailJob] Linked event #{event.id} to festival container #{festival_container_id}"
              )

            {:error, reason} ->
              Logger.warning(
                "[WeekPl.DetailJob] Failed to link event #{event.id} to container: #{inspect(reason)}"
              )
          end
        end

        {:ok, event_data.external_id}

      {:error, reason} ->
        Logger.error(
          "[WeekPl.DetailJob] Failed to process event #{event_data.external_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  # Generate date range for checking availability
  # Returns list of ISO date strings
  defp generate_date_range(start_days, end_days) do
    today = Date.utc_today()

    start_days..end_days
    |> Enum.map(fn days ->
      today
      |> Date.add(days)
      |> Date.to_string()
    end)
  end
end
