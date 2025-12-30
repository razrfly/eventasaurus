defmodule EventasaurusWeb.Admin.SourceDetailLive do
  @moduledoc """
  Source-specific detail view for monitoring dashboard.

  Phase 5.2-5.3 of Issue #3071: Progressive disclosure with tabbed interface.
  Provides detailed view of a specific source's health, scheduler, coverage, and job history.

  Features:
  - Overview tab: Health trend, baseline comparison, error breakdown
  - Scheduler tab: Day-by-day execution grid (Phase 5.4)
  - Coverage tab: Date coverage heatmap (Phase 5.5)
  - Job History tab: Recent sync runs with child jobs (Phase 5.6)
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Monitoring.Health
  alias EventasaurusDiscovery.Monitoring.Errors
  alias EventasaurusDiscovery.Monitoring.Scheduler
  alias EventasaurusDiscovery.Monitoring.Coverage
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary
  alias EventasaurusApp.Repo
  alias EventasaurusWeb.Components.Sparkline
  import Ecto.Query

  # Source configuration with display names
  @source_config %{
    "cinema_city" => %{display_name: "Cinema City", slug: "cinema-city"},
    "repertuary" => %{display_name: "Repertuary", slug: "repertuary"},
    "kino_krakow" => %{display_name: "Kino Kraków", slug: "kino-krakow"},
    "karnet" => %{display_name: "Karnet", slug: "karnet"},
    "week_pl" => %{display_name: "Week.pl", slug: "week-pl"},
    "bandsintown" => %{display_name: "Bandsintown", slug: "bandsintown"},
    "resident_advisor" => %{display_name: "Resident Advisor", slug: "resident-advisor"},
    "sortiraparis" => %{display_name: "Sortir à Paris", slug: "sortiraparis"},
    "inquizition" => %{display_name: "Inquizition", slug: "inquizition"},
    "waw4free" => %{display_name: "Waw4Free", slug: "waw4free"}
  }

  @impl true
  def mount(%{"source_key" => source_key}, _session, socket) do
    source_config = Map.get(@source_config, source_key)

    if source_config do
      socket =
        socket
        |> assign(:source_key, source_key)
        |> assign(:source_config, source_config)
        |> assign(:page_title, "#{source_config.display_name} - Monitoring")
        |> assign(:active_tab, "overview")
        |> assign(:time_range, 24)
        |> assign(:loading, true)
        |> assign(:selected_execution, nil)
        |> assign(:expanded_sync_runs, MapSet.new())
        |> load_source_data()
        |> assign(:loading, false)

      {:ok, socket}
    else
      # Unknown source - redirect to main dashboard
      {:ok,
       socket
       |> put_flash(:error, "Unknown source: #{source_key}")
       |> push_navigate(to: ~p"/admin/monitoring")}
    end
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket)
      when tab in ~w(overview scheduler coverage history) do
    {:noreply, assign(socket, :active_tab, tab)}
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
      |> load_source_data()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    socket =
      socket
      |> assign(:loading, true)
      |> load_source_data()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_execution", %{"id" => id}, socket) do
    execution = Enum.find(socket.assigns.recent_executions, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, :selected_execution, execution)}
  end

  @impl true
  def handle_event("close_execution_detail", _params, socket) do
    {:noreply, assign(socket, :selected_execution, nil)}
  end

  @impl true
  def handle_event("toggle_sync_run", %{"id" => id}, socket) do
    sync_run_id = String.to_integer(id)
    expanded = socket.assigns.expanded_sync_runs

    new_expanded =
      if MapSet.member?(expanded, sync_run_id) do
        MapSet.delete(expanded, sync_run_id)
      else
        MapSet.put(expanded, sync_run_id)
      end

    {:noreply, assign(socket, :expanded_sync_runs, new_expanded)}
  end

  # Data loading

  defp load_source_data(socket) do
    source_key = socket.assigns.source_key
    hours = socket.assigns.time_range

    # Load health data for this source
    health_data = load_health_data(source_key, hours)
    error_analysis = load_error_analysis(source_key, hours)
    trend_data = load_trend_data(source_key)
    scheduler_health = load_scheduler_health(source_key)
    coverage_data = load_coverage_data(source_key)
    recent_executions = load_recent_executions(source_key)
    sync_runs = load_sync_runs(source_key)

    socket
    |> assign(:health_data, health_data)
    |> assign(:error_analysis, error_analysis)
    |> assign(:trend_data, trend_data)
    |> assign(:scheduler_health, scheduler_health)
    |> assign(:coverage_data, coverage_data)
    |> assign(:recent_executions, recent_executions)
    |> assign(:sync_runs, sync_runs)
  end

  defp load_health_data(source_key, hours) do
    case Health.check(source: source_key, hours: hours) do
      {:ok, health} -> health
      {:error, _} -> nil
    end
  end

  defp load_error_analysis(source_key, hours) do
    case Errors.analyze(source_key, hours: hours, limit: 50) do
      {:ok, analysis} ->
        # Add recommendations to the analysis for template access
        recommendations = Errors.recommendations(analysis)
        Map.put(analysis, :recommendations, recommendations)

      {:error, _} ->
        nil
    end
  end

  defp load_trend_data(source_key) do
    case Health.trend_data(source_key, hours: 168) do
      {:ok, trend} -> trend
      {:error, _} -> nil
    end
  end

  defp load_scheduler_health(source_key) do
    case Scheduler.check(source: source_key, days: 7) do
      {:ok, health} ->
        # Get the source-specific data
        Enum.find(health.sources, &(&1.source == source_key))

      {:error, _} ->
        nil
    end
  end

  defp load_coverage_data(source_key) do
    case Coverage.check(source: source_key, days: 7) do
      {:ok, coverage} ->
        # Get the source-specific data
        Enum.find(coverage.sources, &(&1.source == source_key))

      {:error, _} ->
        nil
    end
  end

  defp load_recent_executions(source_key) do
    # Build worker pattern for this source (e.g., "EventasaurusDiscovery.Sources.CinemaCity.%")
    source_module = source_key_to_module(source_key)
    worker_pattern = "%#{source_module}%"

    from_time = DateTime.add(DateTime.utc_now(), -7, :day)

    from(j in JobExecutionSummary,
      where: like(j.worker, ^worker_pattern),
      where: j.attempted_at >= ^from_time,
      order_by: [desc: j.attempted_at],
      limit: 20,
      select: %{
        id: j.id,
        job_id: j.job_id,
        worker: j.worker,
        state: j.state,
        attempted_at: j.attempted_at,
        completed_at: j.completed_at,
        duration_ms: j.duration_ms,
        error: j.error,
        results: j.results,
        args: j.args
      }
    )
    |> Repo.replica().all()
  end

  defp load_sync_runs(source_key) do
    # Load recent SyncJob runs with their child job statistics
    source_module = source_key_to_module(source_key)
    sync_worker_pattern = "%#{source_module}%SyncJob"
    child_worker_pattern = "%#{source_module}%"

    from_time = DateTime.add(DateTime.utc_now(), -7, :day)

    # Get recent SyncJobs
    sync_jobs =
      from(j in JobExecutionSummary,
        where: like(j.worker, ^sync_worker_pattern),
        where: j.attempted_at >= ^from_time,
        order_by: [desc: j.attempted_at],
        limit: 20,
        select: %{
          id: j.id,
          job_id: j.job_id,
          worker: j.worker,
          state: j.state,
          attempted_at: j.attempted_at,
          completed_at: j.completed_at,
          duration_ms: j.duration_ms,
          error: j.error,
          results: j.results,
          args: j.args
        }
      )
      |> Repo.replica().all()

    # For each SyncJob, find child jobs (non-SyncJob workers that started after it)
    Enum.map(sync_jobs, fn sync_job ->
      # Child jobs started within 1 hour after SyncJob
      window_end = DateTime.add(sync_job.attempted_at, 3600, :second)

      child_jobs =
        from(j in JobExecutionSummary,
          where: like(j.worker, ^child_worker_pattern),
          where: not like(j.worker, ^sync_worker_pattern),
          where: j.attempted_at >= ^sync_job.attempted_at,
          where: j.attempted_at <= ^window_end,
          order_by: [asc: j.attempted_at],
          select: %{
            id: j.id,
            job_id: j.job_id,
            worker: j.worker,
            state: j.state,
            attempted_at: j.attempted_at,
            completed_at: j.completed_at,
            duration_ms: j.duration_ms,
            error: j.error
          }
        )
        |> Repo.replica().all()

      # Group child jobs by worker type
      child_stats = calculate_child_stats(child_jobs)

      Map.merge(sync_job, %{
        child_jobs: child_jobs,
        child_stats: child_stats,
        total_child_jobs: length(child_jobs)
      })
    end)
  end

  defp calculate_child_stats(child_jobs) do
    child_jobs
    |> Enum.group_by(&extract_job_name(&1.worker))
    |> Enum.map(fn {job_type, jobs} ->
      completed = Enum.count(jobs, &(&1.state == "completed"))
      failed = Enum.count(jobs, &(&1.state in ["discarded", "retryable"]))

      %{
        job_type: job_type,
        total: length(jobs),
        completed: completed,
        failed: failed,
        success_rate: if(length(jobs) > 0, do: round(completed / length(jobs) * 100), else: 0)
      }
    end)
    |> Enum.sort_by(& &1.total, :desc)
  end

  defp source_key_to_module(source_key) do
    # Convert source_key like "cinema_city" to module path like "CinemaCity"
    source_key
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen py-8">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <!-- Back Navigation -->
        <div class="mb-6">
          <.link
            navigate={~p"/admin/monitoring"}
            class="inline-flex items-center text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200"
          >
            <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
            </svg>
            Back to Dashboard
          </.link>
        </div>

        <!-- Header -->
        <div class="flex items-center justify-between mb-6">
          <div>
            <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
              <%= @source_config.display_name %>
            </h1>
            <p class="text-sm text-gray-500 dark:text-gray-400 mt-1">
              Source monitoring details
            </p>
          </div>

          <div class="flex items-center gap-3">
            <!-- Time Range Selector -->
            <select
              phx-change="change_time_range"
              name="time_range"
              class="block rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 dark:text-white text-sm focus:border-blue-500 focus:ring-blue-500"
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
              class="inline-flex items-center px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md text-sm text-gray-700 dark:text-gray-200 bg-white dark:bg-gray-700 hover:bg-gray-50 dark:hover:bg-gray-600"
            >
              <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
              </svg>
              Refresh
            </button>
          </div>
        </div>

        <!-- Tab Navigation -->
        <div class="border-b border-gray-200 dark:border-gray-700 mb-6">
          <nav class="-mb-px flex space-x-8">
            <button
              phx-click="change_tab"
              phx-value-tab="overview"
              class={"py-4 px-1 border-b-2 font-medium text-sm #{if @active_tab == "overview", do: "border-blue-500 text-blue-600 dark:text-blue-400", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300 dark:text-gray-400 dark:hover:text-gray-300"}"}
            >
              Overview
            </button>
            <button
              phx-click="change_tab"
              phx-value-tab="scheduler"
              class={"py-4 px-1 border-b-2 font-medium text-sm #{if @active_tab == "scheduler", do: "border-blue-500 text-blue-600 dark:text-blue-400", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300 dark:text-gray-400 dark:hover:text-gray-300"}"}
            >
              Scheduler
              <%= if @scheduler_health && length(@scheduler_health.alerts) > 0 do %>
                <span class="ml-2 inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200">
                  <%= length(@scheduler_health.alerts) %>
                </span>
              <% end %>
            </button>
            <button
              phx-click="change_tab"
              phx-value-tab="coverage"
              class={"py-4 px-1 border-b-2 font-medium text-sm #{if @active_tab == "coverage", do: "border-blue-500 text-blue-600 dark:text-blue-400", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300 dark:text-gray-400 dark:hover:text-gray-300"}"}
            >
              Coverage
              <%= if @coverage_data && length(@coverage_data.alerts) > 0 do %>
                <span class="ml-2 inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200">
                  <%= length(@coverage_data.alerts) %>
                </span>
              <% end %>
            </button>
            <button
              phx-click="change_tab"
              phx-value-tab="history"
              class={"py-4 px-1 border-b-2 font-medium text-sm #{if @active_tab == "history", do: "border-blue-500 text-blue-600 dark:text-blue-400", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300 dark:text-gray-400 dark:hover:text-gray-300"}"}
            >
              Job History
            </button>
          </nav>
        </div>

        <!-- Loading State -->
        <%= if @loading do %>
          <div class="flex items-center justify-center py-12">
            <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
            <span class="ml-3 text-gray-500 dark:text-gray-400">Loading...</span>
          </div>
        <% else %>
          <!-- Tab Content -->
          <%= case @active_tab do %>
            <% "overview" -> %>
              <%= render_overview_tab(assigns) %>
            <% "scheduler" -> %>
              <%= render_scheduler_tab(assigns) %>
            <% "coverage" -> %>
              <%= render_coverage_tab(assigns) %>
            <% "history" -> %>
              <%= render_history_tab(assigns) %>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  # Overview Tab (Phase 5.3)
  defp render_overview_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Key Metrics Cards -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
        <!-- Health Score -->
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <div class="text-sm font-medium text-gray-500 dark:text-gray-400">Health Score</div>
          <div class={"mt-2 text-3xl font-bold #{health_score_color(@health_data)}"}>
            <%= if @health_data, do: "#{Float.round(@health_data.overall_score, 1)}%", else: "--" %>
          </div>
          <div class="mt-2">
            <%= if @trend_data do %>
              <%= Phoenix.HTML.raw(Sparkline.render(@trend_data.data_points, width: 100, height: 24)) %>
            <% end %>
          </div>
        </div>

        <!-- Success Rate -->
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <div class="text-sm font-medium text-gray-500 dark:text-gray-400">Success Rate</div>
          <div class={"mt-2 text-3xl font-bold #{success_rate_color(@health_data)}"}>
            <%= if @health_data, do: "#{Float.round(@health_data.success_rate, 1)}%", else: "--" %>
          </div>
          <div class="mt-2 text-sm text-gray-500 dark:text-gray-400">
            <%= if @health_data do %>
              <%= @health_data.successful %> / <%= @health_data.total %> jobs
            <% end %>
          </div>
        </div>

        <!-- Failed Jobs -->
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <div class="text-sm font-medium text-gray-500 dark:text-gray-400">Failed Jobs</div>
          <div class={"mt-2 text-3xl font-bold #{if @health_data && @health_data.failed > 0, do: "text-red-600 dark:text-red-400", else: "text-gray-900 dark:text-white"}"}>
            <%= if @health_data, do: @health_data.failed, else: "--" %>
          </div>
          <div class="mt-2 text-sm text-gray-500 dark:text-gray-400">
            in last <%= @time_range %> hours
          </div>
        </div>

        <!-- Avg Duration -->
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <div class="text-sm font-medium text-gray-500 dark:text-gray-400">Avg Duration</div>
          <div class="mt-2 text-3xl font-bold text-gray-900 dark:text-white">
            <%= if @health_data && @health_data.avg_duration_ms do %>
              <%= format_duration(@health_data.avg_duration_ms) %>
            <% else %>
              --
            <% end %>
          </div>
          <div class="mt-2 text-sm text-gray-500 dark:text-gray-400">
            per job execution
          </div>
        </div>
      </div>

      <!-- Health Trend Chart -->
      <%= if @trend_data && length(@trend_data.data_points) > 0 do %>
        <% daily_data = aggregate_hourly_to_daily(@trend_data.data_points) %>
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <h3 class="text-lg font-medium text-gray-900 dark:text-white mb-4">7-Day Health Trend</h3>
          <div class="flex items-center gap-2 mb-4">
            <span class={"font-medium #{trend_color(@trend_data.trend_direction)}"}>
              <%= trend_arrow(@trend_data.trend_direction) %> <%= trend_label(@trend_data.trend_direction) %>
            </span>
          </div>

          <!-- Trend Data Points -->
          <div class="grid grid-cols-7 gap-2">
            <%= for day <- daily_data do %>
              <div class="text-center">
                <div class={"h-16 flex items-end justify-center rounded #{trend_bar_color(day.success_rate)}"}>
                  <div
                    class="w-full bg-current rounded"
                    style={"height: #{day.success_rate}%"}
                  >
                  </div>
                </div>
                <div class="text-xs text-gray-500 dark:text-gray-400 mt-1">
                  <%= Calendar.strftime(day.date, "%a") %>
                </div>
                <div class="text-xs font-medium text-gray-700 dark:text-gray-300">
                  <%= Float.round(day.success_rate, 0) %>%
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- Error Breakdown -->
      <%= if @error_analysis && length(@error_analysis.category_distribution) > 0 do %>
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <h3 class="text-lg font-medium text-gray-900 dark:text-white mb-4">Error Breakdown</h3>
          <div class="space-y-3">
            <%= for {category, count} <- @error_analysis.category_distribution do %>
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-2">
                  <span class={"inline-flex items-center px-2 py-1 rounded text-xs font-medium #{error_category_color(category)}"}>
                    <%= format_category(category) %>
                  </span>
                </div>
                <div class="flex items-center gap-4">
                  <span class="text-sm font-medium text-gray-700 dark:text-gray-300">
                    <%= count %> errors
                  </span>
                  <div class="w-32 bg-gray-200 dark:bg-gray-700 rounded-full h-2">
                    <div
                      class={"h-2 rounded-full #{error_bar_color(category)}"}
                      style={"width: #{min(count / max(@error_analysis.total_failures, 1) * 100, 100)}%"}
                    >
                    </div>
                  </div>
                </div>
              </div>
            <% end %>
          </div>

          <!-- Recommendations -->
          <%= if @error_analysis.recommendations && map_size(@error_analysis.recommendations) > 0 do %>
            <div class="mt-6 pt-4 border-t border-gray-200 dark:border-gray-700">
              <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Recommendations</h4>
              <ul class="space-y-1 text-sm text-gray-600 dark:text-gray-400">
                <%= for {_category, recommendation} <- @error_analysis.recommendations do %>
                  <li class="flex items-start gap-2">
                    <span class="text-blue-500">•</span>
                    <%= recommendation %>
                  </li>
                <% end %>
              </ul>
            </div>
          <% end %>
        </div>
      <% end %>

      <!-- Quick Status Summary -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <!-- Scheduler Status -->
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-medium text-gray-900 dark:text-white">Scheduler Status</h3>
            <button
              phx-click="change_tab"
              phx-value-tab="scheduler"
              class="text-sm text-blue-600 dark:text-blue-400 hover:underline"
            >
              View Details →
            </button>
          </div>
          <%= if @scheduler_health do %>
            <div class="flex items-center gap-4">
              <div class={"text-2xl font-bold #{if @scheduler_health.has_recent_execution, do: "text-green-600 dark:text-green-400", else: "text-red-600 dark:text-red-400"}"}>
                <%= if @scheduler_health.has_recent_execution, do: "Running", else: "Stale" %>
              </div>
              <div class="text-sm text-gray-500 dark:text-gray-400">
                <%= @scheduler_health.successful %>/<%= @scheduler_health.total_executions %> successful in 7 days
              </div>
            </div>
            <%= if length(@scheduler_health.alerts) > 0 do %>
              <div class="mt-3 text-sm text-yellow-600 dark:text-yellow-400">
                <%= length(@scheduler_health.alerts) %> alert(s)
              </div>
            <% end %>
          <% else %>
            <div class="text-gray-500 dark:text-gray-400">Not monitored</div>
          <% end %>
        </div>

        <!-- Coverage Status -->
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-medium text-gray-900 dark:text-white">Coverage Status</h3>
            <button
              phx-click="change_tab"
              phx-value-tab="coverage"
              class="text-sm text-blue-600 dark:text-blue-400 hover:underline"
            >
              View Details →
            </button>
          </div>
          <%= if @coverage_data do %>
            <div class="flex items-center gap-4">
              <div class="text-2xl font-bold text-gray-900 dark:text-white">
                <%= @coverage_data.days_with_events %>/<%= length(@coverage_data.days) %> days
              </div>
              <div class="text-sm text-gray-500 dark:text-gray-400">
                <%= @coverage_data.total_events %> total events
              </div>
            </div>
            <%= if length(@coverage_data.alerts) > 0 do %>
              <div class="mt-3 text-sm text-yellow-600 dark:text-yellow-400">
                <%= length(@coverage_data.alerts) %> alert(s)
              </div>
            <% end %>
          <% else %>
            <div class="text-gray-500 dark:text-gray-400">Not monitored</div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Scheduler Tab (Phase 5.4)
  defp render_scheduler_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Scheduler Health Card -->
      <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
        <h3 class="text-lg font-medium text-gray-900 dark:text-white mb-4">Scheduler Health</h3>
        <%= if @scheduler_health do %>
          <!-- Day-by-day grid -->
          <div class="mb-6">
            <div class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Last 7 Days</div>
            <div class="flex gap-2">
              <%= for day <- @scheduler_health.days do %>
                <div class={"flex-1 p-3 rounded text-center #{scheduler_day_color(day.status)}"}>
                  <div class="text-xs text-gray-500 dark:text-gray-400">
                    <%= Calendar.strftime(day.date, "%a") %>
                  </div>
                  <div class="text-lg font-medium">
                    <%= scheduler_status_icon(day.status) %>
                  </div>
                  <div class="text-xs">
                    <%= if day.jobs_spawned, do: "#{day.jobs_spawned} jobs", else: "--" %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Alerts -->
          <%= if length(@scheduler_health.alerts) > 0 do %>
            <div class="border-t border-gray-200 dark:border-gray-700 pt-4">
              <div class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Alerts</div>
              <div class="space-y-2">
                <%= for alert <- @scheduler_health.alerts do %>
                  <div class={"p-3 rounded text-sm #{scheduler_alert_color(alert.type)}"}>
                    <%= alert.message %>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <!-- Stats -->
          <div class="border-t border-gray-200 dark:border-gray-700 pt-4 mt-4">
            <div class="grid grid-cols-3 gap-4 text-center">
              <div>
                <div class="text-2xl font-bold text-gray-900 dark:text-white">
                  <%= @scheduler_health.total_executions %>
                </div>
                <div class="text-sm text-gray-500 dark:text-gray-400">Total Runs</div>
              </div>
              <div>
                <div class="text-2xl font-bold text-green-600 dark:text-green-400">
                  <%= @scheduler_health.successful %>
                </div>
                <div class="text-sm text-gray-500 dark:text-gray-400">Successful</div>
              </div>
              <div>
                <div class="text-2xl font-bold text-red-600 dark:text-red-400">
                  <%= @scheduler_health.failed %>
                </div>
                <div class="text-sm text-gray-500 dark:text-gray-400">Failed</div>
              </div>
            </div>
          </div>
        <% else %>
          <p class="text-gray-500 dark:text-gray-400">Scheduler monitoring not configured for this source.</p>
        <% end %>
      </div>

      <!-- Recent Executions List -->
      <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
        <h3 class="text-lg font-medium text-gray-900 dark:text-white mb-4">Recent Executions</h3>
        <%= if length(@recent_executions) > 0 do %>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
              <thead>
                <tr>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    Worker
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    State
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    Duration
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    Started
                  </th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                <%= for execution <- @recent_executions do %>
                  <tr class="hover:bg-gray-50 dark:hover:bg-gray-700">
                    <td class="px-4 py-3 whitespace-nowrap">
                      <div class="text-sm font-medium text-gray-900 dark:text-white">
                        <%= extract_job_name(execution.worker) %>
                      </div>
                      <div class="text-xs text-gray-500 dark:text-gray-400">
                        Job #<%= execution.job_id %>
                      </div>
                    </td>
                    <td class="px-4 py-3 whitespace-nowrap">
                      <span class={"inline-flex items-center px-2 py-0.5 rounded text-xs font-medium #{execution_state_color(execution.state)}"}>
                        <%= execution_state_icon(execution.state) %> <%= execution.state %>
                      </span>
                    </td>
                    <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-500 dark:text-gray-400">
                      <%= format_duration(execution.duration_ms) %>
                    </td>
                    <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-500 dark:text-gray-400">
                      <%= format_relative_time(execution.attempted_at) %>
                    </td>
                    <td class="px-4 py-3 whitespace-nowrap text-right">
                      <button
                        phx-click="select_execution"
                        phx-value-id={execution.id}
                        class="text-blue-600 dark:text-blue-400 hover:text-blue-800 dark:hover:text-blue-300 text-sm"
                      >
                        View Details
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% else %>
          <p class="text-gray-500 dark:text-gray-400">No recent executions found for this source.</p>
        <% end %>
      </div>

      <!-- Execution Detail Modal -->
      <%= if @selected_execution do %>
        <div class="fixed inset-0 z-50 overflow-y-auto" aria-labelledby="modal-title" role="dialog" aria-modal="true">
          <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
            <!-- Background overlay -->
            <div
              class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"
              phx-click="close_execution_detail"
            ></div>

            <!-- Modal panel -->
            <div class="inline-block align-bottom bg-white dark:bg-gray-800 rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-2xl sm:w-full">
              <div class="bg-white dark:bg-gray-800 px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
                <!-- Header -->
                <div class="flex items-center justify-between mb-4">
                  <h3 class="text-lg font-medium text-gray-900 dark:text-white" id="modal-title">
                    Execution Details
                  </h3>
                  <button
                    phx-click="close_execution_detail"
                    class="text-gray-400 hover:text-gray-500 dark:hover:text-gray-300"
                  >
                    <svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                    </svg>
                  </button>
                </div>

                <!-- Content -->
                <div class="space-y-4">
                  <!-- Job Info -->
                  <div class="grid grid-cols-2 gap-4">
                    <div>
                      <div class="text-sm font-medium text-gray-500 dark:text-gray-400">Worker</div>
                      <div class="mt-1 text-sm text-gray-900 dark:text-white">
                        <%= extract_job_name(@selected_execution.worker) %>
                      </div>
                    </div>
                    <div>
                      <div class="text-sm font-medium text-gray-500 dark:text-gray-400">Job ID</div>
                      <div class="mt-1 text-sm text-gray-900 dark:text-white">
                        <%= @selected_execution.job_id %>
                      </div>
                    </div>
                    <div>
                      <div class="text-sm font-medium text-gray-500 dark:text-gray-400">State</div>
                      <div class="mt-1">
                        <span class={"inline-flex items-center px-2 py-0.5 rounded text-xs font-medium #{execution_state_color(@selected_execution.state)}"}>
                          <%= execution_state_icon(@selected_execution.state) %> <%= @selected_execution.state %>
                        </span>
                      </div>
                    </div>
                    <div>
                      <div class="text-sm font-medium text-gray-500 dark:text-gray-400">Duration</div>
                      <div class="mt-1 text-sm text-gray-900 dark:text-white">
                        <%= format_duration(@selected_execution.duration_ms) %>
                      </div>
                    </div>
                    <div>
                      <div class="text-sm font-medium text-gray-500 dark:text-gray-400">Started At</div>
                      <div class="mt-1 text-sm text-gray-900 dark:text-white">
                        <%= format_datetime(@selected_execution.attempted_at) %>
                      </div>
                    </div>
                    <div>
                      <div class="text-sm font-medium text-gray-500 dark:text-gray-400">Completed At</div>
                      <div class="mt-1 text-sm text-gray-900 dark:text-white">
                        <%= if @selected_execution.completed_at do %>
                          <%= format_datetime(@selected_execution.completed_at) %>
                        <% else %>
                          --
                        <% end %>
                      </div>
                    </div>
                  </div>

                  <!-- Args -->
                  <%= if @selected_execution.args && map_size(@selected_execution.args) > 0 do %>
                    <div>
                      <div class="text-sm font-medium text-gray-500 dark:text-gray-400 mb-2">Arguments</div>
                      <div class="bg-gray-100 dark:bg-gray-900 rounded p-3 text-xs font-mono overflow-x-auto">
                        <pre class="text-gray-800 dark:text-gray-200"><%= format_json(@selected_execution.args) %></pre>
                      </div>
                    </div>
                  <% end %>

                  <!-- Results -->
                  <%= if @selected_execution.results && map_size(@selected_execution.results) > 0 do %>
                    <div>
                      <div class="text-sm font-medium text-gray-500 dark:text-gray-400 mb-2">Results</div>
                      <div class="bg-gray-100 dark:bg-gray-900 rounded p-3 text-xs font-mono overflow-x-auto">
                        <pre class="text-gray-800 dark:text-gray-200"><%= format_json(@selected_execution.results) %></pre>
                      </div>
                    </div>
                  <% end %>

                  <!-- Error -->
                  <%= if @selected_execution.error do %>
                    <div>
                      <div class="text-sm font-medium text-red-600 dark:text-red-400 mb-2">Error</div>
                      <div class="bg-red-50 dark:bg-red-900/20 rounded p-3 text-xs font-mono overflow-x-auto">
                        <pre class="text-red-800 dark:text-red-200 whitespace-pre-wrap"><%= @selected_execution.error %></pre>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>

              <!-- Footer -->
              <div class="bg-gray-50 dark:bg-gray-700 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
                <button
                  phx-click="close_execution_detail"
                  class="w-full inline-flex justify-center rounded-md border border-gray-300 dark:border-gray-600 shadow-sm px-4 py-2 bg-white dark:bg-gray-800 text-base font-medium text-gray-700 dark:text-gray-200 hover:bg-gray-50 dark:hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 sm:mt-0 sm:w-auto sm:text-sm"
                >
                  Close
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Coverage Tab (Phase 5.5)
  defp render_coverage_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Coverage Summary Card -->
      <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-medium text-gray-900 dark:text-white">Coverage Summary</h3>
          <%= if @coverage_data do %>
            <div class={"inline-flex items-center px-3 py-1 rounded-full text-sm font-medium #{coverage_health_color(@coverage_data)}"}>
              <%= coverage_health_label(@coverage_data) %>
            </div>
          <% end %>
        </div>

        <%= if @coverage_data do %>
          <!-- Stats Row -->
          <div class="grid grid-cols-4 gap-4 mb-6">
            <div class="text-center">
              <div class="text-3xl font-bold text-gray-900 dark:text-white">
                <%= @coverage_data.total_events %>
              </div>
              <div class="text-sm text-gray-500 dark:text-gray-400">Total Events</div>
            </div>
            <div class="text-center">
              <div class="text-3xl font-bold text-gray-900 dark:text-white">
                <%= @coverage_data.days_with_events %>/<%= length(@coverage_data.days) %>
              </div>
              <div class="text-sm text-gray-500 dark:text-gray-400">Days Covered</div>
            </div>
            <div class="text-center">
              <div class="text-3xl font-bold text-gray-900 dark:text-white">
                <%= @coverage_data.avg_events_per_day %>
              </div>
              <div class="text-sm text-gray-500 dark:text-gray-400">Avg/Day</div>
            </div>
            <div class="text-center">
              <div class={"text-3xl font-bold #{coverage_percentage_color(@coverage_data)}"}>
                <%= calculate_coverage_percentage(@coverage_data) %>%
              </div>
              <div class="text-sm text-gray-500 dark:text-gray-400">Coverage</div>
            </div>
          </div>

          <!-- Coverage Heatmap -->
          <div class="mb-6">
            <div class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-3">Next 7 Days Coverage</div>
            <div class="grid grid-cols-7 gap-2">
              <%= for day <- @coverage_data.days do %>
                <div class="relative group">
                  <div class={"aspect-square rounded-lg flex flex-col items-center justify-center cursor-pointer transition-transform hover:scale-105 #{coverage_heatmap_color(day.status, day.coverage_pct)}"}>
                    <div class="text-xs font-medium opacity-80">
                      <%= day.day_name %>
                    </div>
                    <div class="text-2xl font-bold">
                      <%= day.event_count %>
                    </div>
                    <div class="text-xs opacity-70">
                      <%= day.coverage_pct %>%
                    </div>
                  </div>
                  <!-- Tooltip -->
                  <div class="absolute bottom-full left-1/2 -translate-x-1/2 mb-2 px-3 py-2 bg-gray-900 dark:bg-gray-700 text-white text-xs rounded shadow-lg opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none whitespace-nowrap z-10">
                    <div class="font-medium"><%= Calendar.strftime(day.date, "%A, %b %d") %></div>
                    <div><%= day.event_count %> events</div>
                    <div>Expected: <%= day.expected %></div>
                    <div>Status: <%= format_coverage_status(day.status) %></div>
                    <div class="absolute top-full left-1/2 -translate-x-1/2 -mt-1">
                      <div class="border-4 border-transparent border-t-gray-900 dark:border-t-gray-700"></div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>

            <!-- Legend -->
            <div class="flex items-center justify-center gap-4 mt-4 text-xs text-gray-500 dark:text-gray-400">
              <div class="flex items-center gap-1">
                <div class="w-3 h-3 rounded bg-green-500"></div>
                <span>OK (100%+)</span>
              </div>
              <div class="flex items-center gap-1">
                <div class="w-3 h-3 rounded bg-yellow-500"></div>
                <span>Fair (50-99%)</span>
              </div>
              <div class="flex items-center gap-1">
                <div class="w-3 h-3 rounded bg-orange-500"></div>
                <span>Low (&lt;50%)</span>
              </div>
              <div class="flex items-center gap-1">
                <div class="w-3 h-3 rounded bg-red-500"></div>
                <span>Missing</span>
              </div>
            </div>
          </div>
        <% else %>
          <p class="text-gray-500 dark:text-gray-400">Coverage monitoring not configured for this source.</p>
        <% end %>
      </div>

      <!-- Day-by-Day Details -->
      <%= if @coverage_data && length(@coverage_data.days) > 0 do %>
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <h3 class="text-lg font-medium text-gray-900 dark:text-white mb-4">Day-by-Day Details</h3>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
              <thead>
                <tr>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    Date
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    Status
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    Events
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    Expected
                  </th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                    Coverage
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                <%= for day <- @coverage_data.days do %>
                  <tr class="hover:bg-gray-50 dark:hover:bg-gray-700">
                    <td class="px-4 py-3 whitespace-nowrap">
                      <div class="text-sm font-medium text-gray-900 dark:text-white">
                        <%= Calendar.strftime(day.date, "%a, %b %d") %>
                      </div>
                      <div class="text-xs text-gray-500 dark:text-gray-400">
                        <%= days_from_now(day.date) %>
                      </div>
                    </td>
                    <td class="px-4 py-3 whitespace-nowrap">
                      <span class={"inline-flex items-center px-2 py-0.5 rounded text-xs font-medium #{coverage_status_badge_color(day.status)}"}>
                        <%= coverage_status_icon(day.status) %> <%= format_coverage_status(day.status) %>
                      </span>
                    </td>
                    <td class="px-4 py-3 whitespace-nowrap">
                      <span class="text-sm font-medium text-gray-900 dark:text-white">
                        <%= day.event_count %>
                      </span>
                    </td>
                    <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-500 dark:text-gray-400">
                      <%= day.expected %>
                    </td>
                    <td class="px-4 py-3 whitespace-nowrap">
                      <div class="flex items-center gap-2">
                        <div class="w-24 bg-gray-200 dark:bg-gray-700 rounded-full h-2">
                          <div
                            class={"h-2 rounded-full #{coverage_bar_fill_color(day.status)}"}
                            style={"width: #{min(day.coverage_pct, 100)}%"}
                          >
                          </div>
                        </div>
                        <span class="text-sm text-gray-600 dark:text-gray-300">
                          <%= day.coverage_pct %>%
                        </span>
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      <% end %>

      <!-- Alerts Section -->
      <%= if @coverage_data && length(@coverage_data.alerts) > 0 do %>
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-medium text-gray-900 dark:text-white">Coverage Alerts</h3>
            <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200">
              <%= length(@coverage_data.alerts) %> alert(s)
            </span>
          </div>
          <div class="space-y-3">
            <%= for alert <- @coverage_data.alerts do %>
              <div class={"flex items-start gap-3 p-4 rounded-lg #{coverage_alert_bg_color(alert.type)}"}>
                <div class={"flex-shrink-0 #{coverage_alert_icon_color(alert.type)}"}>
                  <%= coverage_alert_icon(alert.type) %>
                </div>
                <div class="flex-1">
                  <div class={"font-medium #{coverage_alert_text_color(alert.type)}"}>
                    <%= alert.message %>
                  </div>
                  <%= if alert.date do %>
                    <div class="text-sm opacity-75 mt-1">
                      <%= Calendar.strftime(alert.date, "%A, %B %d, %Y") %>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Job History Tab (Phase 5.6)
  defp render_history_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <!-- Header -->
      <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
        <div class="flex items-center justify-between">
          <div>
            <h3 class="text-lg font-medium text-gray-900 dark:text-white">Sync Run History</h3>
            <p class="text-sm text-gray-500 dark:text-gray-400 mt-1">
              Recent orchestration runs with child job breakdown
            </p>
          </div>
          <div class="text-sm text-gray-500 dark:text-gray-400">
            <%= length(@sync_runs) %> runs in last 7 days
          </div>
        </div>
      </div>

      <!-- Sync Runs List -->
      <%= if Enum.empty?(@sync_runs) do %>
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-8 text-center">
          <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
          </svg>
          <h3 class="mt-2 text-sm font-medium text-gray-900 dark:text-white">No sync runs found</h3>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            No SyncJob executions found in the last 7 days.
          </p>
        </div>
      <% else %>
        <div class="space-y-3">
          <%= for sync_run <- @sync_runs do %>
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow overflow-hidden">
              <!-- Sync Run Header (clickable) -->
              <button
                phx-click="toggle_sync_run"
                phx-value-id={sync_run.id}
                class="w-full px-4 py-3 flex items-center justify-between hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors"
              >
                <div class="flex items-center gap-4">
                  <!-- Expand/Collapse Icon -->
                  <svg
                    class={"w-5 h-5 text-gray-400 transition-transform #{if MapSet.member?(@expanded_sync_runs, sync_run.id), do: "rotate-90", else: ""}"}
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                  </svg>

                  <!-- Status Icon -->
                  <span class={sync_run_status_color(sync_run.state)}>
                    <%= sync_run_status_icon(sync_run.state) %>
                  </span>

                  <!-- Sync Info -->
                  <div class="text-left">
                    <div class="text-sm font-medium text-gray-900 dark:text-white">
                      <%= format_datetime(sync_run.attempted_at) %>
                    </div>
                    <div class="text-xs text-gray-500 dark:text-gray-400">
                      <%= format_relative_time(sync_run.attempted_at) %>
                      <%= if sync_run.args["options"]["city_name"] do %>
                        • <%= sync_run.args["options"]["city_name"] %>
                      <% end %>
                    </div>
                  </div>
                </div>

                <div class="flex items-center gap-6">
                  <!-- Child Jobs Summary -->
                  <div class="text-right">
                    <div class="text-sm font-medium text-gray-900 dark:text-white">
                      <%= sync_run.total_child_jobs %> child jobs
                    </div>
                    <div class="text-xs text-gray-500 dark:text-gray-400">
                      <%= if sync_run.results["jobs_scheduled"] do %>
                        <%= sync_run.results["jobs_scheduled"] %> scheduled
                      <% end %>
                    </div>
                  </div>

                  <!-- Duration -->
                  <div class="text-right min-w-[60px]">
                    <div class="text-sm text-gray-600 dark:text-gray-300">
                      <%= format_duration(sync_run.duration_ms) %>
                    </div>
                  </div>

                  <!-- State Badge -->
                  <span class={"inline-flex items-center px-2 py-0.5 rounded text-xs font-medium #{execution_state_color(sync_run.state)}"}>
                    <%= sync_run.state %>
                  </span>
                </div>
              </button>

              <!-- Expanded Child Jobs -->
              <%= if MapSet.member?(@expanded_sync_runs, sync_run.id) do %>
                <div class="border-t border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-900">
                  <!-- Child Stats Summary -->
                  <%= if length(sync_run.child_stats) > 0 do %>
                    <div class="px-4 py-3 border-b border-gray-200 dark:border-gray-700">
                      <div class="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider mb-2">
                        Job Type Breakdown
                      </div>
                      <div class="flex flex-wrap gap-2">
                        <%= for stat <- sync_run.child_stats do %>
                          <div class="inline-flex items-center gap-2 px-3 py-1.5 rounded-lg bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700">
                            <span class="text-sm font-medium text-gray-900 dark:text-white">
                              <%= stat.job_type %>
                            </span>
                            <span class="text-xs text-gray-500 dark:text-gray-400">
                              <%= stat.completed %>/<%= stat.total %>
                            </span>
                            <span class={"text-xs font-medium #{if stat.success_rate >= 90, do: "text-green-600", else: if(stat.success_rate >= 70, do: "text-yellow-600", else: "text-red-600")}"}>
                              <%= stat.success_rate %>%
                            </span>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>

                  <!-- Child Jobs List -->
                  <%= if length(sync_run.child_jobs) > 0 do %>
                    <div class="max-h-64 overflow-y-auto">
                      <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
                        <thead class="bg-gray-100 dark:bg-gray-800 sticky top-0">
                          <tr>
                            <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Job Type</th>
                            <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">State</th>
                            <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Started</th>
                            <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Duration</th>
                          </tr>
                        </thead>
                        <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                          <%= for child <- Enum.take(sync_run.child_jobs, 50) do %>
                            <tr class="hover:bg-gray-100 dark:hover:bg-gray-800">
                              <td class="px-4 py-2 text-sm text-gray-900 dark:text-white">
                                <%= extract_job_name(child.worker) %>
                              </td>
                              <td class="px-4 py-2">
                                <span class={"inline-flex items-center px-2 py-0.5 rounded text-xs font-medium #{execution_state_color(child.state)}"}>
                                  <%= execution_state_icon(child.state) %> <%= child.state %>
                                </span>
                              </td>
                              <td class="px-4 py-2 text-sm text-gray-500 dark:text-gray-400">
                                <%= Calendar.strftime(child.attempted_at, "%H:%M:%S") %>
                              </td>
                              <td class="px-4 py-2 text-sm text-gray-500 dark:text-gray-400 text-right">
                                <%= format_duration(child.duration_ms) %>
                              </td>
                            </tr>
                          <% end %>
                        </tbody>
                      </table>
                      <%= if length(sync_run.child_jobs) > 50 do %>
                        <div class="px-4 py-2 text-center text-xs text-gray-500 dark:text-gray-400 bg-gray-100 dark:bg-gray-800">
                          Showing 50 of <%= length(sync_run.child_jobs) %> child jobs
                        </div>
                      <% end %>
                    </div>
                  <% else %>
                    <div class="px-4 py-6 text-center text-sm text-gray-500 dark:text-gray-400">
                      No child jobs found for this sync run
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp sync_run_status_color("completed"), do: "text-green-500"
  defp sync_run_status_color("discarded"), do: "text-red-500"
  defp sync_run_status_color("retryable"), do: "text-yellow-500"
  defp sync_run_status_color(_), do: "text-gray-400"

  defp sync_run_status_icon("completed"), do: "✓"
  defp sync_run_status_icon("discarded"), do: "✗"
  defp sync_run_status_icon("retryable"), do: "↻"
  defp sync_run_status_icon(_), do: "○"

  # Helper functions

  defp health_score_color(nil), do: "text-gray-500"

  defp health_score_color(%{overall_score: score}) when score >= 95,
    do: "text-green-600 dark:text-green-400"

  defp health_score_color(%{overall_score: score}) when score >= 80,
    do: "text-yellow-600 dark:text-yellow-400"

  defp health_score_color(_), do: "text-red-600 dark:text-red-400"

  defp success_rate_color(nil), do: "text-gray-500"

  defp success_rate_color(%{success_rate: rate}) when rate >= 95,
    do: "text-green-600 dark:text-green-400"

  defp success_rate_color(%{success_rate: rate}) when rate >= 80,
    do: "text-yellow-600 dark:text-yellow-400"

  defp success_rate_color(_), do: "text-red-600 dark:text-red-400"

  defp format_duration(nil), do: "--"
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"

  defp trend_color(:improving), do: "text-green-600 dark:text-green-400"
  defp trend_color(:degrading), do: "text-red-600 dark:text-red-400"
  defp trend_color(_), do: "text-gray-500 dark:text-gray-400"

  defp trend_arrow(:improving), do: "↑"
  defp trend_arrow(:degrading), do: "↓"
  defp trend_arrow(_), do: "→"

  defp trend_label(:improving), do: "Improving"
  defp trend_label(:degrading), do: "Degrading"
  defp trend_label(_), do: "Stable"

  # Aggregate hourly data points into daily summaries for the trend chart
  defp aggregate_hourly_to_daily(hourly_points) do
    hourly_points
    |> Enum.group_by(fn point ->
      datetime_to_date(point.hour)
    end)
    |> Enum.map(fn {date, points} ->
      total = points |> Enum.map(& &1.total) |> Enum.sum()
      completed = points |> Enum.map(& &1.completed) |> Enum.sum()

      success_rate =
        if total > 0 do
          Float.round(completed / total * 100, 1)
        else
          100.0
        end

      %{date: date, success_rate: success_rate, total: total, completed: completed}
    end)
    |> Enum.sort_by(& &1.date, Date)
    |> Enum.take(-7)
  end

  defp trend_bar_color(rate) when rate >= 95,
    do: "bg-green-100 dark:bg-green-900 text-green-600 dark:text-green-400"

  defp trend_bar_color(rate) when rate >= 80,
    do: "bg-yellow-100 dark:bg-yellow-900 text-yellow-600 dark:text-yellow-400"

  defp trend_bar_color(_), do: "bg-red-100 dark:bg-red-900 text-red-600 dark:text-red-400"

  defp error_category_color("network_error"),
    do: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200"

  defp error_category_color("validation_error"),
    do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200"

  defp error_category_color("geocoding_error"),
    do: "bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200"

  defp error_category_color("data_quality_error"),
    do: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200"

  defp error_category_color(_),
    do: "bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200"

  defp error_bar_color("network_error"), do: "bg-blue-500"
  defp error_bar_color("validation_error"), do: "bg-yellow-500"
  defp error_bar_color("geocoding_error"), do: "bg-purple-500"
  defp error_bar_color("data_quality_error"), do: "bg-orange-500"
  defp error_bar_color(_), do: "bg-gray-500"

  defp format_category(category) do
    category
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  # Helper to convert DateTime or NaiveDateTime to Date
  defp datetime_to_date(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp datetime_to_date(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_date(ndt)
  defp datetime_to_date(%Date{} = date), do: date

  # Scheduler tab helpers

  defp scheduler_day_color(:ok),
    do: "bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-200"

  defp scheduler_day_color(:failure),
    do: "bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-200"

  defp scheduler_day_color(:missing),
    do: "bg-gray-100 dark:bg-gray-700 text-gray-500 dark:text-gray-400"

  defp scheduler_day_color(_), do: "bg-gray-100 dark:bg-gray-700 text-gray-500 dark:text-gray-400"

  defp scheduler_status_icon(:ok), do: "✓"
  defp scheduler_status_icon(:failure), do: "✗"
  defp scheduler_status_icon(:missing), do: "−"
  defp scheduler_status_icon(_), do: "?"

  defp scheduler_alert_color(:missing),
    do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200"

  defp scheduler_alert_color(:failure),
    do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"

  defp scheduler_alert_color(:stale),
    do: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200"

  defp scheduler_alert_color(:no_executions),
    do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"

  defp scheduler_alert_color(_),
    do: "bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200"

  # Execution helpers (Phase 5.4)

  defp extract_job_name(worker) when is_binary(worker) do
    worker
    |> String.split(".")
    |> List.last()
  end

  defp extract_job_name(_), do: "Unknown"

  defp execution_state_color("completed"),
    do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"

  defp execution_state_color("discarded"),
    do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"

  defp execution_state_color("cancelled"),
    do: "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300"

  defp execution_state_color("retryable"),
    do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200"

  defp execution_state_color(_),
    do: "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300"

  defp execution_state_icon("completed"), do: "✓"
  defp execution_state_icon("discarded"), do: "✗"
  defp execution_state_icon("cancelled"), do: "⊘"
  defp execution_state_icon("retryable"), do: "↻"
  defp execution_state_icon(_), do: "?"

  defp format_relative_time(nil), do: "--"

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 -> "Just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86_400 -> "#{div(diff_seconds, 3600)}h ago"
      diff_seconds < 604_800 -> "#{div(diff_seconds, 86_400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end

  defp format_datetime(nil), do: "--"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_json(data) when is_map(data) do
    Jason.encode!(data, pretty: true)
  end

  defp format_json(data), do: inspect(data)

  # Coverage helpers (Phase 5.5)

  defp coverage_health_color(coverage_data) do
    cond do
      length(coverage_data.alerts) == 0 ->
        "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"

      Enum.any?(coverage_data.alerts, &(&1.type in [:missing_near, :critical_gaps])) ->
        "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"

      true ->
        "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200"
    end
  end

  defp coverage_health_label(coverage_data) do
    cond do
      length(coverage_data.alerts) == 0 -> "Healthy"
      Enum.any?(coverage_data.alerts, &(&1.type in [:missing_near, :critical_gaps])) -> "Critical"
      true -> "Warning"
    end
  end

  defp coverage_percentage_color(coverage_data) do
    pct = calculate_coverage_percentage(coverage_data)

    cond do
      pct >= 90 -> "text-green-600 dark:text-green-400"
      pct >= 70 -> "text-yellow-600 dark:text-yellow-400"
      true -> "text-red-600 dark:text-red-400"
    end
  end

  defp calculate_coverage_percentage(coverage_data) do
    total_days = length(coverage_data.days)

    if total_days > 0 do
      ok_days = Enum.count(coverage_data.days, &(&1.status == :ok))
      round(ok_days / total_days * 100)
    else
      0
    end
  end

  defp coverage_heatmap_color(:ok, pct) when pct >= 100,
    do: "bg-green-500 text-white"

  defp coverage_heatmap_color(:ok, _pct),
    do: "bg-green-400 text-white"

  defp coverage_heatmap_color(:fair, _pct),
    do: "bg-yellow-400 text-gray-900"

  defp coverage_heatmap_color(:low, _pct),
    do: "bg-orange-400 text-white"

  defp coverage_heatmap_color(:missing, _pct),
    do: "bg-red-500 text-white"

  defp coverage_heatmap_color(_, _),
    do: "bg-gray-300 dark:bg-gray-600 text-gray-700 dark:text-gray-300"

  defp format_coverage_status(:ok), do: "OK"
  defp format_coverage_status(:fair), do: "Fair"
  defp format_coverage_status(:low), do: "Low"
  defp format_coverage_status(:missing), do: "Missing"
  defp format_coverage_status(_), do: "Unknown"

  defp days_from_now(date) do
    today = Date.utc_today()
    diff = Date.diff(date, today)

    cond do
      diff == 0 -> "Today"
      diff == 1 -> "Tomorrow"
      diff > 0 -> "In #{diff} days"
      diff == -1 -> "Yesterday"
      true -> "#{abs(diff)} days ago"
    end
  end

  defp coverage_status_badge_color(:ok),
    do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"

  defp coverage_status_badge_color(:fair),
    do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200"

  defp coverage_status_badge_color(:low),
    do: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200"

  defp coverage_status_badge_color(:missing),
    do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"

  defp coverage_status_badge_color(_),
    do: "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300"

  defp coverage_status_icon(:ok), do: "✓"
  defp coverage_status_icon(:fair), do: "~"
  defp coverage_status_icon(:low), do: "↓"
  defp coverage_status_icon(:missing), do: "✗"
  defp coverage_status_icon(_), do: "?"

  defp coverage_bar_fill_color(:ok), do: "bg-green-500"
  defp coverage_bar_fill_color(:fair), do: "bg-yellow-500"
  defp coverage_bar_fill_color(:low), do: "bg-orange-500"
  defp coverage_bar_fill_color(:missing), do: "bg-red-500"
  defp coverage_bar_fill_color(_), do: "bg-gray-400"

  defp coverage_alert_bg_color(:missing_near), do: "bg-red-50 dark:bg-red-900/20"
  defp coverage_alert_bg_color(:critical_gaps), do: "bg-red-50 dark:bg-red-900/20"
  defp coverage_alert_bg_color(:low_near), do: "bg-orange-50 dark:bg-orange-900/20"
  defp coverage_alert_bg_color(:missing_far), do: "bg-yellow-50 dark:bg-yellow-900/20"
  defp coverage_alert_bg_color(_), do: "bg-gray-50 dark:bg-gray-900/20"

  defp coverage_alert_icon_color(:missing_near), do: "text-red-500"
  defp coverage_alert_icon_color(:critical_gaps), do: "text-red-500"
  defp coverage_alert_icon_color(:low_near), do: "text-orange-500"
  defp coverage_alert_icon_color(:missing_far), do: "text-yellow-500"
  defp coverage_alert_icon_color(_), do: "text-gray-500"

  defp coverage_alert_text_color(:missing_near), do: "text-red-800 dark:text-red-200"
  defp coverage_alert_text_color(:critical_gaps), do: "text-red-800 dark:text-red-200"
  defp coverage_alert_text_color(:low_near), do: "text-orange-800 dark:text-orange-200"
  defp coverage_alert_text_color(:missing_far), do: "text-yellow-800 dark:text-yellow-200"
  defp coverage_alert_text_color(_), do: "text-gray-800 dark:text-gray-200"

  defp coverage_alert_icon(:missing_near) do
    Phoenix.HTML.raw("""
    <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
      <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clip-rule="evenodd" />
    </svg>
    """)
  end

  defp coverage_alert_icon(:critical_gaps) do
    Phoenix.HTML.raw("""
    <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
      <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd" />
    </svg>
    """)
  end

  defp coverage_alert_icon(:low_near) do
    Phoenix.HTML.raw("""
    <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
      <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-11a1 1 0 10-2 0v3.586L7.707 9.293a1 1 0 00-1.414 1.414l3 3a1 1 0 001.414 0l3-3a1 1 0 00-1.414-1.414L11 10.586V7z" clip-rule="evenodd" />
    </svg>
    """)
  end

  defp coverage_alert_icon(_) do
    Phoenix.HTML.raw("""
    <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
      <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" />
    </svg>
    """)
  end
end
