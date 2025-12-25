defmodule EventasaurusWeb.Admin.CategoryDashboardLive do
  @moduledoc """
  LiveView for category analytics dashboard.
  Shows summary statistics, distribution charts, and top categories.
  """

  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.CategoryAnalytics

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Category Dashboard")
      |> assign(:loading, true)
      |> load_stats()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  defp load_stats(socket) do
    stats = CategoryAnalytics.summary_stats()
    distribution = CategoryAnalytics.category_distribution(limit: 12)
    top_categories = CategoryAnalytics.top_categories(limit: 10)
    source_breakdown = CategoryAnalytics.source_breakdown()
    recent_assignments = CategoryAnalytics.recent_assignments(limit: 15)

    socket
    |> assign(:stats, stats)
    |> assign(:distribution, distribution)
    |> assign(:top_categories, top_categories)
    |> assign(:source_breakdown, source_breakdown)
    |> assign(:recent_assignments, recent_assignments)
    |> assign(:loading, false)
  end

  # Helper functions for formatting
  def format_number(n) when is_integer(n) and n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  def format_number(n) when is_integer(n) and n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}K"
  end

  def format_number(n) when is_integer(n), do: Integer.to_string(n)
  def format_number(n) when is_float(n), do: Float.round(n, 1) |> to_string()
  def format_number(nil), do: "0"

  def format_percentage(n) when is_float(n), do: "#{Float.round(n, 1)}%"
  def format_percentage(n) when is_integer(n), do: "#{n}%"
  def format_percentage(nil), do: "0%"

  def category_color(nil), do: "#6B7280"
  def category_color(""), do: "#6B7280"
  def category_color(color), do: color

  def source_label("scraper"), do: "Scraper"
  def source_label("manual"), do: "Manual"
  def source_label("ml"), do: "ML Model"
  def source_label("inference"), do: "Inference"
  def source_label(nil), do: "Unknown"
  def source_label(other), do: String.capitalize(to_string(other))

  def source_color("scraper"), do: "bg-blue-500"
  def source_color("manual"), do: "bg-green-500"
  def source_color("ml"), do: "bg-purple-500"
  def source_color("inference"), do: "bg-indigo-500"
  def source_color(_), do: "bg-gray-400"

  def format_relative_time(nil), do: "Unknown"

  def format_relative_time(%NaiveDateTime{} = naive_datetime) do
    # Convert NaiveDateTime to DateTime (assuming UTC)
    {:ok, datetime} = DateTime.from_naive(naive_datetime, "Etc/UTC")
    format_relative_time(datetime)
  end

  def format_relative_time(%DateTime{} = datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 -> "Just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
      diff_seconds < 604_800 -> "#{div(diff_seconds, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end

  def confidence_badge_class(confidence) when confidence >= 0.8, do: "bg-green-100 text-green-800"
  def confidence_badge_class(confidence) when confidence >= 0.5, do: "bg-yellow-100 text-yellow-800"
  def confidence_badge_class(_), do: "bg-gray-100 text-gray-600"

  def confidence_label(confidence) when is_float(confidence) do
    "#{round(confidence * 100)}%"
  end

  def confidence_label(_), do: "N/A"
end
