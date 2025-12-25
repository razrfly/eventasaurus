defmodule EventasaurusWeb.Admin.CategoryInsightsLive do
  @moduledoc """
  LiveView for category insights and analytics.
  Shows trend analysis, source breakdown, and category overlap data.
  """

  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.CategoryAnalytics

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Category Insights")
      |> assign(:loading, true)
      |> load_insights()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  defp load_insights(socket) do
    # Load all insights data
    trends = CategoryAnalytics.category_trends(months: 6, limit_categories: 8)
    months = CategoryAnalytics.trend_months(6)
    source_breakdown = CategoryAnalytics.all_categories_source_breakdown(limit_categories: 10)
    overlap_matrix = CategoryAnalytics.category_overlap_matrix(limit: 10)
    category_count_dist = CategoryAnalytics.category_count_distribution()
    confidence_dist = CategoryAnalytics.confidence_distribution()
    multi_category_count = CategoryAnalytics.multi_category_events_count()

    # Transform trends data for chart display
    trends_by_category = transform_trends_for_chart(trends, months)

    socket
    |> assign(:trends, trends)
    |> assign(:months, months)
    |> assign(:trends_by_category, trends_by_category)
    |> assign(:source_breakdown, source_breakdown)
    |> assign(:overlap_matrix, overlap_matrix)
    |> assign(:category_count_dist, category_count_dist)
    |> assign(:confidence_dist, confidence_dist)
    |> assign(:multi_category_count, multi_category_count)
    |> assign(:loading, false)
  end

  defp transform_trends_for_chart(trends, months) do
    # Group by category and fill in missing months with 0
    trends
    |> Enum.group_by(& &1.category_name)
    |> Enum.map(fn {category_name, data} ->
      # Get the first entry for color
      color = List.first(data)[:category_color] || "#6B7280"

      # Create a map of month -> count for this category
      month_counts = Map.new(data, fn d -> {d.month, d.event_count} end)

      # Fill in all months
      monthly_data =
        Enum.map(months, fn month ->
          %{month: month, count: Map.get(month_counts, month, 0)}
        end)

      %{
        category: category_name,
        color: color,
        data: monthly_data,
        total: Enum.sum(Enum.map(monthly_data, & &1.count))
      }
    end)
    |> Enum.sort_by(& &1.total, :desc)
  end

  # Helper functions for template

  def format_number(nil), do: "0"
  def format_number(num) when is_integer(num) and num >= 1000 do
    "#{Float.round(num / 1000, 1)}K"
  end
  def format_number(num) when is_integer(num), do: Integer.to_string(num)
  def format_number(num) when is_float(num), do: Float.round(num, 1) |> to_string()

  def format_month(month_str) do
    # Convert "2024-12" to "Dec 24"
    case String.split(month_str, "-") do
      [year, month] ->
        month_name = month_abbrev(String.to_integer(month))
        year_short = String.slice(year, 2, 2)
        "#{month_name} '#{year_short}"

      _ ->
        month_str
    end
  end

  defp month_abbrev(1), do: "Jan"
  defp month_abbrev(2), do: "Feb"
  defp month_abbrev(3), do: "Mar"
  defp month_abbrev(4), do: "Apr"
  defp month_abbrev(5), do: "May"
  defp month_abbrev(6), do: "Jun"
  defp month_abbrev(7), do: "Jul"
  defp month_abbrev(8), do: "Aug"
  defp month_abbrev(9), do: "Sep"
  defp month_abbrev(10), do: "Oct"
  defp month_abbrev(11), do: "Nov"
  defp month_abbrev(12), do: "Dec"

  def source_label(nil), do: "Unknown"
  def source_label("unknown"), do: "Unknown"
  def source_label(source), do: String.capitalize(source)

  def source_color(nil), do: "bg-gray-500"
  def source_color("unknown"), do: "bg-gray-500"
  def source_color("karnet"), do: "bg-purple-500"
  def source_color("bandsintown"), do: "bg-teal-500"
  def source_color("ticketmaster"), do: "bg-blue-500"
  def source_color("manual"), do: "bg-green-500"
  def source_color("migration"), do: "bg-amber-500"
  def source_color("cinema_city"), do: "bg-red-500"
  def source_color("kino_krakow"), do: "bg-orange-500"
  def source_color("repertuary"), do: "bg-pink-500"
  def source_color("week_pl"), do: "bg-indigo-500"
  def source_color(_), do: "bg-gray-400"

  def category_color(nil), do: "#6B7280"
  def category_color(""), do: "#6B7280"
  def category_color(color), do: color

  def max_trend_value(trends_by_category) do
    trends_by_category
    |> Enum.flat_map(fn cat -> Enum.map(cat.data, & &1.count) end)
    |> Enum.max(fn -> 1 end)
  end

  def bar_height(count, max_val) when max_val > 0 do
    height = count / max_val * 100
    "#{max(height, 2)}%"
  end
  def bar_height(_, _), do: "2%"
end
