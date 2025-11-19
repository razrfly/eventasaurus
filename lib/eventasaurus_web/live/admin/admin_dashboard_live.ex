defmodule EventasaurusWeb.Admin.AdminDashboardLive do
  @moduledoc """
  Central admin dashboard providing quick access to all admin functionality.
  Displays key metrics and organized navigation to all admin pages.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Cache.DashboardStats

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Admin Dashboard")
      |> load_stats()

    {:ok, socket}
  end

  defp load_stats(socket) do
    # Get overall statistics from cache
    # All cache functions return {:ok, value} | {:error, reason}
    stats = %{
      total_events: get_cached(:total_events, &DashboardStats.get_total_events/0),
      unique_venues: get_cached(:unique_venues, &DashboardStats.get_unique_venues/0),
      performers: get_cached(:performers, &DashboardStats.get_unique_performers/0),
      upcoming_events: get_cached(:upcoming_events, &DashboardStats.get_upcoming_events/0),
      past_events: get_cached(:past_events, &DashboardStats.get_past_events/0),
      active_jobs: get_cached(:active_jobs, &DashboardStats.get_active_jobs_count/0),
      geocoding_queue: get_cached(:geocoding_queue, &DashboardStats.get_geocoding_queue_count/0),
      recent_errors: get_cached(:recent_errors, &DashboardStats.get_recent_scraper_errors/0)
    }

    assign(socket, :stats, stats)
  end

  # Helper to get cached value and handle errors gracefully
  # Cachex.fetch returns:
  # - {:ok, value} when cache hit
  # - {:commit, value} when cache miss and fallback executed
  # - {:error, reason} on error
  defp get_cached(name, cache_fn) do
    case cache_fn.() do
      {:ok, value} ->
        value

      {:commit, value} ->
        value

      {:error, reason} ->
        Logger.warning("Failed to get cached stat #{name}: #{inspect(reason)}")
        0
    end
  end

  # Format large numbers with commas
  defp format_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join(&1, ""))
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_number(_), do: "0"
end
