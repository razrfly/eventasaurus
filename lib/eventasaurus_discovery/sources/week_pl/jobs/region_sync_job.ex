defmodule EventasaurusDiscovery.Sources.WeekPl.Jobs.RegionSyncJob do
  @moduledoc """
  Per-city restaurant fetching job for week.pl.

  ## Responsibilities
  - Fetch restaurant listings for a specific city
  - Queue RestaurantDetailJob for each restaurant found
  - Handle pagination if needed (week.pl typically returns all restaurants)

  ## API Integration
  - Endpoint: /_next/data/{BUILD_ID}/pl/restaurants.json
  - Parameters: location, date, slot, peopleCount
  - Returns: List of restaurants with basic info + available slots

  ## Optimization Note
  - Event-level freshness optimization happens in EventProcessor
  - Consolidation logic prevents duplicate processing
  - last_seen_at tracking provides natural freshness checking

  ## Job Arguments
  - source_id: Source database ID
  - region_id: City ID from week.pl (e.g., "1" for Kraków)
  - region_name: Human-readable city name
  - country: "Poland"
  - festival_code: Current festival code (e.g., "RWP26W")
  - festival_name: Festival display name
  - festival_price: Menu price for this festival
  """

  use Oban.Worker,
    queue: :week_pl_region_sync,
    max_attempts: 3,
    priority: 2

  require Logger
  alias EventasaurusDiscovery.Sources.WeekPl.{Client, Config}
  alias EventasaurusDiscovery.Sources.WeekPl.Jobs.RestaurantDetailJob

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{
            "source_id" => source_id,
            "region_id" => region_id,
            "region_name" => region_name
          } = args,
        meta: meta
      } = job) do
    Logger.info("🍽️  [WeekPl.RegionSync] Fetching restaurants for #{region_name}...")

    # Query tomorrow's date - restaurants typically don't offer same-day reservations
    # Validated: Tomorrow's date returns available restaurants, today returns 0
    # See: https://github.com/razrfly/eventasaurus/issues/2332
    date = Date.utc_today() |> Date.add(1) |> Date.to_string()

    # Use popular dinner time slot (7:00 PM = 1140 minutes)
    slot = 1140
    people_count = 2

    # Build query params for observability (Phase 2: #2332)
    query_params = %{
      "date" => date,
      "slot" => slot,
      "people_count" => people_count,
      "region_id" => region_id,
      "region_name" => region_name
    }

    # Rate limiting: 2 seconds between requests (configured in Config)
    Process.sleep(Config.request_delay_ms())

    case Client.fetch_restaurants(region_id, region_name, date, slot, people_count) do
      {:ok, response} ->
        process_restaurants(response, source_id, args, job.id, meta, query_params)

      {:error, :rate_limited} ->
        Logger.warning("[WeekPl.RegionSync] Rate limited for #{region_name}, retrying...")
        {:error, :rate_limited}

      {:error, reason} ->
        Logger.error("[WeekPl.RegionSync] Failed for #{region_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Process restaurant listing response (Apollo GraphQL state format)
  defp process_restaurants(%{"pageProps" => %{"apolloState" => apollo_state}}, source_id, args, job_id, meta, query_params)
       when is_map(apollo_state) do
    # Extract restaurants from Apollo state (keys like "Restaurant:3525")
    restaurants =
      apollo_state
      |> Enum.filter(fn {key, _value} -> String.starts_with?(key, "Restaurant:") end)
      |> Enum.map(fn {_key, restaurant} -> restaurant end)

    Logger.info("[WeekPl.RegionSync] Found #{length(restaurants)} restaurants")

    pipeline_id = Map.get(meta, "pipeline_id") || "week_pl_#{Date.utc_today()}"
    parent_job_id = Map.get(meta, "parent_job_id")

    # Queue detail job for each restaurant
    # Event-level optimization happens in EventProcessor via consolidation
    results =
      restaurants
      |> Enum.map(fn restaurant ->
        queue_detail_job(restaurant, source_id, args, job_id, pipeline_id)
      end)

    succeeded = Enum.count(results, fn {status, _} -> status == :ok end)
    failed = length(results) - succeeded

    Logger.info(
      "[WeekPl.RegionSync] Queued #{succeeded} detail jobs, #{failed} failed for #{args["region_name"]}"
    )

    {:ok, %{
      "job_role" => "region_fetcher",
      "pipeline_id" => pipeline_id,
      "parent_job_id" => parent_job_id,
      "entity_id" => args["region_id"],
      "entity_type" => "region",
      "status" => "success",
      "restaurants_found" => length(restaurants),
      "jobs_queued" => succeeded,
      "jobs_failed" => failed,
      # Phase 2 observability enhancements (#2332)
      "query_params" => query_params,
      "api_response" => %{
        "has_apollo_state" => true,
        "restaurant_count" => length(restaurants)
      },
      "decision_context" => %{
        "date_strategy" => "tomorrow",
        "slot_choice" => "7pm_dinner",
        "rationale" => "Restaurants typically don't offer same-day reservations"
      }
    }}
  end

  defp process_restaurants(response, _source_id, args, _job_id, meta, query_params) do
    Logger.error("""
    [WeekPl.RegionSync] ❌ Unexpected response structure for #{args["region_name"]}
    Response keys: #{inspect(Map.keys(response))}
    Full response: #{inspect(response, pretty: true, limit: 100)}

    Expected structure: %{"pageProps" => %{"apolloState" => %{"Restaurant:XXX" => {...}}}}
    """)

    pipeline_id = Map.get(meta, "pipeline_id") || "week_pl_#{Date.utc_today()}"
    parent_job_id = Map.get(meta, "parent_job_id")

    {:ok, %{
      "job_role" => "region_fetcher",
      "pipeline_id" => pipeline_id,
      "parent_job_id" => parent_job_id,
      "entity_id" => args["region_id"],
      "entity_type" => "region",
      "status" => "invalid_response",
      "restaurants_found" => 0,
      "jobs_queued" => 0,
      # Phase 2 observability enhancements (#2332)
      "query_params" => query_params,
      "api_response" => %{
        "has_apollo_state" => false,
        "response_keys" => Map.keys(response)
      },
      "decision_context" => %{
        "error_type" => "invalid_response_structure",
        "expected" => "apolloState with Restaurant objects",
        "received" => "unexpected structure"
      }
    }}
  end

  # Queue restaurant detail job
  defp queue_detail_job(restaurant, source_id, region_args, parent_job_id, pipeline_id) do
    restaurant_id = get_restaurant_id(restaurant)
    slug = restaurant["slug"]

    if restaurant_id && slug do
      args = %{
        source_id: source_id,
        restaurant_id: restaurant_id,
        restaurant_slug: slug,
        restaurant_name: restaurant["name"],
        region_id: region_args["region_id"],
        region_name: region_args["region_name"],
        country: region_args["country"],
        festival_code: region_args["festival_code"],
        festival_name: region_args["festival_name"],
        festival_price: region_args["festival_price"]
      }

      meta = %{
        parent_job_id: parent_job_id,
        pipeline_id: pipeline_id,
        entity_id: slug,
        entity_type: "restaurant"
      }

      case Oban.insert(RestaurantDetailJob.new(args, meta: meta)) do
        {:ok, _job} ->
          {:ok, slug}

        {:error, reason} ->
          Logger.error(
            "[WeekPl.RegionSync] Failed to queue detail job for #{slug}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    else
      Logger.warning(
        "[WeekPl.RegionSync] Missing restaurant_id or slug: #{inspect(restaurant)}"
      )

      {:error, :missing_required_fields}
    end
  end

  defp get_restaurant_id(%{"id" => id}) when is_binary(id), do: id
  defp get_restaurant_id(%{"id" => id}) when is_integer(id), do: Integer.to_string(id)
  defp get_restaurant_id(_), do: nil
end
