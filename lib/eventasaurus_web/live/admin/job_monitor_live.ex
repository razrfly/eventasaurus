defmodule EventasaurusWeb.Admin.JobMonitorLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Monitoring

  @impl true
  def mount(_params, _session, socket) do
    socket = assign_defaults(socket)

    if connected?(socket) do
      # Auto-refresh stats every 5 minutes (reduced from 30s to lower query load)
      :timer.send_interval(300_000, self(), :refresh_stats)
      {:ok, load_stats(socket)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_stats(socket)}
  end

  @impl true
  def handle_event("toggle_expand", %{"worker" => worker}, socket) do
    expanded = socket.assigns.expanded

    new_expanded =
      if MapSet.member?(expanded, worker) do
        MapSet.delete(expanded, worker)
      else
        MapSet.put(expanded, worker)
      end

    {:noreply, assign(socket, :expanded, new_expanded)}
  end

  @impl true
  def handle_event("filter", %{"category" => category}, socket) do
    filter =
      case category do
        "all" -> :all
        "discovery" -> :discovery
        "scheduled" -> :scheduled
        "maintenance" -> :maintenance
        _ -> :all
      end

    socket
    |> assign(:filter, filter)
    |> filter_jobs()
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_info(:refresh_stats, socket) do
    {:noreply, load_stats(socket)}
  end

  # Private Functions

  defp assign_defaults(socket) do
    socket
    |> assign(:page_title, "Oban Jobs Monitor")
    |> assign(:loading, true)
    |> assign(:jobs, [])
    |> assign(:summary, nil)
    |> assign(:filter, :all)
    |> assign(:expanded, MapSet.new())
    |> assign(:last_refresh, nil)
    # Prevent SSR crash
    |> assign(:filtered_jobs, [])
  end

  defp load_stats(socket) do
    jobs = Monitoring.get_all_job_stats()
    summary = Monitoring.get_summary_stats()

    socket
    |> assign(:loading, false)
    |> assign(:jobs, jobs)
    |> assign(:summary, summary)
    |> assign(:last_refresh, DateTime.utc_now())
    |> filter_jobs()
  end

  defp filter_jobs(socket) do
    filtered =
      case socket.assigns.filter do
        :all -> socket.assigns.jobs
        filter_category -> Enum.filter(socket.assigns.jobs, &(&1.category == filter_category))
      end

    assign(socket, :filtered_jobs, filtered)
  end

  # Helper functions for template

  defp health_icon(:healthy), do: "🟢"
  defp health_icon(:warning), do: "🟡"
  defp health_icon(:error), do: "🔴"
  # Unknown status
  defp health_icon(_), do: "⚪"

  defp category_badge_class(:discovery), do: "bg-purple-100 text-purple-800"
  defp category_badge_class(:scheduled), do: "bg-blue-100 text-blue-800"
  defp category_badge_class(:maintenance), do: "bg-gray-100 text-gray-800"
  defp category_badge_class(:background), do: "bg-indigo-100 text-indigo-800"
  # Unknown category
  defp category_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp format_time_ago(nil), do: "Never"

  defp format_time_ago(datetime) do
    diff_seconds = DateTime.diff(DateTime.utc_now(), datetime)

    cond do
      diff_seconds < 60 -> "#{diff_seconds}s ago"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
      true -> "#{div(diff_seconds, 86400)}d ago"
    end
  end

  defp format_state("completed"), do: "✓"
  defp format_state("executing"), do: "⏳"
  defp format_state("retryable"), do: "↻"
  defp format_state("discarded"), do: "✗"
  defp format_state("cancelled"), do: "⊗"
  defp format_state(_), do: "?"

  defp is_expanded?(expanded, worker) do
    MapSet.member?(expanded, worker)
  end
end
