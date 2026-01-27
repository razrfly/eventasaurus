defmodule EventasaurusWeb.Admin.CityHealthDetailLive do
  @moduledoc """
  Detailed health view for a single city.

  Shows comprehensive health metrics using the 4-component formula:
  - Event Coverage (40%): Days with events in last 14 days
  - Source Activity (30%): Recent sync job success rate
  - Data Quality (20%): Events with complete metadata
  - Venue Health (10%): Venues with complete information

  Uses CityHierarchy to aggregate metrics across metro area clusters.
  """
  use EventasaurusWeb, :live_view

  import Ecto.Query
  import EventasaurusWeb.Admin.Components.HealthComponents

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusApp.Venues.RegenerateSlugsByCityJob
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Locations.CityHierarchy
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Categories.Category
  alias EventasaurusDiscovery.Admin.CityHealthCalculator
  alias EventasaurusDiscovery.Admin.TrendAnalyzer
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary
  alias EventasaurusWeb.Admin.UnifiedDashboardStats

  # Auto-refresh every 5 minutes
  @refresh_interval :timer.minutes(5)

  # Valid sort columns for the source status table (whitelist for security)
  @valid_source_sort_columns ~w(display_name health_score success_rate p95_duration last_execution coverage_days)a

  # Valid sort columns for venues table
  @valid_venue_sort_columns ~w(venue_name event_count last_seen)a

  # Valid sort columns for category distribution table
  @valid_category_sort_columns ~w(category_name count percentage)a

  @type socket :: Phoenix.LiveView.Socket.t()

  @spec mount(map(), map(), socket()) :: {:ok, socket()}
  @impl true
  def mount(%{"city_slug" => city_slug}, _session, socket) do
    city = get_city_by_slug(city_slug)

    if city do
      if connected?(socket) do
        Process.send_after(self(), :refresh, @refresh_interval)
      end

      socket =
        socket
        |> assign(:page_title, "#{city.name} Health")
        |> assign(:city, city)
        |> assign(:city_slug, city_slug)
        |> assign(:loading, true)
        |> load_city_health_data()

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, "City not found")
       |> push_navigate(to: ~p"/admin/cities/health")}
    end
  end

  @spec handle_info(:refresh, socket()) :: {:noreply, socket()}
  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load_city_health_data(socket)}
  end

  @spec handle_event(String.t(), map(), socket()) :: {:noreply, socket()}
  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_city_health_data(socket)}
  end

  @impl true
  def handle_event("toggle_source", %{"source" => source_slug}, socket) do
    expanded = socket.assigns.expanded_sources

    expanded =
      if MapSet.member?(expanded, source_slug) do
        MapSet.delete(expanded, source_slug)
      else
        MapSet.put(expanded, source_slug)
      end

    {:noreply, assign(socket, :expanded_sources, expanded)}
  end

  @impl true
  def handle_event("expand_all_sources", _params, socket) do
    all_sources = MapSet.new(socket.assigns.source_data, & &1.slug)
    {:noreply, assign(socket, :expanded_sources, all_sources)}
  end

  @impl true
  def handle_event("collapse_all_sources", _params, socket) do
    {:noreply, assign(socket, :expanded_sources, MapSet.new())}
  end

  @impl true
  def handle_event("sort_sources", %{"column" => column}, socket) do
    column_atom = validate_source_sort_column(column)

    {new_sort_by, new_sort_dir} =
      if socket.assigns.sort_by == column_atom do
        # Toggle direction
        new_dir = if socket.assigns.sort_dir == :desc, do: :asc, else: :desc
        {column_atom, new_dir}
      else
        # New column, default to descending
        {column_atom, :desc}
      end

    sorted = sort_sources(socket.assigns.source_table_stats, new_sort_by, new_sort_dir)

    {:noreply,
     socket
     |> assign(:sort_by, new_sort_by)
     |> assign(:sort_dir, new_sort_dir)
     |> assign(:source_table_stats, sorted)}
  end

  @impl true
  def handle_event("sort_venues", %{"column" => column}, socket) do
    column_atom = validate_venue_sort_column(column)

    {new_sort_by, new_sort_dir} =
      if socket.assigns.venue_sort_by == column_atom do
        new_dir = if socket.assigns.venue_sort_dir == :desc, do: :asc, else: :desc
        {column_atom, new_dir}
      else
        {column_atom, :desc}
      end

    sorted = sort_venues(socket.assigns.top_venues, new_sort_by, new_sort_dir)

    {:noreply,
     socket
     |> assign(:venue_sort_by, new_sort_by)
     |> assign(:venue_sort_dir, new_sort_dir)
     |> assign(:top_venues, sorted)}
  end

  @impl true
  def handle_event("sort_categories", %{"column" => column}, socket) do
    column_atom = validate_category_sort_column(column)

    {new_sort_by, new_sort_dir} =
      if socket.assigns.category_sort_by == column_atom do
        new_dir = if socket.assigns.category_sort_dir == :desc, do: :asc, else: :desc
        {column_atom, new_dir}
      else
        {column_atom, :desc}
      end

    sorted = sort_categories(socket.assigns.category_distribution, new_sort_by, new_sort_dir)

    {:noreply,
     socket
     |> assign(:category_sort_by, new_sort_by)
     |> assign(:category_sort_dir, new_sort_dir)
     |> assign(:category_distribution, sorted)}
  end

  @impl true
  def handle_event("change_date_range", %{"date_range" => date_range}, socket) do
    date_range = parse_date_range(date_range)
    cluster_city_ids = socket.assigns.cluster_city_ids

    # Get new chart data for the selected date range (using cluster for metro area consistency)
    chart_data = get_chart_data(cluster_city_ids, date_range)

    socket =
      socket
      |> assign(:date_range, date_range)
      |> assign(:chart_data, chart_data)
      |> push_event("update-chart", %{
        chart_id: "city-event-trend-chart",
        chart_data: chart_data
      })

    {:noreply, socket}
  end

  @impl true
  def handle_event("regenerate_venue_slugs", _params, socket) do
    city = socket.assigns.city

    case RegenerateSlugsByCityJob.enqueue(city.id, city.slug) do
      {:ok, _job} ->
        socket =
          socket
          |> put_flash(
            :info,
            "✅ Venue slug regeneration queued for #{city.name}. This will take a few minutes."
          )

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> put_flash(:error, "Failed to queue slug regeneration: #{inspect(reason)}")

        {:noreply, socket}
    end
  end

  # Private helper to safely validate sort column from user input
  defp validate_source_sort_column(column) when is_binary(column) do
    column_map = Map.new(@valid_source_sort_columns, fn atom -> {Atom.to_string(atom), atom} end)
    Map.get(column_map, column, :health_score)
  end

  defp validate_source_sort_column(_), do: :health_score

  # Private helper to safely validate venue sort column from user input
  defp validate_venue_sort_column(column) when is_binary(column) do
    column_map = Map.new(@valid_venue_sort_columns, fn atom -> {Atom.to_string(atom), atom} end)
    Map.get(column_map, column, :event_count)
  end

  defp validate_venue_sort_column(_), do: :event_count

  # Private helper to safely validate category sort column from user input
  defp validate_category_sort_column(column) when is_binary(column) do
    column_map = Map.new(@valid_category_sort_columns, fn atom -> {Atom.to_string(atom), atom} end)
    Map.get(column_map, column, :count)
  end

  defp validate_category_sort_column(_), do: :count

  defp load_city_health_data(socket) do
    city = socket.assigns.city

    # Get metro area city IDs for aggregation
    cluster_city_ids = CityHierarchy.get_cluster_city_ids(city.id)

    # Calculate health for the primary city (handle deleted city case)
    case CityHealthCalculator.calculate_city_health(city.id) do
      {:ok, health_data} ->
        load_city_health_data_with_health(socket, city, cluster_city_ids, health_data)

      {:error, :city_not_found} ->
        # City was deleted between mount and refresh - redirect to list
        socket
        |> put_flash(:error, "City no longer exists")
        |> push_navigate(to: ~p"/admin/cities/health")
    end
  end

  defp load_city_health_data_with_health(socket, city, cluster_city_ids, health_data) do
    # Get additional metrics
    event_count = count_events(cluster_city_ids)
    upcoming_event_count = count_upcoming_events(cluster_city_ids)
    venue_count = count_venues(cluster_city_ids)
    category_count = count_categories(cluster_city_ids)
    source_data = get_source_data(cluster_city_ids)
    weekly_change = calculate_weekly_change(cluster_city_ids)
    sparkline_data = get_daily_sparkline_data(city.id)

    # Get top venues and category distribution (Phase 5)
    top_venues = get_top_venues(cluster_city_ids, 10)
    category_distribution = get_category_distribution(cluster_city_ids)

    # Get metro area info
    metro_cities = get_metro_cities(cluster_city_ids, city.id)

    # Get source errors for error lookup (pass source_data for worker pattern matching)
    source_errors = get_source_errors(source_data)

    # Preserve expanded state if already set, otherwise initialize empty
    expanded_sources = Map.get(socket.assigns, :expanded_sources, MapSet.new())

    # Preserve date range if already set, otherwise default to 30 days
    date_range = Map.get(socket.assigns, :date_range, 30)

    # Get chart data for the trend chart (using cluster for metro area consistency)
    chart_data = get_chart_data(cluster_city_ids, date_range)

    # Get source table stats using UnifiedDashboardStats (same format as admin dashboard)
    # Preserve sort state or initialize to health_score descending
    sort_by = Map.get(socket.assigns, :sort_by, :health_score)
    sort_dir = Map.get(socket.assigns, :sort_dir, :desc)
    source_table_stats = UnifiedDashboardStats.fetch_source_table_stats_for_city(cluster_city_ids)
    sorted_source_table_stats = sort_sources(source_table_stats, sort_by, sort_dir)

    # Preserve venue sort state or initialize to event_count descending
    venue_sort_by = Map.get(socket.assigns, :venue_sort_by, :event_count)
    venue_sort_dir = Map.get(socket.assigns, :venue_sort_dir, :desc)
    sorted_venues = sort_venues(top_venues, venue_sort_by, venue_sort_dir)

    # Preserve category sort state or initialize to count descending
    category_sort_by = Map.get(socket.assigns, :category_sort_by, :count)
    category_sort_dir = Map.get(socket.assigns, :category_sort_dir, :desc)
    sorted_categories = sort_categories(category_distribution, category_sort_by, category_sort_dir)

    # Calculate total events for category distribution
    total_category_events = Enum.sum(Enum.map(category_distribution, & &1.count))

    socket
    |> assign(:loading, false)
    |> assign(:health_data, health_data)
    |> assign(:cluster_city_ids, cluster_city_ids)
    |> assign(:metro_cities, metro_cities)
    |> assign(:event_count, event_count)
    |> assign(:upcoming_event_count, upcoming_event_count)
    |> assign(:venue_count, venue_count)
    |> assign(:category_count, category_count)
    |> assign(:source_data, source_data)
    |> assign(:source_table_stats, sorted_source_table_stats)
    |> assign(:source_errors, source_errors)
    |> assign(:expanded_sources, expanded_sources)
    |> assign(:weekly_change, weekly_change)
    |> assign(:sparkline, sparkline_data)
    |> assign(:date_range, date_range)
    |> assign(:chart_data, chart_data)
    |> assign(:top_venues, sorted_venues)
    |> assign(:category_distribution, sorted_categories)
    |> assign(:total_category_events, total_category_events)
    |> assign(:sort_by, sort_by)
    |> assign(:sort_dir, sort_dir)
    |> assign(:venue_sort_by, venue_sort_by)
    |> assign(:venue_sort_dir, venue_sort_dir)
    |> assign(:category_sort_by, category_sort_by)
    |> assign(:category_sort_dir, category_sort_dir)
    |> assign(:last_updated, DateTime.utc_now())
  end

  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen">
      <!-- Back Navigation -->
      <div class="bg-white border-b">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <.link
            navigate={~p"/admin/cities/health"}
            class="inline-flex items-center text-sm text-gray-500 hover:text-gray-700"
          >
            <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
            </svg>
            Back to City Health Dashboard
          </.link>
        </div>
      </div>

      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <%= if @loading do %>
          <div class="flex items-center justify-center h-64">
            <div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
          </div>
        <% else %>
          <!-- Header Section (Compact) -->
          <div class="flex items-center justify-between mb-6">
            <div>
              <h1 class="text-xl font-semibold text-gray-900 flex items-center gap-3">
                <%= @city.name %>
                <.health_score_pill score={@health_data.health_score} status={@health_data.health_status} />
              </h1>
              <div class="mt-1 text-sm text-gray-500 flex items-center gap-2">
                <span><%= @city.country.name %></span>
                <%= if length(@metro_cities) > 0 do %>
                  <span class="text-gray-300">•</span>
                  <span>Metro area: <%= length(@metro_cities) + 1 %> cities</span>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Health Overview (Admin Dashboard Style) -->
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
            <.admin_stat_card
              title="Events Discovered"
              value={format_number(@event_count)}
              icon_type={:chart}
              color={:blue}
              subtitle={"#{format_number(@upcoming_event_count)} upcoming • #{format_change(@weekly_change)} this week"}
            />
            <.admin_stat_card
              title="Active Sources"
              value={length(@source_table_stats || [])}
              icon_type={:plug}
              color={:purple}
              subtitle={"#{count_healthy_sources(@source_table_stats || [])} healthy"}
            />
            <.admin_stat_card
              title="Venues"
              value={format_number(@venue_count)}
              icon_type={:location}
              color={:green}
            />
            <.admin_stat_card
              title="Categories"
              value={@category_count}
              icon_type={:tag}
              color={:yellow}
            />
          </div>

          <!-- Health Score Breakdown (4-Column Grid) -->
          <div class="mb-6">
            <h2 class="text-lg font-semibold text-gray-900 mb-4">Health Score Breakdown</h2>

            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
              <.health_metric_card
                label="Event Coverage"
                value={@health_data.components.event_coverage}
                weight="40%"
                color={component_color(@health_data.components.event_coverage)}
                target={80}
                description="7-day availability"
              />

              <.health_metric_card
                label="Source Activity"
                value={@health_data.components.source_activity}
                weight="30%"
                color={component_color(@health_data.components.source_activity)}
                target={90}
                description="Job success rate"
              />

              <.health_metric_card
                label="Data Quality"
                value={@health_data.components.data_quality}
                weight="20%"
                color={component_color(@health_data.components.data_quality)}
                target={85}
                description="Events with metadata"
              />

              <.health_metric_card
                label="Venue Health"
                value={@health_data.components.venue_health}
                weight="10%"
                color={component_color(@health_data.components.venue_health)}
                target={90}
                description="Venues with slugs"
              />
            </div>
          </div>

          <!-- Event Trend Chart -->
          <div class="bg-white rounded-lg shadow-sm border p-6 mb-6">
            <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-4">
              <div class="flex items-center gap-3">
                <h2 class="text-lg font-semibold text-gray-900">Event Trend</h2>
                <.trend_indicator change={@weekly_change} size={:sm} />
              </div>

              <!-- Date Range Selector -->
              <form phx-change="change_date_range" class="flex items-center gap-2">
                <label for="date-range" class="text-sm text-gray-500">Period:</label>
                <select
                  id="date-range"
                  name="date_range"
                  class="text-sm border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500"
                >
                  <option value="7" selected={@date_range == 7}>Last 7 days</option>
                  <option value="14" selected={@date_range == 14}>Last 14 days</option>
                  <option value="30" selected={@date_range == 30}>Last 30 days</option>
                  <option value="90" selected={@date_range == 90}>Last 90 days</option>
                </select>
              </form>
            </div>

            <!-- Chart Container -->
            <div class="h-64">
              <canvas
                id="city-event-trend-chart"
                phx-hook="ChartHook"
                phx-update="ignore"
                data-chart-data={Jason.encode!(@chart_data)}
                data-chart-type="line"
                class="w-full h-full"
              >
              </canvas>
            </div>

            <!-- Quick Stats Below Chart -->
            <div class="mt-4 pt-4 border-t grid grid-cols-3 gap-4 text-center">
              <div>
                <div class="text-2xl font-bold text-gray-900">
                  <%= total_events_in_period(@chart_data) %>
                </div>
                <div class="text-xs text-gray-500">Total Events</div>
              </div>
              <div>
                <div class="text-2xl font-bold text-gray-900">
                  <%= avg_events_per_day(@chart_data) %>
                </div>
                <div class="text-xs text-gray-500">Avg/Day</div>
              </div>
              <div>
                <div class="text-2xl font-bold text-gray-900">
                  <%= peak_events_day(@chart_data) %>
                </div>
                <div class="text-xs text-gray-500">Peak Day</div>
              </div>
            </div>
          </div>

          <!-- Source Status Table (same design as admin dashboard) -->
          <.source_status_table
            sources={@source_table_stats}
            title="Source Status"
            sort_by={@sort_by}
            sort_dir={@sort_dir}
            on_sort="sort_sources"
            empty_state_text="No sources found for this city."
          />

          <!-- Top Venues Table (Phase 5) -->
          <div class="mb-6">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-xl font-semibold text-gray-900">Top Venues</h2>
              <div class="flex items-center gap-4">
                <button
                  phx-click="regenerate_venue_slugs"
                  class="text-sm text-amber-600 hover:text-amber-800 font-medium"
                >
                  🔄 Regenerate Slugs
                </button>
                <.link
                  navigate={~p"/venues/duplicates"}
                  class="text-sm text-blue-600 hover:text-blue-800 font-medium"
                >
                  View All &rarr;
                </.link>
              </div>
            </div>

            <%= if Enum.empty?(@top_venues) do %>
              <div class="bg-white shadow rounded-lg overflow-hidden px-6 py-12 text-center text-gray-500">
                <p>No venues found for this city.</p>
              </div>
            <% else %>
              <div class="bg-white shadow rounded-lg overflow-hidden">
                <div class="overflow-x-auto">
                  <table class="min-w-full">
                    <thead class="bg-gray-50 border-b border-gray-200">
                      <tr>
                        <th
                          scope="col"
                          class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100 select-none"
                          phx-click="sort_venues"
                          phx-value-column="venue_name"
                        >
                          <div class="flex items-center gap-1">
                            Venue
                            <%= if @venue_sort_by == :venue_name do %>
                              <span class="text-blue-600"><%= if @venue_sort_dir == :asc, do: "▲", else: "▼" %></span>
                            <% end %>
                          </div>
                        </th>
                        <th
                          scope="col"
                          class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100 select-none"
                          phx-click="sort_venues"
                          phx-value-column="event_count"
                        >
                          <div class="flex items-center justify-end gap-1">
                            Events
                            <%= if @venue_sort_by == :event_count do %>
                              <span class="text-blue-600"><%= if @venue_sort_dir == :asc, do: "▲", else: "▼" %></span>
                            <% end %>
                          </div>
                        </th>
                        <th scope="col" class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                          Sources
                        </th>
                        <th
                          scope="col"
                          class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100 select-none"
                          phx-click="sort_venues"
                          phx-value-column="last_seen"
                        >
                          <div class="flex items-center justify-end gap-1">
                            Last Seen
                            <%= if @venue_sort_by == :last_seen do %>
                              <span class="text-blue-600"><%= if @venue_sort_dir == :asc, do: "▲", else: "▼" %></span>
                            <% end %>
                          </div>
                        </th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-gray-100">
                      <%= for venue <- @top_venues do %>
                        <tr class="hover:bg-gray-50 transition-colors">
                          <td class="px-4 py-3 whitespace-nowrap">
                            <.link
                              navigate={~p"/venues/duplicates?venue_id=#{venue.venue_id}"}
                              class="text-sm font-medium text-gray-900 hover:text-blue-600"
                            >
                              <%= venue.venue_name %>
                            </.link>
                          </td>
                          <td class="px-4 py-3 whitespace-nowrap text-right">
                            <span class="text-sm font-medium text-gray-900">
                              <%= venue.event_count %>
                            </span>
                          </td>
                          <td class="px-4 py-3 whitespace-nowrap">
                            <span class="text-sm text-gray-600">
                              <%= format_sources_list(venue.sources) %>
                            </span>
                          </td>
                          <td class="px-4 py-3 whitespace-nowrap text-right">
                            <span class="text-sm text-gray-500">
                              <%= format_compact_time(venue.last_seen) %>
                            </span>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </div>
            <% end %>
          </div>

          <!-- Category Distribution (Phase 5) -->
          <div class="mb-6">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-xl font-semibold text-gray-900">Category Distribution</h2>
              <span class="text-sm text-gray-500">Total: <%= @total_category_events %> events</span>
            </div>

            <%= if Enum.empty?(@category_distribution) do %>
              <div class="bg-white shadow rounded-lg overflow-hidden px-6 py-12 text-center text-gray-500">
                <p>No category data available.</p>
              </div>
            <% else %>
              <div class="bg-white shadow rounded-lg overflow-hidden">
                <div class="overflow-x-auto">
                  <table class="min-w-full">
                    <thead class="bg-gray-50 border-b border-gray-200">
                      <tr>
                        <th
                          scope="col"
                          class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100 select-none"
                          phx-click="sort_categories"
                          phx-value-column="category_name"
                        >
                          <div class="flex items-center gap-1">
                            Category
                            <%= if @category_sort_by == :category_name do %>
                              <span class="text-blue-600"><%= if @category_sort_dir == :asc, do: "▲", else: "▼" %></span>
                            <% end %>
                          </div>
                        </th>
                        <th
                          scope="col"
                          class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100 select-none w-24"
                          phx-click="sort_categories"
                          phx-value-column="count"
                        >
                          <div class="flex items-center justify-end gap-1">
                            Events
                            <%= if @category_sort_by == :count do %>
                              <span class="text-blue-600"><%= if @category_sort_dir == :asc, do: "▲", else: "▼" %></span>
                            <% end %>
                          </div>
                        </th>
                        <th
                          scope="col"
                          class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100 select-none w-20"
                          phx-click="sort_categories"
                          phx-value-column="percentage"
                        >
                          <div class="flex items-center justify-end gap-1">
                            %
                            <%= if @category_sort_by == :percentage do %>
                              <span class="text-blue-600"><%= if @category_sort_dir == :asc, do: "▲", else: "▼" %></span>
                            <% end %>
                          </div>
                        </th>
                        <th scope="col" class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                          Distribution
                        </th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-gray-100">
                      <%= for category <- @category_distribution do %>
                        <tr class="hover:bg-gray-50 transition-colors">
                          <td class="px-4 py-3 whitespace-nowrap">
                            <span class={"text-sm font-medium #{if category.category_slug == "unknown", do: "text-gray-500 italic", else: "text-gray-900"}"}>
                              <%= category.category_name %>
                            </span>
                          </td>
                          <td class="px-4 py-3 whitespace-nowrap text-right">
                            <span class="text-sm font-medium text-gray-900">
                              <%= category.count %>
                            </span>
                          </td>
                          <td class="px-4 py-3 whitespace-nowrap text-right">
                            <span class="text-sm text-gray-600">
                              <%= category.percentage %>%
                            </span>
                          </td>
                          <td class="px-4 py-3">
                            <div class="w-full bg-gray-100 rounded-full h-2 overflow-hidden">
                              <div
                                class={"h-full rounded-full transition-all #{if category.category_slug == "unknown", do: "bg-gray-400", else: "bg-blue-500"}"}
                                style={"width: #{category.percentage}%"}
                              >
                              </div>
                            </div>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </div>
            <% end %>
          </div>

          <!-- Metro Area Cities (if applicable) -->
          <%= if length(@metro_cities) > 0 do %>
            <div class="bg-white rounded-lg shadow-sm border p-6 mb-6">
              <h2 class="text-lg font-semibold text-gray-900 mb-4">Metro Area Cities</h2>
              <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
                <%= for metro_city <- @metro_cities do %>
                  <div class="px-3 py-2 bg-gray-50 rounded-lg text-sm">
                    <span class="font-medium text-gray-900"><%= metro_city.name %></span>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <!-- Last Updated -->
          <div class="text-center text-sm text-gray-500">
            Last updated: <%= time_ago_in_words(@last_updated) %>
            <button
              phx-click="refresh"
              class="ml-2 text-blue-600 hover:text-blue-800"
            >
              Refresh
            </button>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Private Functions

  # Valid date ranges for the chart selector
  @valid_date_ranges [7, 14, 30, 90]

  defp parse_date_range(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int in @valid_date_ranges -> int
      _ -> 30  # Default to 30 days for invalid input
    end
  end

  defp parse_date_range(value) when is_integer(value) and value in @valid_date_ranges, do: value
  defp parse_date_range(_), do: 30

  defp get_city_by_slug(slug) do
    from(c in City,
      where: c.slug == ^slug,
      preload: [:country]
    )
    |> Repo.one()
  end

  # Count events added to DB in last 30 days (discovery activity)
  defp count_events(city_ids) do
    now = DateTime.utc_now()
    thirty_days_ago = DateTime.add(now, -30, :day)

    from(e in PublicEvent,
      join: v in Venue,
      on: v.id == e.venue_id,
      where: v.city_id in ^city_ids,
      where: e.inserted_at >= ^thirty_days_ago
    )
    |> Repo.replica().aggregate(:count, :id, timeout: 30_000)
  end

  # Count events with future start dates (upcoming events for users)
  defp count_upcoming_events(city_ids) do
    now = NaiveDateTime.utc_now()

    from(e in PublicEvent,
      join: v in Venue,
      on: v.id == e.venue_id,
      where: v.city_id in ^city_ids,
      where: e.starts_at > ^now
    )
    |> Repo.replica().aggregate(:count, :id, timeout: 30_000)
  end

  defp count_venues(city_ids) do
    from(v in Venue,
      where: v.city_id in ^city_ids
    )
    |> Repo.replica().aggregate(:count, :id, timeout: 30_000)
  end

  defp count_categories(city_ids) do
    # Use join table instead of deprecated category_id field
    from(e in PublicEvent,
      join: v in Venue,
      on: v.id == e.venue_id,
      join: pec in "public_event_categories",
      on: pec.event_id == e.id,
      where: v.city_id in ^city_ids,
      select: count(pec.category_id, :distinct)
    )
    |> Repo.replica().one(timeout: 30_000) || 0
  end

  defp get_source_data(city_ids) do
    # Get sources that have events in these cities
    now = DateTime.utc_now()
    seven_days_ago = DateTime.add(now, -7, :day)

    sources =
      from(pes in PublicEventSource,
        join: pe in PublicEvent,
        on: pe.id == pes.event_id,
        join: v in Venue,
        on: v.id == pe.venue_id,
        join: s in Source,
        on: s.id == pes.source_id,
        where: v.city_id in ^city_ids,
        where: pe.inserted_at >= ^seven_days_ago,
        group_by: [s.id, s.name, s.slug],
        select: %{
          id: s.id,
          name: s.name,
          slug: s.slug,
          event_count: count(pe.id, :distinct)
        },
        order_by: [desc: count(pe.id, :distinct)]
      )
      |> Repo.replica().all(timeout: 30_000)

    # Enrich with job success rates (pass full sources for worker pattern matching)
    job_stats = get_source_job_stats(sources)

    # Get recent job history for the timeline visualization
    recent_jobs_by_source = get_source_recent_jobs(sources)

    Enum.map(sources, fn source ->
      stats = Map.get(job_stats, source.id, %{success_rate: 0, total_jobs: 0})
      health_status = calculate_source_health(stats.success_rate)
      recent_jobs = Map.get(recent_jobs_by_source, source.slug, [])

      source
      |> Map.put(:success_rate, stats.success_rate)
      |> Map.put(:total_jobs, stats.total_jobs)
      |> Map.put(:health_status, health_status)
      |> Map.put(:recent_jobs, recent_jobs)
    end)
  end

  defp get_source_job_stats(sources) when sources == [], do: %{}

  defp get_source_job_stats(sources) do
    now = DateTime.utc_now()
    seven_days_ago = DateTime.add(now, -7, :day)

    # Extract source from worker name using regex, then group by it
    # Worker format: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob"
    from(j in JobExecutionSummary,
      where: j.attempted_at >= ^seven_days_ago,
      where: like(j.worker, "EventasaurusDiscovery.Sources.%"),
      group_by: fragment("substring(? from 'Sources\\.([^.]+)\\.Jobs')", j.worker),
      select: %{
        source_match: fragment("substring(? from 'Sources\\.([^.]+)\\.Jobs')", j.worker),
        total: count(j.id),
        successes: sum(fragment("CASE WHEN ? = 'completed' THEN 1 ELSE 0 END", j.state))
      }
    )
    |> Repo.replica().all(timeout: 30_000)
    |> Enum.reduce(%{}, fn row, acc ->
      # Convert PascalCase source match to canonical hyphenated slug
      # CinemaCity -> cinema-city (matches database slug format)
      slug = Source.module_name_to_slug(row.source_match || "")

      # Find the source by slug to get the ID
      source = Enum.find(sources, fn s -> s.slug == slug end)

      if source do
        success_rate =
          if row.total > 0 do
            round((row.successes || 0) / row.total * 100)
          else
            0
          end

        Map.put(acc, source.id, %{success_rate: success_rate, total_jobs: row.total})
      else
        acc
      end
    end)
  end

  defp get_source_recent_jobs(sources) when sources == [], do: %{}

  defp get_source_recent_jobs(sources) do
    now = DateTime.utc_now()
    seven_days_ago = DateTime.add(now, -7, :day)

    # Only fetch SyncJob runs for the timeline (main orchestrator jobs)
    # Limit to 10 most recent per source
    from(j in JobExecutionSummary,
      where: j.attempted_at >= ^seven_days_ago,
      where: like(j.worker, "EventasaurusDiscovery.Sources.%"),
      where: like(j.worker, "%SyncJob"),
      order_by: [desc: j.attempted_at],
      select: %{
        id: j.id,
        worker: j.worker,
        state: j.state,
        attempted_at: j.attempted_at,
        completed_at: j.completed_at,
        duration_seconds: fragment("EXTRACT(EPOCH FROM (? - ?))", j.completed_at, j.attempted_at),
        errors: fragment("?->>'error_message'", j.results)
      }
    )
    |> Repo.replica().all(timeout: 30_000)
    |> Enum.reduce(%{}, fn job, acc ->
      # Extract source slug from worker name
      # Worker format: "EventasaurusDiscovery.Sources.CinemaCity.Jobs.SyncJob"
      source_match = Regex.run(~r/Sources\.([^.]+)\.Jobs/, job.worker)

      if source_match do
        # Convert PascalCase module name to canonical hyphenated slug
        slug = source_match |> List.last() |> Source.module_name_to_slug()

        # Only add if we have this source and haven't exceeded 10 jobs
        if Enum.any?(sources, fn s -> s.slug == slug end) do
          current_jobs = Map.get(acc, slug, [])

          if length(current_jobs) < 10 do
            # Convert state from "completed" to "success" for display consistency
            state = if job.state == "completed", do: "success", else: job.state

            job_with_state = %{
              id: job.id,
              state: state,
              completed_at: job.completed_at || job.attempted_at,
              duration_seconds: parse_duration(job.duration_seconds),
              errors: job.errors
            }

            Map.put(acc, slug, current_jobs ++ [job_with_state])
          else
            acc
          end
        else
          acc
        end
      else
        acc
      end
    end)
  end

  # Parse duration from SQL result, handling Decimal type
  defp parse_duration(nil), do: 0
  defp parse_duration(%Decimal{} = d), do: d |> Decimal.round() |> Decimal.to_integer()
  defp parse_duration(d) when is_float(d), do: round(d)
  defp parse_duration(d) when is_integer(d), do: d
  defp parse_duration(_), do: 0

  defp calculate_source_health(success_rate) when success_rate >= 90, do: :healthy
  defp calculate_source_health(success_rate) when success_rate >= 70, do: :warning
  defp calculate_source_health(_), do: :critical

  defp get_source_errors(sources) when sources == [], do: %{}

  defp get_source_errors(sources) do
    now = DateTime.utc_now()
    twenty_four_hours_ago = DateTime.add(now, -24, :hour)

    # Query errors using worker pattern matching (same approach as get_source_job_stats)
    from(j in JobExecutionSummary,
      where: j.attempted_at >= ^twenty_four_hours_ago,
      where: like(j.worker, "EventasaurusDiscovery.Sources.%"),
      where: j.state in ["failure", "cancelled", "discarded"],
      order_by: [desc: j.attempted_at],
      select: %{
        id: j.id,
        source_match: fragment("substring(? from 'Sources\\.([^.]+)\\.Jobs')", j.worker),
        worker: j.worker,
        state: j.state,
        attempted_at: j.attempted_at,
        error_category: fragment("?->>'error_category'", j.results),
        error_message: fragment("?->>'error'", j.results)
      }
    )
    |> Repo.replica().all(timeout: 30_000)
    |> Enum.reduce(%{}, fn row, acc ->
      # Convert PascalCase source match to canonical hyphenated slug (CinemaCity -> cinema-city)
      slug = Source.module_name_to_slug(row.source_match || "")

      # Find the source by slug to get the ID
      source = Enum.find(sources, fn s -> s.slug == slug end)

      if source do
        errors = Map.get(acc, source.id, [])

        error_entry = %{
          id: row.id,
          worker: row.worker,
          state: row.state,
          attempted_at: row.attempted_at,
          error_category: row.error_category,
          error_message: row.error_message
        }

        Map.put(acc, source.id, [error_entry | errors])
      else
        acc
      end
    end)
    # Reverse each list to maintain order (newest first)
    |> Enum.map(fn {source_id, errors} -> {source_id, Enum.reverse(errors)} end)
    |> Map.new()
  end

  defp calculate_weekly_change(city_ids) do
    now = DateTime.utc_now()
    one_week_ago = DateTime.add(now, -7, :day)
    two_weeks_ago = DateTime.add(now, -14, :day)

    this_week =
      from(e in PublicEvent,
        join: v in Venue,
        on: v.id == e.venue_id,
        where: v.city_id in ^city_ids,
        where: e.inserted_at >= ^one_week_ago
      )
      |> Repo.replica().aggregate(:count, :id, timeout: 30_000)

    last_week =
      from(e in PublicEvent,
        join: v in Venue,
        on: v.id == e.venue_id,
        where: v.city_id in ^city_ids,
        where: e.inserted_at >= ^two_weeks_ago,
        where: e.inserted_at < ^one_week_ago
      )
      |> Repo.replica().aggregate(:count, :id, timeout: 30_000)

    if last_week > 0 do
      round((this_week - last_week) / last_week * 100)
    else
      if this_week > 0, do: 100, else: 0
    end
  end

  defp get_daily_sparkline_data(city_id) do
    # Get event counts for last 7 days
    now = DateTime.utc_now()
    seven_days_ago = DateTime.add(now, -7, :day)

    # Get cluster for this city
    cluster_city_ids = CityHierarchy.get_cluster_city_ids(city_id)

    daily_counts =
      from(e in PublicEvent,
        join: v in Venue,
        on: v.id == e.venue_id,
        where: v.city_id in ^cluster_city_ids,
        where: e.inserted_at >= ^seven_days_ago,
        group_by: fragment("DATE(?)::date", e.inserted_at),
        select: %{
          date: fragment("DATE(?)::date", e.inserted_at),
          count: count(e.id)
        },
        order_by: [asc: fragment("DATE(?)::date", e.inserted_at)]
      )
      |> Repo.replica().all(timeout: 30_000)

    # Fill in missing days with 0
    today = Date.utc_today()
    dates = Enum.map(6..0//-1, fn days_ago -> Date.add(today, -days_ago) end)
    counts_by_date = Map.new(daily_counts, fn %{date: d, count: c} -> {d, c} end)

    Enum.map(dates, fn date -> Map.get(counts_by_date, date, 0) end)
  end

  defp get_metro_cities(cluster_city_ids, primary_city_id) do
    other_ids = Enum.reject(cluster_city_ids, &(&1 == primary_city_id))

    if Enum.empty?(other_ids) do
      []
    else
      from(c in City,
        where: c.id in ^other_ids,
        order_by: [asc: c.name],
        select: %{id: c.id, name: c.name, slug: c.slug}
      )
      |> Repo.all()
    end
  end

  defp get_chart_data(city_ids, date_range) do
    # Get event trend data for the chart (supports single city or metro cluster)
    city_event_trend = TrendAnalyzer.get_city_event_trend(city_ids, date_range)
    TrendAnalyzer.format_for_chartjs(city_event_trend, :count, "Events", "#3B82F6")
  end

  defp count_healthy_sources(source_data) do
    Enum.count(source_data, fn s -> s.health_status == :healthy end)
  end

  defp format_number(num) when num >= 1_000_000, do: "#{Float.round(num / 1_000_000, 1)}M"
  defp format_number(num) when num >= 1_000, do: "#{Float.round(num / 1_000, 1)}K"
  defp format_number(num), do: to_string(num)

  # Chart stat helpers
  defp total_events_in_period(%{datasets: [%{data: data} | _]}) do
    Enum.sum(data) |> format_number()
  end

  defp total_events_in_period(_), do: "0"

  defp avg_events_per_day(%{datasets: [%{data: data} | _]}) when length(data) > 0 do
    avg = Enum.sum(data) / length(data)
    Float.round(avg, 1) |> format_decimal()
  end

  defp avg_events_per_day(_), do: "0"

  defp peak_events_day(%{datasets: [%{data: data} | _], labels: labels})
       when length(data) > 0 and length(labels) > 0 do
    max_value = Enum.max(data)
    max_index = Enum.find_index(data, fn x -> x == max_value end)
    Enum.at(labels, max_index) || "N/A"
  end

  defp peak_events_day(_), do: "N/A"

  defp format_decimal(num) when is_float(num) do
    if Float.floor(num) == num do
      trunc(num) |> to_string()
    else
      :erlang.float_to_binary(num, decimals: 1)
    end
  end

  defp format_decimal(num), do: to_string(num)

  # Phase 5: Top Venues
  defp get_top_venues(city_ids, limit) do
    now = DateTime.utc_now()
    thirty_days_ago = DateTime.add(now, -30, :day)

    from(e in PublicEvent,
      join: v in Venue,
      on: v.id == e.venue_id,
      left_join: pes in PublicEventSource,
      on: pes.event_id == e.id,
      left_join: s in Source,
      on: s.id == pes.source_id,
      where: v.city_id in ^city_ids,
      where: e.inserted_at >= ^thirty_days_ago,
      group_by: [v.id, v.name, v.slug],
      order_by: [desc: count(e.id, :distinct)],
      limit: ^limit,
      select: %{
        venue_id: v.id,
        venue_name: v.name,
        venue_slug: v.slug,
        event_count: count(e.id, :distinct),
        sources: fragment("array_agg(DISTINCT ?)", s.name),
        last_seen: max(e.inserted_at)
      }
    )
    |> Repo.replica().all(timeout: 30_000)
    |> Enum.map(fn venue ->
      # Clean up sources array (remove nils)
      sources = venue.sources |> Enum.reject(&is_nil/1) |> Enum.uniq()
      %{venue | sources: sources}
    end)
  end

  # Phase 5: Category Distribution
  defp get_category_distribution(city_ids) do
    now = DateTime.utc_now()
    thirty_days_ago = DateTime.add(now, -30, :day)

    # Get categorized events
    categorized =
      from(e in PublicEvent,
        join: v in Venue,
        on: v.id == e.venue_id,
        join: pec in "public_event_categories",
        on: pec.event_id == e.id,
        join: c in Category,
        on: c.id == pec.category_id,
        where: v.city_id in ^city_ids,
        where: e.inserted_at >= ^thirty_days_ago,
        group_by: [c.id, c.name, c.slug],
        order_by: [desc: count(e.id)],
        select: %{
          category_id: c.id,
          category_name: c.name,
          category_slug: c.slug,
          count: count(e.id)
        }
      )
      |> Repo.replica().all(timeout: 30_000)

    # Get total count of events with categories
    total_categorized = Enum.sum(Enum.map(categorized, & &1.count))

    # Count uncategorized events
    uncategorized_count =
      from(e in PublicEvent,
        join: v in Venue,
        on: v.id == e.venue_id,
        left_join: pec in "public_event_categories",
        on: pec.event_id == e.id,
        where: v.city_id in ^city_ids,
        where: e.inserted_at >= ^thirty_days_ago,
        where: is_nil(pec.category_id),
        select: count(e.id, :distinct)
      )
      |> Repo.replica().one(timeout: 30_000) || 0

    # Calculate total for percentages
    total = total_categorized + uncategorized_count

    # Calculate percentages and add to result
    categories_with_percentage =
      Enum.map(categorized, fn cat ->
        percentage = if total > 0, do: round(cat.count / total * 100), else: 0
        Map.put(cat, :percentage, percentage)
      end)

    # Add "Unknown" category if there are uncategorized events
    if uncategorized_count > 0 do
      percentage = if total > 0, do: round(uncategorized_count / total * 100), else: 0

      categories_with_percentage ++
        [
          %{
            category_id: nil,
            category_name: "Unknown",
            category_slug: "unknown",
            count: uncategorized_count,
            percentage: percentage
          }
        ]
    else
      categories_with_percentage
    end
  end

  # Sort sources for the source_status_table component
  defp sort_sources(sources, sort_by, sort_dir) when is_list(sources) do
    Enum.sort_by(sources, &source_sort_key(&1, sort_by), sort_dir)
  end

  defp sort_sources(sources, _sort_by, _sort_dir), do: sources

  defp source_sort_key(source, :display_name), do: String.downcase(source.display_name || source.name || "")
  defp source_sort_key(source, :health_score), do: source.health_score || 0
  defp source_sort_key(source, :success_rate), do: source.success_rate || 0
  defp source_sort_key(source, :p95_duration), do: source.p95_duration || 0
  defp source_sort_key(source, :last_execution), do: source.last_execution || ~U[1970-01-01 00:00:00Z]
  defp source_sort_key(source, :coverage_days), do: source.coverage_days || 0
  defp source_sort_key(_source, _), do: 0

  # Sort venues for the top venues table
  defp sort_venues(venues, sort_by, sort_dir) when is_list(venues) do
    Enum.sort_by(venues, &venue_sort_key(&1, sort_by), sort_dir)
  end

  defp sort_venues(venues, _sort_by, _sort_dir), do: venues

  defp venue_sort_key(venue, :venue_name), do: String.downcase(venue.venue_name || "")
  defp venue_sort_key(venue, :event_count), do: venue.event_count || 0
  defp venue_sort_key(venue, :last_seen), do: venue.last_seen || ~N[1970-01-01 00:00:00]
  defp venue_sort_key(_venue, _), do: 0

  # Sort categories for the category distribution table
  defp sort_categories(categories, sort_by, sort_dir) when is_list(categories) do
    Enum.sort_by(categories, &category_sort_key(&1, sort_by), sort_dir)
  end

  defp sort_categories(categories, _sort_by, _sort_dir), do: categories

  defp category_sort_key(cat, :category_name), do: String.downcase(cat.category_name || "")
  defp category_sort_key(cat, :count), do: cat.count || 0
  defp category_sort_key(cat, :percentage), do: cat.percentage || 0
  defp category_sort_key(_cat, _), do: 0

  # Format sources list with truncation (comma-separated, max 2 shown)
  defp format_sources_list(nil), do: "—"
  defp format_sources_list([]), do: "—"

  defp format_sources_list(sources) when is_list(sources) do
    case length(sources) do
      0 -> "—"
      1 -> Enum.at(sources, 0)
      2 -> Enum.join(sources, ", ")
      n -> "#{Enum.join(Enum.take(sources, 2), ", ")} +#{n - 2}"
    end
  end

  # Format time in compact form (2h, 1d, etc.)
  defp format_compact_time(nil), do: "—"

  defp format_compact_time(%NaiveDateTime{} = naive_dt) do
    datetime = DateTime.from_naive!(naive_dt, "Etc/UTC")
    format_compact_time(datetime)
  end

  defp format_compact_time(%DateTime{} = datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime)

    cond do
      diff_seconds < 60 -> "now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h"
      diff_seconds < 604_800 -> "#{div(diff_seconds, 86400)}d"
      diff_seconds < 2_592_000 -> "#{div(diff_seconds, 604_800)}w"
      true -> "#{div(diff_seconds, 2_592_000)}mo"
    end
  end
end
