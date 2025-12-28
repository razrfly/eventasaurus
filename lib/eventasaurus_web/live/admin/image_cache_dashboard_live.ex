defmodule EventasaurusWeb.Admin.ImageCacheDashboardLive do
  @moduledoc """
  Admin dashboard for monitoring and managing the image cache.

  Uses cached stats from image_cache_stats_snapshots table, computed daily by
  ComputeImageCacheStatsJob. Falls back to live queries if cache is empty.

  Features:
  - Summary stats cards (total, cached, pending, failed, storage size)
  - Stats by entity type
  - Stats by provider/source
  - Stats by image type
  - Recent activity feed
  - Recent failures with error details
  - "Last updated" timestamp
  - Manual refresh button (triggers Oban job)
  """

  use EventasaurusWeb, :live_view
  require Logger

  alias EventasaurusApp.Images.{
    ImageCacheStats,
    ImageCacheStatsSnapshot,
    ComputeImageCacheStatsJob
  }

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      {:ok, load_stats(socket)}
    else
      {:ok, assign_defaults(socket)}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    # Trigger Oban job for background refresh
    case ComputeImageCacheStatsJob.trigger_now() do
      {:ok, job} ->
        Logger.info("Triggered image cache stats refresh job ##{job.id}")

        {:noreply,
         socket
         |> assign(:refreshing, true)
         |> put_flash(:info, "Refresh started. Stats will update in a few seconds.")}

      {:error, reason} ->
        Logger.error("Failed to trigger refresh: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to start refresh")}
    end
  end

  @impl true
  def handle_event("reload", _params, socket) do
    # Reload from cache/database without triggering new computation
    {:noreply, load_stats(socket)}
  end

  defp assign_defaults(socket) do
    socket
    |> assign(:page_title, "Image Cache Dashboard")
    |> assign(:loading, true)
    |> assign(:refreshing, false)
    |> assign(:summary, nil)
    |> assign(:by_entity_type, [])
    |> assign(:by_provider, [])
    |> assign(:by_image_type, [])
    |> assign(:recent_activity, [])
    |> assign(:recent_failures, [])
    |> assign(:failure_breakdown, [])
    |> assign(:last_updated, nil)
    |> assign(:is_stale, false)
    |> assign(:error, nil)
  end

  defp load_stats(socket) do
    # Try cached stats first
    case ImageCacheStatsSnapshot.get_latest() do
      nil ->
        # No cache - fall back to live query (first load or cache cleared)
        Logger.info("No image cache stats snapshot found - computing live")
        load_live_stats(socket)

      snapshot ->
        # Use cached stats
        stats = ImageCacheStatsSnapshot.get_latest_stats()
        is_stale = is_stale?(snapshot.computed_at)

        socket
        |> assign(:loading, false)
        |> assign(:refreshing, false)
        |> assign(:summary, stats[:summary] || stats["summary"])
        |> assign(:by_entity_type, stats[:by_entity_type] || stats["by_entity_type"] || [])
        |> assign(:by_provider, stats[:by_provider] || stats["by_provider"] || [])
        |> assign(:by_image_type, stats[:by_image_type] || stats["by_image_type"] || [])
        |> assign(:recent_activity, stats[:recent_activity] || stats["recent_activity"] || [])
        |> assign(:recent_failures, stats[:recent_failures] || stats["recent_failures"] || [])
        |> assign(:failure_breakdown, stats[:failure_breakdown] || stats["failure_breakdown"] || [])
        |> assign(:last_updated, snapshot.computed_at)
        |> assign(:is_stale, is_stale)
        |> assign(:error, nil)
    end
  rescue
    e ->
      Logger.error("Failed to load image cache stats: #{Exception.message(e)}")

      socket
      |> assign(:loading, false)
      |> assign(:refreshing, false)
      |> assign(:error, "Failed to load stats: #{Exception.message(e)}")
  end

  defp load_live_stats(socket) do
    stats = ImageCacheStats.get_dashboard_stats()

    socket
    |> assign(:loading, false)
    |> assign(:refreshing, false)
    |> assign(:summary, stats.summary)
    |> assign(:by_entity_type, stats.by_entity_type)
    |> assign(:by_provider, stats.by_provider)
    |> assign(:by_image_type, stats.by_image_type)
    |> assign(:recent_activity, stats.recent_activity)
    |> assign(:recent_failures, stats.recent_failures)
    |> assign(:failure_breakdown, stats.failure_breakdown)
    |> assign(:last_updated, nil)
    |> assign(:is_stale, false)
    |> assign(:error, nil)
  rescue
    e ->
      socket
      |> assign(:loading, false)
      |> assign(:refreshing, false)
      |> assign(:error, "Failed to load stats: #{Exception.message(e)}")
  end

  # Stats are considered stale if older than 25 hours (slightly more than daily refresh)
  defp is_stale?(nil), do: true

  defp is_stale?(computed_at) do
    twenty_five_hours_ago = DateTime.utc_now() |> DateTime.add(-25, :hour)
    DateTime.compare(computed_at, twenty_five_hours_ago) == :lt
  end

  # Helper functions for template

  defp format_bytes(nil), do: "0 B"
  defp format_bytes(0), do: "0 B"

  defp format_bytes(bytes) when bytes < 1024 do
    "#{bytes} B"
  end

  defp format_bytes(bytes) when bytes < 1_048_576 do
    "#{Float.round(bytes / 1024, 1)} KB"
  end

  defp format_bytes(bytes) when bytes < 1_073_741_824 do
    "#{Float.round(bytes / 1_048_576, 1)} MB"
  end

  defp format_bytes(bytes) do
    "#{Float.round(bytes / 1_073_741_824, 2)} GB"
  end

  defp format_entity_type("public_event_source"), do: "Event Sources"
  defp format_entity_type("movie"), do: "Movies"
  defp format_entity_type("venue"), do: "Venues"
  defp format_entity_type("performer"), do: "Performers"
  defp format_entity_type("event"), do: "Events"
  defp format_entity_type("group"), do: "Groups"
  defp format_entity_type(name) when is_binary(name), do: String.capitalize(name)
  defp format_entity_type(_), do: "Unknown"

  defp format_provider("ticketmaster"), do: "Ticketmaster"
  defp format_provider("resident-advisor"), do: "Resident Advisor"
  defp format_provider("resident_advisor"), do: "Resident Advisor"
  defp format_provider("tmdb"), do: "TMDB"
  defp format_provider("bandsintown"), do: "Bandsintown"
  defp format_provider("cinema_city"), do: "Cinema City"
  defp format_provider("google_places"), do: "Google Places"
  defp format_provider(nil), do: "Unknown"
  defp format_provider(name) when is_binary(name), do: String.capitalize(name)
  defp format_provider(_), do: "Unknown"

  defp format_image_type("hero"), do: "Hero"
  defp format_image_type("gallery"), do: "Gallery"
  defp format_image_type("poster"), do: "Poster"
  defp format_image_type("backdrop"), do: "Backdrop"
  defp format_image_type("primary"), do: "Primary"
  defp format_image_type("still"), do: "Still"
  defp format_image_type("logo"), do: "Logo"
  defp format_image_type(name) when is_binary(name), do: String.capitalize(name)
  defp format_image_type(_), do: "Unknown"

  defp entity_type_badge_class("public_event_source"), do: "bg-blue-100 text-blue-800"
  defp entity_type_badge_class("movie"), do: "bg-purple-100 text-purple-800"
  defp entity_type_badge_class("venue"), do: "bg-green-100 text-green-800"
  defp entity_type_badge_class("performer"), do: "bg-pink-100 text-pink-800"
  defp entity_type_badge_class("event"), do: "bg-orange-100 text-orange-800"
  defp entity_type_badge_class("group"), do: "bg-teal-100 text-teal-800"
  defp entity_type_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp provider_badge_class("ticketmaster"), do: "bg-blue-100 text-blue-800"
  defp provider_badge_class("resident-advisor"), do: "bg-purple-100 text-purple-800"
  defp provider_badge_class("resident_advisor"), do: "bg-purple-100 text-purple-800"
  defp provider_badge_class("tmdb"), do: "bg-green-100 text-green-800"
  defp provider_badge_class("bandsintown"), do: "bg-pink-100 text-pink-800"
  defp provider_badge_class("cinema_city"), do: "bg-orange-100 text-orange-800"
  defp provider_badge_class("google_places"), do: "bg-yellow-100 text-yellow-800"
  defp provider_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp image_type_badge_class("hero"), do: "bg-indigo-100 text-indigo-800"
  defp image_type_badge_class("gallery"), do: "bg-cyan-100 text-cyan-800"
  defp image_type_badge_class("poster"), do: "bg-amber-100 text-amber-800"
  defp image_type_badge_class("backdrop"), do: "bg-violet-100 text-violet-800"
  defp image_type_badge_class("primary"), do: "bg-gray-100 text-gray-800"
  defp image_type_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp success_rate_badge_class(rate) when rate >= 95.0, do: "bg-green-100 text-green-800"
  defp success_rate_badge_class(rate) when rate >= 85.0, do: "bg-yellow-100 text-yellow-800"
  defp success_rate_badge_class(_), do: "bg-red-100 text-red-800"

  defp status_badge_class("cached"), do: "bg-green-100 text-green-800"
  defp status_badge_class("pending"), do: "bg-yellow-100 text-yellow-800"
  defp status_badge_class("downloading"), do: "bg-blue-100 text-blue-800"
  defp status_badge_class("failed"), do: "bg-red-100 text-red-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_datetime(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_datetime(_), do: "N/A"

  defp truncate_url(nil), do: "N/A"

  defp truncate_url(url) when is_binary(url) do
    if String.length(url) > 50 do
      String.slice(url, 0, 47) <> "..."
    else
      url
    end
  end

  defp truncate_url(_), do: "N/A"

  defp truncate_error(nil), do: "Unknown error"

  defp truncate_error(error) when is_binary(error) do
    if String.length(error) > 60 do
      String.slice(error, 0, 57) <> "..."
    else
      error
    end
  end

  defp truncate_error(_), do: "Unknown error"
end
