defmodule EventasaurusWeb.Admin.AdminDashboardLive do
  @moduledoc """
  Central admin dashboard providing quick access to all admin functionality.
  Displays key metrics and organized navigation to all admin pages.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Monitoring
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.ScraperProcessingLogs.ScraperProcessingLog

  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Admin Dashboard")
      |> load_stats()

    {:ok, socket}
  end

  defp load_stats(socket) do
    # Get overall statistics
    stats = %{
      total_events: get_total_events(),
      unique_venues: count_unique_venues(),
      performers: count_unique_performers(),
      upcoming_events: count_upcoming_events(),
      past_events: count_past_events(),
      active_jobs: get_active_jobs_count(),
      geocoding_queue: get_geocoding_queue_count(),
      recent_errors: get_recent_scraper_errors()
    }

    assign(socket, :stats, stats)
  end

  defp get_total_events do
    Repo.aggregate(PublicEvent, :count, :id)
  end

  defp count_unique_venues do
    Repo.one(
      from(e in PublicEvent,
        where: not is_nil(e.venue_id),
        select: count(e.venue_id, :distinct)
      )
    ) || 0
  end

  defp count_unique_performers do
    # Count unique performers through the join table
    alias EventasaurusDiscovery.PublicEvents.PublicEventPerformer

    Repo.aggregate(
      from(pep in PublicEventPerformer, select: pep.performer_id, distinct: true),
      :count,
      :performer_id
    )
  end

  defp count_upcoming_events do
    today = DateTime.utc_now()

    Repo.aggregate(
      from(e in PublicEvent, where: e.starts_at >= ^today),
      :count,
      :id
    )
  end

  defp count_past_events do
    today = DateTime.utc_now()

    Repo.aggregate(
      from(e in PublicEvent, where: e.starts_at < ^today),
      :count,
      :id
    )
  end

  defp get_active_jobs_count do
    # Get count from Monitoring module if available
    case Monitoring.get_summary_stats() do
      %{total_jobs: count} -> count
      _ -> 0
    end
  rescue
    _ -> 0
  end

  defp get_geocoding_queue_count do
    # Query Oban jobs for geocoding workers that are scheduled/available
    query =
      from(j in Oban.Job,
        where:
          j.worker in [
            "EventasaurusDiscovery.Geocoding.Workers.GeocodingWorker",
            "EventasaurusDiscovery.Geocoding.Workers.BulkGeocodingWorker"
          ],
        where: j.state in ["available", "scheduled"],
        select: count(j.id)
      )

    Repo.one(query) || 0
  rescue
    _ -> 0
  end

  defp get_recent_scraper_errors do
    # Get scraper errors from last 24 hours
    twenty_four_hours_ago = DateTime.add(DateTime.utc_now(), -24, :hour)

    query =
      from(log in ScraperProcessingLog,
        where: log.status == :error,
        where: log.processed_at >= ^twenty_four_hours_ago,
        select: count(log.id)
      )

    Repo.one(query) || 0
  rescue
    _ -> 0
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
