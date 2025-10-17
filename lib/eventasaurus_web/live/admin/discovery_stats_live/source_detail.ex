defmodule EventasaurusWeb.Admin.DiscoveryStatsLive.SourceDetail do
  @moduledoc """
  Source detail view for discovery statistics.

  Provides detailed information about a specific discovery source including:
  - Overall metrics and health
  - Recent run history
  - Error logs
  - Events by city (for city-scoped sources)
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.SourceRegistry
  alias EventasaurusDiscovery.Admin.{DiscoveryStatsCollector, SourceHealthCalculator, EventChangeTracker, DataQualityChecker, TrendAnalyzer}
  alias EventasaurusDiscovery.Locations.City

  import Ecto.Query
  require Logger

  @refresh_interval 30_000  # 30 seconds

  @impl true
  def mount(%{"source_slug" => source_slug}, _session, socket) do
    # Verify source exists
    case SourceRegistry.get_sync_job(source_slug) do
      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Source not found: #{source_slug}")
         |> push_navigate(to: ~p"/admin/discovery/stats")}

      {:ok, _} ->
        if connected?(socket) do
          Process.send_after(self(), :refresh, @refresh_interval)
        end

        socket =
          socket
          |> assign(:source_slug, source_slug)
          |> assign(:page_title, "#{source_slug |> String.capitalize()} Statistics")
          |> assign(:date_range, 30)
          |> assign(:loading, true)
          |> load_source_data()
          |> assign(:loading, false)

        {:ok, socket}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    socket =
      socket
      |> load_source_data()
      |> then(fn socket ->
        Process.send_after(self(), :refresh, @refresh_interval)
        socket
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_date_range", %{"date_range" => date_range}, socket) do
    date_range = String.to_integer(date_range)

    source_slug = socket.assigns.source_slug

    # Get new trend data only
    event_trend = TrendAnalyzer.get_event_trend(source_slug, date_range)
    event_chart_data = TrendAnalyzer.format_for_chartjs(event_trend, :count, "Events", "#3B82F6")

    success_rate_trend = TrendAnalyzer.get_success_rate_trend(source_slug, date_range)
    success_chart_data = TrendAnalyzer.format_for_chartjs(success_rate_trend, :success_rate, "Success Rate", "#10B981")

    socket =
      socket
      |> assign(:date_range, date_range)
      |> assign(:event_chart_data, Jason.encode!(event_chart_data))
      |> assign(:success_chart_data, Jason.encode!(success_chart_data))
      |> push_event("update-chart", %{
        chart_id: "event-trend-chart",
        chart_data: event_chart_data
      })
      |> push_event("update-chart", %{
        chart_id: "success-rate-chart",
        chart_data: success_chart_data
      })

    {:noreply, socket}
  end

  defp load_source_data(socket) do
    source_slug = socket.assigns.source_slug
    date_range = socket.assigns.date_range

    # Get source scope
    scope =
      case SourceRegistry.get_scope(source_slug) do
        {:ok, scope} -> scope
        {:error, _} -> :unknown
      end

    # Get basic stats for the source (using first city as reference)
    first_city = Repo.one(from(c in City, limit: 1, select: c.id))

    stats =
      case first_city do
        nil ->
          %{run_count: 0, success_count: 0, error_count: 0, last_run_at: nil, last_error: nil}
        city_id ->
          DiscoveryStatsCollector.get_source_stats(city_id, source_slug)
      end

    # Calculate health and success rate
    health_status = SourceHealthCalculator.calculate_health_score(stats)
    success_rate = SourceHealthCalculator.success_rate_percentage(stats)

    # Get run history (last 10 runs)
    run_history = DiscoveryStatsCollector.get_run_history(source_slug, 10)

    # Get average runtime (uses date_range)
    avg_runtime = DiscoveryStatsCollector.get_average_runtime(source_slug, date_range)

    # Get events by city (if city-scoped source)
    events_by_city =
      if scope == :city do
        DiscoveryStatsCollector.get_events_by_city_for_source(source_slug, 20)
      else
        []
      end

    # Get total event count
    total_events = count_events_for_source(source_slug)

    # Get source coverage description
    coverage = get_coverage_description(source_slug, scope)

    # Get change tracking data (Phase 3)
    new_events = EventChangeTracker.calculate_new_events(source_slug, 24)
    dropped_events = EventChangeTracker.calculate_dropped_events(source_slug, 48)
    percentage_change =
      case first_city do
        nil -> 0
        city_id -> EventChangeTracker.calculate_percentage_change(source_slug, city_id)
      end
    {trend_emoji, trend_text, trend_class} = EventChangeTracker.get_trend_indicator(percentage_change)

    # Get data quality metrics (Phase 5)
    quality_data = DataQualityChecker.check_quality(source_slug)

    # Ensure all required fields exist when not_found is true
    quality_data =
      if Map.get(quality_data, :not_found, false) do
        Map.merge(
          %{
            quality_score: 0,
            total_events: 0,
            venue_completeness: 0,
            image_completeness: 0,
            category_completeness: 0,
            missing_venues: 0,
            missing_images: 0,
            missing_categories: 0
          },
          quality_data
        )
      else
        quality_data
      end

    {quality_emoji, quality_text, quality_class} =
      if Map.get(quality_data, :not_found, false) do
        {"⚪", "N/A", "text-gray-600"}
      else
        DataQualityChecker.quality_status(quality_data.quality_score)
      end

    recommendations = DataQualityChecker.get_recommendations(source_slug)

    # Get trend data (Phase 6) - uses date_range
    event_trend = TrendAnalyzer.get_event_trend(source_slug, date_range)
    event_chart_data = TrendAnalyzer.format_for_chartjs(event_trend, :count, "Events", "#3B82F6")

    success_rate_trend = TrendAnalyzer.get_success_rate_trend(source_slug, date_range)
    success_chart_data = TrendAnalyzer.format_for_chartjs(success_rate_trend, :success_rate, "Success Rate", "#10B981")

    socket
    |> assign(:scope, scope)
    |> assign(:coverage, coverage)
    |> assign(:stats, stats)
    |> assign(:health_status, health_status)
    |> assign(:success_rate, success_rate)
    |> assign(:run_history, run_history)
    |> assign(:avg_runtime, avg_runtime)
    |> assign(:events_by_city, events_by_city)
    |> assign(:total_events, total_events)
    |> assign(:new_events, new_events)
    |> assign(:dropped_events, dropped_events)
    |> assign(:percentage_change, percentage_change)
    |> assign(:trend_emoji, trend_emoji)
    |> assign(:trend_text, trend_text)
    |> assign(:trend_class, trend_class)
    |> assign(:quality_data, quality_data)
    |> assign(:quality_emoji, quality_emoji)
    |> assign(:quality_text, quality_text)
    |> assign(:quality_class, quality_class)
    |> assign(:recommendations, recommendations)
    |> assign(:event_chart_data, Jason.encode!(event_chart_data))
    |> assign(:success_chart_data, Jason.encode!(success_chart_data))
  end

  defp count_events_for_source(source_slug) do
    query =
      from(pes in EventasaurusDiscovery.PublicEvents.PublicEventSource,
        join: s in EventasaurusDiscovery.Sources.Source,
        on: s.id == pes.source_id,
        where: s.slug == ^source_slug,
        select: count(pes.id)
      )

    Repo.one(query) || 0
  end

  defp get_coverage_description(source_slug, scope) do
    case scope do
      :country ->
        case source_slug do
          "pubquiz-pl" -> "Poland"
          "inquizition" -> "United Kingdom"
          _ -> "Country-wide"
        end

      :regional ->
        case source_slug do
          "question-one" -> "UK & Ireland"
          "geeks-who-drink" -> "US & Canada"
          "quizmeisters" -> "Australia"
          "speed-quizzing" -> "International (UK, US, UAE)"
          _ -> "Regional"
        end

      :city ->
        "Global (requires city selection)"
    end
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
            ← Back
          </.link>
          <h1 class="text-3xl font-bold text-gray-900">🎵 <%= String.capitalize(@source_slug) %> Discovery Statistics</h1>
        </div>

        <!-- Source Info -->
        <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <p class="text-sm font-medium text-blue-900">Name</p>
              <p class="text-lg text-blue-700"><%= String.capitalize(@source_slug) %></p>
            </div>
            <div>
              <p class="text-sm font-medium text-blue-900">Scope</p>
              <p class="text-lg text-blue-700"><%= @scope %></p>
            </div>
            <div>
              <p class="text-sm font-medium text-blue-900">Coverage</p>
              <p class="text-lg text-blue-700"><%= @coverage %></p>
            </div>
          </div>
        </div>
      </div>

      <%= if @loading do %>
        <div class="flex justify-center items-center h-64">
          <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600"></div>
        </div>
      <% else %>
        <!-- Metrics Cards (Last 30 Days) -->
        <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
          <!-- Total Runs Card -->
          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <span class="text-3xl">📊</span>
              </div>
              <div class="ml-4">
                <p class="text-sm font-medium text-gray-500">Runs</p>
                <p class="text-2xl font-semibold text-gray-900"><%= @stats.run_count %></p>
                <p class="text-xs text-gray-500 mt-1">Last 30 days</p>
              </div>
            </div>
          </div>

          <!-- Success Rate Card -->
          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <span class="text-3xl">✅</span>
              </div>
              <div class="ml-4">
                <p class="text-sm font-medium text-gray-500">Success</p>
                <p class="text-2xl font-semibold text-gray-900"><%= @success_rate %>%</p>
                <p class="text-xs text-gray-500 mt-1">
                  <%= @stats.success_count %>/<%= @stats.run_count %> runs
                </p>
              </div>
            </div>
          </div>

          <!-- Average Time Card -->
          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <span class="text-3xl">⏱️</span>
              </div>
              <div class="ml-4">
                <p class="text-sm font-medium text-gray-500">Avg Time</p>
                <p class="text-2xl font-semibold text-gray-900">
                  <%= format_duration(@avg_runtime) %>
                </p>
                <p class="text-xs text-gray-500 mt-1">per run</p>
              </div>
            </div>
          </div>

          <!-- Last Run Card -->
          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <span class="text-3xl">🔄</span>
              </div>
              <div class="ml-4">
                <p class="text-sm font-medium text-gray-500">Last Run</p>
                <p class="text-lg font-semibold text-gray-900">
                  <%= format_last_run(@stats.last_run_at) %>
                </p>
                <p class="text-xs text-gray-500 mt-1">
                  <span class={"inline-flex items-center px-2 py-0.5 rounded text-xs font-medium #{SourceHealthCalculator.status_classes(@health_status)}"}>
                    <%= SourceHealthCalculator.status_emoji(@health_status) %> <%= SourceHealthCalculator.status_text(@health_status) %>
                  </span>
                </p>
              </div>
            </div>
          </div>
        </div>

        <!-- Change Tracking (Phase 3) -->
        <div class="bg-white rounded-lg shadow mb-8">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">📊 Event Change Tracking</h2>
            <p class="mt-1 text-sm text-gray-500">Changes detected in last 24-48 hours</p>
          </div>
          <div class="p-6">
            <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
              <!-- New Events -->
              <div class="flex items-center p-4 bg-green-50 rounded-lg">
                <div class="flex-shrink-0">
                  <span class="text-3xl">➕</span>
                </div>
                <div class="ml-4">
                  <p class="text-sm font-medium text-green-900">New Events</p>
                  <p class="text-2xl font-semibold text-green-700">+<%= @new_events %></p>
                  <p class="text-xs text-green-600 mt-1">Last 24 hours</p>
                </div>
              </div>

              <!-- Dropped Events -->
              <div class="flex items-center p-4 bg-red-50 rounded-lg">
                <div class="flex-shrink-0">
                  <span class="text-3xl">➖</span>
                </div>
                <div class="ml-4">
                  <p class="text-sm font-medium text-red-900">Dropped Events</p>
                  <p class="text-2xl font-semibold text-red-700">-<%= @dropped_events %></p>
                  <p class="text-xs text-red-600 mt-1">Not seen (48h)</p>
                </div>
              </div>

              <!-- Trend -->
              <div class="flex items-center p-4 bg-blue-50 rounded-lg">
                <div class="flex-shrink-0">
                  <span class="text-3xl"><%= @trend_emoji %></span>
                </div>
                <div class="ml-4">
                  <p class="text-sm font-medium text-blue-900">Week-over-Week</p>
                  <p class={"text-2xl font-semibold #{@trend_class}"}>
                    <%= if @percentage_change > 0 do %>+<% end %><%= @percentage_change %>%
                  </p>
                  <p class="text-xs text-blue-600 mt-1"><%= @trend_text %></p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Data Quality Dashboard (Phase 5) -->
        <div class="bg-white rounded-lg shadow mb-8">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">🎯 Data Quality Dashboard</h2>
            <p class="mt-1 text-sm text-gray-500">Completeness metrics and quality score</p>
          </div>
          <div class="p-6">
            <!-- Overall Quality Score -->
            <div class="mb-6 p-4 bg-gray-50 rounded-lg">
              <div class="flex items-center justify-between">
                <div>
                  <p class="text-sm font-medium text-gray-500">Overall Quality Score</p>
                  <div class="flex items-center mt-1">
                    <span class="text-3xl mr-2"><%= @quality_emoji %></span>
                    <span class={"text-3xl font-bold #{@quality_class}"}><%= @quality_data.quality_score %>%</span>
                    <span class={"ml-2 text-sm font-medium #{@quality_class}"}><%= @quality_text %></span>
                  </div>
                </div>
                <div class="text-right">
                  <p class="text-xs text-gray-500">Total Events</p>
                  <p class="text-2xl font-semibold text-gray-900"><%= format_number(@quality_data.total_events) %></p>
                </div>
              </div>
            </div>

            <!-- Completeness Metrics -->
            <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-6">
              <!-- Venue Completeness -->
              <div class="p-4 border rounded-lg">
                <div class="flex items-center justify-between mb-2">
                  <p class="text-sm font-medium text-gray-700">Venues</p>
                  <span class="text-lg font-bold text-gray-900"><%= @quality_data.venue_completeness %>%</span>
                </div>
                <div class="w-full bg-gray-200 rounded-full h-2.5">
                  <div class="bg-blue-600 h-2.5 rounded-full" style={"width: #{@quality_data.venue_completeness}%"}></div>
                </div>
                <p class="mt-2 text-xs text-gray-500">
                  <%= @quality_data.missing_venues %> events missing venue data
                </p>
              </div>

              <!-- Image Completeness -->
              <div class="p-4 border rounded-lg">
                <div class="flex items-center justify-between mb-2">
                  <p class="text-sm font-medium text-gray-700">Images</p>
                  <span class="text-lg font-bold text-gray-900"><%= @quality_data.image_completeness %>%</span>
                </div>
                <div class="w-full bg-gray-200 rounded-full h-2.5">
                  <div class="bg-green-600 h-2.5 rounded-full" style={"width: #{@quality_data.image_completeness}%"}></div>
                </div>
                <p class="mt-2 text-xs text-gray-500">
                  <%= @quality_data.missing_images %> events missing image data
                </p>
              </div>

              <!-- Category Completeness -->
              <div class="p-4 border rounded-lg">
                <div class="flex items-center justify-between mb-2">
                  <p class="text-sm font-medium text-gray-700">Categories</p>
                  <span class="text-lg font-bold text-gray-900"><%= @quality_data.category_completeness %>%</span>
                </div>
                <div class="w-full bg-gray-200 rounded-full h-2.5">
                  <div class="bg-purple-600 h-2.5 rounded-full" style={"width: #{@quality_data.category_completeness}%"}></div>
                </div>
                <p class="mt-2 text-xs text-gray-500">
                  <%= @quality_data.missing_categories %> events missing category data
                </p>
              </div>
            </div>

            <!-- Recommendations -->
            <div class="border-t pt-4">
              <h3 class="text-sm font-semibold text-gray-900 mb-3">💡 Recommendations</h3>
              <ul class="space-y-2">
                <%= for rec <- @recommendations do %>
                  <li class="flex items-start">
                    <span class="flex-shrink-0 w-1.5 h-1.5 mt-2 bg-blue-600 rounded-full mr-3"></span>
                    <span class="text-sm text-gray-700"><%= rec %></span>
                  </li>
                <% end %>
              </ul>
            </div>
          </div>
        </div>

        <!-- Historical Trends (Phase 6) -->
        <div class="mb-4 flex items-center justify-between">
          <div>
            <h2 class="text-lg font-semibold text-gray-900">📊 Historical Trends</h2>
            <p class="text-sm text-gray-500">Event counts and success rates over time</p>
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
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-8">
          <!-- Event Count Trend -->
          <div class="bg-white rounded-lg shadow">
            <div class="px-6 py-4 border-b border-gray-200">
              <h2 class="text-lg font-semibold text-gray-900">📈 Event Count Trend</h2>
              <p class="mt-1 text-sm text-gray-500">Last <%= @date_range %> days</p>
            </div>
            <div class="p-6">
              <div style="height: 300px;">
                <canvas
                  id="event-trend-chart"
                  phx-hook="ChartHook"
                  phx-update="ignore"
                  data-chart-data={@event_chart_data}
                  data-chart-type="line"
                ></canvas>
              </div>
            </div>
          </div>

          <!-- Success Rate Trend -->
          <div class="bg-white rounded-lg shadow">
            <div class="px-6 py-4 border-b border-gray-200">
              <h2 class="text-lg font-semibold text-gray-900">✅ Success Rate Trend</h2>
              <p class="mt-1 text-sm text-gray-500">Last <%= @date_range %> days</p>
            </div>
            <div class="p-6">
              <div style="height: 300px;">
                <canvas
                  id="success-rate-chart"
                  phx-hook="ChartHook"
                  phx-update="ignore"
                  data-chart-data={@success_chart_data}
                  data-chart-type="line"
                ></canvas>
              </div>
            </div>
          </div>
        </div>

        <!-- Run History -->
        <div class="bg-white rounded-lg shadow mb-8">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">Run History (Last 10)</h2>
          </div>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Time</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Duration</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Errors</th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for run <- @run_history do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      <%= format_datetime(run.completed_at) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <%= if run.state == "completed" do %>
                        <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-green-100 text-green-800">
                          ✅ Success
                        </span>
                      <% else %>
                        <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-red-100 text-red-800">
                          ❌ Failed
                        </span>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= format_duration(run.duration_seconds) %>
                    </td>
                    <td class="px-6 py-4 text-sm text-gray-500">
                      <%= if run.errors do %>
                        <span class="text-red-600 text-xs"><%= run.errors %></span>
                      <% else %>
                        <span class="text-gray-400">None</span>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
                <%= if Enum.empty?(@run_history) do %>
                  <tr>
                    <td colspan="4" class="px-6 py-4 text-center text-sm text-gray-500">
                      No run history available
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <!-- Recent Errors (if any) -->
        <%= if @stats.error_count > 0 && @stats.last_error do %>
          <div class="bg-red-50 border border-red-200 rounded-lg p-4 mb-8">
            <h3 class="text-lg font-semibold text-red-900 mb-2">Recent Errors</h3>
            <div class="text-sm text-red-700">
              <p class="font-mono bg-red-100 p-2 rounded"><%= @stats.last_error %></p>
            </div>
          </div>
        <% end %>

        <!-- Events by City (for city-scoped sources) -->
        <%= if @scope == :city && not Enum.empty?(@events_by_city) do %>
          <div class="bg-white rounded-lg shadow mb-8">
            <div class="px-6 py-4 border-b border-gray-200">
              <h2 class="text-lg font-semibold text-gray-900">Events by City</h2>
              <p class="text-sm text-gray-500 mt-1">Total events: <%= format_number(@total_events) %></p>
            </div>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-gray-50">
                  <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">City</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Events</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">New (Week)</th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-gray-200">
                  <%= for city <- @events_by_city do %>
                    <tr class="hover:bg-gray-50">
                      <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                        <%= city.city_name %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                        <%= format_number(city.event_count) %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                        +<%= city.new_this_week %>
                      </td>
                      <td class="px-6 py-4 whitespace-nowrap">
                        🟢
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        <% end %>

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

  defp format_datetime(nil), do: "Never"
  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %Y %I:%M %p")
  end
  defp format_datetime(%NaiveDateTime{} = dt) do
    dt
    |> DateTime.from_naive!("Etc/UTC")
    |> format_datetime()
  end

  defp format_duration(nil), do: "N/A"
  defp format_duration(seconds) when is_number(seconds) do
    cond do
      seconds < 60 -> "#{round(seconds)}s"
      seconds < 3600 -> "#{Float.round(seconds / 60, 1)}m"
      true -> "#{Float.round(seconds / 3600, 1)}h"
    end
  end
  defp format_duration(_), do: "N/A"
end
