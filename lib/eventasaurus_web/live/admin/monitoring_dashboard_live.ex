defmodule EventasaurusWeb.Admin.MonitoringDashboardLive do
  @moduledoc """
  Unified monitoring dashboard for scraper health and error analysis.

  Phase 4 implementation of error categorization master plan (Issue #3055).
  Wraps the existing Monitoring.* modules (Health, Errors) into a web interface.

  Features:
  - Health overview with overall score
  - Z-score based relative performance (replaces arbitrary SLO thresholds)
  - Statistical outlier detection comparing sources to their peers
  - Error category breakdown with recommendations
  - Time range filtering
  - Action items for degraded workers
  - 7-day sparkline trends with trend indicators (Phase 4.1)

  Z-Score System (Issue #3135):
  - Compares each source's performance to the population mean
  - Success rate: z < -1.0 = warning, z < -1.5 = critical
  - Duration: z > 1.5 = warning, z > 2.0 = critical
  - Self-calibrating: thresholds adjust as overall performance improves

  Target: < 500ms load time using existing optimized queries.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Monitoring.Health
  alias EventasaurusDiscovery.Monitoring.Errors
  alias EventasaurusDiscovery.Monitoring.Scheduler
  alias EventasaurusDiscovery.Monitoring.Coverage
  alias EventasaurusWeb.Components.Sparkline

  @impl true
  def mount(_params, _session, socket) do
    # Dynamically discover sources from job execution data
    sources = discover_sources()

    socket =
      socket
      |> assign(:page_title, "Scraper Monitoring")
      |> assign(:time_range, 24)
      |> assign(:loading, true)
      |> assign(:sources, sources)
      |> assign(:health_results, %{})
      |> assign(:error_results, %{})
      |> assign(:trend_results, %{})
      |> assign(:scheduler_health, %{sources: [], total_alerts: 0})
      |> assign(:coverage_data, %{sources: [], total_alerts: 0})
      |> assign(:overall_score, 0.0)
      |> assign(:meeting_slo_count, 0)
      |> assign(:at_risk_count, 0)
      |> assign(:total_executions, 0)
      |> assign(:total_failures, 0)
      |> assign(:action_items, [])
      |> assign(:top_errors, [])
      # Z-score data for relative performance assessment
      |> assign(:zscore_data, nil)
      |> assign(:normal_count, 0)
      |> assign(:warning_count, 0)
      |> assign(:critical_count, 0)
      |> assign(:outliers, [])

    # Load data asynchronously to avoid blocking mount and exhausting connection pool
    send(self(), :load_initial_data)

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

  # Extract canonical source slug from worker module name
  # e.g., "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob" -> "cinema-city"
  # Uses centralized Source.worker_to_slug for consistent hyphenated slugs
  defp extract_source_from_worker(worker) when is_binary(worker) do
    alias EventasaurusDiscovery.Sources.Source
    Source.worker_to_slug(worker)
  end

  defp extract_source_from_worker(_), do: nil

  @impl true
  def handle_event("change_time_range", %{"time_range" => time_range}, socket) do
    time_range_hours =
      case Integer.parse(time_range) do
        {hours, _} when hours in [1, 6, 24, 48, 168] -> hours
        _ -> 24
      end

    # Use async pattern so loading state is visible to user
    send(self(), :refresh_data)

    {:noreply, socket |> assign(:time_range, time_range_hours) |> assign(:loading, true)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    # Use async pattern so loading state is visible to user
    send(self(), :refresh_data)
    {:noreply, assign(socket, :loading, true)}
  end

  def handle_event("navigate_to_source", %{"source" => source}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin/monitoring/sources/#{source}")}
  end

  @impl true
  def handle_info(:load_initial_data, socket) do
    socket =
      socket
      |> load_dashboard_data()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh_data, socket) do
    socket =
      socket
      |> load_dashboard_data()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  # Test helper - allows tests to wait for async loading to complete
  # by sending a ping and waiting for pong (messages are processed in order)
  @impl true
  def handle_info({:test_ping, pid}, socket) do
    send(pid, :test_pong)
    {:noreply, socket}
  end

  # Data loading

  # Max concurrency reduced to 2 to avoid exhausting the connection pool (replica pool is only 5 connections)
  # Running health + error + trend streams with 4 concurrent each would require 12+ connections
  @max_concurrency 2
  @task_timeout 15_000

  defp load_dashboard_data(socket) do
    hours = socket.assigns.time_range
    sources = socket.assigns.sources

    # Always check all sources
    sources_to_check = sources

    # Load health data for all sources with reduced concurrency
    # Using sequential streams (one at a time) to avoid connection pool exhaustion
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
        timeout: @task_timeout,
        max_concurrency: @max_concurrency,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, _reason} -> {nil, {:error, :timeout}}
      end)
      |> Enum.reject(fn {source, _} -> is_nil(source) end)
      |> Map.new()

    # Load error analysis for sources - runs AFTER health to avoid concurrent pool exhaustion
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
        timeout: @task_timeout,
        max_concurrency: @max_concurrency,
        on_timeout: :kill_task
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

    # Load scheduler health (SyncJob execution tracking) - needed for status indicators
    scheduler_health =
      case Scheduler.check(days: 7) do
        {:ok, data} -> data
        {:error, _} -> %{sources: [], total_alerts: 0}
      end

    # Load date coverage (event coverage for next 7 days) - needed for status indicators
    coverage_data =
      case Coverage.check(days: 7) do
        {:ok, data} -> data
        {:error, _} -> %{sources: [], total_alerts: 0}
      end

    # Load z-score data for relative performance assessment
    # Always use 7 days for z-score calculation to have stable baseline
    {zscore_data, normal_count, warning_count, critical_count, outliers} =
      case Health.compute_source_zscores(hours: 168) do
        {:ok, data} ->
          outlier_names =
            data.sources |> Enum.filter(&(&1.overall_status != :normal)) |> Enum.map(& &1.source)

          {data, data.normal_count, data.warning_count, data.critical_count, outlier_names}

        {:error, _} ->
          {nil, 0, 0, 0, []}
      end

    socket
    |> assign(:health_results, health_results)
    |> assign(:error_results, error_results)
    |> assign(:trend_results, trend_results)
    |> assign(:scheduler_health, scheduler_health)
    |> assign(:coverage_data, coverage_data)
    |> assign(:overall_score, overall_score)
    |> assign(:meeting_slo_count, meeting_slo_count)
    |> assign(:at_risk_count, at_risk_count)
    |> assign(:total_executions, total_executions)
    |> assign(:total_failures, total_failures)
    |> assign(:action_items, action_items)
    |> assign(:top_errors, top_errors)
    |> assign(:zscore_data, zscore_data)
    |> assign(:normal_count, normal_count)
    |> assign(:warning_count, warning_count)
    |> assign(:critical_count, critical_count)
    |> assign(:outliers, outliers)
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
            <!-- Time Range Filter -->
            <form phx-change="change_time_range">
              <select
                name="time_range"
                class="rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-800 dark:text-white text-sm"
              >
                <option value="1" selected={@time_range == 1}>Last 1 hour</option>
                <option value="6" selected={@time_range == 6}>Last 6 hours</option>
                <option value="24" selected={@time_range == 24}>Last 24 hours</option>
                <option value="48" selected={@time_range == 48}>Last 48 hours</option>
                <option value="168" selected={@time_range == 168}>Last 7 days</option>
              </select>
            </form>

            <!-- Refresh Button -->
            <button
              type="button"
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
          <!-- Summary Cards (4 cards - Health Score, SLO Compliance, Executions, Failures) -->
          <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
            <!-- Health Score -->
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
              <div class="text-sm font-medium text-gray-500 dark:text-gray-400">Health Score</div>
              <div class={"text-3xl font-bold mt-1 #{health_score_color(@overall_score)}"}>
                <%= @overall_score %>%
              </div>
            </div>

            <!-- Relative Performance (Z-Score based) -->
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
              <div class="text-sm font-medium text-gray-500 dark:text-gray-400" title="Statistical outliers vs population mean">
                Relative Performance
              </div>
              <div class="flex items-baseline gap-2 mt-1">
                <span class="text-3xl font-bold text-green-600 dark:text-green-400">
                  <%= @normal_count %>
                </span>
                <span class="text-sm text-gray-400">normal</span>
                <%= if @warning_count > 0 do %>
                  <span class="text-xl font-semibold text-yellow-600 dark:text-yellow-400">
                    <%= @warning_count %>
                  </span>
                  <span class="text-sm text-gray-400">warn</span>
                <% end %>
                <%= if @critical_count > 0 do %>
                  <span class="text-xl font-semibold text-red-600 dark:text-red-400">
                    <%= @critical_count %>
                  </span>
                  <span class="text-sm text-gray-400">outlier</span>
                <% end %>
              </div>
              <%= if @zscore_data do %>
                <div class="text-xs text-gray-400 dark:text-gray-500 mt-1" title="Population baseline">
                  μ: <%= Float.round(@zscore_data.success_mean, 1) %>% success, <%= Float.round(@zscore_data.duration_mean, 1) %>s avg
                </div>
              <% end %>
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
                      <th class="px-4 py-2 text-center text-xs font-medium text-gray-500 dark:text-gray-400 uppercase" title="Scheduler Health">
                        Sched
                      </th>
                      <th class="px-4 py-2 text-center text-xs font-medium text-gray-500 dark:text-gray-400 uppercase" title="Date Coverage">
                        Cov
                      </th>
                      <th class="px-4 py-2 text-center text-xs font-medium text-gray-500 dark:text-gray-400 uppercase" title="Z-Score relative to peers">
                        Z
                      </th>
                      <th class="w-8"></th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                    <%= for source <- @sources do %>
                      <% result = Map.get(@health_results, source) %>
                      <% trend = Map.get(@trend_results, source) %>
                      <% scheduler_status = get_scheduler_status(source, @scheduler_health) %>
                      <% coverage_status = get_coverage_status(source, @coverage_data) %>
                      <% zscore_status = get_zscore_status(source, @zscore_data) %>
                      <tr
                        phx-click="navigate_to_source"
                        phx-value-source={source}
                        class="hover:bg-gray-50 dark:hover:bg-gray-700 cursor-pointer transition-colors group"
                      >
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
                              <%= Phoenix.HTML.raw(render_status_indicator(scheduler_status)) %>
                            </td>
                            <td class="px-4 py-2 text-center">
                              <%= Phoenix.HTML.raw(render_status_indicator(coverage_status)) %>
                            </td>
                            <td class="px-4 py-2 text-center">
                              <%= Phoenix.HTML.raw(render_zscore_indicator(zscore_status)) %>
                            </td>
                          <% {:error, :no_executions} -> %>
                            <td colspan="2" class="px-4 py-2 text-sm text-gray-400 text-center">
                              No data
                            </td>
                            <td class="px-4 py-2 text-center">
                              <%= Phoenix.HTML.raw(render_status_indicator(scheduler_status)) %>
                            </td>
                            <td class="px-4 py-2 text-center">
                              <%= Phoenix.HTML.raw(render_status_indicator(coverage_status)) %>
                            </td>
                            <td class="px-4 py-2 text-center">
                              <%= Phoenix.HTML.raw(render_zscore_indicator(zscore_status)) %>
                            </td>
                          <% {:error, _} -> %>
                            <td colspan="2" class="px-4 py-2 text-sm text-red-500 text-center">
                              Error
                            </td>
                            <td class="px-4 py-2 text-center">
                              <%= Phoenix.HTML.raw(render_status_indicator(scheduler_status)) %>
                            </td>
                            <td class="px-4 py-2 text-center">
                              <%= Phoenix.HTML.raw(render_status_indicator(coverage_status)) %>
                            </td>
                            <td class="px-4 py-2 text-center">
                              <%= Phoenix.HTML.raw(render_zscore_indicator(zscore_status)) %>
                            </td>
                          <% nil -> %>
                            <td colspan="2" class="px-4 py-2 text-sm text-gray-400 text-center">
                              --
                            </td>
                            <td class="px-4 py-2 text-center">
                              <%= Phoenix.HTML.raw(render_status_indicator(scheduler_status)) %>
                            </td>
                            <td class="px-4 py-2 text-center">
                              <%= Phoenix.HTML.raw(render_status_indicator(coverage_status)) %>
                            </td>
                            <td class="px-4 py-2 text-center">
                              <%= Phoenix.HTML.raw(render_zscore_indicator(zscore_status)) %>
                            </td>
                        <% end %>
                        <td class="px-2 py-2 text-gray-400 group-hover:text-gray-600 dark:group-hover:text-gray-300">
                          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
                          </svg>
                        </td>
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

          <!-- Action Items Summary (condensed) -->
          <%= if not Enum.empty?(@action_items) do %>
            <% critical_count = Enum.count(@action_items, &(&1.success_rate < 50)) %>
            <% warning_count = Enum.count(@action_items, &(&1.success_rate < 80 and &1.success_rate >= 50)) %>
            <% worst_item = Enum.min_by(@action_items, & &1.success_rate) %>
            <div class="mt-6 bg-yellow-50 dark:bg-yellow-900/20 rounded-lg shadow px-4 py-3">
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <span class="text-yellow-600 dark:text-yellow-400">⚠</span>
                  <span class="text-sm font-medium text-yellow-800 dark:text-yellow-200">
                    <%= length(@action_items) %> degraded workers
                  </span>
                  <%= if critical_count > 0 do %>
                    <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200">
                      <%= critical_count %> critical
                    </span>
                  <% end %>
                  <%= if warning_count > 0 do %>
                    <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200">
                      <%= warning_count %> warning
                    </span>
                  <% end %>
                </div>
                <span class="text-xs text-yellow-700 dark:text-yellow-300">
                  Worst: <%= format_source_name(worst_item.source) %> / <%= worst_item.worker %> (<%= worst_item.success_rate %>%)
                </span>
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

  # Get scheduler status for a source from scheduler_health data
  # Returns {:ok, status} | :not_monitored
  defp get_scheduler_status(source, scheduler_health) do
    case Enum.find(scheduler_health.sources, &(&1.source == source)) do
      nil ->
        :not_monitored

      source_data ->
        cond do
          source_data.has_recent_execution && Enum.empty?(source_data.alerts) ->
            {:ok, :healthy}

          source_data.has_recent_execution ->
            {:ok, :warning}

          true ->
            {:ok, :critical}
        end
    end
  end

  # Get coverage status for a source from coverage_data
  # Returns {:ok, status} | :not_monitored
  defp get_coverage_status(source, coverage_data) do
    case Enum.find(coverage_data.sources, &(&1.source == source)) do
      nil ->
        :not_monitored

      source_data ->
        critical_alerts =
          Enum.count(source_data.alerts, fn a ->
            a.type in [:missing_near, :critical_gaps, :source_not_found]
          end)

        cond do
          Enum.empty?(source_data.alerts) ->
            {:ok, :healthy}

          critical_alerts > 0 ->
            {:ok, :critical}

          true ->
            {:ok, :warning}
        end
    end
  end

  # Get z-score status for a source from zscore_data
  # Returns {:ok, status, zscore_info} | :not_available
  defp get_zscore_status(_source, nil), do: :not_available

  defp get_zscore_status(source, zscore_data) do
    case Enum.find(zscore_data.sources, &(&1.source == source)) do
      nil ->
        :not_available

      source_data ->
        {:ok, source_data.overall_status, source_data}
    end
  end

  # Render z-score indicator with tooltip showing details
  defp render_zscore_indicator(:not_available) do
    "<span class=\"text-gray-400 dark:text-gray-500\" title=\"No z-score data\">-</span>"
  end

  defp render_zscore_indicator({:ok, :normal, _data}) do
    "<span class=\"text-green-500 dark:text-green-400\" title=\"Normal (within expected range)\">✓</span>"
  end

  defp render_zscore_indicator({:ok, :warning, data}) do
    tooltip = zscore_tooltip(data)
    "<span class=\"text-yellow-500 dark:text-yellow-400\" title=\"#{tooltip}\">⚠</span>"
  end

  defp render_zscore_indicator({:ok, :critical, data}) do
    tooltip = zscore_tooltip(data)
    "<span class=\"text-red-500 dark:text-red-400\" title=\"#{tooltip}\">✗</span>"
  end

  # Build tooltip text showing z-score details
  defp zscore_tooltip(data) do
    parts = []

    parts =
      if data.success_status != :normal do
        z_val = Float.round(data.success_zscore, 2)
        parts ++ ["Success z=#{z_val} (#{data.success_status})"]
      else
        parts
      end

    parts =
      if data.duration_status != :normal do
        z_val = Float.round(data.duration_zscore, 2)
        parts ++ ["Duration z=#{z_val} (#{data.duration_status})"]
      else
        parts
      end

    if Enum.empty?(parts) do
      "Statistical outlier"
    else
      Enum.join(parts, ", ")
    end
  end

  # Render compact status indicator (✓/⚠/✗/-)
  defp render_status_indicator(:not_monitored) do
    ~s(<span class="text-gray-400 dark:text-gray-500" title="Not monitored">-</span>)
  end

  defp render_status_indicator({:ok, :healthy}) do
    ~s(<span class="text-green-500 dark:text-green-400" title="Healthy">✓</span>)
  end

  defp render_status_indicator({:ok, :warning}) do
    ~s(<span class="text-yellow-500 dark:text-yellow-400" title="Warning">⚠</span>)
  end

  defp render_status_indicator({:ok, :critical}) do
    ~s(<span class="text-red-500 dark:text-red-400" title="Critical">✗</span>)
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
end
