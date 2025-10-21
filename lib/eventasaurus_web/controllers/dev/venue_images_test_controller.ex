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

  alias EventasaurusDiscovery.VenueImages.{Orchestrator, Monitor, RateLimiter}
  alias EventasaurusDiscovery.Geocoding.Schema.GeocodingProvider
  alias EventasaurusApp.{Repo, Venues.Venue}
  import Ecto.Query

  def index(conn, _params) do
    render(conn, :index,
      system_status: get_system_status(),
      global_stats: get_global_statistics(),
      provider_stats: get_provider_statistics(),
      sample_venues: get_sample_enriched_venues(),
      cost_analysis: get_cost_analysis(),
      staleness_monitor: get_staleness_monitor()
    )
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
      avg_images_per_venue: if(enriched_venues > 0, do: total_images / enriched_venues, else: 0),
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
        order_by: [asc: fragment("CAST(? -> 'images' AS INTEGER)", p.priorities)]
      )
      |> Repo.all()

    Enum.map(providers, fn provider ->
      rate_stats = RateLimiter.get_stats(provider.name)

      # Count images contributed by this provider
      images_count = count_provider_images(provider.name)

      # Calculate success rate from metadata
      {successes, attempts} = calculate_provider_success_rate(provider.name)
      success_rate = if attempts > 0, do: successes / attempts * 100, else: 0.0

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
      preload: [:city]
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
      last_enriched: get_in(metadata, ["last_enriched_at"]) || get_in(metadata, [:last_enriched_at]),
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
                val when is_float(val) -> val
                val when is_binary(val) -> String.to_float(val)
                val when is_integer(val) -> val / 1.0
                _ -> 0.0
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
end
