defmodule EventasaurusWeb.Admin.SourcePipelineMonitorLive do
  @moduledoc """
  Source-specific pipeline monitor showing job execution flow and metrics.

  Displays:
  - Visual pipeline flow with stage success rates
  - Error breakdown by pipeline stage
  - Recent pipeline runs with expandable details
  - Overall pipeline metrics
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.JobExecutionSummaries

  @impl true
  def mount(%{"source_slug" => source_slug}, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    # Normalize kebab-case to snake_case for backend compatibility
    source_slug = String.replace(source_slug, "-", "_")

    pipeline_metrics = JobExecutionSummaries.get_source_pipeline_metrics(source_slug, 24)
    error_breakdown = JobExecutionSummaries.get_source_error_breakdown(source_slug, 24)
    recent_runs = JobExecutionSummaries.get_source_recent_pipeline_runs(source_slug, 20)

    # Calculate overall metrics
    total_runs = Enum.sum(Enum.map(pipeline_metrics, & &1.total_runs))
    successful_runs = Enum.sum(Enum.map(pipeline_metrics, & &1.completed))
    cancelled_failed_runs = Enum.sum(Enum.map(pipeline_metrics, & &1.cancelled_failed))
    cancelled_expected_runs = Enum.sum(Enum.map(pipeline_metrics, & &1.cancelled_expected))
    cancelled_runs = cancelled_failed_runs + cancelled_expected_runs
    failed_runs = Enum.sum(Enum.map(pipeline_metrics, & &1.failed))
    retryable_runs = Enum.sum(Enum.map(pipeline_metrics, & &1.retryable))

    # Pipeline Health: (completed + cancelled_expected) / total
    # Only count intentional cancellations as healthy, not processing failures
    overall_pipeline_health =
      if total_runs > 0,
        do: (successful_runs + cancelled_expected_runs) / total_runs * 100,
        else: 0.0

    # Processing Failure Rate: (cancelled_failed + failed + retryable) / total
    # Includes retryable jobs since they've failed at least once
    overall_processing_failure_rate =
      if total_runs > 0,
        do: (cancelled_failed_runs + failed_runs + retryable_runs) / total_runs * 100,
        else: 0.0

    # Match Rate: completed / (completed + cancelled_expected)
    overall_match_rate =
      if successful_runs + cancelled_expected_runs > 0 do
        successful_runs / (successful_runs + cancelled_expected_runs) * 100
      else
        0.0
      end

    avg_duration =
      if total_runs > 0 do
        total_duration =
          Enum.sum(
            Enum.map(pipeline_metrics, fn m ->
              (m.avg_duration_ms || 0) * m.total_runs
            end)
          )

        total_duration / total_runs
      else
        0.0
      end

    {:ok,
     assign(socket,
       source_slug: source_slug,
       pipeline_metrics: pipeline_metrics,
       error_breakdown: error_breakdown,
       recent_runs: recent_runs,
       total_runs: total_runs,
       successful_runs: successful_runs,
       cancelled_failed_runs: cancelled_failed_runs,
       cancelled_expected_runs: cancelled_expected_runs,
       cancelled_runs: cancelled_runs,
       failed_runs: failed_runs,
       retryable_runs: retryable_runs,
       overall_pipeline_health: overall_pipeline_health,
       overall_processing_failure_rate: overall_processing_failure_rate,
       overall_match_rate: overall_match_rate,
       avg_duration_ms: avg_duration,
       expanded_runs: MapSet.new(),
       page_title: "#{format_source_name(source_slug)} Pipeline Monitor"
     )}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()

    source_slug = socket.assigns.source_slug
    pipeline_metrics = JobExecutionSummaries.get_source_pipeline_metrics(source_slug, 24)
    error_breakdown = JobExecutionSummaries.get_source_error_breakdown(source_slug, 24)
    recent_runs = JobExecutionSummaries.get_source_recent_pipeline_runs(source_slug, 20)

    total_runs = Enum.sum(Enum.map(pipeline_metrics, & &1.total_runs))
    successful_runs = Enum.sum(Enum.map(pipeline_metrics, & &1.completed))
    cancelled_failed_runs = Enum.sum(Enum.map(pipeline_metrics, & &1.cancelled_failed))
    cancelled_expected_runs = Enum.sum(Enum.map(pipeline_metrics, & &1.cancelled_expected))
    cancelled_runs = cancelled_failed_runs + cancelled_expected_runs
    failed_runs = Enum.sum(Enum.map(pipeline_metrics, & &1.failed))
    retryable_runs = Enum.sum(Enum.map(pipeline_metrics, & &1.retryable))

    # Pipeline Health: (completed + cancelled_expected) / total
    # Only count intentional cancellations as healthy, not processing failures
    overall_pipeline_health =
      if total_runs > 0,
        do: (successful_runs + cancelled_expected_runs) / total_runs * 100,
        else: 0.0

    # Processing Failure Rate: (cancelled_failed + failed + retryable) / total
    # Includes retryable jobs since they've failed at least once
    overall_processing_failure_rate =
      if total_runs > 0,
        do: (cancelled_failed_runs + failed_runs + retryable_runs) / total_runs * 100,
        else: 0.0

    # Match Rate: completed / (completed + cancelled_expected)
    overall_match_rate =
      if successful_runs + cancelled_expected_runs > 0 do
        successful_runs / (successful_runs + cancelled_expected_runs) * 100
      else
        0.0
      end

    avg_duration =
      if total_runs > 0 do
        total_duration =
          Enum.sum(
            Enum.map(pipeline_metrics, fn m ->
              (m.avg_duration_ms || 0) * m.total_runs
            end)
          )

        total_duration / total_runs
      else
        0.0
      end

    {:noreply,
     assign(socket,
       pipeline_metrics: pipeline_metrics,
       error_breakdown: error_breakdown,
       recent_runs: recent_runs,
       total_runs: total_runs,
       successful_runs: successful_runs,
       cancelled_failed_runs: cancelled_failed_runs,
       cancelled_expected_runs: cancelled_expected_runs,
       cancelled_runs: cancelled_runs,
       failed_runs: failed_runs,
       retryable_runs: retryable_runs,
       overall_pipeline_health: overall_pipeline_health,
       overall_processing_failure_rate: overall_processing_failure_rate,
       overall_match_rate: overall_match_rate,
       avg_duration_ms: avg_duration
     )}
  end

  @impl true
  def handle_event("toggle_run", %{"run_id" => run_id}, socket) do
    expanded_runs =
      if MapSet.member?(socket.assigns.expanded_runs, run_id) do
        MapSet.delete(socket.assigns.expanded_runs, run_id)
      else
        MapSet.put(socket.assigns.expanded_runs, run_id)
      end

    {:noreply, assign(socket, :expanded_runs, expanded_runs)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Header -->
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900">
          <%= format_source_name(@source_slug) %> Pipeline Monitor
        </h1>
        <p class="mt-2 text-sm text-gray-600">
          Visual pipeline monitoring and stage-by-stage execution tracking
        </p>
      </div>

      <!-- Overall Metrics -->
      <div class="grid grid-cols-1 md:grid-cols-5 gap-6 mb-8">
        <div class="bg-white rounded-lg shadow p-6">
          <dt class="text-sm font-medium text-gray-500">Total Runs</dt>
          <dd class="mt-1 text-3xl font-semibold text-gray-900"><%= @total_runs %></dd>
        </div>

        <div class="bg-white rounded-lg shadow p-6">
          <dt class="text-sm font-medium text-gray-500">Pipeline Health</dt>
          <dd class="mt-1 text-3xl font-semibold text-blue-600">
            <%= Float.round(@overall_pipeline_health, 1) %>%
          </dd>
          <p class="mt-1 text-xs text-gray-500">
            <%= @successful_runs %> completed, <%= @cancelled_expected_runs %> expected skips
          </p>
        </div>

        <div class="bg-white rounded-lg shadow p-6">
          <dt class="text-sm font-medium text-gray-500">Processing Failures</dt>
          <dd class="mt-1 text-3xl font-semibold text-red-600">
            <%= Float.round(@overall_processing_failure_rate, 1) %>%
          </dd>
          <p class="mt-1 text-xs text-gray-500">
            <%= @cancelled_failed_runs %> failed, <%= @failed_runs %> discarded<%= if @retryable_runs > 0, do: ", #{@retryable_runs} retrying" %>
          </p>
        </div>

        <div class="bg-white rounded-lg shadow p-6">
          <dt class="text-sm font-medium text-gray-500">Match Rate</dt>
          <dd class="mt-1 text-3xl font-semibold text-green-600">
            <%= Float.round(@overall_match_rate, 1) %>%
          </dd>
          <p class="mt-1 text-xs text-gray-500">
            Data processing success
          </p>
        </div>

        <div class="bg-white rounded-lg shadow p-6">
          <dt class="text-sm font-medium text-gray-500">Avg Duration</dt>
          <dd class="mt-1 text-3xl font-semibold text-gray-900">
            <%= format_duration(@avg_duration_ms) %>
          </dd>
        </div>

        <div class="bg-white rounded-lg shadow p-6">
          <dt class="text-sm font-medium text-gray-500">Pipeline Stages</dt>
          <dd class="mt-1 text-3xl font-semibold text-gray-900">
            <%= length(@pipeline_metrics) %>
          </dd>
        </div>
      </div>

      <%= if Enum.empty?(@pipeline_metrics) do %>
        <div class="bg-yellow-50 border-l-4 border-yellow-400 p-4">
          <div class="flex">
            <div class="flex-shrink-0">
              <svg class="h-5 w-5 text-yellow-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd" />
              </svg>
            </div>
            <div class="ml-3">
              <p class="text-sm text-yellow-700">
                No pipeline data found for <%= format_source_name(@source_slug) %> in the last 24 hours.
              </p>
            </div>
          </div>
        </div>
      <% else %>
        <!-- Pipeline Visualization -->
        <div class="bg-white rounded-lg shadow p-6 mb-8">
          <h2 class="text-lg font-semibold text-gray-900 mb-6">Pipeline Flow</h2>

          <div class="flex flex-wrap gap-4 items-center">
            <%= for {stage, index} <- Enum.with_index(@pipeline_metrics) do %>
              <div class="flex items-center">
                <!-- Stage Card -->
                <div class="bg-gray-50 border-2 border-gray-200 rounded-lg p-4 min-w-[200px]">
                  <div class="flex items-center justify-between mb-2">
                    <span class="font-semibold text-gray-900"><%= stage.job_type %></span>
                    <%= status_badge(stage.pipeline_health) %>
                  </div>
                  <div class="text-sm text-gray-600 space-y-1">
                    <div><%= stage.total_runs %> runs</div>
                    <div><%= format_duration(stage.avg_duration_ms) %> avg</div>
                    <div class="text-xs">Match: <%= Float.round(stage.match_rate, 1) %>%</div>
                    <div class="text-xs text-red-600">Failures: <%= Float.round(stage.processing_failure_rate, 1) %>%</div>
                  </div>
                </div>

                <!-- Arrow between stages -->
                <%= if index < length(@pipeline_metrics) - 1 do %>
                  <div class="flex-shrink-0 mx-2 text-gray-400 text-2xl">→</div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Error Breakdown -->
        <%= if not Enum.empty?(@error_breakdown) do %>
          <div class="bg-white rounded-lg shadow p-6 mb-8">
            <h2 class="text-lg font-semibold text-gray-900 mb-4">Error Breakdown by Stage</h2>

            <div class="space-y-4">
              <%= for error <- @error_breakdown do %>
                <div class="border-l-4 border-red-400 bg-red-50 p-4">
                  <div class="flex items-start">
                    <div class="flex-1">
                      <div class="flex items-center justify-between mb-2">
                        <span class="font-medium text-gray-900"><%= error.job_type %></span>
                        <span class="text-sm text-red-600"><%= error.count %> errors</span>
                      </div>

                      <%= if error.error_category do %>
                        <div class="mt-2">
                          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800">
                            <%= format_error_category(error.error_category) %>
                          </span>
                        </div>
                      <% end %>

                      <%= if error.example_error do %>
                        <p class="mt-2 text-sm text-gray-600 font-mono bg-white p-2 rounded border border-gray-200">
                          <%= String.slice(error.example_error, 0, 200) %><%= if String.length(error.example_error) > 200, do: "..." %>
                        </p>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <!-- Recent Pipeline Runs -->
        <div class="bg-white rounded-lg shadow overflow-hidden">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">Recent Pipeline Runs</h2>
          </div>

          <div class="divide-y divide-gray-200">
            <%= for run <- @recent_runs do %>
              <% run_id = DateTime.to_unix(run.started_at) |> to_string() %>
              <% is_expanded = MapSet.member?(@expanded_runs, run_id) %>
              <div class="hover:bg-gray-50">
                <!-- Pipeline Run Header (Clickable) -->
                <button
                  type="button"
                  phx-click="toggle_run"
                  phx-value-run_id={run_id}
                  class="w-full px-6 py-4 text-left flex items-center justify-between"
                >
                  <div class="flex-1 flex items-center gap-4">
                    <span class="text-sm"><%= if is_expanded, do: "▼", else: "▶" %></span>

                    <div class="flex-1">
                      <div class="flex items-center gap-2">
                        <span class="font-medium text-gray-900">Pipeline Run</span>
                        <%= pipeline_status_badge(run.status) %>
                      </div>
                      <p class="text-sm text-gray-500 mt-1">
                        <%= format_timestamp(run.started_at) %> •
                        <%= run.total_jobs %> jobs •
                        Duration: <%= format_duration(run.total_duration_ms) %>
                      </p>
                    </div>

                    <%= if run.failed_jobs > 0 do %>
                      <div class="text-xs text-red-600 bg-red-50 px-2 py-1 rounded">
                        <%= run.failed_jobs %> failed
                      </div>
                    <% end %>
                  </div>
                </button>

                <!-- Expanded Stages -->
                <%= if is_expanded do %>
                  <div class="px-6 pb-4 bg-gray-50">
                    <div class="space-y-2">
                      <%= for stage <- run.stages do %>
                        <div class="bg-white border border-gray-200 rounded p-3">
                          <div class="flex items-center justify-between">
                            <div class="flex-1">
                              <div class="flex items-center gap-2">
                                <span class="font-medium text-sm"><%= stage.job_type %></span>
                                <%= state_badge(stage) %>
                              </div>
                              <p class="text-xs text-gray-500 mt-1">
                                <%= format_timestamp(stage.attempted_at) %> •
                                <%= format_duration(stage.duration_ms) %>
                              </p>
                            </div>
                          </div>

                          <%= if stage.error_message do %>
                            <div class="mt-2">
                              <div class="text-xs font-medium text-gray-500 mb-1">Error:</div>
                              <div class="text-xs text-red-600 font-mono bg-red-50 p-2 rounded border border-red-200">
                                <%= stage.error_message %>
                              </div>
                            </div>
                          <% end %>

                          <%= if stage.error_category do %>
                            <div class="mt-2">
                              <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800">
                                <%= format_error_category(stage.error_category) %>
                              </span>
                            </div>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>

            <%= if Enum.empty?(@recent_runs) do %>
              <div class="px-6 py-8 text-center text-gray-500">
                No recent pipeline runs found
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Private helper functions

  defp schedule_refresh do
    Process.send_after(self(), :refresh, 5000)
  end

  defp format_source_name(slug) do
    slug
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_duration(nil), do: "—"
  defp format_duration(ms) when ms < 1000, do: "#{Float.round(ms / 1, 1)}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"

  defp format_timestamp(nil), do: "—"

  defp format_timestamp(datetime) do
    Timex.from_now(datetime)
  end

  defp format_error_category(nil), do: "Unknown"

  defp format_error_category(category) do
    category
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp status_badge(health_percentage) when health_percentage >= 95 do
    assigns = %{percentage: health_percentage}

    ~H"""
    <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-green-100 text-green-800">
      <%= Float.round(@percentage, 1) %>%
    </span>
    """
  end

  defp status_badge(health_percentage) when health_percentage >= 75 do
    assigns = %{percentage: health_percentage}

    ~H"""
    <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800">
      <%= Float.round(@percentage, 1) %>%
    </span>
    """
  end

  defp status_badge(health_percentage) do
    assigns = %{percentage: health_percentage}

    ~H"""
    <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-red-100 text-red-800">
      <%= Float.round(@percentage, 1) %>%
    </span>
    """
  end

  defp state_badge(run) do
    assigns = %{state: run.state}

    cond do
      run.state == "completed" ->
        ~H"""
        <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-green-100 text-green-800">
          completed
        </span>
        """

      run.state == "discarded" ->
        ~H"""
        <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-red-100 text-red-800">
          discarded
        </span>
        """

      run.state == "retryable" ->
        ~H"""
        <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-orange-100 text-orange-800">
          retrying
        </span>
        """

      true ->
        ~H"""
        <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
          <%= @state %>
        </span>
        """
    end
  end

  defp pipeline_status_badge(status) do
    assigns = %{status: status}

    case status do
      :success ->
        ~H"""
        <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-green-100 text-green-800">
          success
        </span>
        """

      :failed ->
        ~H"""
        <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-red-100 text-red-800">
          failed
        </span>
        """

      :partial ->
        ~H"""
        <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800">
          partial
        </span>
        """
    end
  end
end
