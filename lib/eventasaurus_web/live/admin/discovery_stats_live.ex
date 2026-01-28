defmodule EventasaurusWeb.Admin.DiscoveryStatsLive do
  @moduledoc """
  Admin dashboard for viewing discovery source statistics.

  This LiveView provides a comprehensive overview of all discovery sources,
  showing health metrics, run statistics, and city-level performance data.

  Features:
  - Overall system health score
  - Per-source health and run statistics
  - Per-city event counts and changes
  - Auto-refresh every 15 minutes (matches stats computation schedule)
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Admin.{DiscoveryStatsCache, SourceHealthCalculator}

  require Logger

  # 15 minutes - matches the Oban job schedule for stats computation
  @refresh_interval :timer.minutes(15)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh, @refresh_interval)
    end

    socket =
      socket
      |> assign(:page_title, "Discovery Source Statistics")
      |> assign(:refreshing, false)
      |> load_stats()

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    socket =
      socket
      |> load_stats()
      |> then(fn socket ->
        Process.send_after(self(), :refresh, @refresh_interval)
        socket
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:check_refresh_complete, old_timestamp, poll_count}, socket) do
    new_timestamp = DiscoveryStatsCache.last_refreshed_at()

    cond do
      # Timestamp changed - refresh completed!
      new_timestamp != old_timestamp ->
        socket =
          socket
          |> assign(:refreshing, false)
          |> load_stats()
          |> put_flash(:info, "Cache refreshed successfully!")

        {:noreply, socket}

      # Max polling attempts (30 seconds)
      poll_count >= 30 ->
        socket =
          socket
          |> assign(:refreshing, false)
          |> put_flash(:error, "Cache refresh timeout. Please try again.")

        {:noreply, socket}

      # Keep polling
      true ->
        Process.send_after(self(), {:check_refresh_complete, old_timestamp, poll_count + 1}, 1000)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("force_refresh", _params, socket) do
    # Prevent multiple concurrent refreshes to avoid duplicate polling loops
    if socket.assigns.refreshing do
      {:noreply, socket}
    else
      # Capture the current timestamp before refresh
      current_timestamp = DiscoveryStatsCache.last_refreshed_at()

      # Force immediate cache refresh (runs async in background)
      DiscoveryStatsCache.refresh()

      # Start polling to check when refresh completes
      Process.send_after(self(), {:check_refresh_complete, current_timestamp, 0}, 1000)

      socket =
        socket
        |> assign(:refreshing, true)
        |> put_flash(:info, "Cache refresh initiated. Stats will update in a moment...")

      {:noreply, socket}
    end
  end

  defp load_stats(socket) do
    # Stats are precomputed by ComputeStatsJob and stored in database
    # DiscoveryStatsCache reads from database and caches in memory
    case DiscoveryStatsCache.get_stats() do
      nil ->
        # No stats snapshot exists yet - show loading state
        Logger.warning("No stats snapshot found - waiting for ComputeStatsJob to run")

        socket
        |> assign(:loading, true)
        |> assign(:sources_data, [])
        |> assign(:overall_health, 0)
        |> assign(:total_sources, 0)
        |> assign(:total_cities, 0)
        |> assign(:events_this_week, 0)
        |> assign(:city_stats, [])
        |> assign(:computed_at, nil)
        |> assign(:is_stale, true)
        |> assign(:computation_time_ms, nil)

      %{stats: nil} ->
        # Stats data is nil - show loading state
        Logger.warning("Stats snapshot has nil data - waiting for computation")

        socket
        |> assign(:loading, true)
        |> assign(:sources_data, [])
        |> assign(:overall_health, 0)
        |> assign(:total_sources, 0)
        |> assign(:total_cities, 0)
        |> assign(:events_this_week, 0)
        |> assign(:city_stats, [])
        |> assign(:computed_at, nil)
        |> assign(:is_stale, true)
        |> assign(:computation_time_ms, nil)

      %{
        stats: stats,
        computed_at: computed_at,
        is_stale: is_stale,
        computation_time_ms: computation_time_ms
      } ->
        # Load from cache (fast!)
        socket
        |> assign(:loading, false)
        |> assign(:sources_data, stats[:sources_data] || [])
        |> assign(:overall_health, stats[:overall_health] || 0)
        |> assign(:total_sources, stats[:total_sources] || 0)
        |> assign(:total_cities, stats[:total_cities] || 0)
        |> assign(:events_this_week, stats[:events_this_week] || 0)
        |> assign(:city_stats, stats[:city_stats] || [])
        |> assign(:computed_at, computed_at)
        |> assign(:is_stale, is_stale)
        |> assign(:computation_time_ms, computation_time_ms)
    end
  end

  # All query functions have been moved to DiscoveryStatsCache GenServer
  # Phase 1 batched queries are now executed in the background cache refresh
  # This keeps the LiveView lightweight - it only reads from cache

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <div class="mb-8">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-3xl font-bold text-gray-900">🎯 Discovery Source Statistics</h1>
            <p class="mt-2 text-sm text-gray-600">Real-time monitoring of event discovery sources</p>
          </div>
          <div class="flex items-center gap-4">
          <!-- Freshness indicator (compact) -->
          <div class="text-sm text-right">
            <%= if @loading do %>
              <span class="text-gray-400">Loading...</span>
            <% else %>
              <%= if @computed_at do %>
                <div class={if @is_stale, do: "text-amber-600", else: "text-gray-600"}>
                  <%= if @is_stale do %>
                    <span class="inline-block">⚠️</span>
                  <% end %>
                  Updated <%= format_computed_at(@computed_at) %>
                </div>
              <% else %>
                <span class="text-amber-600">⏳ Computing...</span>
              <% end %>
            <% end %>
          </div>
          <button
            phx-click="force_refresh"
            disabled={@refreshing}
            class={"inline-flex items-center px-4 py-2 border border-indigo-300 rounded-md shadow-sm text-sm font-medium text-indigo-700 bg-indigo-50 hover:bg-indigo-100 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 #{if @refreshing, do: "opacity-50 cursor-not-allowed", else: ""}"}
          >
            <%= if @refreshing do %>
              <svg class="animate-spin -ml-1 mr-2 h-5 w-5 text-indigo-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
              Refreshing...
            <% else %>
              <svg class="-ml-1 mr-2 h-5 w-5 text-indigo-500" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M4 2a1 1 0 011 1v2.101a7.002 7.002 0 0111.601 2.566 1 1 0 11-1.885.666A5.002 5.002 0 005.999 7H9a1 1 0 010 2H4a1 1 0 01-1-1V3a1 1 0 011-1zm.008 9.057a1 1 0 011.276.61A5.002 5.002 0 0014.001 13H11a1 1 0 110-2h5a1 1 0 011 1v5a1 1 0 11-2 0v-2.101a7.002 7.002 0 01-11.601-2.566 1 1 0 01.61-1.276z" clip-rule="evenodd" />
              </svg>
              Refresh
            <% end %>
          </button>
            <.link
              navigate={~p"/admin/discovery"}
              class="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
            >
              <svg class="-ml-1 mr-2 h-5 w-5 text-gray-500" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L5.414 9H17a1 1 0 110 2H5.414l4.293 4.293a1 1 0 010 1.414z" clip-rule="evenodd" />
              </svg>
              Back to Discovery
            </.link>
          </div>
        </div>
      </div>

      <%= if @loading do %>
        <div class="flex justify-center items-center h-64">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600"></div>
        </div>
      <% else %>
        <!-- Summary Cards -->
        <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
          <!-- Sources Card -->
          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <span class="text-3xl">📊</span>
              </div>
              <div class="ml-4">
                <p class="text-sm font-medium text-gray-500">Sources</p>
                <p class="text-2xl font-semibold text-gray-900"><%= @total_sources %></p>
                <p class="text-xs text-gray-500 mt-1">Active</p>
              </div>
            </div>
          </div>

          <!-- Cities Card -->
          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <span class="text-3xl">🏙️</span>
              </div>
              <div class="ml-4">
                <p class="text-sm font-medium text-gray-500">Cities</p>
                <p class="text-2xl font-semibold text-gray-900"><%= @total_cities %></p>
                <p class="text-xs text-gray-500 mt-1">Covered</p>
              </div>
            </div>
          </div>

          <!-- Events This Week Card -->
          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <span class="text-3xl">📅</span>
              </div>
              <div class="ml-4">
                <p class="text-sm font-medium text-gray-500">Events</p>
                <p class="text-2xl font-semibold text-gray-900">+<%= format_number(@events_this_week) %></p>
                <p class="text-xs text-gray-500 mt-1">This Week</p>
              </div>
            </div>
          </div>

          <!-- Health Score Card -->
          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <span class="text-3xl">✅</span>
              </div>
              <div class="ml-4">
                <p class="text-sm font-medium text-gray-500">Health</p>
                <p class="text-2xl font-semibold text-gray-900"><%= @overall_health %>%</p>
                <p class="text-xs text-gray-500 mt-1">Score</p>
              </div>
            </div>
          </div>
        </div>

        <!-- Sources Status Table -->
        <div class="bg-white rounded-lg shadow mb-8">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">Sources Status</h2>
          </div>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Source</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Scope</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Events</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">New</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Dropped</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Change %</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Quality</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Last Run</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Success Rate</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for source <- @sources_data do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-6 py-4 whitespace-nowrap">
                      <.link navigate={~p"/admin/discovery/stats/source/#{source.name}"} class="text-sm font-medium text-indigo-600 hover:text-indigo-900">
                        <%= source.name %>
                      </.link>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-blue-100 text-blue-800">
                        <%= source.scope %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      <%= format_number(source.event_count) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class="text-sm font-medium text-green-600">+<%= source.new_events %></span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <%= if source.dropped_events > 0 do %>
                        <span class="text-sm font-medium text-red-600">-<%= source.dropped_events %></span>
                      <% else %>
                        <span class="text-sm text-gray-400">0</span>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <div class="flex items-center">
                        <span class={"text-sm font-medium #{source.trend_class}"}>
                          <%= source.trend_emoji %> <%= format_change(source.percentage_change) %>
                        </span>
                      </div>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <div class="flex items-center">
                        <span class="text-lg mr-1"><%= source.quality_emoji %></span>
                        <span class={"text-sm font-medium #{source.quality_class}"}>
                          <%= if source.quality_text == "N/A", do: "N/A", else: "#{source.quality_score}%" %>
                        </span>
                      </div>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= format_last_run(source.stats.last_run_at) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <div class="flex items-center">
                        <div class="text-sm font-medium text-gray-900"><%= source.success_rate %>%</div>
                        <%= if source.stats.run_count > 0 do %>
                          <div class="ml-2 text-xs text-gray-500">
                            (<%= source.stats.success_count %>/<%= source.stats.run_count %>)
                          </div>
                        <% end %>
                      </div>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{SourceHealthCalculator.status_classes(source.health_status)}"}>
                        <%= SourceHealthCalculator.status_emoji(source.health_status) %> <%= SourceHealthCalculator.status_text(source.health_status) %>
                      </span>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <!-- Cities Performance Table -->
        <div class="bg-white rounded-lg shadow">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">Cities Performance</h2>
            <p class="mt-1 text-sm text-gray-500">Top 10 cities by event count</p>
          </div>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">City</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Events</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Δ Week</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for city <- @city_stats do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-6 py-4 whitespace-nowrap">
                      <.link navigate={~p"/admin/cities/#{city.city_slug}/health"} class="text-sm font-medium text-indigo-600 hover:text-indigo-900">
                        <%= city.city_name %>
                      </.link>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      <%= format_number(city.event_count) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <div class={"text-sm font-medium #{change_color(city.weekly_change)}"}>
                        <%= format_change(city.weekly_change) %>
                      </div>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <%= status_emoji_for_change(city.weekly_change) %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <!-- Footer note -->
        <div class="mt-4 text-center text-xs text-gray-400">
          Stats computed every 15 minutes by background job
          <%= if @computation_time_ms do %>
            • Last computation took <%= format_duration(@computation_time_ms) %>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper functions

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

  defp format_last_run(nil), do: "Never"

  defp format_last_run(%DateTime{} = dt) do
    time_ago_in_words(dt)
  end

  defp format_last_run(%NaiveDateTime{} = dt) do
    dt
    |> DateTime.from_naive!("Etc/UTC")
    |> time_ago_in_words()
  end

  # Handle ISO8601 string from JSON (when stats are loaded from database snapshot)
  defp format_last_run(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _offset} ->
        time_ago_in_words(dt)

      {:error, _} ->
        # Try as naive datetime
        case NaiveDateTime.from_iso8601(iso_string) do
          {:ok, ndt} ->
            ndt
            |> DateTime.from_naive!("Etc/UTC")
            |> time_ago_in_words()

          {:error, _} ->
            "Unknown"
        end
    end
  end

  defp time_ago_in_words(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime)

    cond do
      diff_seconds < 60 ->
        "#{diff_seconds}s ago"

      diff_seconds < 3600 ->
        minutes = div(diff_seconds, 60)
        "#{minutes}m ago"

      diff_seconds < 86400 ->
        hours = div(diff_seconds, 3600)
        "#{hours}h ago"

      true ->
        days = div(diff_seconds, 86400)
        "#{days}d ago"
    end
  end

  defp format_change(nil), do: "New"
  defp format_change(change) when change > 0, do: "+#{change}%"
  defp format_change(change) when change < 0, do: "#{change}%"
  defp format_change(0), do: "0%"

  defp change_color(nil), do: "text-blue-600"
  defp change_color(change) when change > 0, do: "text-green-600"
  defp change_color(change) when change < 0, do: "text-red-600"
  defp change_color(_), do: "text-gray-600"

  defp status_emoji_for_change(nil), do: "🆕"
  defp status_emoji_for_change(change) when change > 5, do: "🟢"
  defp status_emoji_for_change(change) when change < -5, do: "🔴"
  defp status_emoji_for_change(_), do: "🟡"

  defp format_computed_at(nil), do: "Never"

  defp format_computed_at(%DateTime{} = dt) do
    time_ago_in_words(dt)
  end

  defp format_duration(nil), do: ""

  defp format_duration(ms) when ms < 1000 do
    "#{ms}ms"
  end

  defp format_duration(ms) when ms < 60_000 do
    seconds = Float.round(ms / 1000, 1)
    "#{seconds}s"
  end

  defp format_duration(ms) do
    minutes = Float.round(ms / 60_000, 1)
    "#{minutes}m"
  end
end
