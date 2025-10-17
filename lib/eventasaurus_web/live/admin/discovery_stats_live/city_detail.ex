defmodule EventasaurusWeb.Admin.DiscoveryStatsLive.CityDetail do
  @moduledoc """
  City detail view for discovery statistics.

  Provides city-focused information including:
  - All sources active in this city
  - Event counts per source
  - Top venues by event count
  - Category distribution
  - Change tracking metrics per source
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.PublicEvents.{PublicEvent, PublicEventSource}
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Admin.{DiscoveryStatsCollector, SourceHealthCalculator, EventChangeTracker, TrendAnalyzer}
  alias EventasaurusApp.Venues.Venue

  import Ecto.Query
  require Logger

  @refresh_interval 30_000  # 30 seconds

  @impl true
  def mount(%{"city_slug" => city_slug}, _session, socket) do
    query = from(c in City, where: c.slug == ^city_slug, select: c)

    case Repo.one(query) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "City not found")
         |> push_navigate(to: ~p"/admin/discovery/stats")}

      city ->
        if connected?(socket) do
          Process.send_after(self(), :refresh, @refresh_interval)
        end

        socket =
          socket
          |> assign(:city_id, city.id)
          |> assign(:city, city)
          |> assign(:page_title, "#{city.name} Discovery Statistics")
          |> assign(:date_range, 30)
          |> assign(:loading, true)
          |> load_city_data()
          |> assign(:loading, false)

        {:ok, socket}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    socket =
      socket
      |> load_city_data()
      |> then(fn socket ->
        Process.send_after(self(), :refresh, @refresh_interval)
        socket
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_date_range", %{"date_range" => date_range}, socket) do
    date_range = String.to_integer(date_range)

    city_id = socket.assigns.city_id

    # Get new trend data
    city_event_trend = TrendAnalyzer.get_city_event_trend(city_id, date_range)
    city_chart_data = TrendAnalyzer.format_for_chartjs(city_event_trend, :count, "Events", "#3B82F6")

    socket =
      socket
      |> assign(:date_range, date_range)
      |> assign(:city_chart_data, Jason.encode!(city_chart_data))
      |> push_event("update-chart", %{
        chart_id: "city-event-trend-chart",
        chart_data: city_chart_data
      })

    {:noreply, socket}
  end

  defp load_city_data(socket) do
    city_id = socket.assigns.city_id
    date_range = socket.assigns.date_range

    # Get all sources active in this city
    sources_data = get_sources_for_city(city_id)

    # Get top venues
    top_venues = get_top_venues(city_id, 10)

    # Get category distribution
    category_distribution = get_category_distribution(city_id)

    # Get total events for city
    total_events = count_city_events(city_id)

    # Get events added this week
    events_this_week = count_city_events_this_week(city_id)

    # Get trend data (Phase 6) - uses date_range
    city_event_trend = TrendAnalyzer.get_city_event_trend(city_id, date_range)
    city_chart_data = TrendAnalyzer.format_for_chartjs(city_event_trend, :count, "Events", "#3B82F6")

    socket
    |> assign(:sources_data, sources_data)
    |> assign(:top_venues, top_venues)
    |> assign(:category_distribution, category_distribution)
    |> assign(:total_events, total_events)
    |> assign(:events_this_week, events_this_week)
    |> assign(:city_chart_data, Jason.encode!(city_chart_data))
  end

  defp get_sources_for_city(city_id) do
    # Query for all sources that have events in this city
    query =
      from(pes in PublicEventSource,
        join: e in PublicEvent,
        on: e.id == pes.event_id,
        join: v in Venue,
        on: v.id == e.venue_id,
        join: s in Source,
        on: s.id == pes.source_id,
        where: v.city_id == ^city_id,
        group_by: [s.id, s.name, s.slug],
        select: %{
          source_id: s.id,
          source_name: s.name,
          source_slug: s.slug,
          event_count: count(e.id)
        }
      )

    sources = Repo.all(query)

    # Enrich with run stats and change tracking
    sources
    |> Enum.map(fn source ->
      # Get run statistics
      stats = DiscoveryStatsCollector.get_source_stats(city_id, source.source_slug)
      health_status = SourceHealthCalculator.calculate_health_score(stats)
      success_rate = SourceHealthCalculator.success_rate_percentage(stats)

      # Get change tracking data
      new_events = EventChangeTracker.calculate_new_events(source.source_slug, 24)
      dropped_events = EventChangeTracker.calculate_dropped_events(source.source_slug, 48)
      percentage_change = EventChangeTracker.calculate_percentage_change(source.source_slug, city_id)
      {trend_emoji, trend_text, trend_class} = EventChangeTracker.get_trend_indicator(percentage_change)

      %{
        source_id: source.source_id,
        source_name: source.source_name,
        source_slug: source.source_slug,
        event_count: source.event_count,
        stats: stats,
        health_status: health_status,
        success_rate: success_rate,
        new_events: new_events,
        dropped_events: dropped_events,
        percentage_change: percentage_change,
        trend_emoji: trend_emoji,
        trend_text: trend_text,
        trend_class: trend_class
      }
    end)
    |> Enum.sort_by(& &1.event_count, :desc)
  end

  defp get_top_venues(city_id, limit) do
    query =
      from(e in PublicEvent,
        join: v in Venue,
        on: v.id == e.venue_id,
        where: v.city_id == ^city_id,
        group_by: [v.id, v.name],
        order_by: [desc: count(e.id)],
        limit: ^limit,
        select: %{
          venue_id: v.id,
          venue_name: v.name,
          event_count: count(e.id)
        }
      )

    Repo.all(query)
  end

  defp get_category_distribution(city_id) do
    query =
      from(e in PublicEvent,
        join: v in Venue,
        on: v.id == e.venue_id,
        join: pec in "public_event_categories",
        on: pec.event_id == e.id,
        join: c in EventasaurusDiscovery.Categories.Category,
        on: c.id == pec.category_id,
        where: v.city_id == ^city_id,
        group_by: [c.id, c.name],
        order_by: [desc: count(e.id)],
        select: %{
          category: c.name,
          count: count(e.id)
        }
      )

    Repo.all(query)
  end

  defp count_city_events(city_id) do
    query =
      from(e in PublicEvent,
        join: v in Venue,
        on: v.id == e.venue_id,
        where: v.city_id == ^city_id,
        select: count(e.id)
      )

    Repo.one(query) || 0
  end

  defp count_city_events_this_week(city_id) do
    week_ago = DateTime.utc_now() |> DateTime.add(-7, :day)

    query =
      from(e in PublicEvent,
        join: v in Venue,
        on: v.id == e.venue_id,
        where: v.city_id == ^city_id,
        where: e.inserted_at >= ^week_ago,
        select: count(e.id)
      )

    Repo.one(query) || 0
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Header with Back Button -->
      <div class="mb-8">
        <div class="flex items-center mb-4">
          <.link
            navigate={~p"/admin/discovery/stats"}
            class="mr-4 text-gray-600 hover:text-gray-900"
          >
            ← Back to Overview
          </.link>
          <h1 class="text-3xl font-bold text-gray-900">🏙️ <%= @city.name %> Discovery Statistics</h1>
        </div>

        <!-- City Info Card -->
        <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <p class="text-sm font-medium text-blue-900">City</p>
              <p class="text-lg text-blue-700"><%= @city.name %></p>
            </div>
            <div>
              <p class="text-sm font-medium text-blue-900">Total Events</p>
              <p class="text-lg text-blue-700"><%= format_number(@total_events) %></p>
            </div>
            <div>
              <p class="text-sm font-medium text-blue-900">Added This Week</p>
              <p class="text-lg text-blue-700">+<%= format_number(@events_this_week) %></p>
            </div>
          </div>
        </div>
      </div>

      <%= if @loading do %>
        <div class="flex justify-center items-center h-64">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600"></div>
        </div>
      <% else %>
        <!-- City Event Trend (Phase 6) -->
        <div class="mb-4 flex items-center justify-between">
          <div>
            <h2 class="text-lg font-semibold text-gray-900">📊 Event Count Trend</h2>
            <p class="text-sm text-gray-500">Events over time for <%= @city.name %></p>
          </div>
          <form phx-change="change_date_range" class="flex items-center gap-2">
            <label for="date-range" class="text-sm font-medium text-gray-700">Time Range:</label>
            <select
              id="date-range"
              name="date_range"
              class="block rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm"
            >
              <option value="7" selected={@date_range == 7}>Last 7 days</option>
              <option value="14" selected={@date_range == 14}>Last 14 days</option>
              <option value="30" selected={@date_range == 30}>Last 30 days</option>
              <option value="90" selected={@date_range == 90}>Last 90 days</option>
            </select>
          </form>
        </div>
        <div class="bg-white rounded-lg shadow mb-8">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">📈 Event Count Trend</h2>
            <p class="mt-1 text-sm text-gray-500">Last <%= @date_range %> days for <%= @city.name %></p>
          </div>
          <div class="p-6">
            <div style="height: 300px;">
              <canvas
                id="city-event-trend-chart"
                phx-hook="ChartHook"
                phx-update="ignore"
                data-chart-data={@city_chart_data}
                data-chart-type="line"
              ></canvas>
            </div>
          </div>
        </div>

        <!-- Sources Active in This City -->
        <div class="bg-white rounded-lg shadow mb-8">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">Sources Active in <%= @city.name %></h2>
            <p class="mt-1 text-sm text-gray-500"><%= length(@sources_data) %> sources</p>
          </div>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Source</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Events</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">New (24h)</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Dropped (48h)</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Change %</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Last Run</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Success Rate</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for source <- @sources_data do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-6 py-4 whitespace-nowrap">
                      <.link navigate={~p"/admin/discovery/stats/source/#{source.source_slug}"} class="text-sm font-medium text-indigo-600 hover:text-indigo-900">
                        <%= source.source_name %>
                      </.link>
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
                <%= if Enum.empty?(@sources_data) do %>
                  <tr>
                    <td colspan="8" class="px-6 py-4 text-center text-sm text-gray-500">
                      No sources have events in this city yet
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <!-- Top Venues -->
        <div class="bg-white rounded-lg shadow mb-8">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">🎭 Top Venues</h2>
            <p class="mt-1 text-sm text-gray-500">By event count</p>
          </div>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Venue</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Events</th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for venue <- @top_venues do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-6 py-4 text-sm font-medium text-gray-900">
                      <%= venue.venue_name %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      <%= format_number(venue.event_count) %>
                    </td>
                  </tr>
                <% end %>
                <%= if Enum.empty?(@top_venues) do %>
                  <tr>
                    <td colspan="2" class="px-6 py-4 text-center text-sm text-gray-500">
                      No venues found
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <!-- Category Distribution -->
        <div class="bg-white rounded-lg shadow mb-8">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">📊 Category Distribution</h2>
            <p class="mt-1 text-sm text-gray-500">Event categories in <%= @city.name %></p>
          </div>
          <div class="p-6">
            <%= if Enum.empty?(@category_distribution) do %>
              <p class="text-center text-sm text-gray-500">No category data available</p>
            <% else %>
              <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
                <%= for cat <- @category_distribution do %>
                  <div class="bg-gray-50 rounded-lg p-4">
                    <p class="text-sm font-medium text-gray-500"><%= cat.category || "Uncategorized" %></p>
                    <p class="text-2xl font-semibold text-gray-900"><%= format_number(cat.count) %></p>
                  </div>
                <% end %>
              </div>
            <% end %>
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
  defp format_last_run(%DateTime{} = dt), do: time_ago_in_words(dt)
  defp format_last_run(%NaiveDateTime{} = dt) do
    dt
    |> DateTime.from_naive!("Etc/UTC")
    |> time_ago_in_words()
  end

  defp time_ago_in_words(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime)

    cond do
      diff_seconds < 60 -> "#{diff_seconds}s ago"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
      true -> "#{div(diff_seconds, 86400)}d ago"
    end
  end

  defp format_change(change) when change > 0, do: "+#{change}%"
  defp format_change(change) when change < 0, do: "#{change}%"
  defp format_change(_), do: "0%"
end
