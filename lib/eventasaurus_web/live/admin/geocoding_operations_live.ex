defmodule EventasaurusWeb.Admin.GeocodingOperationsLive do
  @moduledoc """
  City geocoding operations view.

  Shows all venue image backfill operations for a specific city, including:
  - Recent backfill job history
  - Job-level summaries (total, enriched, skipped, failed)
  - Per-venue details (geocoding, images, costs)
  - Provider filter
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
          |> assign(:page_title, "#{city.name} - Geocoding Operations")
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
    query =
      from(j in "oban_jobs",
        where: j.worker == "EventasaurusDiscovery.VenueImages.BackfillJob",
        where: fragment("args->>'city_id' = ?", ^to_string(city_id)),
        where: j.state in ["completed", "discarded"],
        order_by: [desc: j.completed_at],
        limit: ^limit,
        select: %{
          id: j.id,
          completed_at: j.completed_at,
          attempted_at: j.attempted_at,
          state: j.state,
          args: j.args,
          meta: j.meta
        }
      )

    query
    |> Repo.all()
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

    # Extract data from meta (Phase 1 + Phase 2)
    meta = job.meta || %{}

    # Extract data from args
    args = job.args || %{}
    providers = args["providers"] || []

    %{
      id: job.id,
      completed_at: job.completed_at,
      duration_seconds: duration_seconds,
      state: meta["status"] || (if job.state == "completed", do: "success", else: "failed"),
      providers: providers,
      # Job-level summary (Phase 1)
      total_venues: meta["total_venues"] || 0,
      enriched: meta["enriched"] || 0,
      geocoded: meta["geocoded"] || 0,
      skipped: meta["skipped"] || 0,
      failed: meta["failed"] || 0,
      by_provider: meta["by_provider"] || %{},
      total_cost_usd: meta["total_cost_usd"] || 0,
      # Venue-level details (Phase 2)
      venue_results: meta["venue_results"] || [],
      processed_at: meta["processed_at"],
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
