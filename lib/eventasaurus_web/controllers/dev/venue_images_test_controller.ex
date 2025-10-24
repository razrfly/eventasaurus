defmodule EventasaurusWeb.Dev.VenueImagesTestController do
  @moduledoc """
  Development-only controller for testing and visualizing venue image aggregation.

  This page shows:
  - System status and API key configuration
  - Provider statistics and performance metrics
  - Sample enriched venues with image galleries
  - Cost analysis and tracking
  - Manual testing controls
  - Staleness monitoring

  Access at: /dev/venue-images (dev environment only)
  """
  use EventasaurusWeb, :controller

  alias EventasaurusDiscovery.VenueImages.{Orchestrator, RateLimiter}
  alias EventasaurusDiscovery.Geocoding.Schema.GeocodingProvider
  alias EventasaurusApp.{Repo, Venues.Venue}
  import Ecto.Query

  # Suppress dialyzer warnings for dynamic module calls (runtime module resolution)
  @dialyzer {:nowarn_function, fetch_provider_id_dynamically: 2}
  @dialyzer {:nowarn_function, fetch_images_from_provider: 3}

  def index(conn, _params) do
    # Get testable venues (venues with provider_ids for manual testing)
    testable_venues = get_testable_venues()

    # Get active cities for dropdown
    active_cities = get_active_cities()

    render(conn, :index,
      system_status: get_system_status(),
      global_stats: get_global_statistics(),
      provider_stats: get_provider_statistics(),
      sample_venues: get_sample_enriched_venues(),
      cost_analysis: get_cost_analysis(),
      staleness_monitor: get_staleness_monitor(),
      testable_venues: testable_venues,
      active_cities: active_cities
    )
  end

  @doc """
  POST /dev/venue-images/test-enrichment
  Synchronously test image enrichment for a specific venue.
  """
  def test_enrichment(conn, params) do
    venue_id = params["venue_id"]
    provider_filter = params["provider"]

    case Repo.get(Venue, venue_id) do
      nil ->
        json(conn, %{success: false, error: "Venue not found"})

      venue ->
        # Test enrichment synchronously
        result = test_venue_enrichment(venue, provider_filter)
        json(conn, result)
    end
  end

  @doc """
  PUT /dev/venue-images/update-provider-ids
  Update provider_ids for a venue (dev only).
  """
  def update_provider_ids(conn, params) do
    venue_id = params["venue_id"]
    provider_ids = params["provider_ids"] || %{}

    case Repo.get(Venue, venue_id) do
      nil ->
        json(conn, %{success: false, error: "Venue not found"})

      venue ->
        case Repo.update(Ecto.Changeset.change(venue, provider_ids: provider_ids)) do
          {:ok, updated_venue} ->
            json(conn, %{
              success: true,
              venue_id: updated_venue.id,
              provider_ids: updated_venue.provider_ids
            })

          {:error, changeset} ->
            json(conn, %{
              success: false,
              error: "Failed to update venue",
              details: inspect(changeset.errors)
            })
        end
    end
  end

  @doc """
  POST /dev/venue-images/save-discovered-ids
  Save dynamically discovered provider IDs to venue.
  """
  def save_discovered_ids(conn, params) do
    venue_id = params["venue_id"]
    discovered_ids = params["discovered_ids"] || %{}

    case Repo.get(Venue, venue_id) do
      nil ->
        json(conn, %{success: false, error: "Venue not found"})

      venue ->
        # Merge discovered IDs with existing provider_ids
        existing_ids = venue.provider_ids || %{}
        updated_ids = Map.merge(existing_ids, discovered_ids)

        case Repo.update(Ecto.Changeset.change(venue, provider_ids: updated_ids)) do
          {:ok, updated_venue} ->
            json(conn, %{
              success: true,
              venue_id: updated_venue.id,
              provider_ids: updated_venue.provider_ids,
              saved_count: map_size(discovered_ids)
            })

          {:error, changeset} ->
            json(conn, %{
              success: false,
              error: "Failed to save provider IDs",
              details: inspect(changeset.errors)
            })
        end
    end
  end

  @doc """
  POST /dev/venue-images/clear-cache
  Clear image cache for testing purposes. Accepts optional filters.
  """
  def clear_cache(conn, params) do
    city_slug = params["city_slug"]
    venue_id = params["venue_id"]

    query = from(v in Venue)

    query =
      if venue_id do
        from(v in query, where: v.id == ^venue_id)
      else
        query
      end

    query =
      if city_slug do
        from(v in query,
          join: c in assoc(v, :city_ref),
          where: c.slug == ^city_slug
        )
      else
        query
      end

    # Clear image data
    {count, _} =
      Repo.update_all(query,
        set: [
          venue_images: nil,
          image_enrichment_metadata: nil
        ]
      )

    json(conn, %{
      success: true,
      cleared_count: count,
      filters: %{
        city_slug: city_slug,
        venue_id: venue_id
      }
    })
  end

  # ========================================
  # Manual Testing Functions
  # ========================================

  defp get_testable_venues do
    # Get venues that have provider_ids populated
    from(v in Venue,
      where: fragment("? IS NOT NULL", v.provider_ids),
      where: fragment("jsonb_typeof(?) = 'object'", v.provider_ids),
      where: fragment("(SELECT COUNT(*) FROM jsonb_object_keys(?)) > 0", v.provider_ids),
      order_by: [desc: v.id],
      limit: 50
    )
    |> Repo.all()
    |> Enum.map(fn venue ->
      %{
        id: venue.id,
        name: venue.name,
        city: nil,
        provider_ids: venue.provider_ids || %{},
        has_images: venue.venue_images && length(venue.venue_images) > 0
      }
    end)
  end

  defp test_venue_enrichment(venue, provider_filter) do
    start_time = System.monotonic_time(:millisecond)

    # Get active image providers
    providers =
      from(p in GeocodingProvider,
        where: p.is_active == true,
        where: fragment("? @> ?", p.capabilities, ^%{"images" => true}),
        order_by: [asc: fragment("COALESCE((? ->> 'images')::int, 99)", p.priorities)]
      )
      |> Repo.all()
      |> then(fn providers ->
        if provider_filter do
          Enum.filter(providers, &(&1.name == provider_filter))
        else
          providers
        end
      end)

    # Test each provider
    results =
      Enum.map(providers, fn provider ->
        {provider.name, test_provider(venue, provider)}
      end)
      |> Enum.into(%{})

    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time

    # Aggregate results
    total_images =
      Enum.reduce(results, 0, fn {_provider, result}, acc ->
        acc + length(Map.get(result, :images, []))
      end)

    total_cost =
      Enum.reduce(results, 0.0, fn {_provider, result}, acc ->
        acc + Map.get(result, :cost, 0.0)
      end)

    # Collect dynamically discovered provider IDs
    discovered_ids =
      Enum.reduce(results, %{}, fn {provider_name, result}, acc ->
        if Map.get(result, :id_source) == :dynamic and Map.get(result, :provider_id) do
          Map.put(acc, provider_name, result.provider_id)
        else
          acc
        end
      end)

    %{
      success: true,
      venue_id: venue.id,
      venue_name: venue.name,
      results: results,
      total_images: total_images,
      total_cost: total_cost,
      duration_ms: duration_ms,
      discovered_ids: discovered_ids,
      has_discovered_ids: map_size(discovered_ids) > 0
    }
  end

  defp test_provider(venue, provider) do
    start_time = System.monotonic_time(:millisecond)

    # Get provider ID for this venue - use Map.get for string-keyed JSONB maps
    stored_provider_id = Map.get(venue.provider_ids, provider.name)

    # Determine ID and source (stored or dynamic)
    {provider_id, id_source} =
      if stored_provider_id do
        {stored_provider_id, :stored}
      else
        # Try to fetch provider ID dynamically using coordinates
        case fetch_provider_id_dynamically(venue, provider) do
          {:ok, dynamic_id} -> {dynamic_id, :dynamic}
          {:error, _reason} -> {nil, :unavailable}
        end
      end

    if provider_id do
      # Try to fetch images from this provider
      result = fetch_images_from_provider(venue, provider, provider_id)

      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time

      Map.merge(result, %{
        provider_id: provider_id,
        # Track how we got the ID
        id_source: id_source,
        duration_ms: duration_ms
      })
    else
      %{
        success: false,
        error: "Could not fetch provider ID (venue not found or API unavailable)",
        images: [],
        api_calls: [],
        cost: 0.0,
        id_source: :unavailable
      }
    end
  end

  defp fetch_provider_id_dynamically(venue, provider) do
    require Logger

    # Check if venue has coordinates
    if is_nil(venue.latitude) or is_nil(venue.longitude) do
      Logger.debug("❌ fetch_provider_id_dynamically: no coordinates for venue #{venue.id}")
      {:error, :no_coordinates}
    else
      case get_adapter_module(provider.name) do
        nil ->
          Logger.debug("❌ fetch_provider_id_dynamically: no adapter module for #{provider.name}")
          {:error, :not_supported}

        provider_module ->
          # Try calling search_by_coordinates/3 directly without function_exported? check
          # (function_exported? returns false for functions with default parameters in some cases)
          try do
            Logger.debug(
              "🔍 fetch_provider_id_dynamically: calling #{provider.name}.search_by_coordinates(#{venue.latitude}, #{venue.longitude}, #{inspect(venue.name)})"
            )

            result =
              apply(provider_module, :search_by_coordinates, [
                venue.latitude,
                venue.longitude,
                venue.name
              ])

            Logger.debug("✅ fetch_provider_id_dynamically result: #{inspect(result)}")
            result
          rescue
            UndefinedFunctionError ->
              Logger.debug(
                "❌ fetch_provider_id_dynamically: search_by_coordinates/3 not implemented for #{provider.name}"
              )

              {:error, :not_supported}

            e ->
              Logger.error("❌ fetch_provider_id_dynamically exception: #{Exception.message(e)}")
              {:error, {:exception, Exception.message(e)}}
          end
      end
    end
  end

  defp fetch_images_from_provider(_venue, provider, provider_id) do
    # Call the geocoding provider's get_images/1 function
    case get_adapter_module(provider.name) do
      nil ->
        %{
          success: false,
          error: "Provider module not found for #{provider.name}",
          images: [],
          api_calls: [],
          cost: 0.0
        }

      provider_module ->
        try do
          # Geocoding providers implement get_images/1 (takes place_id only)
          case apply(provider_module, :get_images, [provider_id]) do
            {:ok, images} ->
              %{
                success: true,
                images: images,
                images_found: length(images),
                api_calls: [
                  %{
                    provider: provider.name,
                    status: 200,
                    message: "Successfully fetched #{length(images)} images"
                  }
                ],
                cost: calculate_cost(provider, length(images))
              }

            {:error, reason} ->
              %{
                success: false,
                error: inspect(reason),
                images: [],
                api_calls: [
                  %{
                    provider: provider.name,
                    status: :error,
                    message: inspect(reason)
                  }
                ],
                cost: 0.0
              }
          end
        rescue
          e ->
            %{
              success: false,
              error: Exception.message(e),
              images: [],
              api_calls: [
                %{
                  provider: provider.name,
                  status: :exception,
                  message: Exception.message(e),
                  stacktrace: Exception.format_stacktrace(__STACKTRACE__)
                }
              ],
              cost: 0.0
            }
        end
    end
  end

  defp get_adapter_module(provider_name) do
    # These are geocoding providers that also implement get_images/1
    case provider_name do
      "here" -> EventasaurusDiscovery.Geocoding.Providers.Here
      "geoapify" -> EventasaurusDiscovery.Geocoding.Providers.Geoapify
      "foursquare" -> EventasaurusDiscovery.Geocoding.Providers.Foursquare
      "google_places" -> EventasaurusDiscovery.Geocoding.Providers.GooglePlaces
      _ -> nil
    end
  end

  defp calculate_cost(provider, api_calls) do
    cost_per_call = get_in(provider.metadata, ["cost_per_image"]) || 0.0
    cost_per_call * api_calls
  end

  # ========================================
  # System Status
  # ========================================

  defp get_system_status do
    %{
      api_keys: %{
        google_places: System.get_env("GOOGLE_PLACES_API_KEY") != nil,
        foursquare: System.get_env("FOURSQUARE_API_KEY") != nil,
        here: System.get_env("HERE_API_KEY") != nil,
        geoapify: System.get_env("GEOAPIFY_API_KEY") != nil,
        unsplash: System.get_env("UNSPLASH_ACCESS_KEY") != nil
      },
      rate_limiter_running: Process.whereis(EventasaurusDiscovery.VenueImages.RateLimiter) != nil,
      oban_queue_depth: get_oban_queue_depth(),
      providers_enabled: get_enabled_providers_count()
    }
  end

  defp get_oban_queue_depth do
    # Get count of jobs in venue_enrichment queue
    case Oban.check_queue(queue: :venue_enrichment) do
      {:ok, %{running: running, available: available}} ->
        running + available

      _ ->
        0
    end
  rescue
    _ -> 0
  end

  defp get_enabled_providers_count do
    from(p in GeocodingProvider,
      where: p.is_active == true and fragment("? @> ?", p.capabilities, ^%{"images" => true}),
      select: count(p.id)
    )
    |> Repo.one()
  end

  # ========================================
  # Global Statistics
  # ========================================

  defp get_global_statistics do
    total_venues = Repo.aggregate(Venue, :count, :id)

    enriched_venues =
      from(v in Venue,
        where: fragment("jsonb_array_length(COALESCE(?, '[]'::jsonb)) > 0", v.venue_images),
        select: count(v.id)
      )
      |> Repo.one() || 0

    # Get needs enrichment count by loading venues
    needs_enrichment_count =
      from(v in Venue, limit: 1000)
      |> Repo.all()
      |> Enum.count(&Orchestrator.needs_enrichment?/1)

    total_images =
      from(v in Venue,
        where: fragment("jsonb_array_length(COALESCE(?, '[]'::jsonb)) > 0", v.venue_images),
        select: fragment("SUM(jsonb_array_length(COALESCE(?, '[]'::jsonb)))", v.venue_images)
      )
      |> Repo.one() || 0

    total_cost =
      from(v in Venue,
        where: fragment("? IS NOT NULL", v.image_enrichment_metadata),
        select:
          fragment(
            "SUM(CAST(COALESCE(? ->> 'total_cost', '0') AS FLOAT))",
            v.image_enrichment_metadata
          )
      )
      |> Repo.one() || 0.0

    %{
      total_venues: total_venues,
      enriched_venues: enriched_venues,
      needs_enrichment: needs_enrichment_count,
      total_images: total_images,
      total_cost: total_cost,
      avg_images_per_venue:
        if(enriched_venues > 0, do: total_images / enriched_venues * 1.0, else: 0.0),
      avg_cost_per_venue: if(enriched_venues > 0, do: total_cost / enriched_venues, else: 0.0)
    }
  end

  # ========================================
  # Provider Statistics
  # ========================================

  defp get_provider_statistics do
    providers =
      from(p in GeocodingProvider,
        where: fragment("? @> ?", p.capabilities, ^%{"images" => true}),
        order_by: [asc: fragment("COALESCE((? ->> 'images')::int, 99)", p.priorities)]
      )
      |> Repo.all()

    Enum.map(providers, fn provider ->
      rate_stats = RateLimiter.get_stats(provider.name)

      # Count images contributed by this provider
      images_count = count_provider_images(provider.name)

      # Calculate success rate from metadata
      {successes, attempts} = calculate_provider_success_rate(provider.name)
      success_rate = if attempts > 0, do: successes / attempts * 100.0, else: 0.0

      # Calculate total cost for this provider
      total_cost = calculate_provider_total_cost(provider.name)

      %{
        name: provider.name,
        is_active: provider.is_active,
        priority: get_in(provider.priorities, ["images"]) || 99,
        images_contributed: images_count,
        success_rate: success_rate,
        cost_per_image: get_in(provider.metadata, ["cost_per_image"]) || 0.0,
        total_cost: total_cost,
        rate_limit_stats: rate_stats
      }
    end)
  end

  defp count_provider_images(provider_name) do
    from(v in Venue,
      where:
        fragment(
          """
          EXISTS (
            SELECT 1 FROM jsonb_array_elements(COALESCE(?, '[]'::jsonb)) AS img
            WHERE img ->> 'provider' = ?
          )
          """,
          v.venue_images,
          ^provider_name
        ),
      select:
        fragment(
          """
          COALESCE(SUM((
            SELECT COUNT(*)
            FROM jsonb_array_elements(COALESCE(?, '[]'::jsonb)) AS img
            WHERE img ->> 'provider' = ?
          )), 0)
          """,
          v.venue_images,
          ^provider_name
        )
    )
    |> Repo.one() || 0
  end

  defp calculate_provider_success_rate(provider_name) do
    results =
      from(v in Venue,
        where: fragment("? IS NOT NULL", v.image_enrichment_metadata),
        select: %{
          succeeded:
            fragment(
              "? -> 'providers_succeeded' @> ?::jsonb",
              v.image_enrichment_metadata,
              ^Jason.encode!([provider_name])
            ),
          attempted:
            fragment(
              "? -> 'providers_attempted' @> ?::jsonb",
              v.image_enrichment_metadata,
              ^Jason.encode!([provider_name])
            )
        }
      )
      |> Repo.all()

    successes = Enum.count(results, & &1.succeeded)
    attempts = Enum.count(results, & &1.attempted)

    {successes, attempts}
  end

  defp calculate_provider_total_cost(provider_name) do
    from(v in Venue,
      where: fragment("? IS NOT NULL", v.image_enrichment_metadata),
      select:
        fragment(
          "SUM(CAST(COALESCE(? -> 'cost_breakdown' ->> ?, '0') AS FLOAT))",
          v.image_enrichment_metadata,
          ^provider_name
        )
    )
    |> Repo.one() || 0.0
  end

  # ========================================
  # Sample Enriched Venues
  # ========================================

  defp get_sample_enriched_venues do
    from(v in Venue,
      where: fragment("jsonb_array_length(COALESCE(?, '[]'::jsonb)) > 0", v.venue_images),
      order_by: [
        desc:
          fragment(
            "COALESCE(? ->> 'last_enriched_at', '1970-01-01T00:00:00Z')",
            v.image_enrichment_metadata
          )
      ],
      limit: 20,
      preload: [:city_ref]
    )
    |> Repo.all()
    |> Enum.map(&enrich_venue_data/1)
  end

  defp enrich_venue_data(venue) do
    metadata = venue.image_enrichment_metadata || %{}
    images = venue.venue_images || []

    provider_breakdown =
      images
      |> Enum.group_by(fn img ->
        case img do
          %{"provider" => provider} -> provider
          %{provider: provider} -> provider
          _ -> "unknown"
        end
      end)
      |> Enum.map(fn {provider, imgs} -> {provider, length(imgs)} end)
      |> Enum.into(%{})

    primary_image =
      images
      |> Enum.sort_by(fn img ->
        case img do
          %{"position" => pos} -> pos
          %{position: pos} -> pos
          _ -> 999
        end
      end)
      |> List.first()

    %{
      venue: venue,
      image_count: length(images),
      primary_image: normalize_image(primary_image),
      provider_breakdown: provider_breakdown,
      is_stale: Orchestrator.needs_enrichment?(venue),
      last_enriched:
        get_in(metadata, ["last_enriched_at"]) || get_in(metadata, [:last_enriched_at]),
      total_cost: get_in(metadata, ["total_cost"]) || get_in(metadata, [:total_cost]) || 0.0,
      metadata: metadata
    }
  end

  defp normalize_image(nil), do: nil

  defp normalize_image(img) when is_map(img) do
    %{
      url: Map.get(img, "url") || Map.get(img, :url),
      width: Map.get(img, "width") || Map.get(img, :width),
      height: Map.get(img, "height") || Map.get(img, :height),
      provider: Map.get(img, "provider") || Map.get(img, :provider),
      attribution: Map.get(img, "attribution") || Map.get(img, :attribution),
      attribution_url: Map.get(img, "attribution_url") || Map.get(img, :attribution_url)
    }
  end

  # ========================================
  # Cost Analysis
  # ========================================

  defp get_cost_analysis do
    # Get provider cost breakdown
    provider_costs =
      from(v in Venue,
        where: fragment("? IS NOT NULL", v.image_enrichment_metadata),
        select:
          fragment(
            "? -> 'cost_breakdown'",
            v.image_enrichment_metadata
          )
      )
      |> Repo.all()
      |> aggregate_provider_costs()

    # Calculate total and projected costs
    total_cost =
      from(v in Venue,
        where: fragment("? IS NOT NULL", v.image_enrichment_metadata),
        select:
          fragment(
            "SUM(CAST(COALESCE(? ->> 'total_cost', '0') AS FLOAT))",
            v.image_enrichment_metadata
          )
      )
      |> Repo.one() || 0.0

    enriched_count =
      from(v in Venue,
        where: fragment("jsonb_array_length(COALESCE(?, '[]'::jsonb)) > 0", v.venue_images),
        select: count(v.id)
      )
      |> Repo.one() || 0

    avg_cost_per_venue = if enriched_count > 0, do: total_cost / enriched_count, else: 0.0

    total_venues = Repo.aggregate(Venue, :count, :id)
    projected_total_cost = total_venues * avg_cost_per_venue

    %{
      total_cost: total_cost,
      provider_costs: provider_costs,
      avg_cost_per_venue: avg_cost_per_venue,
      projected_total_cost: projected_total_cost
    }
  end

  defp aggregate_provider_costs(cost_breakdowns) do
    cost_breakdowns
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(%{}, fn breakdown, acc ->
      case breakdown do
        map when is_map(map) ->
          Enum.reduce(map, acc, fn {provider, cost}, inner_acc ->
            current = Map.get(inner_acc, provider, 0.0)

            new_cost =
              case cost do
                val when is_float(val) ->
                  val

                val when is_binary(val) ->
                  case Float.parse(val) do
                    {f, _} -> f
                    :error -> 0.0
                  end

                val when is_integer(val) ->
                  val / 1.0

                _ ->
                  0.0
              end

            Map.put(inner_acc, provider, current + new_cost)
          end)

        _ ->
          acc
      end
    end)
  end

  # ========================================
  # Staleness Monitor
  # ========================================

  defp get_staleness_monitor do
    now = DateTime.utc_now()
    thirty_days_ago = DateTime.add(now, -30, :day)
    twenty_five_days_ago = DateTime.add(now, -25, :day)

    # Get stale venues (needs enrichment check)
    stale_venues =
      from(v in Venue, limit: 1000)
      |> Repo.all()
      |> Enum.filter(&Orchestrator.needs_enrichment?/1)
      |> length()

    # Get upcoming stale (25-30 days old)
    upcoming_stale =
      from(v in Venue,
        where:
          fragment(
            "? ->> 'last_enriched_at' < ?",
            v.image_enrichment_metadata,
            ^DateTime.to_iso8601(twenty_five_days_ago)
          ) and
            fragment(
              "? ->> 'last_enriched_at' >= ?",
              v.image_enrichment_metadata,
              ^DateTime.to_iso8601(thirty_days_ago)
            ),
        select: count(v.id)
      )
      |> Repo.one() || 0

    # Get never enriched venues with provider_ids
    never_enriched =
      from(v in Venue,
        where:
          fragment("? IS NOT NULL", v.provider_ids) and
            (fragment("jsonb_array_length(COALESCE(?, '[]'::jsonb)) = 0", v.venue_images) or
               is_nil(v.venue_images)),
        select: count(v.id)
      )
      |> Repo.one() || 0

    # Calculate next cron run (4 AM UTC)
    next_cron = calculate_next_cron_run(now)

    %{
      stale_venues: stale_venues,
      upcoming_stale: upcoming_stale,
      never_enriched: never_enriched,
      next_cron_run: next_cron,
      time_until_cron: DateTime.diff(next_cron, now)
    }
  end

  defp calculate_next_cron_run(now) do
    # Cron runs at 4 AM UTC daily
    today_4am = %{now | hour: 4, minute: 0, second: 0, microsecond: {0, 6}}

    if DateTime.compare(now, today_4am) == :lt do
      today_4am
    else
      DateTime.add(today_4am, 1, :day)
    end
  end

  # ========================================
  # City Management
  # ========================================

  defp get_active_cities do
    alias EventasaurusDiscovery.Locations.City

    Repo.all(
      from(c in City,
        where: c.discovery_enabled == true,
        select: %{
          id: c.id,
          name: c.name,
          slug: c.slug
        },
        order_by: [asc: c.name]
      )
    )
  end
end
