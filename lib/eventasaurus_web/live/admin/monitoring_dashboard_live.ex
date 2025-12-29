defmodule EventasaurusWeb.Admin.MonitoringDashboardLive do
  @moduledoc """
  Unified monitoring dashboard for scraper health and error analysis.

  Phase 4 implementation of error categorization master plan (Issue #3055).
  Wraps the existing Monitoring.* modules (Health, Errors) into a web interface.

  Features:
  - Health overview with overall score
  - SLO compliance status per source
  - Error category breakdown with recommendations
  - Source and time range filtering
  - Action items for degraded workers

  Target: < 500ms load time using existing optimized queries.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Monitoring.Health
  alias EventasaurusDiscovery.Monitoring.Errors

  @sources ~w(cinema_city repertuary karnet week_pl bandsintown resident_advisor sortiraparis inquizition waw4free)

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Scraper Monitoring")
      |> assign(:time_range, 24)
      |> assign(:selected_source, nil)
      |> assign(:loading, true)
      |> assign(:sources, @sources)
      |> load_dashboard_data()
      |> assign(:loading, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("change_time_range", %{"time_range" => time_range}, socket) do
    time_range_hours =
      case Integer.parse(time_range) do
        {hours, _} when hours in [1, 6, 24, 48, 168] -> hours
        _ -> 24
      end

    socket =
      socket
      |> assign(:time_range, time_range_hours)
      |> assign(:loading, true)
      |> load_dashboard_data()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_source", %{"source" => source}, socket) do
    selected_source = if source == "all", do: nil, else: source

    socket =
      socket
      |> assign(:selected_source, selected_source)
      |> assign(:loading, true)
      |> load_dashboard_data()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    socket =
      socket
      |> assign(:loading, true)
      |> load_dashboard_data()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  # Data loading

  defp load_dashboard_data(socket) do
    hours = socket.assigns.time_range
    selected_source = socket.assigns.selected_source

    sources_to_check =
      if selected_source do
        [selected_source]
      else
        @sources
      end

    # Load health data for all sources in parallel
    health_results =
      sources_to_check
      |> Task.async_stream(
        fn source ->
          case Health.check(source, hours: hours) do
            {:ok, health} ->
              score = Health.score(health)
              degraded = Health.degraded_workers(health, threshold: 90.0)
              {source, {:ok, health, score, degraded}}

            {:error, reason} ->
              {source, {:error, reason}}
          end
        end,
        timeout: 10_000,
        max_concurrency: 4
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, _reason} -> {nil, {:error, :timeout}}
      end)
      |> Enum.reject(fn {source, _} -> is_nil(source) end)
      |> Map.new()

    # Load error analysis for sources
    error_results =
      sources_to_check
      |> Task.async_stream(
        fn source ->
          case Errors.analyze(source, hours: hours, limit: 10) do
            {:ok, analysis} ->
              summary = Errors.summary(analysis)
              recommendations = Errors.recommendations(analysis)
              {source, {:ok, analysis, summary, recommendations}}

            {:error, reason} ->
              {source, {:error, reason}}
          end
        end,
        timeout: 10_000,
        max_concurrency: 4
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, _reason} -> {nil, {:error, :timeout}}
      end)
      |> Enum.reject(fn {source, _} -> is_nil(source) end)
      |> Map.new()

    # Aggregate metrics
    {overall_score, meeting_slo_count, at_risk_count, total_executions, total_failures} =
      calculate_aggregates(health_results)

    # Collect all action items (degraded workers across sources)
    action_items = collect_action_items(health_results)

    # Collect top errors with recommendations
    top_errors = collect_top_errors(error_results)

    socket
    |> assign(:health_results, health_results)
    |> assign(:error_results, error_results)
    |> assign(:overall_score, overall_score)
    |> assign(:meeting_slo_count, meeting_slo_count)
    |> assign(:at_risk_count, at_risk_count)
    |> assign(:total_executions, total_executions)
    |> assign(:total_failures, total_failures)
    |> assign(:action_items, action_items)
    |> assign(:top_errors, top_errors)
  end

  defp calculate_aggregates(health_results) do
    valid_health =
      health_results
      |> Enum.filter(fn {_source, result} ->
        match?({:ok, _, _, _}, result)
      end)
      |> Enum.map(fn {_source, {:ok, health, score, _}} ->
        {health, score}
      end)

    if Enum.empty?(valid_health) do
      {0.0, 0, 0, 0, 0}
    else
      scores = Enum.map(valid_health, fn {_, score} -> score end)
      overall_score = Enum.sum(scores) / length(scores)

      meeting_slo_count =
        valid_health
        |> Enum.count(fn {health, _} -> health.meeting_slos end)

      at_risk_count = length(valid_health) - meeting_slo_count

      total_executions =
        valid_health
        |> Enum.map(fn {health, _} -> health.total_executions end)
        |> Enum.sum()

      total_failures =
        valid_health
        |> Enum.map(fn {health, _} -> health.failed end)
        |> Enum.sum()

      {Float.round(overall_score, 1), meeting_slo_count, at_risk_count, total_executions,
       total_failures}
    end
  end

  defp collect_action_items(health_results) do
    health_results
    |> Enum.flat_map(fn
      {source, {:ok, _health, _score, degraded}} ->
        Enum.map(degraded, fn {worker, rate} ->
          %{source: source, worker: worker, success_rate: Float.round(rate, 1)}
        end)

      _ ->
        []
    end)
    |> Enum.sort_by(fn item -> item.success_rate end)
    |> Enum.take(10)
  end

  defp collect_top_errors(error_results) do
    error_results
    |> Enum.flat_map(fn
      {source, {:ok, analysis, _summary, recommendations}} ->
        analysis.category_distribution
        |> Enum.take(3)
        |> Enum.map(fn {category, count} ->
          %{
            source: source,
            category: category,
            count: count,
            recommendation: Map.get(recommendations, category, "Review error logs")
          }
        end)

      _ ->
        []
    end)
    |> Enum.sort_by(fn item -> -item.count end)
    |> Enum.take(10)
  end

  # Template

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 dark:bg-gray-900">
      <div class="max-w-7xl mx-auto px-4 py-6">
        <!-- Header -->
        <div class="flex flex-col md:flex-row md:items-center md:justify-between mb-6">
          <div>
            <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Scraper Monitoring</h1>
            <p class="text-sm text-gray-500 dark:text-gray-400 mt-1">
              Health, SLOs, and error analysis for all scrapers
            </p>
          </div>

          <div class="flex items-center gap-4 mt-4 md:mt-0">
            <!-- Source Filter -->
            <select
              phx-change="select_source"
              name="source"
              class="rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-800 dark:text-white text-sm"
            >
              <option value="all" selected={is_nil(@selected_source)}>All Sources</option>
              <%= for source <- @sources do %>
                <option value={source} selected={@selected_source == source}>
                  <%= format_source_name(source) %>
                </option>
              <% end %>
            </select>

            <!-- Time Range Filter -->
            <select
              phx-change="change_time_range"
              name="time_range"
              class="rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-800 dark:text-white text-sm"
            >
              <option value="1" selected={@time_range == 1}>Last 1 hour</option>
              <option value="6" selected={@time_range == 6}>Last 6 hours</option>
              <option value="24" selected={@time_range == 24}>Last 24 hours</option>
              <option value="48" selected={@time_range == 48}>Last 48 hours</option>
              <option value="168" selected={@time_range == 168}>Last 7 days</option>
            </select>

            <!-- Refresh Button -->
            <button
              phx-click="refresh"
              class="inline-flex items-center px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md text-sm font-medium text-gray-700 dark:text-gray-300 bg-white dark:bg-gray-800 hover:bg-gray-50 dark:hover:bg-gray-700"
            >
              <svg
                class={"h-4 w-4 mr-1.5 #{if @loading, do: "animate-spin"}"}
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                />
              </svg>
              Refresh
            </button>
          </div>
        </div>

        <%= if @loading do %>
          <div class="flex items-center justify-center py-12">
            <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
          </div>
        <% else %>
          <!-- Summary Cards -->
          <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
            <!-- Overall Health Score -->
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
              <div class="text-sm font-medium text-gray-500 dark:text-gray-400">Health Score</div>
              <div class={"text-3xl font-bold mt-1 #{health_score_color(@overall_score)}"}>
                <%= @overall_score %>%
              </div>
              <div class="text-xs text-gray-400 dark:text-gray-500 mt-1">
                Last <%= @time_range %> hours
              </div>
            </div>

            <!-- SLO Status -->
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
              <div class="text-sm font-medium text-gray-500 dark:text-gray-400">SLO Compliance</div>
              <div class="flex items-baseline gap-2 mt-1">
                <span class="text-3xl font-bold text-green-600 dark:text-green-400">
                  <%= @meeting_slo_count %>
                </span>
                <span class="text-gray-400">/</span>
                <span class={"text-xl font-semibold #{if @at_risk_count > 0, do: "text-red-600 dark:text-red-400", else: "text-gray-400"}"}>
                  <%= @at_risk_count %> at risk
                </span>
              </div>
            </div>

            <!-- Total Executions -->
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
              <div class="text-sm font-medium text-gray-500 dark:text-gray-400">
                Total Executions
              </div>
              <div class="text-3xl font-bold text-gray-900 dark:text-white mt-1">
                <%= format_number(@total_executions) %>
              </div>
            </div>

            <!-- Total Failures -->
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
              <div class="text-sm font-medium text-gray-500 dark:text-gray-400">Failures</div>
              <div class={"text-3xl font-bold mt-1 #{if @total_failures > 0, do: "text-red-600 dark:text-red-400", else: "text-green-600 dark:text-green-400"}"}>
                <%= format_number(@total_failures) %>
              </div>
              <div class="text-xs text-gray-400 dark:text-gray-500 mt-1">
                <%= if @total_executions > 0 do %>
                  <%= Float.round(@total_failures / @total_executions * 100, 1) %>% error rate
                <% else %>
                  No data
                <% end %>
              </div>
            </div>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <!-- Sources Health Table -->
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow">
              <div class="px-4 py-3 border-b border-gray-200 dark:border-gray-700">
                <h2 class="text-lg font-medium text-gray-900 dark:text-white">Sources Health</h2>
              </div>
              <div class="overflow-x-auto">
                <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
                  <thead class="bg-gray-50 dark:bg-gray-900">
                    <tr>
                      <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                        Source
                      </th>
                      <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                        Success
                      </th>
                      <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                        P95
                      </th>
                      <th class="px-4 py-2 text-center text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                        SLO
                      </th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                    <%= for source <- @sources do %>
                      <% result = Map.get(@health_results, source) %>
                      <tr class="hover:bg-gray-50 dark:hover:bg-gray-700">
                        <td class="px-4 py-2 text-sm font-medium text-gray-900 dark:text-white">
                          <%= format_source_name(source) %>
                        </td>
                        <%= case result do %>
                          <% {:ok, health, _score, _degraded} -> %>
                            <td class={"px-4 py-2 text-sm text-right #{success_rate_color(health.success_rate)}"}>
                              <%= Float.round(health.success_rate, 1) %>%
                            </td>
                            <td class={"px-4 py-2 text-sm text-right #{p95_color(health.p95_duration)}"}>
                              <%= format_duration(health.p95_duration) %>
                            </td>
                            <td class="px-4 py-2 text-center">
                              <%= if health.meeting_slos do %>
                                <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200">
                                  OK
                                </span>
                              <% else %>
                                <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200">
                                  At Risk
                                </span>
                              <% end %>
                            </td>
                          <% {:error, :no_executions} -> %>
                            <td colspan="3" class="px-4 py-2 text-sm text-gray-400 text-center">
                              No data
                            </td>
                          <% {:error, _} -> %>
                            <td colspan="3" class="px-4 py-2 text-sm text-red-500 text-center">
                              Error loading
                            </td>
                          <% nil -> %>
                            <td colspan="3" class="px-4 py-2 text-sm text-gray-400 text-center">
                              --
                            </td>
                        <% end %>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>

            <!-- Top Errors & Recommendations -->
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow">
              <div class="px-4 py-3 border-b border-gray-200 dark:border-gray-700">
                <h2 class="text-lg font-medium text-gray-900 dark:text-white">
                  Top Errors & Recommendations
                </h2>
              </div>
              <div class="divide-y divide-gray-200 dark:divide-gray-700">
                <%= if Enum.empty?(@top_errors) do %>
                  <div class="px-4 py-8 text-center text-gray-500 dark:text-gray-400">
                    No errors in the selected time range
                  </div>
                <% else %>
                  <%= for error <- @top_errors do %>
                    <div class="px-4 py-3">
                      <div class="flex items-center justify-between">
                        <div class="flex items-center gap-2">
                          <span class={"inline-flex items-center px-2 py-0.5 rounded text-xs font-medium #{error_category_color(error.category)}"}>
                            <%= error.category %>
                          </span>
                          <span class="text-sm text-gray-500 dark:text-gray-400">
                            <%= format_source_name(error.source) %>
                          </span>
                        </div>
                        <span class="text-sm font-medium text-gray-900 dark:text-white">
                          <%= error.count %> errors
                        </span>
                      </div>
                      <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                        <%= error.recommendation %>
                      </p>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Action Items -->
          <%= if not Enum.empty?(@action_items) do %>
            <div class="mt-6 bg-white dark:bg-gray-800 rounded-lg shadow">
              <div class="px-4 py-3 border-b border-gray-200 dark:border-gray-700">
                <h2 class="text-lg font-medium text-gray-900 dark:text-white">
                  Action Items
                  <span class="ml-2 inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200">
                    <%= length(@action_items) %> degraded workers
                  </span>
                </h2>
              </div>
              <div class="overflow-x-auto">
                <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
                  <thead class="bg-gray-50 dark:bg-gray-900">
                    <tr>
                      <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                        Source
                      </th>
                      <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                        Worker
                      </th>
                      <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                        Success Rate
                      </th>
                      <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                        Status
                      </th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                    <%= for item <- @action_items do %>
                      <tr class="hover:bg-gray-50 dark:hover:bg-gray-700">
                        <td class="px-4 py-2 text-sm font-medium text-gray-900 dark:text-white">
                          <%= format_source_name(item.source) %>
                        </td>
                        <td class="px-4 py-2 text-sm text-gray-700 dark:text-gray-300">
                          <%= item.worker %>
                        </td>
                        <td class={"px-4 py-2 text-sm text-right #{success_rate_color(item.success_rate)}"}>
                          <%= item.success_rate %>%
                        </td>
                        <td class="px-4 py-2">
                          <%= cond do %>
                            <% item.success_rate < 50 -> %>
                              <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200">
                                Critical
                              </span>
                            <% item.success_rate < 80 -> %>
                              <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200">
                                Warning
                              </span>
                            <% true -> %>
                              <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200">
                                Degraded
                              </span>
                          <% end %>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper functions

  defp format_source_name(source) do
    source
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_number(num) when num >= 1000 do
    "#{Float.round(num / 1000, 1)}k"
  end

  defp format_number(num), do: to_string(num)

  defp format_duration(ms) when ms >= 1000 do
    "#{Float.round(ms / 1000, 1)}s"
  end

  defp format_duration(ms) do
    "#{round(ms)}ms"
  end

  defp health_score_color(score) when score >= 95, do: "text-green-600 dark:text-green-400"
  defp health_score_color(score) when score >= 80, do: "text-yellow-600 dark:text-yellow-400"
  defp health_score_color(_), do: "text-red-600 dark:text-red-400"

  defp success_rate_color(rate) when rate >= 95, do: "text-green-600 dark:text-green-400"
  defp success_rate_color(rate) when rate >= 80, do: "text-yellow-600 dark:text-yellow-400"
  defp success_rate_color(_), do: "text-red-600 dark:text-red-400"

  defp p95_color(ms) when ms <= 3000, do: "text-green-600 dark:text-green-400"
  defp p95_color(ms) when ms <= 5000, do: "text-yellow-600 dark:text-yellow-400"
  defp p95_color(_), do: "text-red-600 dark:text-red-400"

  defp error_category_color(category) do
    case category do
      "network_error" ->
        "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200"

      "validation_error" ->
        "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200"

      "parsing_error" ->
        "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200"

      "rate_limit_error" ->
        "bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200"

      "authentication_error" ->
        "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"

      "tmdb_error" ->
        "bg-pink-100 text-pink-800 dark:bg-pink-900 dark:text-pink-200"

      "geocoding_error" ->
        "bg-indigo-100 text-indigo-800 dark:bg-indigo-900 dark:text-indigo-200"

      "venue_error" ->
        "bg-teal-100 text-teal-800 dark:bg-teal-900 dark:text-teal-200"

      "performer_error" ->
        "bg-cyan-100 text-cyan-800 dark:bg-cyan-900 dark:text-cyan-200"

      _ ->
        "bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200"
    end
  end
end
