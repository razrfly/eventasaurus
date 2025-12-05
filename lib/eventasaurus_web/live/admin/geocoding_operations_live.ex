defmodule EventasaurusWeb.Admin.GeocodingOperationsLive do
  @moduledoc """
  City venue image operations view.

  Shows all venue image enrichment operations for a specific city, including:
  - Recent backfill and individual enrichment job history
  - Job-level summaries (total venues, enriched, skipped, failed)
  - Per-venue details (images uploaded, costs)
  - Provider filter
  - Supports both BackfillOrchestratorJob (city-wide) and EnrichmentJob (individual venue)
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  import Ecto.Query
  require Logger

  @impl true
  def mount(%{"city_slug" => city_slug}, _session, socket) do
    # Find city by slug
    case Repo.get_by(City, slug: city_slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "City not found: #{city_slug}")
         |> push_navigate(to: ~p"/admin/geocoding")}

      city ->
        socket =
          socket
          |> assign(:city, city)
          |> assign(:city_slug, city_slug)
          |> assign(:page_title, "#{city.name} - Venue Image Operations")
          |> assign(:provider_filter, :all)
          |> assign(:expanded_job_ids, MapSet.new())
          |> assign(:loading, true)
          |> load_operations()
          |> assign(:loading, false)

        {:ok, socket}
    end
  end

  @impl true
  def handle_event("filter_provider", %{"provider" => provider}, socket) do
    provider_filter =
      case provider do
        "all" -> :all
        other -> other
      end

    {:noreply, assign(socket, :provider_filter, provider_filter)}
  end

  @impl true
  def handle_event("toggle_job_details", %{"job_id" => job_id_str}, socket) do
    expanded_job_ids = socket.assigns.expanded_job_ids

    updated_expanded_job_ids =
      if MapSet.member?(expanded_job_ids, job_id_str) do
        MapSet.delete(expanded_job_ids, job_id_str)
      else
        MapSet.put(expanded_job_ids, job_id_str)
      end

    {:noreply, assign(socket, :expanded_job_ids, updated_expanded_job_ids)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_operations(socket)}
  end

  defp load_operations(socket) do
    city_id = socket.assigns.city.id

    operations = get_city_operations(city_id, 20)

    # Extract unique providers from operations
    providers =
      operations
      |> Enum.flat_map(fn op -> op.providers end)
      |> Enum.uniq()
      |> Enum.sort()

    socket
    |> assign(:operations, operations)
    |> assign(:providers, providers)
  end

  defp get_city_operations(city_id, limit) do
    # Query for both BackfillOrchestratorJob (city-wide) and EnrichmentJob (single venue)
    # BackfillOrchestratorJob has city_id in args
    # EnrichmentJob has venue_id in args - need to check venue's city
    query =
      from(j in "oban_jobs",
        where:
          j.worker in [
            "EventasaurusDiscovery.VenueImages.BackfillOrchestratorJob",
            "EventasaurusDiscovery.VenueImages.EnrichmentJob"
          ],
        where:
          fragment("args->>'city_id' = ?", ^to_string(city_id)) or
            fragment(
              """
              EXISTS (
                SELECT 1 FROM venues v
                WHERE v.id = CAST(args->>'venue_id' AS INTEGER)
                AND v.city_id = ?
              )
              """,
              ^city_id
            ),
        where: j.state in ["completed", "discarded"],
        order_by: [desc: j.completed_at],
        limit: ^limit,
        select: %{
          id: j.id,
          completed_at: j.completed_at,
          attempted_at: j.attempted_at,
          state: j.state,
          args: j.args,
          meta: j.meta,
          worker: j.worker
        }
      )

    query
    |> Repo.replica().all()
    |> Enum.map(&enrich_operation/1)
  end

  defp enrich_operation(job) do
    # Calculate duration
    duration_seconds =
      if job.completed_at && job.attempted_at do
        completed = to_datetime(job.completed_at)
        attempted = to_datetime(job.attempted_at)
        DateTime.diff(completed, attempted)
      else
        nil
      end

    # Extract data from meta
    meta = job.meta || %{}

    # Extract data from args
    args = job.args || %{}
    providers = args["providers"] || []

    # Handle both BackfillOrchestratorJob and EnrichmentJob
    worker = job.worker || "EventasaurusDiscovery.VenueImages.BackfillOrchestratorJob"

    {total_venues, enriched, geocoded, skipped, failed, by_provider} =
      if String.ends_with?(worker, "EnrichmentJob") do
        # EnrichmentJob: single venue operation
        status = meta["status"] || "unknown"
        images_uploaded = meta["images_uploaded"] || 0

        enriched_count = if images_uploaded > 0, do: 1, else: 0

        failed_count =
          if status in ["failed", "no_images"] or images_uploaded == 0, do: 1, else: 0

        # Convert provider metadata from EnrichmentJob format
        provider_results =
          case meta["providers"] do
            providers_map when is_map(providers_map) ->
              Map.new(providers_map, fn {provider, info} ->
                status = if is_map(info), do: info["status"], else: "unknown"
                {provider, if(status == "success", do: 1, else: 0)}
              end)

            _ ->
              %{}
          end

        {1, enriched_count, 0, 0, failed_count, provider_results}
      else
        # BackfillOrchestratorJob: city-wide operation (original format)
        {
          meta["total_venues"] || 0,
          meta["enriched"] || 0,
          meta["geocoded"] || 0,
          meta["skipped"] || 0,
          meta["failed"] || 0,
          meta["by_provider"] || %{}
        }
      end

    %{
      id: job.id,
      completed_at: job.completed_at,
      duration_seconds: duration_seconds,
      state: meta["status"] || if(job.state == "completed", do: "success", else: "failed"),
      providers: providers,
      worker: worker,
      # Job-level summary
      total_venues: total_venues,
      enriched: enriched,
      geocoded: geocoded,
      skipped: skipped,
      failed: failed,
      by_provider: by_provider,
      total_cost_usd: meta["total_cost_usd"] || 0,
      # Venue-level details
      venue_results: meta["venue_results"] || [],
      processed_at: meta["processed_at"] || meta["completed_at"],
      args: args
    }
  end

  defp to_datetime(%NaiveDateTime{} = ndt) do
    DateTime.from_naive!(ndt, "Etc/UTC")
  end

  defp to_datetime(%DateTime{} = dt), do: dt

  # Helper functions for template

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %I:%M %p")
  end

  defp format_duration(nil), do: "N/A"
  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)
    "#{minutes}m #{remaining_seconds}s"
  end

  defp format_provider_name("google_places"), do: "Google Places"
  defp format_provider_name("foursquare"), do: "Foursquare"
  defp format_provider_name("here"), do: "HERE"
  defp format_provider_name("mapbox"), do: "Mapbox"
  defp format_provider_name(nil), do: "Unknown"

  defp format_provider_name(name),
    do: name |> String.replace("_", " ") |> String.capitalize()

  defp provider_badge_class("google_places"), do: "bg-orange-100 text-orange-800"
  defp provider_badge_class("foursquare"), do: "bg-pink-100 text-pink-800"
  defp provider_badge_class("here"), do: "bg-purple-100 text-purple-800"
  defp provider_badge_class("mapbox"), do: "bg-blue-100 text-blue-800"
  defp provider_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp status_badge_class("success"), do: "bg-green-100 text-green-800"
  defp status_badge_class("partial"), do: "bg-yellow-100 text-yellow-800"
  defp status_badge_class("skipped"), do: "bg-gray-100 text-gray-800"
  defp status_badge_class("failed"), do: "bg-red-100 text-red-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp action_icon("enriched"), do: "✅"
  defp action_icon("geocoded_and_enriched"), do: "🌐✅"
  defp action_icon("skipped"), do: "⏭️"
  defp action_icon("failed"), do: "❌"
  defp action_icon(_), do: "❓"

  defp format_json(nil), do: "{}"

  defp format_json(data) when is_map(data) do
    Jason.encode!(data, pretty: true)
  rescue
    _ -> inspect(data)
  end

  defp format_cost(cost) when is_float(cost) do
    :erlang.float_to_binary(cost, decimals: 2)
  end

  defp format_cost(cost) when is_integer(cost) do
    :erlang.float_to_binary(cost * 1.0, decimals: 2)
  end

  defp format_cost(_), do: "0.00"
end
