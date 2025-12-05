defmodule EventasaurusWeb.Admin.ScraperLogsLive do
  @moduledoc """
  Admin dashboard for viewing scraper processing logs and analytics.

  This LiveView provides comprehensive scraper health monitoring:
  - Success/failure rates by scraper
  - Error type breakdowns with categorization
  - Recent processing logs with metadata
  - Unknown errors for investigation
  - Time range filtering

  Features:
  - Real-time stats with configurable time ranges
  - Per-scraper analytics
  - Error pattern discovery
  - Link to Oban jobs for debugging
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.ScraperProcessingLogs
  alias EventasaurusDiscovery.ScraperProcessingLogs.ScraperProcessingLog
  alias EventasaurusDiscovery.Sources.SourceStore

  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    sources = SourceStore.list_active_sources()

    socket =
      socket
      |> assign(:page_title, "Scraper Processing Logs")
      |> assign(:sources, sources)
      |> assign(:selected_source, nil)
      |> assign(:time_range, 7)
      |> assign(:status_filter, nil)
      |> assign(:sort_by, :processed_at)
      |> assign(:sort_dir, :desc)
      |> assign(:expanded_source, nil)
      |> assign(:loading, true)
      |> load_analytics()
      |> load_recent_logs()
      |> load_unknown_errors()
      |> assign(:loading, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("update_filters", %{"source" => source_name, "days" => days_str}, socket) do
    # Parse source filter
    selected_source = if source_name == "all", do: nil, else: source_name

    # Parse time range filter
    time_range =
      case Integer.parse(days_str) do
        {days, _} when days > 0 -> days
        _ -> socket.assigns.time_range
      end

    socket =
      socket
      |> assign(:selected_source, selected_source)
      |> assign(:time_range, time_range)
      |> assign(:loading, true)
      |> load_analytics()
      |> load_recent_logs()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  # Legacy handlers kept for backwards compatibility (if needed elsewhere)
  @impl true
  def handle_event("select_source", %{"source" => source_name}, socket) do
    selected_source = if source_name == "all", do: nil, else: source_name

    socket =
      socket
      |> assign(:selected_source, selected_source)
      |> assign(:loading, true)
      |> load_analytics()
      |> load_recent_logs()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_time_range", %{"days" => days_str}, socket) do
    case Integer.parse(days_str) do
      {days, _} when days > 0 ->
        socket =
          socket
          |> assign(:time_range, days)
          |> assign(:loading, true)
          |> load_analytics()
          |> load_recent_logs()
          |> assign(:loading, false)

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    socket =
      socket
      |> assign(:loading, true)
      |> load_analytics()
      |> load_recent_logs()
      |> load_unknown_errors()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    status_filter =
      case status do
        "all" -> nil
        "failure" -> "failure"
        "success" -> "success"
        _ -> nil
      end

    socket =
      socket
      |> assign(:status_filter, status_filter)
      |> assign(:loading, true)
      |> load_recent_logs()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort_column", %{"column" => column}, socket) do
    # Whitelist allowed columns to prevent atom table exhaustion (security)
    column_atom =
      case column do
        "processed_at" -> :processed_at
        "source_name" -> :source_name
        "status" -> :status
        "error_type" -> :error_type
        _ -> socket.assigns.sort_by
      end

    # Toggle direction if same column, else default to desc
    sort_dir =
      if socket.assigns.sort_by == column_atom do
        toggle_direction(socket.assigns.sort_dir)
      else
        :desc
      end

    socket =
      socket
      |> assign(:sort_by, column_atom)
      |> assign(:sort_dir, sort_dir)
      |> assign(:loading, true)
      |> load_recent_logs()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("view_source_details", %{"source" => source_name}, socket) do
    # Toggle: if clicking same source, collapse it; otherwise expand the new one
    expanded_source =
      if socket.assigns.expanded_source == source_name do
        nil
      else
        source_name
      end

    socket = assign(socket, :expanded_source, expanded_source)

    {:noreply, socket}
  end

  # Load analytics data (success rates and error breakdowns)
  defp load_analytics(socket) do
    time_range = socket.assigns.time_range
    selected_source = socket.assigns.selected_source

    analytics =
      if selected_source do
        # Single source analytics
        %{
          sources: [
            %{
              name: selected_source,
              stats: ScraperProcessingLogs.get_success_rate(selected_source, time_range),
              errors: ScraperProcessingLogs.get_error_breakdown(selected_source, time_range)
            }
          ]
        }
      else
        # All sources analytics
        sources_data =
          socket.assigns.sources
          |> Enum.map(fn source ->
            %{
              name: source.name,
              stats: ScraperProcessingLogs.get_success_rate(source.name, time_range),
              errors: ScraperProcessingLogs.get_error_breakdown(source.name, time_range)
            }
          end)
          |> Enum.filter(fn source_data -> source_data.stats.total_count > 0 end)
          |> Enum.sort_by(& &1.stats.failure_count, :desc)

        %{sources: sources_data}
      end

    assign(socket, :analytics, analytics)
  end

  # Load recent processing logs
  defp load_recent_logs(socket) do
    time_range = socket.assigns.time_range
    selected_source = socket.assigns.selected_source
    status_filter = socket.assigns.status_filter
    sort_by = socket.assigns.sort_by
    sort_dir = socket.assigns.sort_dir
    cutoff_date = DateTime.utc_now() |> DateTime.add(-time_range, :day)

    # Build dynamic order_by based on sort direction
    order_by_clause = [{sort_dir, sort_by}]

    query =
      from(l in ScraperProcessingLog,
        where: l.processed_at > ^cutoff_date,
        order_by: ^order_by_clause,
        limit: 50
      )

    query =
      if selected_source do
        from(l in query, where: l.source_name == ^selected_source)
      else
        query
      end

    query =
      if status_filter do
        from(l in query, where: l.status == ^status_filter)
      else
        query
      end

    recent_logs = Repo.replica().all(query)

    assign(socket, :recent_logs, recent_logs)
  end

  # Toggle sort direction
  defp toggle_direction(:asc), do: :desc
  defp toggle_direction(:desc), do: :asc

  # Load unknown errors for investigation
  defp load_unknown_errors(socket) do
    unknown_errors = ScraperProcessingLogs.get_unknown_errors(20)
    assign(socket, :unknown_errors, unknown_errors)
  end

  # Helper functions for view

  defp status_badge_class("success"), do: "bg-green-100 text-green-800"
  defp status_badge_class("failure"), do: "bg-red-100 text-red-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp health_color(rate) when rate >= 95, do: "text-green-600"
  defp health_color(rate) when rate >= 80, do: "text-yellow-600"
  defp health_color(_), do: "text-red-600"

  defp format_error_type(nil), do: "unknown"

  defp format_error_type(error_type) do
    error_type
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp truncate(nil, _), do: ""

  defp truncate(string, length) when is_binary(string) do
    if String.length(string) > length do
      String.slice(string, 0, length) <> "..."
    else
      string
    end
  end

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end
end
