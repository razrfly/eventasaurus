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
  - 7-day sparkline trends with trend indicators (Phase 4.1)

  Target: < 500ms load time using existing optimized queries.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Monitoring.Health
  alias EventasaurusDiscovery.Monitoring.Errors
  alias EventasaurusDiscovery.Monitoring.Scheduler
  alias EventasaurusDiscovery.Monitoring.Coverage
  alias EventasaurusDiscovery.Monitoring.Chain
  alias EventasaurusWeb.Components.Sparkline

  @impl true
  def mount(_params, _session, socket) do
    # Dynamically discover sources from job execution data
    sources = discover_sources()

    socket =
      socket
      |> assign(:page_title, "Scraper Monitoring")
      |> assign(:time_range, 24)
      |> assign(:selected_source, nil)
      |> assign(:loading, true)
      |> assign(:sources, sources)
      |> load_dashboard_data()
      |> assign(:loading, false)

    {:ok, socket}
  end

  # Discover sources dynamically from worker names in job execution summaries
  defp discover_sources do
    import Ecto.Query

    query =
      from(j in EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary,
        where: j.attempted_at > ago(7, "day"),
        select: j.worker,
        distinct: true
      )

    EventasaurusApp.Repo.all(query)
    |> Enum.map(&extract_source_from_worker/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Extract source name from worker module name
  # e.g., "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob" -> "cinema_city"
  defp extract_source_from_worker(worker) when is_binary(worker) do
    case Regex.run(~r/Sources\.(\w+)\.Jobs/, worker) do
      [_, source] -> Macro.underscore(source)
      _ -> nil
    end
  end

  defp extract_source_from_worker(_), do: nil

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
    sources = socket.assigns.sources

    sources_to_check =
      if selected_source do
        [selected_source]
      else
        sources
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

    # Load 7-day trend data for sparklines (always 168 hours for consistency)
    {:ok, trend_results} = Health.trends_for_sources(sources_to_check, hours: 168)

    # Load 7-day health history for the chart (always 168 hours)
    {:ok, health_history} = Health.health_history(hours: 168)

    # Format chart data for Chart.js
    chart_data = format_chart_data(health_history)

    # Load baseline comparison (current vs 7 days ago)
    {:ok, baseline_comparison} = Health.baseline_comparison(hours: hours, sources: sources_to_check)

    # Load scheduler health (SyncJob execution tracking)
    {:ok, scheduler_health} = Scheduler.check(days: 7)

    # Load date coverage (event coverage for next 7 days)
    {:ok, coverage_data} = Coverage.check(days: 7)

    # Load recent job chains for chain-enabled sources (Phase 4.5)
    job_chains = load_job_chains(sources_to_check)

    socket
    |> assign(:health_results, health_results)
    |> assign(:error_results, error_results)
    |> assign(:trend_results, trend_results)
    |> assign(:health_history, health_history)
    |> assign(:chart_data, chart_data)
    |> assign(:baseline_comparison, baseline_comparison)
    |> assign(:scheduler_health, scheduler_health)
    |> assign(:coverage_data, coverage_data)
    |> assign(:job_chains, job_chains)
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

  # Load recent job chains for sources that support chain analysis (Phase 4.5)
  defp load_job_chains(sources) do
    # Only load chains for sources known to have hierarchical job structures
    chain_sources = ["cinema_city", "repertuary"]

    sources
    |> Enum.filter(&(&1 in chain_sources))
    |> Enum.map(fn source ->
      case Chain.recent_chains(source, limit: 3) do
        {:ok, chains} ->
          chains_with_stats =
            Enum.map(chains, fn chain ->
              stats = Chain.statistics(chain)
              %{chain: chain, stats: stats, source: source}
            end)

          {source, chains_with_stats}

        {:error, _} ->
          {source, []}
      end
    end)
    |> Map.new()
  end

  # Template

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen">
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
          <!-- Health Trend Chart -->
          <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4 mb-6">
            <div class="flex items-center justify-between mb-4">
              <div>
                <h2 class="text-lg font-medium text-gray-900 dark:text-white">Health Score Trend</h2>
                <p class="text-sm text-gray-500 dark:text-gray-400">7-day performance vs SLO target (95%)</p>
              </div>
              <div class="flex items-center gap-4">
                <div class="flex items-center gap-2">
                  <div class="w-3 h-3 bg-blue-500 rounded-full"></div>
                  <span class="text-sm text-gray-600 dark:text-gray-400">Health Score</span>
                </div>
                <div class="flex items-center gap-2">
                  <div class="w-3 h-0.5 bg-red-500 border-dashed border-t-2 border-red-500"></div>
                  <span class="text-sm text-gray-600 dark:text-gray-400">SLO Target</span>
                </div>
                <div class={"text-2xl font-bold #{health_score_color(@overall_score)}"}>
                  <%= @overall_score %>%
                </div>
              </div>
            </div>
            <div class="h-64">
              <canvas
                id="health-trend-chart"
                phx-hook="HealthTrendChart"
                data-chart-data={Jason.encode!(@chart_data)}
              ></canvas>
            </div>
          </div>

          <!-- Summary Cards -->
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">

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
                      <th class="px-4 py-2 text-center text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                        7d Trend
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
                      <% trend = Map.get(@trend_results, source) %>
                      <tr class="hover:bg-gray-50 dark:hover:bg-gray-700">
                        <td class="px-4 py-2 text-sm font-medium text-gray-900 dark:text-white">
                          <%= format_source_name(source) %>
                        </td>
                        <td class="px-4 py-2 text-center">
                          <div class="flex items-center justify-center gap-1">
                            <%= if trend do %>
                              <%= Phoenix.HTML.raw(Sparkline.render(trend.data_points)) %>
                              <%= Phoenix.HTML.raw(Sparkline.trend_arrow(trend.trend_direction)) %>
                            <% else %>
                              <span class="text-gray-400 text-xs">--</span>
                            <% end %>
                          </div>
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

          <!-- Baseline Comparison (Phase 4.3) -->
          <div class="mt-6 bg-white dark:bg-gray-800 rounded-lg shadow">
            <div class="px-4 py-3 border-b border-gray-200 dark:border-gray-700">
              <h2 class="text-lg font-medium text-gray-900 dark:text-white">
                Baseline Comparison
                <span class="text-sm font-normal text-gray-500 dark:text-gray-400 ml-2">
                  vs <%= @baseline_comparison.baseline_offset_days %> days ago
                </span>
              </h2>
              <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">
                Comparing <%= format_time_range(@time_range) %> performance against baseline
              </p>
            </div>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
                <thead class="bg-gray-50 dark:bg-gray-900">
                  <tr>
                    <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                      Source
                    </th>
                    <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                      Current
                    </th>
                    <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                      Baseline
                    </th>
                    <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                      Change
                    </th>
                    <th class="px-4 py-2 text-center text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                      Status
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                  <%= for comp <- @baseline_comparison.comparisons do %>
                    <tr class="hover:bg-gray-50 dark:hover:bg-gray-700">
                      <td class="px-4 py-2 text-sm font-medium text-gray-900 dark:text-white">
                        <%= format_source_name(comp.source) %>
                      </td>
                      <td class="px-4 py-2 text-sm text-right">
                        <%= if comp.current.success_rate do %>
                          <span class={success_rate_color(comp.current.success_rate)}>
                            <%= comp.current.success_rate %>%
                          </span>
                          <span class="text-gray-400 text-xs ml-1">
                            (<%= comp.current.total %>)
                          </span>
                        <% else %>
                          <span class="text-gray-400">--</span>
                        <% end %>
                      </td>
                      <td class="px-4 py-2 text-sm text-right">
                        <%= if comp.baseline.success_rate do %>
                          <span class="text-gray-600 dark:text-gray-400">
                            <%= comp.baseline.success_rate %>%
                          </span>
                          <span class="text-gray-400 text-xs ml-1">
                            (<%= comp.baseline.total %>)
                          </span>
                        <% else %>
                          <span class="text-gray-400">--</span>
                        <% end %>
                      </td>
                      <td class="px-4 py-2 text-sm text-right">
                        <%= if comp.changes.success_rate do %>
                          <span class={change_color(comp.changes.success_rate)}>
                            <%= format_change(comp.changes.success_rate) %>
                          </span>
                        <% else %>
                          <span class="text-gray-400">--</span>
                        <% end %>
                      </td>
                      <td class="px-4 py-2 text-center">
                        <%= render_comparison_status(comp.status) %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>

          <!-- Scheduler Health (Phase 4.4) -->
          <div class="mt-6 bg-white dark:bg-gray-800 rounded-lg shadow">
            <div class="px-4 py-3 border-b border-gray-200 dark:border-gray-700">
              <div class="flex items-center justify-between">
                <div>
                  <h2 class="text-lg font-medium text-gray-900 dark:text-white">
                    Scheduler Health
                  </h2>
                  <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">
                    SyncJob execution status for the last 7 days
                  </p>
                </div>
                <%= if @scheduler_health.total_alerts > 0 do %>
                  <span class="inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200">
                    <%= @scheduler_health.total_alerts %> alerts
                  </span>
                <% else %>
                  <span class="inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200">
                    All OK
                  </span>
                <% end %>
              </div>
            </div>
            <div class="p-4">
              <%= for source <- @scheduler_health.sources do %>
                <div class="mb-4 last:mb-0">
                  <div class="flex items-center justify-between mb-2">
                    <span class="text-sm font-medium text-gray-900 dark:text-white">
                      <%= source.display_name %>
                    </span>
                    <span class="text-xs text-gray-500 dark:text-gray-400">
                      <%= source.successful %>/<%= source.total_executions %> successful
                      (<%= Float.round(source.success_rate, 1) %>%)
                    </span>
                  </div>
                  <!-- Day-by-day grid -->
                  <div class="grid grid-cols-7 gap-1">
                    <%= for day <- source.days do %>
                      <div
                        class={"rounded p-2 text-center #{scheduler_day_color(day.status)}"}
                        title={"#{day.date}: #{day.status}#{if day.jobs_spawned, do: ", #{day.jobs_spawned} jobs", else: ""}#{if day.error_message, do: " - #{day.error_message}", else: ""}"}
                      >
                        <div class="text-xs font-medium">
                          <%= Calendar.strftime(day.date, "%a") %>
                        </div>
                        <div class="text-lg">
                          <%= scheduler_status_icon(day.status) %>
                        </div>
                        <div class="text-xs opacity-75">
                          <%= Calendar.strftime(day.date, "%d") %>
                        </div>
                      </div>
                    <% end %>
                  </div>
                  <!-- Alerts for this source -->
                  <%= if not Enum.empty?(source.alerts) do %>
                    <div class="mt-2 space-y-1">
                      <%= for alert <- source.alerts do %>
                        <div class={"text-xs px-2 py-1 rounded #{scheduler_alert_color(alert.type)}"}>
                          <%= alert.message %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Date Coverage Heatmap (Phase 4.4) -->
          <div class="mt-6 bg-white dark:bg-gray-800 rounded-lg shadow">
            <div class="px-4 py-3 border-b border-gray-200 dark:border-gray-700">
              <div class="flex items-center justify-between">
                <div>
                  <h2 class="text-lg font-medium text-gray-900 dark:text-white">
                    Date Coverage
                  </h2>
                  <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">
                    Event coverage for the next 7 days
                  </p>
                </div>
                <%= if @coverage_data.total_alerts > 0 do %>
                  <span class="inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200">
                    <%= @coverage_data.total_alerts %> gaps
                  </span>
                <% else %>
                  <span class="inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200">
                    Full coverage
                  </span>
                <% end %>
              </div>
            </div>
            <div class="p-4">
              <%= for source <- @coverage_data.sources do %>
                <div class="mb-4 last:mb-0">
                  <div class="flex items-center justify-between mb-2">
                    <span class="text-sm font-medium text-gray-900 dark:text-white">
                      <%= source.display_name %>
                    </span>
                    <span class="text-xs text-gray-500 dark:text-gray-400">
                      <%= source.total_events %> events across <%= source.days_with_events %> days
                      (avg: <%= source.avg_events_per_day %>/day)
                    </span>
                  </div>
                  <!-- Day-by-day heatmap -->
                  <div class="grid grid-cols-7 gap-1">
                    <%= for day <- source.days do %>
                      <div
                        class={"rounded p-2 text-center #{coverage_day_color(day.status, day.coverage_pct)}"}
                        title={"#{day.date}: #{day.event_count} events (expected: #{day.expected}, #{day.coverage_pct}% coverage)"}
                      >
                        <div class="text-xs font-medium">
                          <%= day.day_name %>
                        </div>
                        <div class="text-lg font-bold">
                          <%= day.event_count %>
                        </div>
                        <div class="text-xs opacity-75">
                          <%= day.coverage_pct %>%
                        </div>
                      </div>
                    <% end %>
                  </div>
                  <!-- Alerts for this source -->
                  <%= if not Enum.empty?(source.alerts) do %>
                    <div class="mt-2 space-y-1">
                      <%= for alert <- source.alerts do %>
                        <div class={"text-xs px-2 py-1 rounded #{coverage_alert_color(alert.type)}"}>
                          <%= alert.message %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Job Chain Visualization (Phase 4.5) -->
          <%= if map_size(@job_chains) > 0 do %>
            <div class="mt-6 bg-white dark:bg-gray-800 rounded-lg shadow">
              <div class="px-4 py-3 border-b border-gray-200 dark:border-gray-700">
                <div class="flex items-center justify-between">
                  <div>
                    <h2 class="text-lg font-medium text-gray-900 dark:text-white">
                      Job Chains
                    </h2>
                    <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">
                      Recent execution chains with cascade failure detection
                    </p>
                  </div>
                </div>
              </div>
              <div class="p-4 space-y-6">
                <%= for {source, chains} <- @job_chains do %>
                  <%= if not Enum.empty?(chains) do %>
                    <div>
                      <h3 class="text-sm font-medium text-gray-900 dark:text-white mb-3">
                        <%= format_source_name(source) %>
                      </h3>
                      <div class="space-y-4">
                        <%= for chain_data <- chains do %>
                          <div class="border border-gray-200 dark:border-gray-700 rounded-lg overflow-hidden">
                            <!-- Chain Header -->
                            <div class="px-4 py-2 bg-gray-50 dark:bg-gray-900 flex items-center justify-between">
                              <div class="flex items-center gap-3">
                                <span class={"inline-flex items-center px-2 py-0.5 rounded text-xs font-medium #{chain_status_color(chain_data.stats)}"}>
                                  <%= chain_status_label(chain_data.stats) %>
                                </span>
                                <span class="text-sm text-gray-600 dark:text-gray-400">
                                  <%= format_chain_datetime(chain_data.chain.attempted_at) %>
                                </span>
                              </div>
                              <div class="flex items-center gap-4 text-xs text-gray-500 dark:text-gray-400">
                                <span>
                                  <span class="font-medium text-gray-700 dark:text-gray-300"><%= chain_data.stats.total %></span> jobs
                                </span>
                                <span class="text-green-600 dark:text-green-400">
                                  <span class="font-medium"><%= chain_data.stats.completed %></span> ✓
                                </span>
                                <%= if chain_data.stats.failed > 0 do %>
                                  <span class="text-red-600 dark:text-red-400">
                                    <span class="font-medium"><%= chain_data.stats.failed %></span> ✗
                                  </span>
                                <% end %>
                                <span class={"font-medium #{chain_success_rate_color(chain_data.stats.success_rate)}"}>
                                  <%= Float.round(chain_data.stats.success_rate, 1) %>%
                                </span>
                              </div>
                            </div>
                            <!-- Chain Tree -->
                            <div class="px-4 py-3">
                              <%= render_chain_tree(chain_data.chain, 0) %>
                            </div>
                            <!-- Cascade Failures -->
                            <%= if not Enum.empty?(chain_data.stats.cascade_failures) do %>
                              <div class="px-4 py-2 bg-red-50 dark:bg-red-900/20 border-t border-red-100 dark:border-red-900">
                                <div class="text-xs font-medium text-red-800 dark:text-red-200 mb-1">
                                  ⚠️ Cascade Failures Detected
                                </div>
                                <div class="space-y-1">
                                  <%= for cascade <- chain_data.stats.cascade_failures do %>
                                    <div class="text-xs text-red-700 dark:text-red-300">
                                      <span class="font-mono"><%= cascade.worker %></span>
                                      failed (<%= cascade.error_category || "unknown" %>)
                                      → blocked <span class="font-medium"><%= cascade.prevented_count %></span> downstream jobs
                                    </div>
                                  <% end %>
                                </div>
                              </div>
                            <% end %>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          <% end %>

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

  # Format health history data for Chart.js
  defp format_chart_data(health_history) do
    slo_target = health_history.slo_target

    # Create an array of SLO target values (same length as data points)
    slo_data = List.duplicate(slo_target, length(health_history.data_points))

    %{
      "labels" => health_history.labels,
      "datasets" => [
        %{
          "label" => "Health Score (%)",
          "data" => health_history.data_points,
          "borderColor" => "#3b82f6",
          "backgroundColor" => "rgba(59, 130, 246, 0.1)",
          "fill" => true,
          "tension" => 0.3,
          "pointRadius" => 0,
          "pointHoverRadius" => 4
        },
        %{
          "label" => "SLO Target (95%)",
          "data" => slo_data,
          "borderColor" => "#ef4444",
          "borderDash" => [5, 5],
          "borderWidth" => 2,
          "pointRadius" => 0,
          "fill" => false
        }
      ]
    }
  end

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

  # Baseline comparison helpers

  defp format_time_range(1), do: "last hour"
  defp format_time_range(6), do: "last 6 hours"
  defp format_time_range(24), do: "last 24 hours"
  defp format_time_range(48), do: "last 48 hours"
  defp format_time_range(168), do: "last 7 days"
  defp format_time_range(hours), do: "last #{hours} hours"

  defp change_color(change) when change > 2.0, do: "text-green-600 dark:text-green-400"
  defp change_color(change) when change > 0, do: "text-green-500 dark:text-green-500"
  defp change_color(change) when change > -2.0, do: "text-gray-600 dark:text-gray-400"
  defp change_color(change) when change > -5.0, do: "text-yellow-600 dark:text-yellow-400"
  defp change_color(_), do: "text-red-600 dark:text-red-400"

  defp format_change(change) when change > 0, do: "+#{change}%"
  defp format_change(change), do: "#{change}%"

  defp render_comparison_status(:ok) do
    Phoenix.HTML.raw("""
    <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200">
      OK
    </span>
    """)
  end

  defp render_comparison_status(:warning) do
    Phoenix.HTML.raw("""
    <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200">
      Warning
    </span>
    """)
  end

  defp render_comparison_status(:alert) do
    Phoenix.HTML.raw("""
    <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200">
      Alert
    </span>
    """)
  end

  defp render_comparison_status(:no_data) do
    Phoenix.HTML.raw("""
    <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200">
      No Data
    </span>
    """)
  end

  defp render_comparison_status(:no_baseline) do
    Phoenix.HTML.raw("""
    <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200">
      No Baseline
    </span>
    """)
  end

  defp render_comparison_status(:no_current) do
    Phoenix.HTML.raw("""
    <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200">
      No Current
    </span>
    """)
  end

  defp render_comparison_status(_) do
    Phoenix.HTML.raw("""
    <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200">
      --
    </span>
    """)
  end

  # Scheduler Health helpers (Phase 4.4)

  defp scheduler_day_color(:ok), do: "bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-200"
  defp scheduler_day_color(:failure), do: "bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-200"
  defp scheduler_day_color(:missing), do: "bg-gray-100 dark:bg-gray-700 text-gray-500 dark:text-gray-400"
  defp scheduler_day_color(_), do: "bg-gray-100 dark:bg-gray-700 text-gray-500 dark:text-gray-400"

  defp scheduler_status_icon(:ok), do: "✓"
  defp scheduler_status_icon(:failure), do: "✗"
  defp scheduler_status_icon(:missing), do: "−"
  defp scheduler_status_icon(_), do: "?"

  defp scheduler_alert_color(:missing), do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200"
  defp scheduler_alert_color(:failure), do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"
  defp scheduler_alert_color(:stale), do: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200"
  defp scheduler_alert_color(:no_executions), do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"
  defp scheduler_alert_color(_), do: "bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200"

  # Date Coverage helpers (Phase 4.4)

  defp coverage_day_color(:ok, pct) when pct >= 100, do: "bg-green-200 dark:bg-green-800 text-green-900 dark:text-green-100"
  defp coverage_day_color(:ok, _pct), do: "bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-200"
  defp coverage_day_color(:fair, _pct), do: "bg-yellow-100 dark:bg-yellow-900 text-yellow-800 dark:text-yellow-200"
  defp coverage_day_color(:low, _pct), do: "bg-orange-100 dark:bg-orange-900 text-orange-800 dark:text-orange-200"
  defp coverage_day_color(:missing, _pct), do: "bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-200"
  defp coverage_day_color(_, _), do: "bg-gray-100 dark:bg-gray-700 text-gray-500 dark:text-gray-400"

  defp coverage_alert_color(:missing_near), do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"
  defp coverage_alert_color(:missing_far), do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200"
  defp coverage_alert_color(:low_near), do: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200"
  defp coverage_alert_color(:critical_gaps), do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"
  defp coverage_alert_color(:source_not_found), do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"
  defp coverage_alert_color(_), do: "bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200"

  # Job Chain helpers (Phase 4.5)

  defp chain_status_color(%{failed: 0}), do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"
  defp chain_status_color(%{success_rate: rate}) when rate >= 90, do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"
  defp chain_status_color(%{success_rate: rate}) when rate >= 70, do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200"
  defp chain_status_color(_), do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"

  defp chain_status_label(%{failed: 0}), do: "Success"
  defp chain_status_label(%{success_rate: rate}) when rate >= 90, do: "Success"
  defp chain_status_label(%{success_rate: rate}) when rate >= 70, do: "Partial"
  defp chain_status_label(_), do: "Failed"

  defp chain_success_rate_color(rate) when rate >= 95, do: "text-green-600 dark:text-green-400"
  defp chain_success_rate_color(rate) when rate >= 80, do: "text-yellow-600 dark:text-yellow-400"
  defp chain_success_rate_color(_), do: "text-red-600 dark:text-red-400"

  defp format_chain_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %H:%M")
  end

  # Render job chain tree recursively
  defp render_chain_tree(node, depth) do
    worker_name = extract_worker_name(node.worker)
    status_icon = chain_node_icon(node.state)
    status_color = chain_node_color(node.state)
    indent = depth * 20

    has_children = not Enum.empty?(node.children)
    children_count = length(node.children)

    Phoenix.HTML.raw("""
    <div class="font-mono text-xs">
      <div class="flex items-center gap-2 py-0.5" style="padding-left: #{indent}px">
        #{if depth > 0 do
          "<span class=\"text-gray-400 dark:text-gray-600\">├─→</span>"
        else
          ""
        end}
        <span class="#{status_color}">#{status_icon}</span>
        <span class="text-gray-700 dark:text-gray-300">#{worker_name}</span>
        #{if has_children do
          "<span class=\"text-gray-400 dark:text-gray-500\">(#{children_count})</span>"
        else
          ""
        end}
        #{render_chain_node_details(node)}
      </div>
      #{render_children_trees(node.children, depth + 1)}
    </div>
    """)
  end

  defp render_children_trees(children, depth) do
    children
    |> Enum.map(fn child -> render_chain_tree(child, depth) end)
    |> Enum.map(&Phoenix.HTML.safe_to_string/1)
    |> Enum.join("")
  end

  defp render_chain_node_details(node) do
    details = []

    # Add duration if available
    details =
      case get_in(node.results, ["duration_ms"]) || node[:duration_ms] do
        nil -> details
        ms when is_number(ms) -> details ++ ["#{ms}ms"]
        _ -> details
      end

    # Add error category if failed
    details =
      if node.state in ["discarded", "cancelled"] do
        case get_in(node.results, ["error_category"]) do
          nil ->
            details

          cat ->
            # Escape error category to prevent XSS
            escaped_cat = Phoenix.HTML.html_escape(cat) |> Phoenix.HTML.safe_to_string()
            details ++ ["<span class=\"text-red-500\">#{escaped_cat}</span>"]
        end
      else
        details
      end

    if Enum.empty?(details) do
      ""
    else
      "<span class=\"text-gray-400 dark:text-gray-500 ml-2\">#{Enum.join(details, " · ")}</span>"
    end
  end

  defp extract_worker_name(worker) when is_binary(worker) do
    worker
    |> String.split(".")
    |> List.last()
  end

  defp extract_worker_name(_), do: "Unknown"

  defp chain_node_icon("completed"), do: "✓"
  defp chain_node_icon("discarded"), do: "✗"
  defp chain_node_icon("cancelled"), do: "⊘"
  defp chain_node_icon("executing"), do: "◐"
  defp chain_node_icon("available"), do: "○"
  defp chain_node_icon("scheduled"), do: "◔"
  defp chain_node_icon(_), do: "?"

  defp chain_node_color("completed"), do: "text-green-600 dark:text-green-400"
  defp chain_node_color("discarded"), do: "text-red-600 dark:text-red-400"
  defp chain_node_color("cancelled"), do: "text-orange-600 dark:text-orange-400"
  defp chain_node_color("executing"), do: "text-blue-600 dark:text-blue-400"
  defp chain_node_color(_), do: "text-gray-500 dark:text-gray-400"
end
