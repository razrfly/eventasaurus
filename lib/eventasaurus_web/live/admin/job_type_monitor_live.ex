defmodule EventasaurusWeb.Admin.JobTypeMonitorLive do
  @moduledoc """
  LiveView for monitoring individual job type execution details.

  Phase 4: Individual Job Type Dashboard

  Displays detailed metrics, timeline, and execution history for a specific worker type.
  """

  use EventasaurusWeb, :live_view
  alias EventasaurusDiscovery.JobExecutionSummaries
  alias EventasaurusDiscovery.JobExecutionSummaries.Lineage

  @impl true
  def mount(%{"worker" => worker}, _session, socket) do
    socket =
      socket
      |> assign(:worker, worker)
      |> assign(:worker_display_name, format_worker_name(worker))
      # Default to 7 days
      |> assign(:time_range, 7)
      |> assign(:loading, true)
      |> load_worker_data()
      |> assign(:loading, false)
      |> assign(:show_lineage_modal, false)
      |> assign(:selected_job, nil)
      # Track which job's observability is expanded
      |> assign(:expanded_observability, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("change_time_range", %{"time_range" => time_range}, socket) do
    # Defensive parsing
    time_range_days =
      case Integer.parse(time_range) do
        {days, _} when days > 0 -> days
        _ -> socket.assigns.time_range
      end

    socket =
      socket
      |> assign(:time_range, time_range_days)
      |> assign(:loading, true)
      |> load_worker_data()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    socket =
      socket
      |> assign(:loading, true)
      |> load_worker_data()
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("show_lineage", %{"job-id" => job_id_str}, socket) do
    job_id = String.to_integer(job_id_str)
    job_tree = Lineage.get_job_tree(job_id)

    socket =
      socket
      |> assign(:show_lineage_modal, true)
      |> assign(:selected_job, job_tree)

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_lineage", _params, socket) do
    socket =
      socket
      |> assign(:show_lineage_modal, false)
      |> assign(:selected_job, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_observability", %{"job-id" => job_id_str}, socket) do
    job_id = String.to_integer(job_id_str)

    # Toggle: if already expanded, collapse it; otherwise expand it
    expanded_id = if socket.assigns.expanded_observability == job_id, do: nil, else: job_id

    socket =
      socket
      |> assign(:expanded_observability, expanded_id)

    {:noreply, socket}
  end

  # Private functions

  defp load_worker_data(socket) do
    worker = socket.assigns.worker
    time_range = socket.assigns.time_range

    # Get worker metrics for different time periods
    metrics_7d = get_worker_metrics_for_period(worker, 7)
    metrics_30d = get_worker_metrics_for_period(worker, 30)
    metrics_24h = get_worker_metrics_for_period(worker, 1)

    # Get recent executions
    recent_executions = JobExecutionSummaries.get_worker_executions(worker, time_range * 24, 50)

    # Get timeline data (daily buckets)
    timeline_data = get_timeline_data(worker, time_range)

    # Get last execution time
    last_execution = List.first(recent_executions)

    socket
    |> assign(:metrics_7d, metrics_7d)
    |> assign(:metrics_30d, metrics_30d)
    |> assign(:metrics_24h, metrics_24h)
    |> assign(:recent_executions, recent_executions)
    |> assign(:timeline_data, timeline_data)
    |> assign(:last_execution, last_execution)
  end

  defp get_worker_metrics_for_period(worker, days) do
    hours = days * 24
    JobExecutionSummaries.get_worker_metrics_for_period(worker, hours)
  end

  defp get_timeline_data(worker, days) do
    hours = days * 24
    JobExecutionSummaries.get_worker_timeline_data(worker, hours)
  end

  # Format worker module name for display
  defp format_worker_name(worker) do
    worker
    |> String.split(".")
    |> List.last()
    |> String.replace("Worker", "")
    |> String.replace("Job", "")
    |> Phoenix.Naming.humanize()
  end

  # Format job results for display based on worker type
  defp format_job_results(nil), do: "No results"

  defp format_job_results(results) when is_map(results) do
    cond do
      # Unsplash workers
      Map.has_key?(results, "images_fetched") ->
        images = results["images_fetched"] || 0
        categories = results["categories_refreshed"] || 0
        "#{images} images across #{categories} categories"

      # Movie/Cinema scrapers
      Map.has_key?(results, "showtimes_count") ->
        showtimes = results["showtimes_count"] || 0
        "#{showtimes} showtimes processed"

      # Coordinator jobs
      Map.has_key?(results, "child_jobs_scheduled") ->
        scheduled = results["child_jobs_scheduled"] || 0
        "Scheduled #{scheduled} child jobs"

      # Generic fallback
      true ->
        # Show first few key metrics (excluding observability fields for summary)
        results
        |> Enum.reject(fn {k, _v} ->
          k in [
            "job_role",
            "pipeline_id",
            "parent_job_id",
            "entity_id",
            "entity_type",
            "query_params",
            "api_response",
            "decision_context"
          ]
        end)
        |> Enum.take(3)
        |> Enum.map(fn {k, v} -> "#{Phoenix.Naming.humanize(k)}: #{v}" end)
        |> Enum.join(", ")
    end
  end

  # Check if job has Phase 2 observability data (#2332)
  defp has_observability_data?(nil), do: false

  defp has_observability_data?(results) when is_map(results) do
    Map.has_key?(results, "query_params") or
      Map.has_key?(results, "api_response") or
      Map.has_key?(results, "decision_context")
  end

  # Format observability data for display
  defp format_observability_field(nil), do: "N/A"

  defp format_observability_field(data) when is_map(data) do
    Jason.encode!(data, pretty: true)
  end

  defp format_observability_field(data), do: inspect(data)

  # Format duration for display
  defp format_duration(nil), do: "-"
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"

  defp format_duration(ms) do
    seconds = Float.round(ms / 1000, 1)
    "#{seconds}s"
  end

  # Get status badge class
  defp status_badge_class("completed"), do: "bg-green-100 text-green-800"
  defp status_badge_class("discarded"), do: "bg-red-100 text-red-800"
  defp status_badge_class("cancelled"), do: "bg-gray-100 text-gray-800"
  defp status_badge_class("retryable"), do: "bg-yellow-100 text-yellow-800"
  defp status_badge_class(_), do: "bg-blue-100 text-blue-800"

  # Calculate bar width percentage for timeline chart
  defp calculate_bar_width(_count, 0), do: 0

  defp calculate_bar_width(count, total) do
    Float.round(count / total * 100, 1)
  end
end
