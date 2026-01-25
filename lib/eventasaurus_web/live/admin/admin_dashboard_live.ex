defmodule EventasaurusWeb.Admin.AdminDashboardLive do
  @moduledoc """
  Central admin dashboard providing quick access to all admin functionality.

  Uses staged loading pattern to prevent timeout on cold cache:
  - Tier 1 (Critical): System health, errors, queue status - loads first
  - Tier 2 (Important): Events, venues, movies, images - loads second
  - Tier 3 (Context): Geocoding, collisions, sources - loads last

  Each tier loads independently via assign_async for responsive UX.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusWeb.Admin.UnifiedDashboardStats
  import EventasaurusWeb.Admin.Components.HealthComponents, only: [source_status_table: 1]

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Admin Dashboard")
      |> assign(:tier1_stats, nil)
      |> assign(:tier2_stats, nil)
      |> assign(:tier3_stats, nil)
      |> assign(:source_table, nil)
      |> assign(:zscore_data, nil)
      |> assign(:sort_by, :health_score)
      |> assign(:sort_dir, :desc)

    if connected?(socket) do
      # Start loading stats in tiers for staged display
      {:ok, load_stats_async(socket)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_async(:tier1_stats, {:ok, stats}, socket) do
    Logger.info("ADMIN_DEBUG: tier1_stats loaded successfully")
    Logger.info("ADMIN_DEBUG: tier1_stats keys: #{inspect(Map.keys(stats))}")
    {:noreply, assign(socket, :tier1_stats, stats)}
  end

  def handle_async(:tier1_stats, {:exit, reason}, socket) do
    Logger.error("Failed to load tier1 stats: #{inspect(reason)}")
    {:noreply, assign(socket, :tier1_stats, :error)}
  end

  @impl true
  def handle_async(:tier2_stats, {:ok, stats}, socket) do
    Logger.info("ADMIN_DEBUG: tier2_stats loaded successfully")
    {:noreply, assign(socket, :tier2_stats, stats)}
  end

  def handle_async(:tier2_stats, {:exit, reason}, socket) do
    Logger.error("Failed to load tier2 stats: #{inspect(reason)}")
    {:noreply, assign(socket, :tier2_stats, :error)}
  end

  @impl true
  def handle_async(:tier3_stats, {:ok, stats}, socket) do
    {:noreply, assign(socket, :tier3_stats, stats)}
  end

  def handle_async(:tier3_stats, {:exit, reason}, socket) do
    Logger.error("Failed to load tier3 stats: #{inspect(reason)}")
    {:noreply, assign(socket, :tier3_stats, :error)}
  end

  @impl true
  def handle_async(:source_table, {:ok, stats}, socket) do
    sorted = sort_sources(stats, socket.assigns.sort_by, socket.assigns.sort_dir)
    {:noreply, assign(socket, :source_table, sorted)}
  end

  def handle_async(:source_table, {:exit, reason}, socket) do
    Logger.error("Failed to load source table stats: #{inspect(reason)}")
    {:noreply, assign(socket, :source_table, :error)}
  end

  @impl true
  def handle_async(:zscore_data, {:ok, data}, socket) do
    {:noreply, assign(socket, :zscore_data, data)}
  end

  def handle_async(:zscore_data, {:exit, reason}, socket) do
    Logger.error("Failed to load z-score data: #{inspect(reason)}")
    {:noreply, assign(socket, :zscore_data, nil)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_stats_async(socket)}
  end

  # Allowlist of valid sort columns to prevent atom exhaustion
  # Validate as strings BEFORE converting to atom
  @allowed_sort_columns ~w(display_name health_score success_rate p95_duration last_execution coverage_days)

  @impl true
  def handle_event("sort_sources", %{"column" => column}, socket) do
    # Validate against string allowlist BEFORE converting to atom
    # This prevents both atom exhaustion and ArgumentError from to_existing_atom
    if column not in @allowed_sort_columns do
      {:noreply, socket}
    else
      # Safe to convert - we know this atom exists in our allowlist
      column_atom = String.to_existing_atom(column)
      current_sort = socket.assigns.sort_by
      current_dir = socket.assigns.sort_dir

      # Toggle direction if same column, otherwise default to desc
      new_dir =
        if column_atom == current_sort do
          if current_dir == :desc, do: :asc, else: :desc
        else
          :desc
        end

      sorted = sort_sources(socket.assigns.source_table, column_atom, new_dir)

      {:noreply,
       socket
       |> assign(:sort_by, column_atom)
       |> assign(:sort_dir, new_dir)
       |> assign(:source_table, sorted)}
    end
  end

  defp sort_sources(nil, _column, _dir), do: nil
  defp sort_sources(:error, _column, _dir), do: :error

  defp sort_sources(sources, column, dir) when is_list(sources) do
    Enum.sort_by(sources, &Map.get(&1, column), dir)
  end

  defp load_stats_async(socket) do
    socket
    |> start_async(:tier1_stats, fn -> UnifiedDashboardStats.fetch_tier1_stats() end)
    |> start_async(:tier2_stats, fn -> UnifiedDashboardStats.fetch_tier2_stats() end)
    |> start_async(:tier3_stats, fn -> UnifiedDashboardStats.fetch_tier3_stats() end)
    |> start_async(:source_table, fn -> UnifiedDashboardStats.fetch_source_table_stats() end)
    |> start_async(:zscore_data, fn -> UnifiedDashboardStats.fetch_zscore_data() end)
  end

  # Helper function to check if stats are loaded
  def stats_loaded?(nil), do: false
  def stats_loaded?(:error), do: false
  def stats_loaded?(_), do: true

  # Format large numbers with commas
  def format_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join(&1, ""))
    |> Enum.join(",")
    |> String.reverse()
  end

  def format_number(number) when is_float(number) do
    number
    |> Float.round(1)
    |> Float.to_string()
  end

  def format_number(_), do: "0"

  # Format bytes for display
  def format_bytes(bytes), do: UnifiedDashboardStats.format_bytes(bytes)

  # Format source name for display
  def format_source_name(name), do: UnifiedDashboardStats.format_source_name(name)

  # Health status color helper
  def health_color(:healthy), do: "green"
  def health_color(:degraded), do: "yellow"
  def health_color(:warning), do: "orange"
  def health_color(:critical), do: "red"
  def health_color(_), do: "gray"

  # Health status text
  def health_text(:healthy), do: "Healthy"
  def health_text(:degraded), do: "Degraded"
  def health_text(:warning), do: "Warning"
  def health_text(:critical), do: "Critical"
  def health_text(_), do: "Unknown"

  # Health background class for cards
  def health_bg_class(:healthy), do: "bg-green-50"
  def health_bg_class(:degraded), do: "bg-yellow-50"
  def health_bg_class(:warning), do: "bg-orange-50"
  def health_bg_class(:critical), do: "bg-red-50"
  def health_bg_class(_), do: "bg-gray-50"

  # Health border class for cards
  def health_border_class(:healthy), do: "border-green-500"
  def health_border_class(:degraded), do: "border-yellow-500"
  def health_border_class(:warning), do: "border-orange-500"
  def health_border_class(:critical), do: "border-red-500"
  def health_border_class(_), do: "border-gray-300"

  # Health text class for labels
  def health_text_class(:healthy), do: "text-green-600"
  def health_text_class(:degraded), do: "text-yellow-600"
  def health_text_class(:warning), do: "text-orange-600"
  def health_text_class(:critical), do: "text-red-600"
  def health_text_class(_), do: "text-gray-600"

  # Health value class for numbers
  def health_value_class(:healthy), do: "text-green-900"
  def health_value_class(:degraded), do: "text-yellow-900"
  def health_value_class(:warning), do: "text-orange-900"
  def health_value_class(:critical), do: "text-red-900"
  def health_value_class(_), do: "text-gray-900"

  # Alerts border class
  def alerts_border_class(:ok), do: "border-green-500"
  def alerts_border_class(:info), do: "border-blue-500"
  def alerts_border_class(:warning), do: "border-yellow-500"
  def alerts_border_class(:critical), do: "border-red-500"
  def alerts_border_class(_), do: "border-gray-300"

  # Alerts background class
  def alerts_bg_class(:ok), do: "bg-green-100"
  def alerts_bg_class(:info), do: "bg-blue-100"
  def alerts_bg_class(:warning), do: "bg-yellow-100"
  def alerts_bg_class(:critical), do: "bg-red-100"
  def alerts_bg_class(_), do: "bg-gray-100"

  # Alerts value class
  def alerts_value_class(:ok), do: "text-green-900"
  def alerts_value_class(:info), do: "text-blue-900"
  def alerts_value_class(:warning), do: "text-yellow-900"
  def alerts_value_class(:critical), do: "text-red-900"
  def alerts_value_class(_), do: "text-gray-900"

  # Freshness border class
  def freshness_border_class(:fresh), do: "border-green-500"
  def freshness_border_class(:mostly_fresh), do: "border-blue-500"
  def freshness_border_class(:stale), do: "border-yellow-500"
  def freshness_border_class(:very_stale), do: "border-red-500"
  def freshness_border_class(_), do: "border-gray-300"

  # Freshness background class
  def freshness_bg_class(:fresh), do: "bg-green-100"
  def freshness_bg_class(:mostly_fresh), do: "bg-blue-100"
  def freshness_bg_class(:stale), do: "bg-yellow-100"
  def freshness_bg_class(:very_stale), do: "bg-red-100"
  def freshness_bg_class(_), do: "bg-gray-100"

  # Freshness value class
  def freshness_value_class(:fresh), do: "text-green-900"
  def freshness_value_class(:mostly_fresh), do: "text-blue-900"
  def freshness_value_class(:stale), do: "text-yellow-900"
  def freshness_value_class(:very_stale), do: "text-red-900"
  def freshness_value_class(_), do: "text-gray-900"

  # Freshness icon class
  def freshness_icon_class(:fresh), do: "text-green-600"
  def freshness_icon_class(:mostly_fresh), do: "text-blue-600"
  def freshness_icon_class(:stale), do: "text-yellow-600"
  def freshness_icon_class(:very_stale), do: "text-red-600"
  def freshness_icon_class(_), do: "text-gray-600"

  # Format hours ago for display
  def format_hours_ago(nil), do: "Unknown"
  def format_hours_ago(0), do: "Just now"
  def format_hours_ago(1), do: "1 hour ago"
  def format_hours_ago(hours) when hours < 24, do: "#{hours} hours ago"

  def format_hours_ago(hours) do
    days = div(hours, 24)
    if days == 1, do: "1 day ago", else: "#{days} days ago"
  end

  # Helper to build zscore subtitle for source_status_table component
  def zscore_subtitle(nil), do: nil

  def zscore_subtitle(zscore_data) do
    "μ: #{Float.round(zscore_data.success_mean, 1)}% success, #{Float.round(zscore_data.duration_mean, 1)}s avg"
  end

  # Source table helper functions
  # NOTE: These functions are duplicated in HealthComponents. When we use the shared
  # source_status_table component, these are no longer needed for the Source Status table,
  # but may still be used elsewhere in the template.

  # Health status dot color (green/yellow/red dot next to source name)
  def source_health_dot_class(:healthy), do: "bg-green-500"
  def source_health_dot_class(:degraded), do: "bg-yellow-500"
  def source_health_dot_class(:warning), do: "bg-orange-500"
  def source_health_dot_class(:critical), do: "bg-red-500"
  def source_health_dot_class(_), do: "bg-gray-400"

  # Health score badge class (for the health percentage badge)
  def source_health_badge_class(score) when score >= 95, do: "bg-green-100 text-green-800"
  def source_health_badge_class(score) when score >= 85, do: "bg-yellow-100 text-yellow-800"
  def source_health_badge_class(score) when score >= 70, do: "bg-orange-100 text-orange-800"
  def source_health_badge_class(_score), do: "bg-red-100 text-red-800"

  # Success rate color (for success % column)
  def success_rate_color(rate) when rate >= 95.0, do: "text-green-600"
  def success_rate_color(rate) when rate >= 85.0, do: "text-yellow-600"
  def success_rate_color(_rate), do: "text-red-600"

  # Sparkline color based on trend direction
  def sparkline_color(:improving), do: "#22c55e"
  def sparkline_color(:declining), do: "#ef4444"
  def sparkline_color(:stable), do: "#6b7280"
  def sparkline_color(_), do: "#6b7280"

  # Convert daily rates to SVG polyline points
  # daily_rates is a list of maps: [%{day: "2026-01-01", success_rate: 75.5, total: 100}, ...]
  def sparkline_points(daily_rates) when is_list(daily_rates) and length(daily_rates) > 0 do
    # Extract success_rate values from the maps
    rates =
      Enum.map(daily_rates, fn
        %{success_rate: rate} when is_number(rate) -> rate
        rate when is_number(rate) -> rate
        _ -> 0.0
      end)

    # Normalize rates to fit in 64x24 viewbox
    min_val = Enum.min(rates) || 0
    max_val = Enum.max(rates) || 100
    range = max(max_val - min_val, 1)

    rates
    |> Enum.with_index()
    |> Enum.map(fn {rate, i} ->
      x = i * (64 / max(length(rates) - 1, 1))
      # Invert Y because SVG y=0 is top
      y = 22 - (rate - min_val) / range * 20
      "#{Float.round(x, 1)},#{Float.round(y, 1)}"
    end)
    |> Enum.join(" ")
  end

  def sparkline_points(_), do: "0,12 64,12"

  # Trend text color class
  def trend_text_class(:improving), do: "text-green-600"
  def trend_text_class(:declining), do: "text-red-600"
  def trend_text_class(:stable), do: "text-gray-500"
  def trend_text_class(_), do: "text-gray-500"

  # Trend arrow symbol
  def trend_arrow(:improving), do: "↑"
  def trend_arrow(:declining), do: "↓"
  def trend_arrow(:stable), do: "→"
  def trend_arrow(_), do: "→"

  # Format duration in milliseconds to human-readable
  def format_duration(nil), do: "-"
  def format_duration(ms) when ms == 0, do: "0ms"

  def format_duration(ms) when is_number(ms) do
    cond do
      ms < 1000 -> "#{round(ms)}ms"
      ms < 60_000 -> "#{Float.round(ms / 1000, 1)}s"
      true -> "#{Float.round(ms / 60_000, 1)}m"
    end
  end

  # Format last run timestamp
  def format_last_run(nil), do: "Never"

  def format_last_run(%DateTime{} = dt) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, dt)

    cond do
      diff_seconds < 60 -> "Just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
      true -> "#{div(diff_seconds, 86400)}d ago"
    end
  end

  def format_last_run(%NaiveDateTime{} = dt) do
    dt
    |> DateTime.from_naive!("Etc/UTC")
    |> format_last_run()
  end

  def format_last_run(_), do: "Unknown"

  # Z-score helper functions

  @doc """
  Get z-score status for a source from zscore_data.
  Returns {:ok, status, zscore_info} | :not_available
  """
  def get_zscore_status(_source, nil), do: :not_available

  def get_zscore_status(source, zscore_data) do
    case Enum.find(zscore_data.sources, &(&1.source == source)) do
      nil -> :not_available
      data -> {:ok, data.overall_status, data}
    end
  end

  @doc """
  Render z-score indicator HTML as raw string.
  """
  def render_zscore_indicator(:not_available) do
    # Empty span for no data
    ""
  end

  def render_zscore_indicator({:ok, :normal, _data}) do
    ~s(<span class="text-green-500" title="Normal - within expected range">✓</span>)
  end

  def render_zscore_indicator({:ok, :warning, data}) do
    tooltip = zscore_tooltip(data)
    ~s(<span class="text-yellow-500 cursor-help" title="#{tooltip}">⚠</span>)
  end

  def render_zscore_indicator({:ok, :critical, data}) do
    tooltip = zscore_tooltip(data)
    ~s(<span class="text-red-500 cursor-help" title="#{tooltip}">!</span>)
  end

  defp zscore_tooltip(data) do
    parts = []

    parts =
      if Map.has_key?(data, :success_zscore) && data.success_zscore != nil do
        z_val = Float.round(data.success_zscore, 2)
        parts ++ ["Success z=#{z_val}"]
      else
        parts
      end

    parts =
      if Map.has_key?(data, :duration_zscore) && data.duration_zscore != nil do
        z_val = Float.round(data.duration_zscore, 2)
        parts ++ ["Duration z=#{z_val}"]
      else
        parts
      end

    Enum.join(parts, ", ")
  end
end
