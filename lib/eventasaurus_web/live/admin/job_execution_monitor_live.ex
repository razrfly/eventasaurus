defmodule EventasaurusWeb.Admin.JobExecutionMonitorLive do
  @moduledoc """
  Admin dashboard for monitoring Oban job executions.

  Phase 1 MVP: Basic job execution monitoring with:
  - List of unique workers with execution counts
  - Recent job executions with status
  - Basic filtering by worker and state
  - Job execution metrics (success rate, duration)

  Phase 2: Enhanced dashboard with:
  - System-wide metrics summary cards
  - Time range filtering (24h, 7d, 30d)
  - Execution timeline visualization
  - Per-scraper metrics and comparison

  Future enhancements (Phase 3+):
  - Per-scraper drill-down pages
  - Pipeline visualization
  - Silent failure alerts
  - Correlation tracking
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.JobExecutionSummaries
  alias EventasaurusDiscovery.JobExecutionSummaries.Lineage

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Job Execution Monitor")
      |> assign(:selected_worker, nil)
      |> assign(:state_filter, nil)
      |> assign(:error_category_filter, nil)
      |> assign(:time_range, 24)
      |> assign(:limit, 50)
      |> assign(:loading, true)
      |> assign(:lineage_modal_open, false)
      |> assign(:selected_job_lineage, nil)
      |> assign(:expanded_sources, MapSet.new())
      |> load_system_metrics()
      |> load_timeline_data()
      |> load_scraper_metrics()
      |> load_error_category_breakdown()
      |> load_silent_failures()
      |> load_workers()
      |> load_recent_executions()
      |> assign(:loading, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_worker", %{"worker" => worker}, socket) do
    selected_worker = if worker == "all", do: nil, else: worker

    socket =
      socket
      |> assign(:selected_worker, selected_worker)
      |> assign(:loading, true)
      |> load_recent_executions()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_state", %{"state" => state}, socket) do
    state_filter = if state == "all", do: nil, else: state

    socket =
      socket
      |> assign(:state_filter, state_filter)
      |> assign(:loading, true)
      |> load_recent_executions()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_error_category", %{"error_category" => error_category}, socket) do
    error_category_filter = if error_category == "all", do: nil, else: error_category

    socket =
      socket
      |> assign(:error_category_filter, error_category_filter)
      |> assign(:loading, true)
      |> load_recent_executions()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_time_range", %{"time_range" => time_range}, socket) do
    # Defensive parsing to prevent crashes on invalid input
    time_range_hours =
      case Integer.parse(time_range) do
        {hours, _} when hours > 0 -> hours
        # Keep current value if invalid
        _ -> socket.assigns.time_range
      end

    socket =
      socket
      |> assign(:time_range, time_range_hours)
      |> assign(:loading, true)
      |> load_system_metrics()
      |> load_timeline_data()
      |> load_scraper_metrics()
      |> load_error_category_breakdown()
      |> load_silent_failures()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    socket =
      socket
      |> assign(:loading, true)
      |> load_system_metrics()
      |> load_timeline_data()
      |> load_scraper_metrics()
      |> load_silent_failures()
      |> load_workers()
      |> load_recent_executions()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("show_lineage", %{"job-id" => job_id_str}, socket) do
    job_id = String.to_integer(job_id_str)
    lineage = Lineage.get_job_tree(job_id)

    socket =
      socket
      |> assign(:lineage_modal_open, true)
      |> assign(:selected_job_lineage, lineage)

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_lineage", _params, socket) do
    socket =
      socket
      |> assign(:lineage_modal_open, false)
      |> assign(:selected_job_lineage, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("navigate_to_pipeline", %{"source" => source_slug}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin/job-executions/sources/#{source_slug}")}
  end

  @impl true
  def handle_event("toggle_source", %{"source" => source}, socket) do
    expanded_sources =
      if MapSet.member?(socket.assigns.expanded_sources, source) do
        MapSet.delete(socket.assigns.expanded_sources, source)
      else
        MapSet.put(socket.assigns.expanded_sources, source)
      end

    {:noreply, assign(socket, :expanded_sources, expanded_sources)}
  end

  # Load list of workers with metrics
  defp load_workers(socket) do
    workers = JobExecutionSummaries.list_workers()
    assign(socket, :workers, workers)
  end

  # Load recent executions with filters
  defp load_recent_executions(socket) do
    opts = [
      limit: socket.assigns.limit,
      worker: socket.assigns.selected_worker,
      state: socket.assigns.state_filter,
      error_category: socket.assigns.error_category_filter
    ]

    recent_executions = JobExecutionSummaries.list_summaries(opts)
    assign(socket, :recent_executions, recent_executions)
  end

  # Load system-wide metrics
  defp load_system_metrics(socket) do
    metrics = JobExecutionSummaries.get_system_metrics(socket.assigns.time_range)
    assign(socket, :system_metrics, metrics)
  end

  # Load timeline data for visualization
  defp load_timeline_data(socket) do
    timeline = JobExecutionSummaries.get_execution_timeline(socket.assigns.time_range)
    assign(socket, :timeline, timeline)
  end

  # Load per-scraper metrics
  defp load_scraper_metrics(socket) do
    scraper_metrics = JobExecutionSummaries.get_scraper_metrics(socket.assigns.time_range)
    assign(socket, :scraper_metrics, scraper_metrics)
  end

  # Load silent failure detection data
  defp load_silent_failures(socket) do
    silent_failure_counts =
      JobExecutionSummaries.get_silent_failure_counts(socket.assigns.time_range)

    total_silent_failures =
      Enum.reduce(silent_failure_counts, 0, fn sf, acc -> acc + sf.silent_failure_count end)

    socket
    |> assign(:silent_failure_counts, silent_failure_counts)
    |> assign(:total_silent_failures, total_silent_failures)
  end

  # Load error category breakdown data
  defp load_error_category_breakdown(socket) do
    error_breakdown =
      JobExecutionSummaries.get_error_category_breakdown(socket.assigns.time_range)

    total_errors = Enum.reduce(error_breakdown, 0, fn eb, acc -> acc + eb.count end)

    socket
    |> assign(:error_breakdown, error_breakdown)
    |> assign(:total_errors, total_errors)
  end

  # Get worker display name with source context
  # Format: "source → JobType" (e.g., "week_pl → SyncJob")
  defp worker_name(worker) do
    parts = String.split(worker, ".")

    case parts do
      # Standard format: EventasaurusDiscovery.Sources.{Source}.Jobs.{JobType}
      parts when length(parts) >= 5 ->
        source = parts |> Enum.at(-3) |> Macro.underscore()
        job = List.last(parts)
        "#{source} → #{job}"

      # Fallback: just show job name if format doesn't match
      _ ->
        List.last(parts)
    end
  end

  # Format scraper name for display
  # "cinema_city" -> "Cinema City"
  defp format_scraper_name(scraper_slug) do
    scraper_slug
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  # Extract source name from worker module
  # "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob" -> "cinema_city"
  defp extract_source_from_worker(worker) do
    parts = String.split(worker, ".")

    case parts do
      parts when length(parts) >= 5 ->
        parts |> Enum.at(-3) |> Macro.underscore()

      _ ->
        "other"
    end
  end

  # Group workers by source
  defp group_workers_by_source(workers) do
    workers
    |> Enum.group_by(&extract_source_from_worker(&1.worker))
    |> Enum.map(fn {source, workers} ->
      total_executions = Enum.sum(Enum.map(workers, & &1.total_executions))
      %{source: source, workers: workers, total_executions: total_executions}
    end)
    |> Enum.sort_by(& &1.total_executions, :desc)
  end

  # Get badge class for job state
  defp state_badge_class(state) do
    case state do
      "completed" -> "bg-green-100 text-green-800"
      "discarded" -> "bg-red-100 text-red-800"
      "retryable" -> "bg-yellow-100 text-yellow-800"
      "cancelled" -> "bg-gray-100 text-gray-800"
      _ -> "bg-blue-100 text-blue-800"
    end
  end

  # Get badge class for error category
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
  defp format_error_category(error_category) when is_binary(error_category) do
    error_category
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_error_category(_), do: nil

  # Extract error information from job results
  defp extract_error_info(job) do
    results = job.results || %{}

    %{
      category: get_in(results, ["error_category"]),
      message: get_in(results, ["error_message"])
    }
  end

  # Format duration in human-readable form
  defp format_duration(nil), do: "N/A"

  defp format_duration(%Decimal{} = ms) do
    ms |> Decimal.to_float() |> format_duration()
  end

  defp format_duration(ms) when is_float(ms) and ms < 1000 do
    "#{Float.round(ms, 0)}ms"
  end

  defp format_duration(ms) when is_float(ms) and ms < 60_000 do
    seconds = Float.round(ms / 1000, 1)
    "#{seconds}s"
  end

  defp format_duration(ms) when is_float(ms) do
    minutes = trunc(ms / 60_000)
    seconds = trunc(:erlang.rem(trunc(ms), 60_000) / 1000)
    "#{minutes}m #{seconds}s"
  end

  defp format_duration(ms) when is_integer(ms) and ms < 1000, do: "#{ms}ms"

  defp format_duration(ms) when is_integer(ms) and ms < 60_000 do
    seconds = Float.round(ms / 1000, 1)
    "#{seconds}s"
  end

  defp format_duration(ms) when is_integer(ms) do
    minutes = div(ms, 60_000)
    seconds = div(rem(ms, 60_000), 1000)
    "#{minutes}m #{seconds}s"
  end

  # Format timestamp as relative time
  defp format_relative_time(nil), do: "N/A"

  defp format_relative_time(datetime) do
    diff_seconds = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff_seconds < 60 -> "#{diff_seconds}s ago"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86_400 -> "#{div(diff_seconds, 3600)}h ago"
      true -> "#{div(diff_seconds, 86_400)}d ago"
    end
  end

  # Format number with commas for readability
  defp format_number(nil), do: "0"
  defp format_number(num) when is_float(num), do: format_number(trunc(num))

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  # Format percentage
  defp format_percentage(nil), do: "0%"
  defp format_percentage(value) when is_float(value), do: "#{value}%"
  defp format_percentage(value) when is_integer(value), do: "#{value}%"

  # Get time range label
  defp time_range_label(24), do: "Last 24 hours"
  defp time_range_label(168), do: "Last 7 days"
  defp time_range_label(720), do: "Last 30 days"
  defp time_range_label(_), do: "Custom range"

  # Format timeline bucket time
  defp format_timeline_time(datetime, time_range) when time_range <= 48 do
    Calendar.strftime(datetime, "%I:%M %p")
  end

  defp format_timeline_time(datetime, _time_range) do
    Calendar.strftime(datetime, "%b %d")
  end

  # Get role badge class and label
  defp role_badge(job) do
    role = get_in(job.results, ["job_role"]) || "unknown"

    case role do
      "coordinator" -> {"bg-purple-100 text-purple-800", "Coordinator"}
      "worker" -> {"bg-blue-100 text-blue-800", "Worker"}
      "processor" -> {"bg-green-100 text-green-800", "Processor"}
      _ -> {"bg-gray-100 text-gray-800", "Unknown"}
    end
  end

  # Get entity type label if available
  defp entity_type_label(job) do
    case get_in(job.results, ["entity_type"]) do
      nil -> nil
      "city" -> "City"
      "country" -> "Country"
      "venue" -> "Venue"
      "event" -> "Event"
      "movie" -> "Movie"
      other -> String.capitalize(other)
    end
  end

  # Extract key metrics from job results
  defp extract_metrics(job) do
    results = job.results || %{}

    metrics =
      [
        {get_in(results, ["cities_queued"]), "cities queued"},
        {get_in(results, ["countries_queued"]), "countries queued"},
        {get_in(results, ["total_queued"]), "jobs queued"},
        {get_in(results, ["images_fetched"]), "images"},
        {get_in(results, ["categories_refreshed"]), "categories"},
        {get_in(results, ["movies_scheduled"]), "movies scheduled"},
        {get_in(results, ["showtimes_count"]), "showtimes"},
        {get_in(results, ["age_days"]), "days old"}
      ]
      |> Enum.reject(fn {value, _label} -> is_nil(value) or value == 0 end)

    # Add skip reason if present
    if get_in(results, ["skipped"]) == true do
      reason = get_in(results, ["reason"]) || "unknown"
      metrics ++ [{reason, "skip reason"}]
    else
      metrics
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Header -->
      <div class="md:flex md:items-center md:justify-between mb-8">
        <div class="flex-1 min-w-0">
          <h1 class="text-3xl font-bold text-gray-900">
            Job Execution Monitor
          </h1>
          <p class="mt-2 text-sm text-gray-600">
            Monitor Oban job executions across all workers
          </p>
        </div>
        <div class="mt-4 flex gap-3 md:mt-0 md:ml-4">
          <select
            phx-change="change_time_range"
            name="time_range"
            class="rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 text-sm"
          >
            <option value="24" selected={@time_range == 24}>Last 24 hours</option>
            <option value="168" selected={@time_range == 168}>Last 7 days</option>
            <option value="720" selected={@time_range == 720}>Last 30 days</option>
          </select>
          <button
            type="button"
            phx-click="refresh"
            class="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
          >
            🔄 Refresh
          </button>
        </div>
      </div>

      <!-- System Metrics Summary Cards -->
      <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-5 mb-8">
        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-1">
                <dt class="text-sm font-medium text-gray-500 truncate">
                  Total Jobs
                </dt>
                <dd class="mt-1 text-3xl font-semibold text-gray-900">
                  <%= format_number(@system_metrics.total_jobs) %>
                </dd>
              </div>
            </div>
          </div>
        </div>

        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-1">
                <dt class="text-sm font-medium text-gray-500 truncate">
                  Pipeline Health
                </dt>
                <dd class="mt-1 text-3xl font-semibold text-blue-600">
                  <%= format_percentage(@system_metrics.pipeline_health) %>
                </dd>
              </div>
            </div>
            <div class="mt-2 text-xs text-gray-500">
              <%= format_number(@system_metrics.completed) %> completed, <%= format_number(@system_metrics.cancelled) %> skipped
            </div>
          </div>
        </div>

        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-1">
                <dt class="text-sm font-medium text-gray-500 truncate">
                  Match Rate
                </dt>
                <dd class="mt-1 text-3xl font-semibold text-green-600">
                  <%= format_percentage(@system_metrics.match_rate) %>
                </dd>
              </div>
            </div>
            <div class="mt-2 text-xs text-gray-500">
              Data processing success
            </div>
          </div>
        </div>

        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-1">
                <dt class="text-sm font-medium text-gray-500 truncate">
                  Error Rate
                </dt>
                <dd class="mt-1 text-3xl font-semibold text-red-600">
                  <%= format_percentage(@system_metrics.error_rate) %>
                </dd>
              </div>
            </div>
            <div class="mt-2 text-xs text-gray-500">
              <%= format_number(@system_metrics.failed + @system_metrics.retryable) %> real errors
            </div>
          </div>
        </div>

        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="flex-1">
                <dt class="text-sm font-medium text-gray-500 truncate">
                  Avg Duration
                </dt>
                <dd class="mt-1 text-3xl font-semibold text-gray-900">
                  <%= format_duration(@system_metrics.avg_duration_ms) %>
                </dd>
              </div>
            </div>
            <div class="mt-2 text-xs text-gray-500">
              <%= @system_metrics.unique_workers %> active workers
            </div>
          </div>
        </div>
      </div>

      <!-- Error Category Breakdown -->
      <%= if @total_errors > 0 do %>
        <div class="bg-white shadow rounded-lg mb-8">
          <div class="px-4 py-5 sm:p-6">
            <h2 class="text-lg font-medium text-gray-900 mb-4">
              Error Category Breakdown
              <span class="text-sm font-normal text-gray-500">
                (<%= @total_errors %> total errors in <%= time_range_label(@time_range) %>)
              </span>
            </h2>

            <%= if Enum.empty?(@error_breakdown) do %>
              <div class="text-center py-8 text-gray-500">No error data available</div>
            <% else %>
              <div class="space-y-3">
                <%= for error_cat <- @error_breakdown do %>
                  <% percentage = Float.round(error_cat.count / @total_errors * 100, 1) %>
                  <div>
                    <div class="flex items-center justify-between mb-1">
                      <span class={"inline-flex px-2 py-1 text-xs font-semibold rounded-full " <> error_category_badge_class(error_cat.error_category)}>
                        <%= format_error_category(error_cat.error_category) %>
                      </span>
                      <span class="text-sm text-gray-600">
                        <%= format_number(error_cat.count) %> (<%= percentage %>%)
                      </span>
                    </div>
                    <div class="w-full bg-gray-200 rounded-full h-2">
                      <div
                        class={"h-2 rounded-full " <> String.replace(error_category_badge_class(error_cat.error_category), "text-", "bg-") |> String.replace("-100", "-500")}
                        style={"width: #{percentage}%"}
                      >
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- Execution Timeline -->
      <div class="bg-white shadow rounded-lg mb-8">
        <div class="px-4 py-5 sm:p-6">
          <h2 class="text-lg font-medium text-gray-900 mb-4">
            Execution Timeline
            <span class="text-sm font-normal text-gray-500">
              (<%= time_range_label(@time_range) %>)
            </span>
          </h2>

          <%= if Enum.empty?(@timeline) do %>
            <div class="text-center py-8 text-gray-500">No timeline data available</div>
          <% else %>
            <div class="space-y-2">
              <%= for bucket <- @timeline do %>
                <div class="flex items-center gap-2">
                  <div class="w-24 text-xs text-gray-500 flex-shrink-0">
                    <%= format_timeline_time(bucket.time_bucket, @time_range) %>
                  </div>
                  <div class="flex-1 flex gap-1">
                    <div
                      class="bg-green-500 h-8 flex items-center justify-center text-white text-xs font-medium rounded-l"
                      style={"width: #{if bucket.total > 0, do: Float.round(bucket.completed / bucket.total * 100, 1), else: 0}%"}
                      title={"Completed: #{bucket.completed}"}
                    >
                      <%= if bucket.completed > 0, do: bucket.completed, else: "" %>
                    </div>
                    <div
                      class="bg-red-500 h-8 flex items-center justify-center text-white text-xs font-medium rounded-r"
                      style={"width: #{if bucket.total > 0, do: Float.round(bucket.failed / bucket.total * 100, 1), else: 0}%"}
                      title={"Failed: #{bucket.failed}"}
                    >
                      <%= if bucket.failed > 0, do: bucket.failed, else: "" %>
                    </div>
                  </div>
                  <div class="w-16 text-xs text-gray-500 text-right flex-shrink-0">
                    <%= bucket.total %> total
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Per-Scraper Metrics -->
      <div class="bg-white shadow rounded-lg mb-8">
        <div class="px-4 py-5 sm:p-6">
          <h2 class="text-lg font-medium text-gray-900 mb-4">Scraper Metrics</h2>

          <%= if Enum.empty?(@scraper_metrics) do %>
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
                      Job Types
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Total Executions
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Pipeline Health
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Match Rate
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Avg Duration
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Completed
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Skipped
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Failed
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-gray-200">
                  <%= for scraper <- @scraper_metrics do %>
                    <tr class="hover:bg-gray-50 cursor-pointer" phx-click="navigate_to_pipeline" phx-value-source={scraper.scraper_name}>
                      <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                        <%= format_scraper_name(scraper.scraper_name) %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                          <%= scraper.job_type_count %> stages
                        </span>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        <%= format_number(scraper.total_executions) %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <span class={"inline-flex px-2 py-1 text-xs font-semibold rounded-full " <> if scraper.pipeline_health >= 95, do: "bg-blue-100 text-blue-800", else: if(scraper.pipeline_health >= 85, do: "bg-yellow-100 text-yellow-800", else: "bg-red-100 text-red-800")}>
                          <%= format_percentage(scraper.pipeline_health) %>
                        </span>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        <span class={"inline-flex px-2 py-1 text-xs font-semibold rounded-full " <> if scraper.match_rate >= 70, do: "bg-green-100 text-green-800", else: if(scraper.match_rate >= 50, do: "bg-yellow-100 text-yellow-800", else: "bg-red-100 text-red-800")}>
                          <%= format_percentage(scraper.match_rate) %>
                        </span>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        <%= format_duration(scraper.avg_duration_ms) %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-green-600">
                        <%= format_number(scraper.completed) %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        <%= format_number(scraper.cancelled) %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-red-600">
                        <%= format_number(scraper.failed) %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm">
                        <.link
                          navigate={~p"/admin/job-executions/sources/#{scraper.scraper_name}"}
                          class="inline-flex items-center px-3 py-1.5 border border-transparent text-xs font-medium rounded-md text-blue-700 bg-blue-100 hover:bg-blue-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                          onclick="event.stopPropagation()"
                        >
                          View Pipeline →
                        </.link>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Silent Failures Alert -->
      <%= if @total_silent_failures > 0 do %>
        <div class="bg-yellow-50 border border-yellow-200 shadow rounded-lg mb-8">
          <div class="px-4 py-5 sm:p-6">
            <div class="flex items-center mb-4">
              <div class="flex-shrink-0">
                <span class="text-2xl">⚠️</span>
              </div>
              <div class="ml-3">
                <h2 class="text-lg font-medium text-yellow-800">
                  Silent Failures Detected
                </h2>
                <p class="mt-1 text-sm text-yellow-700">
                  <%= @total_silent_failures %> job(s) completed successfully but produced no output
                </p>
              </div>
            </div>

            <%= if Enum.empty?(@silent_failure_counts) do %>
              <div class="text-center py-4 text-yellow-700">No silent failures detected</div>
            <% else %>
              <div class="overflow-x-auto">
                <table class="min-w-full divide-y divide-yellow-200">
                  <thead class="bg-yellow-100">
                    <tr>
                      <th class="px-6 py-3 text-left text-xs font-medium text-yellow-800 uppercase">
                        Scraper
                      </th>
                      <th class="px-6 py-3 text-left text-xs font-medium text-yellow-800 uppercase">
                        Silent Failures
                      </th>
                      <th class="px-6 py-3 text-left text-xs font-medium text-yellow-800 uppercase">
                        Example Job
                      </th>
                    </tr>
                  </thead>
                  <tbody class="bg-white divide-y divide-yellow-200">
                    <%= for failure <- @silent_failure_counts do %>
                      <tr class="hover:bg-yellow-50">
                        <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                          <%= failure.scraper_name %>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                          <span class="inline-flex px-2 py-1 text-xs font-semibold rounded-full bg-yellow-100 text-yellow-800">
                            <%= format_number(failure.silent_failure_count) %>
                          </span>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                          <a
                            href={"/admin/oban/#{failure.example_job_id}"}
                            class="text-blue-600 hover:text-blue-800"
                          >
                            #<%= failure.example_job_id %>
                          </a>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- Workers Summary -->
      <div class="bg-white shadow rounded-lg mb-8">
        <div class="px-4 py-5 sm:p-6">
          <h2 class="text-lg font-medium text-gray-900 mb-4">Workers by Source</h2>

          <div class="space-y-3">
            <!-- All Workers Option -->
            <button
              type="button"
              phx-click="select_worker"
              phx-value-worker="all"
              class={"w-full text-left px-4 py-3 rounded-lg border transition-colors " <> if(@selected_worker == nil, do: "border-blue-500 bg-blue-50", else: "border-gray-200 hover:bg-gray-50")}
            >
              <div class="flex items-center justify-between">
                <span class="font-medium text-gray-900">All Workers</span>
                <span class="text-sm text-gray-500">
                  <%= Enum.sum(Enum.map(@workers, & &1.total_executions)) %> total
                </span>
              </div>
            </button>

            <!-- Workers Grouped by Source -->
            <%= for source_group <- group_workers_by_source(@workers) do %>
              <% is_expanded = MapSet.member?(@expanded_sources, source_group.source) %>

              <div class="border border-gray-200 rounded-lg overflow-hidden">
                <!-- Source Header (Collapsible) -->
                <button
                  type="button"
                  phx-click="toggle_source"
                  phx-value-source={source_group.source}
                  class="w-full text-left px-4 py-3 bg-gray-50 hover:bg-gray-100 transition-colors flex items-center justify-between"
                >
                  <div class="flex items-center gap-2">
                    <span class="text-sm"><%= if is_expanded, do: "▼", else: "▶" %></span>
                    <span class="font-semibold text-gray-900">
                      <%= format_scraper_name(source_group.source) %>
                    </span>
                    <span class="text-xs text-gray-500">
                      (<%= length(source_group.workers) %> workers)
                    </span>
                  </div>
                  <div class="flex items-center gap-4">
                    <span class="text-sm text-gray-600">
                      <%= format_number(source_group.total_executions) %> total runs
                    </span>
                    <.link
                      navigate={~p"/admin/job-executions/sources/#{source_group.source}"}
                      class="inline-flex items-center px-2.5 py-1 border border-transparent text-xs font-medium rounded text-blue-700 bg-blue-100 hover:bg-blue-200"
                      onclick="event.stopPropagation()"
                    >
                      View Pipeline →
                    </.link>
                  </div>
                </button>

                <!-- Workers in Source (Collapsible Content) -->
                <%= if is_expanded do %>
                  <div class="border-t border-gray-200">
                    <%= for worker <- source_group.workers do %>
                      <button
                        type="button"
                        phx-click="select_worker"
                        phx-value-worker={worker.worker}
                        class={"w-full text-left px-4 py-3 border-b border-gray-100 last:border-b-0 transition-colors " <> if(@selected_worker == worker.worker, do: "bg-blue-50", else: "hover:bg-gray-50")}
                      >
                        <div class="flex items-center justify-between">
                          <span class="text-sm font-medium text-gray-900">
                            <%= String.split(worker.worker, ".") |> List.last() %>
                          </span>
                          <div class="flex items-center gap-3">
                            <span class="text-sm text-gray-500">
                              <%= worker.total_executions %> runs
                            </span>
                            <span class="text-xs text-gray-400">
                              <%= format_relative_time(worker.last_execution) %>
                            </span>
                          </div>
                        </div>
                        <div class="mt-1 text-xs text-gray-500 flex items-center justify-between">
                          <span class="truncate max-w-md"><%= worker.worker %></span>
                          <.link
                            navigate={~p"/admin/job-executions/#{URI.encode_www_form(worker.worker)}"}
                            class="text-blue-600 hover:text-blue-800 text-xs font-medium inline-flex items-center gap-1"
                            onclick="event.stopPropagation()"
                          >
                            View Details →
                          </.link>
                        </div>
                      </button>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Filters -->
      <div class="bg-white shadow rounded-lg mb-8">
        <div class="px-4 py-5 sm:p-6">
          <h2 class="text-lg font-medium text-gray-900 mb-4">Filters</h2>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">State</label>
              <select
                phx-change="filter_state"
                name="state"
                class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
              >
                <option value="all" selected={@state_filter == nil}>All States</option>
                <option value="completed" selected={@state_filter == "completed"}>
                  Completed
                </option>
                <option value="discarded" selected={@state_filter == "discarded"}>
                  Discarded
                </option>
                <option value="retryable" selected={@state_filter == "retryable"}>
                  Retryable
                </option>
                <option value="cancelled" selected={@state_filter == "cancelled"}>
                  Cancelled
                </option>
              </select>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Error Category</label>
              <select
                phx-change="filter_error_category"
                name="error_category"
                class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
              >
                <option value="all" selected={@error_category_filter == nil}>All Categories</option>
                <option value="validation_error" selected={@error_category_filter == "validation_error"}>
                  Validation Error
                </option>
                <option value="parsing_error" selected={@error_category_filter == "parsing_error"}>
                  Parsing Error
                </option>
                <option value="data_quality_error" selected={@error_category_filter == "data_quality_error"}>
                  Data Quality Error
                </option>
                <option value="data_integrity_error" selected={@error_category_filter == "data_integrity_error"}>
                  Data Integrity Error
                </option>
                <option value="dependency_error" selected={@error_category_filter == "dependency_error"}>
                  Dependency Error
                </option>
                <option value="network_error" selected={@error_category_filter == "network_error"}>
                  Network Error
                </option>
                <option value="rate_limit_error" selected={@error_category_filter == "rate_limit_error"}>
                  Rate Limit Error
                </option>
                <option value="authentication_error" selected={@error_category_filter == "authentication_error"}>
                  Authentication Error
                </option>
                <option value="geocoding_error" selected={@error_category_filter == "geocoding_error"}>
                  Geocoding Error
                </option>
                <option value="venue_error" selected={@error_category_filter == "venue_error"}>
                  Venue Error
                </option>
                <option value="performer_error" selected={@error_category_filter == "performer_error"}>
                  Performer Error
                </option>
                <option value="tmdb_error" selected={@error_category_filter == "tmdb_error"}>
                  TMDB Error
                </option>
                <option value="uncategorized_error" selected={@error_category_filter == "uncategorized_error"}>
                  Uncategorized Error
                </option>
              </select>
            </div>
          </div>
        </div>
      </div>

      <!-- Recent Executions -->
      <div class="bg-white shadow rounded-lg">
        <div class="px-4 py-5 sm:p-6">
          <h2 class="text-lg font-medium text-gray-900 mb-4">
            Recent Executions
            <%= if @selected_worker do %>
              <span class="text-sm font-normal text-gray-500">
                for <%= worker_name(@selected_worker) %>
              </span>
            <% end %>
          </h2>

          <%= if @loading do %>
            <div class="text-center py-8 text-gray-500">Loading...</div>
          <% else %>
            <%= if Enum.empty?(@recent_executions) do %>
              <div class="text-center py-8 text-gray-500">No job executions found</div>
            <% else %>
              <div class="overflow-x-auto">
                <table class="min-w-full divide-y divide-gray-200">
                  <thead class="bg-gray-50">
                    <tr>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Worker
                      </th>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        State
                      </th>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Error
                      </th>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Duration
                      </th>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Attempted
                      </th>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Job ID
                      </th>
                      <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Lineage
                      </th>
                    </tr>
                  </thead>
                  <tbody class="bg-white divide-y divide-gray-200">
                    <%= for execution <- @recent_executions do %>
                      <% error_info = extract_error_info(execution) %>
                      <tr class="hover:bg-gray-50">
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                          <%= worker_name(execution.worker) %>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                          <span class={"inline-flex px-2 py-1 text-xs font-semibold rounded-full " <> state_badge_class(execution.state)}>
                            <%= execution.state %>
                          </span>
                        </td>
                        <td class="px-6 py-4 text-sm max-w-xs">
                          <%= if error_info.category do %>
                            <div class="space-y-1">
                              <span class={"inline-flex px-2 py-1 text-xs font-semibold rounded-full " <> error_category_badge_class(error_info.category)}>
                                <%= format_error_category(error_info.category) %>
                              </span>
                              <%= if error_info.message do %>
                                <div class="text-xs text-gray-500 truncate" title={error_info.message}>
                                  <%= error_info.message %>
                                </div>
                              <% end %>
                            </div>
                          <% else %>
                            <%= if execution.error do %>
                              <div class="text-xs text-gray-500 truncate" title={execution.error}>
                                <%= execution.error %>
                              </div>
                            <% else %>
                              <span class="text-gray-400">—</span>
                            <% end %>
                          <% end %>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                          <%= format_duration(execution.duration_ms) %>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                          <%= format_relative_time(execution.attempted_at) %>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                          <a
                            href={"/admin/oban/#{execution.job_id}"}
                            class="text-blue-600 hover:text-blue-800"
                          >
                            #<%= execution.job_id %>
                          </a>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm">
                          <button
                            type="button"
                            phx-click="show_lineage"
                            phx-value-job-id={execution.id}
                            class="inline-flex items-center px-2.5 py-1.5 border border-gray-300 shadow-sm text-xs font-medium rounded text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                          >
                            🌳 View Tree
                          </button>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>

      <!-- Lineage Modal -->
      <%= if @lineage_modal_open and @selected_job_lineage do %>
        <.modal
          id="lineage-modal"
          show
          on_cancel={JS.push("close_lineage")}
        >
          <:title>
            Job Lineage Tree
            <span class="text-sm font-normal text-gray-500">
              (Job #<%= @selected_job_lineage.job.job_id %>)
            </span>
          </:title>

          <div class="space-y-6">
            <!-- Ancestors (Parent Chain) -->
            <%= if length(@selected_job_lineage.ancestors) > 0 do %>
              <div>
                <h3 class="text-sm font-medium text-gray-700 mb-3">
                  ⬆️ Parent Chain (<%= length(@selected_job_lineage.ancestors) %>)
                </h3>
                <div class="space-y-2 pl-4 border-l-2 border-gray-200">
                  <%= for ancestor <- Enum.reverse(@selected_job_lineage.ancestors) do %>
                    <%= render_job_node(ancestor, "ancestor") %>
                  <% end %>
                </div>
              </div>
            <% else %>
              <div class="text-sm text-gray-500">
                No parent jobs (this is a root job)
              </div>
            <% end %>

            <!-- Current Job -->
            <div>
              <h3 class="text-sm font-medium text-gray-700 mb-3">
                🎯 Current Job
              </h3>
              <%= render_job_node(@selected_job_lineage.job, "current") %>
            </div>

            <!-- Descendants (Children) -->
            <%= if length(@selected_job_lineage.descendants) > 0 do %>
              <div>
                <h3 class="text-sm font-medium text-gray-700 mb-3">
                  ⬇️ Child Jobs (<%= length(@selected_job_lineage.descendants) %>)
                </h3>
                <div class="space-y-2 pl-4 border-l-2 border-gray-200">
                  <%= for descendant <- @selected_job_lineage.descendants do %>
                    <%= render_job_node(descendant, "descendant") %>
                  <% end %>
                </div>
              </div>
            <% else %>
              <div class="text-sm text-gray-500">
                No child jobs spawned
              </div>
            <% end %>
          </div>
        </.modal>
      <% end %>
    </div>
    """
  end

  # Render a job node in the lineage tree
  defp render_job_node(job, node_type) do
    # Convert struct to map and add node_type
    job_map = if is_struct(job), do: Map.from_struct(job), else: job
    assigns = Map.put(job_map, :node_type, node_type)

    ~H"""
    <div class={
      "p-3 rounded-lg border " <>
        case @node_type do
          "current" -> "border-blue-500 bg-blue-50"
          "ancestor" -> "border-gray-300 bg-white"
          "descendant" -> "border-gray-300 bg-white"
        end
    }>
      <div class="flex items-start justify-between">
        <div class="flex-1">
          <div class="flex items-center gap-2 mb-1">
            <span class="text-sm font-medium text-gray-900">
              <%= worker_name(@worker) %>
            </span>
            <span class={"inline-flex px-2 py-0.5 text-xs font-semibold rounded-full " <> state_badge_class(@state)}>
              <%= @state %>
            </span>
            <%= if @results do %>
              <% job_struct = struct(EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary, Map.delete(assigns, :node_type)) %>
              <% {badge_class, role_label} = role_badge(job_struct) %>
              <span class={"inline-flex px-2 py-0.5 text-xs font-semibold rounded-full " <> badge_class}>
                <%= role_label %>
              </span>
              <%= if entity_type = entity_type_label(job_struct) do %>
                <span class="inline-flex px-2 py-0.5 text-xs font-semibold rounded-full bg-gray-100 text-gray-700">
                  <%= entity_type %>
                </span>
              <% end %>
            <% end %>
          </div>

          <div class="text-xs text-gray-500 mb-1">
            Job #<%= @job_id %> • <%= format_duration(@duration_ms) %> • <%= format_relative_time(@attempted_at) %>
          </div>

          <!-- Metrics -->
          <%= if @results do %>
            <% job_struct = struct(EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary, Map.delete(assigns, :node_type)) %>
            <% metrics = extract_metrics(job_struct) %>
            <%= if length(metrics) > 0 do %>
              <div class="flex flex-wrap gap-2 mt-2">
                <%= for {value, label} <- metrics do %>
                  <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-800">
                    <%= if is_binary(value) do %>
                      <%= value %>
                    <% else %>
                      <%= format_number(value) %>
                    <% end %>
                    <span class="ml-1 text-gray-500"><%= label %></span>
                  </span>
                <% end %>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
