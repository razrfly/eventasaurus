defmodule EventasaurusWeb.Admin.DiscoveryStatsLive do
  @moduledoc """
  Admin dashboard for viewing discovery source statistics.

  This LiveView provides a comprehensive overview of all discovery sources,
  showing health metrics, run statistics, and city-level performance data.

  Features:
  - Overall system health score
  - Per-source health and run statistics
  - Per-city event counts and changes
  - Auto-refresh every 30 seconds
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Locations.{City, CityHierarchy}
  alias EventasaurusDiscovery.Sources.SourceRegistry
  alias EventasaurusDiscovery.Admin.{DiscoveryStatsCollector, SourceHealthCalculator, EventChangeTracker, DataQualityChecker}

  import Ecto.Query
  require Logger

  @refresh_interval 30_000  # 30 seconds

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh, @refresh_interval)
    end

    socket =
      socket
      |> assign(:page_title, "Discovery Source Statistics")
      |> assign(:loading, true)
      |> assign(:expanded_metro_areas, MapSet.new())
      |> load_stats()
      |> assign(:loading, false)

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
  def handle_event("toggle_metro_area", %{"city-id" => city_id}, socket) do
    case Integer.parse(city_id) do
      {city_id_int, _} ->
        expanded = socket.assigns.expanded_metro_areas

        new_expanded =
          if MapSet.member?(expanded, city_id_int) do
            MapSet.delete(expanded, city_id_int)
          else
            MapSet.put(expanded, city_id_int)
          end

        {:noreply, assign(socket, :expanded_metro_areas, new_expanded)}

      :error ->
        # Invalid city-id, no-op gracefully
        {:noreply, socket}
    end
  end

  defp load_stats(socket) do
    # Get all registered sources
    source_names = SourceRegistry.all_sources()

    # Query stats aggregated across ALL cities (like Imports page does)
    # This avoids the issue of filtering by a city that has no jobs
    # Note: get_metadata_based_source_stats with nil city_id will aggregate across all cities
    source_stats = DiscoveryStatsCollector.get_metadata_based_source_stats(nil, source_names)

    # Get change tracking data aggregated across all cities
    change_stats = EventChangeTracker.get_all_source_changes(source_names, nil)

    # Calculate enriched source data with health metrics
    sources_data =
      source_names
      |> Enum.map(fn source_name ->
        stats = Map.get(source_stats, source_name, %{
          # Metadata-based stats (NEW format)
          events_processed: 0,
          events_succeeded: 0,
          events_failed: 0,
          # Legacy stats (OLD format) - kept for backward compatibility
          run_count: 0,
          success_count: 0,
          error_count: 0,
          last_run_at: nil,
          last_error: nil
        })

        health_status = SourceHealthCalculator.calculate_health_score(stats)
        success_rate = SourceHealthCalculator.success_rate_percentage(stats)

        # Get source scope
        scope = case SourceRegistry.get_scope(source_name) do
          {:ok, scope} -> scope
          {:error, :not_found} ->
            Logger.warning("Source #{source_name} has no scope configured in SourceRegistry")
            "unknown"
        end

        # Count events for this source
        event_count = count_events_for_source(source_name)

        # Get change tracking data
        changes = Map.get(change_stats, source_name, %{
          new_events: 0,
          dropped_events: 0,
          percentage_change: 0
        })

        {trend_emoji, trend_text, trend_class} = EventChangeTracker.get_trend_indicator(changes.percentage_change)

        # Get data quality metrics (Phase 5)
        quality_data = DataQualityChecker.check_quality(source_name)
        {quality_emoji, quality_text, quality_class} =
          if Map.get(quality_data, :not_found, false) || Map.get(quality_data, :total_events, 0) == 0 do
            {"⚪", "N/A", "text-gray-600"}
          else
            DataQualityChecker.quality_status(quality_data.quality_score)
          end

        %{
          name: source_name,
          scope: scope,
          stats: stats,
          health_status: health_status,
          success_rate: success_rate,
          event_count: event_count,
          new_events: changes.new_events,
          dropped_events: changes.dropped_events,
          percentage_change: changes.percentage_change,
          trend_emoji: trend_emoji,
          trend_text: trend_text,
          trend_class: trend_class,
          quality_score: quality_data.quality_score,
          quality_emoji: quality_emoji,
          quality_text: quality_text,
          quality_class: quality_class
        }
      end)
      |> Enum.sort_by(& &1.name)

    # Calculate overall health score
    overall_health = SourceHealthCalculator.overall_health_score(source_stats)

    # Get summary metrics
    total_sources = length(source_names)
    total_cities = count_cities()
    events_this_week = count_events_this_week()

    # Get city performance data
    city_stats = get_city_performance()

    socket
    |> assign(:sources_data, sources_data)
    |> assign(:overall_health, overall_health)
    |> assign(:total_sources, total_sources)
    |> assign(:total_cities, total_cities)
    |> assign(:events_this_week, events_this_week)
    |> assign(:city_stats, city_stats)
  end

  defp count_events_for_source(source_name) do
    # Count events from this source using the public_event_sources join table
    # Note: source_name is actually the source SLUG (e.g., "bandsintown", not "Bandsintown")
    query =
      from(pes in EventasaurusDiscovery.PublicEvents.PublicEventSource,
        join: s in EventasaurusDiscovery.Sources.Source,
        on: s.id == pes.source_id,
        where: s.slug == ^source_name,
        select: count(pes.id)
      )

    Repo.one(query) || 0
  end

  defp count_cities do
    Repo.aggregate(City, :count, :id)
  end

  defp count_events_this_week do
    week_ago = DateTime.utc_now() |> DateTime.add(-7, :day)

    query =
      from(e in PublicEvent,
        where: e.inserted_at >= ^week_ago,
        select: count(e.id)
      )

    Repo.one(query) || 0
  end

  defp get_city_performance do
    # Get cities with the most events
    query =
      from(e in PublicEvent,
        join: v in EventasaurusApp.Venues.Venue,
        on: v.id == e.venue_id,
        join: c in City,
        on: c.id == v.city_id,
        group_by: [c.id, c.name, c.slug],
        having: count(e.id) >= 10,
        select: %{
          city_id: c.id,
          city_name: c.name,
          city_slug: c.slug,
          count: count(e.id)
        },
        order_by: [desc: count(e.id)]
      )

    cities = Repo.all(query)

    # Apply geographic clustering to group metro areas
    clustered_cities = CityHierarchy.aggregate_stats_by_cluster(cities, 20.0)

    # Take top 10 after clustering and calculate week-over-week change
    clustered_cities
    |> Enum.take(10)
    |> Enum.map(fn city ->
      change = calculate_city_change(city.city_id)

      city
      |> Map.put(:event_count, city.count)
      |> Map.put(:weekly_change, change)
    end)
  end

  defp calculate_city_change(city_id) do
    now = DateTime.utc_now()
    one_week_ago = DateTime.add(now, -7, :day)
    two_weeks_ago = DateTime.add(now, -14, :day)

    # Events added this week
    this_week =
      from(e in PublicEvent,
        join: v in EventasaurusApp.Venues.Venue,
        on: v.id == e.venue_id,
        where: v.city_id == ^city_id,
        where: e.inserted_at >= ^one_week_ago,
        select: count(e.id)
      )
      |> Repo.one() || 0

    # Events added last week
    last_week =
      from(e in PublicEvent,
        join: v in EventasaurusApp.Venues.Venue,
        on: v.id == e.venue_id,
        where: v.city_id == ^city_id,
        where: e.inserted_at >= ^two_weeks_ago and e.inserted_at < ^one_week_ago,
        select: count(e.id)
      )
      |> Repo.one() || 0

    # Calculate percentage change
    # Note: When there's no baseline (last_week = 0), return nil instead of 100%
    # This will be displayed as "New" in the UI
    if last_week > 0 do
      ((this_week - last_week) / last_week * 100) |> round()
    else
      # No baseline data - return nil to indicate "New" city
      nil
    end
  end

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
          <.link
            navigate={~p"/admin/imports"}
            class="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
          >
            <svg class="-ml-1 mr-2 h-5 w-5 text-gray-500" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L5.414 9H17a1 1 0 110 2H5.414l4.293 4.293a1 1 0 010 1.414z" clip-rule="evenodd" />
            </svg>
            Back to Imports
          </.link>
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
            <p class="mt-1 text-sm text-gray-500">Top 10 cities by event count (metro areas aggregated)</p>
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
                  <!-- Primary City Row -->
                  <tr class="hover:bg-gray-50">
                    <td class="px-6 py-4 whitespace-nowrap">
                      <%= if length(city.subcities) > 0 do %>
                        <button
                          type="button"
                          phx-click="toggle_metro_area"
                          phx-value-city-id={city.city_id}
                          aria-expanded={to_string(MapSet.member?(@expanded_metro_areas, city.city_id))}
                          class="text-gray-500 hover:text-gray-700 mr-2"
                        >
                          <span class="sr-only">Toggle subcities for <%= city.city_name %></span>
                          <%= if MapSet.member?(@expanded_metro_areas, city.city_id) do %>
                            ▼
                          <% else %>
                            ▶
                          <% end %>
                        </button>
                      <% end %>
                      <.link navigate={~p"/admin/discovery/stats/city/#{city.city_slug}"} class="text-sm font-medium text-indigo-600 hover:text-indigo-900">
                        <%= city.city_name %>
                      </.link>
                      <%= if length(city.subcities) > 0 do %>
                        <span class="ml-2 text-xs text-gray-500">(<%= length(city.subcities) %> areas)</span>
                      <% end %>
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

                  <!-- Subcity Rows (Expandable) -->
                  <%= if MapSet.member?(@expanded_metro_areas, city.city_id) do %>
                    <%= for subcity <- city.subcities do %>
                      <tr class="hover:bg-gray-50 bg-gray-50">
                        <td class="px-6 py-4 whitespace-nowrap pl-12">
                          <.link navigate={~p"/admin/discovery/stats/city/#{subcity.city_slug}"} class="text-sm text-gray-700 hover:text-indigo-900">
                            ↳ <%= subcity.city_name %>
                          </.link>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-700">
                          <%= format_number(subcity.count) %>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                          <div class="text-sm text-gray-500">
                            —
                          </div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                          <span class="text-gray-400">—</span>
                        </td>
                      </tr>
                    <% end %>
                  <% end %>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <!-- Auto-refresh indicator -->
        <div class="mt-4 text-center text-xs text-gray-500">
          Auto-refreshing every 30 seconds
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
end
