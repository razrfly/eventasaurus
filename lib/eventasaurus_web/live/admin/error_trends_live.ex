defmodule EventasaurusWeb.Admin.ErrorTrendsLive do
  @moduledoc """
  LiveView for error trending and analysis dashboard.

  Provides:
  - Error rate trends over time (hourly/daily)
  - Top error messages by frequency
  - Scraper comparison with SLO indicators
  - CSV export of error data
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.JobExecutionSummaries
  alias EventasaurusDiscovery.Metrics.ScraperSLOs

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Error Trends & Analysis")
      |> assign(:time_range, 168)
      # 7 days default
      |> assign(:granularity, :hour)
      |> assign(:top_errors_limit, 10)
      |> assign(:loading, true)
      |> load_error_trends()
      |> load_top_errors()
      |> load_scraper_comparison()
      |> assign(:loading, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("change_time_range", %{"time_range" => time_range}, socket) do
    time_range_hours =
      case Integer.parse(time_range) do
        {hours, _} when hours > 0 -> hours
        _ -> socket.assigns.time_range
      end

    # Auto-adjust granularity based on time range
    granularity =
      cond do
        time_range_hours <= 48 -> :hour
        true -> :day
      end

    socket =
      socket
      |> assign(:time_range, time_range_hours)
      |> assign(:granularity, granularity)
      |> assign(:loading, true)
      |> load_error_trends()
      |> load_top_errors()
      |> load_scraper_comparison()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_granularity", %{"granularity" => granularity_str}, socket) do
    granularity = String.to_existing_atom(granularity_str)

    socket =
      socket
      |> assign(:granularity, granularity)
      |> assign(:loading, true)
      |> load_error_trends()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    socket =
      socket
      |> assign(:loading, true)
      |> load_error_trends()
      |> load_top_errors()
      |> load_scraper_comparison()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("export_csv", _params, socket) do
    # Generate CSV data
    csv_data = generate_csv_export(socket.assigns)

    # Send CSV download to client
    {:noreply,
     push_event(socket, "download_csv", %{
       filename: "error_trends_#{Date.utc_today()}.csv",
       data: csv_data
     })}
  end

  # Load error rate trends over time
  defp load_error_trends(socket) do
    trends =
      JobExecutionSummaries.get_error_trends(
        socket.assigns.time_range,
        granularity: socket.assigns.granularity
      )

    assign(socket, :error_trends, trends)
  end

  # Load top error messages
  defp load_top_errors(socket) do
    top_errors =
      JobExecutionSummaries.get_top_error_messages(
        socket.assigns.time_range,
        limit: socket.assigns.top_errors_limit
      )

    assign(socket, :top_errors, top_errors)
  end

  # Load scraper comparison with SLO enrichment
  defp load_scraper_comparison(socket) do
    scrapers =
      JobExecutionSummaries.compare_scrapers(socket.assigns.time_range)
      |> Enum.map(&ScraperSLOs.enrich_with_slo/1)
      |> Enum.sort_by(& &1.slo_status, :desc)

    assign(socket, :scrapers, scrapers)
  end

  # Generate CSV export
  defp generate_csv_export(assigns) do
    headers = "Worker,Total Jobs,Success Rate,Avg Duration (ms),SLO Status\n"

    rows =
      assigns.scrapers
      |> Enum.map(fn scraper ->
        [
          worker_name(scraper.worker),
          scraper.total_jobs,
          "#{scraper.success_rate}%",
          scraper.avg_duration_ms || "N/A",
          scraper.slo_status
        ]
        |> Enum.join(",")
      end)
      |> Enum.join("\n")

    headers <> rows
  end

  # Get worker display name (short version)
  defp worker_name(worker) do
    worker
    |> String.split(".")
    |> List.last()
  end

  # Format time range label
  defp time_range_label(hours) do
    cond do
      hours <= 24 -> "Last 24 hours"
      hours <= 168 -> "Last 7 days"
      hours <= 720 -> "Last 30 days"
      true -> "Last #{hours} hours"
    end
  end

  # Format relative time
  defp format_relative_time(datetime) when is_nil(datetime), do: "N/A"

  defp format_relative_time(datetime) do
    diff_seconds = DateTime.diff(DateTime.utc_now(), datetime)

    cond do
      diff_seconds < 60 -> "#{diff_seconds}s ago"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
      true -> "#{div(diff_seconds, 86400)}d ago"
    end
  end

  # Format number with thousands separator
  defp format_number(nil), do: "0"

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_number(num) when is_float(num), do: format_number(round(num))
  defp format_number(_), do: "0"

  # Format duration
  defp format_duration(nil), do: "N/A"

  defp format_duration(ms) when is_number(ms) do
    cond do
      ms < 1000 -> "#{round(ms)}ms"
      ms < 60000 -> "#{Float.round(ms / 1000, 1)}s"
      true -> "#{Float.round(ms / 60000, 1)}m"
    end
  end

  defp format_duration(_), do: "N/A"

  # Get error category badge class
  # Categories: 12 standard + 1 fallback (uncategorized_error)
  defp error_category_badge_class(error_category) do
    case error_category do
      "validation_error" -> "bg-red-100 text-red-800"
      "parsing_error" -> "bg-rose-100 text-rose-800"
      "data_quality_error" -> "bg-amber-100 text-amber-800"
      "data_integrity_error" -> "bg-orange-100 text-orange-800"
      "dependency_error" -> "bg-sky-100 text-sky-800"
      "network_error" -> "bg-yellow-100 text-yellow-800"
      "rate_limit_error" -> "bg-lime-100 text-lime-800"
      "authentication_error" -> "bg-fuchsia-100 text-fuchsia-800"
      "geocoding_error" -> "bg-blue-100 text-blue-800"
      "venue_error" -> "bg-purple-100 text-purple-800"
      "performer_error" -> "bg-pink-100 text-pink-800"
      "tmdb_error" -> "bg-indigo-100 text-indigo-800"
      "uncategorized_error" -> "bg-gray-100 text-gray-800"
      # Legacy categories (for historical data)
      "unknown_error" -> "bg-gray-100 text-gray-800"
      "category_error" -> "bg-indigo-100 text-indigo-800"
      "duplicate_error" -> "bg-orange-100 text-orange-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  # Format error category for display
  defp format_error_category(nil), do: "Unknown"

  defp format_error_category(category) do
    category
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Header -->
      <div class="md:flex md:items-center md:justify-between mb-8">
        <div class="flex-1 min-w-0">
          <h1 class="text-3xl font-bold text-gray-900">
            Error Trends & Analysis
          </h1>
          <p class="mt-2 text-sm text-gray-600">
            Historical error patterns and scraper performance analysis
          </p>
        </div>
        <div class="mt-4 flex gap-3 md:mt-0 md:ml-4">
          <form phx-change="change_time_range">
            <select
              name="time_range"
              class="rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 text-sm"
            >
              <option value="24" selected={@time_range == 24}>Last 24 hours</option>
              <option value="168" selected={@time_range == 168}>Last 7 days</option>
              <option value="720" selected={@time_range == 720}>Last 30 days</option>
            </select>
          </form>
          <button
            type="button"
            phx-click="refresh"
            class="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
          >
            🔄 Refresh
          </button>
          <button
            type="button"
            phx-click="export_csv"
            class="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
          >
            📥 Export CSV
          </button>
        </div>
      </div>

      <!-- Error Rate Trends -->
      <div class="bg-white shadow rounded-lg mb-8">
        <div class="px-4 py-5 sm:p-6">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-lg font-medium text-gray-900">
              Error Rate Over Time
              <span class="text-sm font-normal text-gray-500">
                (<%= time_range_label(@time_range) %>)
              </span>
            </h2>
            <form phx-change="change_granularity">
              <select
                name="granularity"
                class="rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 text-sm"
              >
                <option value="hour" selected={@granularity == :hour}>Hourly</option>
                <option value="day" selected={@granularity == :day}>Daily</option>
              </select>
            </form>
          </div>

          <%= if Enum.empty?(@error_trends) do %>
            <div class="text-center py-8 text-gray-500">No trend data available</div>
          <% else %>
            <div class="space-y-2">
              <%= for trend <- @error_trends do %>
                <div class="flex items-center gap-2">
                  <div class="w-32 text-xs text-gray-500 flex-shrink-0">
                    <%= Calendar.strftime(trend.time_bucket, "%m/%d %H:%M") %>
                  </div>
                  <div class="flex-1">
                    <div class="flex items-center gap-2">
                      <div class="flex-1 bg-gray-200 rounded-full h-6">
                        <div
                          class={"h-6 rounded-full flex items-center justify-center text-xs font-medium text-white " <>
                            if trend.error_rate > 20, do: "bg-red-500", else: if(trend.error_rate > 10, do: "bg-yellow-500", else: "bg-green-500")}
                          style={"width: #{min(trend.error_rate, 100)}%"}
                        >
                          <%= if trend.error_rate > 5, do: "#{trend.error_rate}%", else: "" %>
                        </div>
                      </div>
                      <div class="w-24 text-xs text-gray-500 text-right">
                        <%= trend.failed %>/<%= trend.total %> failed
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Scraper Comparison with SLOs -->
      <div class="bg-white shadow rounded-lg mb-8">
        <div class="px-4 py-5 sm:p-6">
          <h2 class="text-lg font-medium text-gray-900 mb-4">
            Scraper Performance vs SLOs
          </h2>

          <%= if Enum.empty?(@scrapers) do %>
            <div class="text-center py-8 text-gray-500">No scraper data available</div>
          <% else %>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-gray-50">
                  <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Scraper
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Total Jobs
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Success Rate
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Target
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Avg Duration
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      SLO Status
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-gray-200">
                  <%= for scraper <- @scrapers do %>
                    <tr>
                      <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                        <%= worker_name(scraper.worker) %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        <%= format_number(scraper.total_jobs) %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm">
                        <span class={
                          "inline-flex px-2 py-1 text-xs font-semibold rounded-full " <>
                            ScraperSLOs.status_badge_class(scraper.slo_status)
                        }>
                          <%= scraper.success_rate %>%
                        </span>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        <%= trunc(scraper.slo.target_success_rate * 100) %>%
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        <%= format_duration(scraper.avg_duration_ms) %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm">
                        <%= scraper.slo_indicator %> <%= Atom.to_string(scraper.slo_status)
                        |> String.replace("_", " ")
                        |> String.capitalize() %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Top Error Messages -->
      <div class="bg-white shadow rounded-lg">
        <div class="px-4 py-5 sm:p-6">
          <h2 class="text-lg font-medium text-gray-900 mb-4">
            Top Error Messages
          </h2>

          <%= if Enum.empty?(@top_errors) do %>
            <div class="text-center py-8 text-gray-500">No errors found</div>
          <% else %>
            <div class="space-y-3">
              <%= for error <- @top_errors do %>
                <div class="border border-gray-200 rounded-lg p-4">
                  <div class="flex items-start justify-between mb-2">
                    <div class="flex-1">
                      <div class="flex items-center gap-2 mb-1">
                        <span class={"inline-flex px-2 py-1 text-xs font-semibold rounded-full " <> error_category_badge_class(error.error_category)}>
                          <%= format_error_category(error.error_category) %>
                        </span>
                        <span class="text-xs text-gray-500">
                          <%= format_number(error.count) %> occurrences
                        </span>
                      </div>
                      <p class="text-sm text-gray-900 font-mono">
                        <%= error.error_message %>
                      </p>
                    </div>
                  </div>
                  <div class="flex items-center gap-4 text-xs text-gray-500">
                    <span>First: <%= format_relative_time(error.first_seen) %></span>
                    <span>Last: <%= format_relative_time(error.last_seen) %></span>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
