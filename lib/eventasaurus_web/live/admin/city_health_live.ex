defmodule EventasaurusWeb.Admin.CityHealthLive do
  @moduledoc """
  Admin dashboard for monitoring city health metrics.

  Shows an overview of all cities with health indicators based on a 4-component formula:
  - Event Coverage (40%): Days with events in last 14 days
  - Source Activity (30%): Recent sync job success rate
  - Data Quality (20%): Events with complete metadata
  - Venue Health (10%): Venues with complete information

  Phase 1: Basic health overview with simple indicators.
  Phase 2: Health score calculation with 4-component formula.
  Phase 3: Activity feed and health status filtering.
  """
  use EventasaurusWeb, :live_view

  import Ecto.Query
  import EventasaurusWeb.Admin.Components.HealthComponents

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary
  alias EventasaurusDiscovery.Admin.CityHealthCalculator
  alias EventasaurusApp.Venues.Venue

  # Auto-refresh every 5 minutes
  @refresh_interval :timer.minutes(5)

  @type socket :: Phoenix.LiveView.Socket.t()

  @spec mount(map(), map(), socket()) :: {:ok, socket()}
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh, @refresh_interval)
    end

    socket =
      socket
      |> assign(:page_title, "City Health Dashboard")
      |> assign(:loading, true)
      |> assign(:expanded_cities, MapSet.new())
      |> assign(:status_filter, "all")
      |> assign(:sort_column, :event_count)
      |> assign(:sort_direction, :desc)
      |> load_city_health_data()

    {:ok, socket}
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
  def handle_event("toggle_city", %{"city-id" => city_id}, socket) do
    city_id = String.to_integer(city_id)
    expanded = socket.assigns.expanded_cities

    new_expanded =
      if MapSet.member?(expanded, city_id) do
        MapSet.delete(expanded, city_id)
      else
        MapSet.put(expanded, city_id)
      end

    {:noreply, assign(socket, :expanded_cities, new_expanded)}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    {:noreply, assign(socket, :status_filter, status)}
  end

  # Valid sort columns for whitelist validation
  @valid_sort_columns ~w(name health_score event_count weekly_change venue_count source_count)a

  @impl true
  def handle_event("sort", %{"column" => column}, socket) do
    column_atom = validate_sort_column(column)

    {new_column, new_direction} =
      if socket.assigns.sort_column == column_atom do
        # Toggle direction if same column
        new_dir = if socket.assigns.sort_direction == :asc, do: :desc, else: :asc
        {column_atom, new_dir}
      else
        # Default to descending for new column (except name which defaults to asc)
        default_dir = if column_atom == :name, do: :asc, else: :desc
        {column_atom, default_dir}
      end

    {:noreply,
     socket
     |> assign(:sort_column, new_column)
     |> assign(:sort_direction, new_direction)}
  end

  defp validate_sort_column(column) when is_binary(column) do
    case String.to_existing_atom(column) do
      atom when atom in @valid_sort_columns -> atom
      _ -> :event_count  # Default fallback
    end
  rescue
    ArgumentError -> :event_count  # Atom doesn't exist
  end

  defp validate_sort_column(_), do: :event_count

  defp load_city_health_data(socket) do
    # Use the new CityHealthCalculator for proper 4-component health scores
    # Only get active cities (with events), ordered by event count
    cities_health = CityHealthCalculator.get_active_cities_health(limit: 100)

    # Get additional data for enrichment
    source_coverage = get_source_coverage_by_city()
    all_sources = get_all_active_sources()
    weekly_changes = get_weekly_changes()
    daily_sparklines = get_daily_sparkline_data()

    # Enrich cities with source coverage, weekly change, and sparkline data
    cities_with_sources =
      Enum.map(cities_health, fn city ->
        city_sources = Map.get(source_coverage, city.city_id, [])
        source_count = length(city_sources)
        weekly_change = Map.get(weekly_changes, city.city_id, 0)
        sparkline = Map.get(daily_sparklines, city.city_id, List.duplicate(0, 7))
        components = city.components || %{}

        city
        |> Map.put(:id, city.city_id)
        |> Map.put(:name, city.city_name)
        |> Map.put(:slug, city.city_slug)
        |> Map.put(:sources, city_sources)
        |> Map.put(:source_count, source_count)
        |> Map.put(:weekly_change, weekly_change)
        |> Map.put(:sparkline, sparkline)
        # Individual component percentages for progress bars
        |> Map.put(:event_coverage_pct, components[:event_coverage] || 0)
        |> Map.put(:source_activity_pct, components[:source_activity] || 0)
        |> Map.put(:data_quality_pct, components[:data_quality] || 0)
        |> Map.put(:venue_health_pct, components[:venue_health] || 0)
      end)

    summary = calculate_summary(cities_with_sources)
    source_summary = calculate_source_summary(source_coverage, all_sources)
    recent_issues = get_recent_issues()

    # Identify cities needing attention (critical or warning with declining trend)
    cities_needing_attention =
      cities_with_sources
      |> Enum.filter(fn city ->
        city.health_status in [:critical, :warning] or city.weekly_change < -20
      end)
      |> Enum.take(5)

    socket
    |> assign(:loading, false)
    |> assign(:cities, cities_with_sources)
    |> assign(:summary, summary)
    |> assign(:source_summary, source_summary)
    |> assign(:all_sources, all_sources)
    |> assign(:recent_issues, recent_issues)
    |> assign(:cities_needing_attention, cities_needing_attention)
    |> assign(:last_updated, DateTime.utc_now())
  end

  defp get_weekly_changes do
    # Calculate weekly change for each city
    now = DateTime.utc_now()
    one_week_ago = DateTime.add(now, -7, :day)
    two_weeks_ago = DateTime.add(now, -14, :day)

    query =
      from(e in PublicEvent,
        join: v in Venue,
        on: v.id == e.venue_id,
        group_by: v.city_id,
        select: %{
          city_id: v.city_id,
          events_this_week:
            fragment(
              "COUNT(DISTINCT CASE WHEN ? >= ? THEN ? END)",
              e.inserted_at,
              ^one_week_ago,
              e.id
            ),
          events_last_week:
            fragment(
              "COUNT(DISTINCT CASE WHEN ? >= ? AND ? < ? THEN ? END)",
              e.inserted_at,
              ^two_weeks_ago,
              e.inserted_at,
              ^one_week_ago,
              e.id
            )
        }
      )

    query
    |> Repo.replica().all(timeout: 60_000)
    |> Enum.map(fn %{city_id: city_id, events_this_week: this_week, events_last_week: last_week} ->
      change = calculate_weekly_change(this_week, last_week)
      {city_id, change}
    end)
    |> Map.new()
  end

  defp calculate_weekly_change(this_week, last_week) do
    cond do
      last_week == 0 and this_week == 0 -> 0
      last_week == 0 -> 100
      true -> round((this_week - last_week) / last_week * 100)
    end
  end

  defp get_daily_sparkline_data do
    # Get event counts per day for the last 7 days per city
    # Returns a map of city_id -> [day1_count, day2_count, ..., day7_count]
    today = Date.utc_today()
    seven_days_ago = Date.add(today, -6)

    query =
      from(pe in PublicEvent,
        join: v in Venue,
        on: v.id == pe.venue_id,
        where: fragment("?::date", pe.starts_at) >= ^seven_days_ago,
        where: fragment("?::date", pe.starts_at) <= ^today,
        group_by: [v.city_id, fragment("?::date", pe.starts_at)],
        select: %{
          city_id: v.city_id,
          event_date: fragment("?::date", pe.starts_at),
          count: count(pe.id, :distinct)
        },
        order_by: [asc: v.city_id, asc: fragment("?::date", pe.starts_at)]
      )

    raw_data = Repo.replica().all(query, timeout: 60_000)

    # Build the 7-day array for each city
    dates = Enum.map(0..6, fn offset -> Date.add(seven_days_ago, offset) end)

    raw_data
    |> Enum.group_by(& &1.city_id)
    |> Enum.map(fn {city_id, entries} ->
      date_counts = Map.new(entries, fn e -> {e.event_date, e.count} end)

      sparkline =
        Enum.map(dates, fn date ->
          Map.get(date_counts, date, 0)
        end)

      {city_id, sparkline}
    end)
    |> Map.new()
  end

  defp calculate_summary(cities) do
    total = length(cities)

    healthy =
      Enum.count(cities, fn c -> c.health_status == :healthy end)

    warning =
      Enum.count(cities, fn c -> c.health_status == :warning end)

    critical =
      Enum.count(cities, fn c -> c.health_status == :critical end)

    disabled =
      Enum.count(cities, fn c -> c.health_status == :disabled end)

    %{
      total: total,
      healthy: healthy,
      warning: warning,
      critical: critical,
      disabled: disabled,
      health_percentage: if(total > 0, do: round(healthy / total * 100), else: 0)
    }
  end

  # Phase 2: Source Coverage Analysis

  defp get_source_coverage_by_city do
    # Query source coverage per city: which sources provide events to each city
    query =
      from(pes in PublicEventSource,
        join: pe in PublicEvent,
        on: pe.id == pes.event_id,
        join: v in Venue,
        on: v.id == pe.venue_id,
        join: s in Source,
        on: s.id == pes.source_id,
        where: s.is_active == true,
        group_by: [v.city_id, s.id, s.slug, s.name],
        select: %{
          city_id: v.city_id,
          source_id: s.id,
          source_slug: s.slug,
          source_name: s.name,
          event_count: count(pes.id, :distinct)
        },
        order_by: [asc: v.city_id, desc: count(pes.id, :distinct)]
      )

    query
    |> Repo.replica().all(timeout: 60_000)
    |> Enum.group_by(& &1.city_id)
  end

  defp get_all_active_sources do
    query =
      from(s in Source,
        where: s.is_active == true,
        select: %{id: s.id, slug: s.slug, name: s.name},
        order_by: [asc: s.name]
      )

    Repo.replica().all(query, timeout: 30_000)
  end

  defp calculate_source_summary(source_coverage, all_sources) do
    total_sources = length(all_sources)

    # Count how many cities each source covers
    source_city_counts =
      source_coverage
      |> Enum.flat_map(fn {_city_id, sources} -> sources end)
      |> Enum.group_by(& &1.source_slug)
      |> Enum.map(fn {slug, entries} ->
        {slug, length(Enum.uniq_by(entries, & &1.city_id))}
      end)
      |> Map.new()

    # Find sources with widest and narrowest coverage
    sources_with_coverage =
      Enum.map(all_sources, fn source ->
        city_count = Map.get(source_city_counts, source.slug, 0)
        Map.put(source, :city_count, city_count)
      end)

    top_sources =
      sources_with_coverage
      |> Enum.sort_by(& &1.city_count, :desc)
      |> Enum.take(5)

    cities_with_coverage = map_size(source_coverage)

    %{
      total_sources: total_sources,
      cities_with_coverage: cities_with_coverage,
      top_sources: top_sources,
      sources_with_coverage: sources_with_coverage
    }
  end

  # Phase 3: Recent Issues Feed (Option C - Only show problems)

  defp get_recent_issues do
    # Query only failed/cancelled job executions that have city data
    # This focuses attention on problems that need investigation
    forty_eight_hours_ago = DateTime.utc_now() |> DateTime.add(-48, :hour)

    query =
      from(j in JobExecutionSummary,
        where: j.attempted_at >= ^forty_eight_hours_ago,
        where: fragment("?->>'city_slug' IS NOT NULL", j.args),
        where: j.state in ["failure", "cancelled", "discarded"],
        order_by: [desc: j.attempted_at],
        limit: 15,
        select: %{
          id: j.id,
          worker: j.worker,
          state: j.state,
          city_slug: fragment("?->>'city_slug'", j.args),
          attempted_at: j.attempted_at,
          completed_at: j.completed_at,
          error: j.error,
          results: j.results
        }
      )

    Repo.replica().all(query, timeout: 30_000)
  end

  # Template helpers

  defp health_indicator(:healthy), do: {"🟢", "Healthy", "text-green-600"}
  defp health_indicator(:warning), do: {"🟡", "Warning", "text-yellow-600"}
  defp health_indicator(:critical), do: {"🔴", "Critical", "text-red-600"}
  defp health_indicator(:disabled), do: {"⚪", "Disabled", "text-gray-400"}

  defp format_number(nil), do: "0"
  defp format_number(num) when is_integer(num), do: Integer.to_string(num)

  defp format_number(num) when is_float(num) do
    num
    |> round()
    |> Integer.to_string()
  end

  defp source_count_color(count, total) when total > 0 do
    percentage = count / total * 100

    cond do
      percentage >= 50 -> "text-green-600"
      percentage >= 25 -> "text-yellow-600"
      percentage > 0 -> "text-orange-600"
      true -> "text-gray-400"
    end
  end

  defp source_count_color(_, _), do: "text-gray-400"

  # Extract error message from job execution
  defp extract_error_message(%{error: error}) when is_binary(error) and error != "" do
    error
  end

  defp extract_error_message(%{results: %{"error" => error}}) when is_binary(error) do
    error
  end

  defp extract_error_message(%{results: %{"error_category" => category}}) when is_binary(category) do
    category |> String.replace("_", " ") |> String.capitalize()
  end

  defp extract_error_message(_), do: "Unknown error"

  # Truncate error message for display
  defp truncate_error(nil, _max), do: "Unknown error"
  defp truncate_error(error, max) when byte_size(error) <= max, do: error

  defp truncate_error(error, max) do
    String.slice(error, 0, max) <> "..."
  end

  defp short_worker_name(nil), do: "Unknown"

  defp short_worker_name(worker) when is_binary(worker) do
    worker
    |> String.split(".")
    |> List.last()
    |> String.replace("Job", "")
  end

  # Valid status filter values (whitelist for security)
  @valid_status_filters %{
    "all" => :all,
    "healthy" => :healthy,
    "warning" => :warning,
    "critical" => :critical,
    "disabled" => :disabled
  }

  defp filter_cities(cities, "all"), do: cities

  defp filter_cities(cities, status) when is_binary(status) do
    case Map.get(@valid_status_filters, status) do
      nil -> cities  # Invalid status, return all cities
      :all -> cities
      status_atom -> Enum.filter(cities, fn city -> city.health_status == status_atom end)
    end
  end

  defp filter_cities(cities, _), do: cities

  defp sort_cities(cities, column, direction) do
    sorter = case column do
      :name -> &(&1.name)
      :health_score -> &(&1.health_score)
      :event_count -> &(&1.event_count)
      :weekly_change -> &(&1.weekly_change)
      :venue_count -> &(&1.venue_count)
      :source_count -> &(&1.source_count)
      _ -> &(&1.event_count)
    end

    sorted = Enum.sort_by(cities, sorter)
    if direction == :desc, do: Enum.reverse(sorted), else: sorted
  end

  defp sort_indicator(column, current_column, direction) when column == current_column do
    if direction == :asc, do: " ↑", else: " ↓"
  end

  defp sort_indicator(_, _, _), do: ""

  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Header -->
      <div class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-3xl font-bold text-gray-900">City Health Dashboard</h1>
          <p class="text-gray-600 mt-1">
            Last updated: <%= time_ago_in_words(@last_updated) %>
          </p>
        </div>
        <div class="flex items-center gap-3">
          <.link
            navigate={~p"/venues/duplicates"}
            class="inline-flex items-center px-3 py-2 text-sm font-medium text-gray-600 hover:text-gray-900"
          >
            🔀 Venue Duplicates
          </.link>
          <.link
            navigate={~p"/admin/discovery/stats"}
            class="inline-flex items-center px-3 py-2 text-sm font-medium text-gray-600 hover:text-gray-900"
          >
            📊 Discovery Stats
          </.link>
          <button
            phx-click="refresh"
            class="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
          >
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
              />
            </svg>
            Refresh
          </button>
        </div>
      </div>

      <!-- Summary Cards -->
      <div class="grid grid-cols-1 md:grid-cols-5 gap-4 mb-8">
        <.stat_card title="Total Cities" value={@summary.total} icon="🏙️" color={:blue} />
        <.stat_card title="Healthy" value={@summary.healthy} icon="🟢" color={:green} />
        <.stat_card title="Warning" value={@summary.warning} icon="🟡" color={:yellow} />
        <.stat_card title="Critical" value={@summary.critical} icon="🔴" color={:red} />
        <.stat_card title="Disabled" value={@summary.disabled} icon="⚪" color={:gray} />
      </div>

      <!-- Health Overview Bar -->
      <div class="bg-white shadow rounded-lg p-5 mb-8">
        <div class="flex items-center justify-between mb-2">
          <span class="text-sm font-medium text-gray-700">Overall Health</span>
          <span class="text-sm font-bold text-gray-900"><%= @summary.health_percentage %>%</span>
        </div>
        <div class="w-full bg-gray-200 rounded-full h-3">
          <div
            class="bg-green-500 h-3 rounded-full transition-all duration-500"
            style={"width: #{@summary.health_percentage}%"}
          >
          </div>
        </div>
      </div>

      <!-- Cities Needing Attention -->
      <%= if length(@cities_needing_attention) > 0 do %>
        <div class="bg-white shadow rounded-lg p-5 border-l-4 border-red-500 mb-8">
          <div class="flex items-start gap-3">
            <span class="text-2xl">⚠️</span>
            <div class="flex-1">
              <h2 class="text-xl font-semibold text-gray-900">Cities Needing Attention</h2>
              <p class="text-sm text-gray-600 mt-1">
                These cities have critical/warning status or significant decline (&gt;20% drop)
              </p>
              <div class="mt-3 flex flex-wrap gap-2">
                <%= for city <- @cities_needing_attention do %>
                  <% {emoji, _label, _color} = health_indicator(city.health_status) %>
                  <.link
                    navigate={~p"/admin/cities/#{city.slug}/health"}
                    class="inline-flex items-center gap-1 px-3 py-1 bg-gray-50 border border-gray-300 rounded-full text-sm text-gray-700 hover:bg-gray-100 transition-colors"
                  >
                    <%= emoji %> <%= city.name %>
                    <%= if city.weekly_change < -20 do %>
                      <span class="text-red-600 font-medium">(<%= format_change(city.weekly_change) %>)</span>
                    <% end %>
                  </.link>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Source Coverage Summary -->
      <div class="bg-white shadow rounded-lg p-5 mb-8">
        <h2 class="text-xl font-semibold text-gray-900 mb-4">Source Coverage Analysis</h2>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
          <!-- Active Sources -->
          <div class="bg-white shadow rounded-lg p-5 border-l-4 border-purple-500">
            <div class="flex items-center justify-between">
              <span class="text-2xl">🔌</span>
              <span class="text-2xl font-bold text-gray-900"><%= @source_summary.total_sources %></span>
            </div>
            <p class="mt-1 text-sm text-gray-600">Active Sources</p>
          </div>

          <!-- Cities with Coverage -->
          <div class="bg-white shadow rounded-lg p-5 border-l-4 border-indigo-500">
            <div class="flex items-center justify-between">
              <span class="text-2xl">🌍</span>
              <span class="text-2xl font-bold text-gray-900"><%= @source_summary.cities_with_coverage %></span>
            </div>
            <p class="mt-1 text-sm text-gray-600">Cities with Source Data</p>
          </div>

          <!-- Top Sources -->
          <div class="bg-white shadow rounded-lg p-5 border-l-4 border-teal-500">
            <div class="text-sm font-medium text-gray-700 mb-2">Top Sources by City Coverage</div>
            <div class="space-y-1">
              <%= for source <- @source_summary.top_sources do %>
                <div class="flex justify-between text-sm">
                  <span class="text-gray-600 truncate"><%= source.name %></span>
                  <span class="font-medium text-gray-900"><%= source.city_count %> cities</span>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <!-- City Table -->
      <div class="bg-white shadow rounded-lg overflow-hidden">
        <div class="px-4 py-4 border-b border-gray-200 flex justify-between items-center">
          <div>
            <h2 class="text-xl font-semibold text-gray-900">City Status</h2>
            <p class="text-sm text-gray-600 mt-1">Click the ▶ arrow to expand health breakdown</p>
          </div>
          <div class="flex items-center gap-2">
            <label for="status-filter" class="text-sm text-gray-600">Filter:</label>
            <select
              id="status-filter"
              phx-change="filter_status"
              name="status"
              class="rounded-md border-gray-300 text-sm shadow-sm focus:border-blue-500 focus:ring-blue-500"
            >
              <option value="all" selected={@status_filter == "all"}>All Status</option>
              <option value="healthy" selected={@status_filter == "healthy"}>🟢 Healthy</option>
              <option value="warning" selected={@status_filter == "warning"}>🟡 Warning</option>
              <option value="critical" selected={@status_filter == "critical"}>🔴 Critical</option>
              <option value="disabled" selected={@status_filter == "disabled"}>⚪ Disabled</option>
            </select>
          </div>
        </div>
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th
                class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                phx-click="sort"
                phx-value-column="name"
              >
                City<%= sort_indicator(:name, @sort_column, @sort_direction) %>
              </th>
              <th
                class="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                phx-click="sort"
                phx-value-column="health_score"
              >
                Health<%= sort_indicator(:health_score, @sort_column, @sort_direction) %>
              </th>
              <th
                class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                phx-click="sort"
                phx-value-column="event_count"
              >
                Events<%= sort_indicator(:event_count, @sort_column, @sort_direction) %>
              </th>
              <th
                class="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                phx-click="sort"
                phx-value-column="weekly_change"
              >
                7-Day Trend<%= sort_indicator(:weekly_change, @sort_column, @sort_direction) %>
              </th>
              <th
                class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                phx-click="sort"
                phx-value-column="venue_count"
              >
                Venues<%= sort_indicator(:venue_count, @sort_column, @sort_direction) %>
              </th>
              <th
                class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer hover:bg-gray-100"
                phx-click="sort"
                phx-value-column="source_count"
              >
                Sources<%= sort_indicator(:source_count, @sort_column, @sort_direction) %>
              </th>
              <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <%= for city <- @cities |> filter_cities(@status_filter) |> sort_cities(@sort_column, @sort_direction) do %>
              <% {emoji, label, color_class} = health_indicator(city.health_status) %>
              <% is_expanded = MapSet.member?(@expanded_cities, city.id) %>
              <tr class={"hover:bg-gray-50 #{if is_expanded, do: "bg-gray-50", else: ""}"}>
                <td class="px-4 py-4 whitespace-nowrap">
                  <div class="flex items-center gap-2">
                    <button
                      type="button"
                      class={"transform transition-transform text-gray-400 hover:text-gray-600 #{if is_expanded, do: "rotate-90", else: ""}"}
                      phx-click="toggle_city"
                      phx-value-city-id={city.id}
                    >
                      ▶
                    </button>
                    <div>
                      <div class="font-medium text-gray-900"><%= city.name %></div>
                      <div class="text-sm text-gray-500"><%= city.slug %></div>
                    </div>
                  </div>
                </td>
                <td class="px-4 py-4 whitespace-nowrap text-center">
                  <div class="flex flex-col items-center gap-1">
                    <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{CityHealthCalculator.status_classes(city.health_status)}"}>
                      <%= emoji %> <%= city.health_score %>%
                    </span>
                    <span class={"text-xs #{color_class}"}><%= label %></span>
                  </div>
                </td>
                <td class="px-4 py-4 whitespace-nowrap text-right text-sm text-gray-900">
                  <%= format_number(city.event_count) %>
                </td>
                <td class="px-4 py-4 whitespace-nowrap">
                  <div class="flex items-center justify-center gap-2">
                    <.sparkline data={city.sparkline} />
                    <.trend_indicator change={city.weekly_change} size={:sm} />
                  </div>
                </td>
                <td class="px-4 py-4 whitespace-nowrap text-right text-sm text-gray-900">
                  <%= city.venue_count %>
                </td>
                <td class="px-4 py-4 whitespace-nowrap text-right">
                  <span class={"text-sm font-medium #{source_count_color(city.source_count, @source_summary.total_sources)}"}>
                    <%= city.source_count %>/<%= @source_summary.total_sources %>
                  </span>
                </td>
                <td class="px-4 py-4 whitespace-nowrap text-right text-sm">
                  <.link
                    navigate={~p"/admin/cities/#{city.slug}/health"}
                    class="text-blue-600 hover:text-blue-900"
                  >
                    View Details →
                  </.link>
                </td>
              </tr>
              <!-- Expanded Row: Source Breakdown -->
              <%= if is_expanded do %>
                <tr class="bg-gray-50">
                  <td colspan="7" class="px-4 py-4">
                    <div class="ml-8">
                      <!-- Health Component Breakdown -->
                      <h4 class="text-sm font-medium text-gray-700 mb-3">Health Score Breakdown</h4>
                      <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
                        <.health_component_bar
                          label="Event Coverage"
                          value={city.event_coverage_pct}
                          weight="40%"
                          color={:blue}
                          target={80}
                        />
                        <.health_component_bar
                          label="Source Activity"
                          value={city.source_activity_pct}
                          weight="30%"
                          color={:green}
                          target={90}
                        />
                        <.health_component_bar
                          label="Data Quality"
                          value={city.data_quality_pct}
                          weight="20%"
                          color={:yellow}
                          target={85}
                        />
                        <.health_component_bar
                          label="Venue Health"
                          value={city.venue_health_pct}
                          weight="10%"
                          color={:purple}
                          target={90}
                        />
                      </div>

                      <!-- Source Breakdown -->
                      <h4 class="text-sm font-medium text-gray-700 mb-3">
                        Source Breakdown for <%= city.name %>
                      </h4>
                      <%= if Enum.empty?(city.sources) do %>
                        <p class="text-sm text-gray-500 italic">No sources contributing events to this city.</p>
                      <% else %>
                        <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
                          <%= for source <- city.sources do %>
                            <div class="bg-white rounded-lg p-3 border border-gray-200 shadow-sm">
                              <div class="flex justify-between items-start">
                                <div class="min-w-0 flex-1">
                                  <p class="text-sm font-medium text-gray-900 truncate" title={source.source_name}>
                                    <%= source.source_name %>
                                  </p>
                                  <p class="text-xs text-gray-500"><%= source.source_slug %></p>
                                </div>
                                <span class="ml-2 text-sm font-bold text-blue-600">
                                  <%= source.event_count %>
                                </span>
                              </div>
                              <!-- Source contribution bar -->
                              <div class="mt-2 w-full bg-gray-200 rounded-full h-1.5">
                                <div
                                  class="bg-blue-500 h-1.5 rounded-full"
                                  style={"width: #{min(100, source.event_count / max(city.event_count, 1) * 100)}%"}
                                >
                                </div>
                              </div>
                            </div>
                          <% end %>
                        </div>
                        <div class="mt-3 text-xs text-gray-500">
                          Total: <%= Enum.sum(Enum.map(city.sources, & &1.event_count)) %> event-source links
                          (events may have multiple sources)
                        </div>
                      <% end %>
                    </div>
                  </td>
                </tr>
              <% end %>
            <% end %>
          </tbody>
        </table>
      </div>

      <!-- Recent Issues (Phase 3 Option C) -->
      <%= if length(@recent_issues) > 0 do %>
        <div class="mt-8 bg-white shadow rounded-lg overflow-hidden border-l-4 border-red-500">
          <div class="px-4 py-4 border-b border-gray-200 bg-red-50">
            <div class="flex items-center gap-2">
              <span class="text-xl">🚨</span>
              <div>
                <h2 class="text-lg font-semibold text-gray-900">Recent Issues (48h)</h2>
                <p class="text-sm text-gray-600">Failed or cancelled jobs that may need investigation</p>
              </div>
            </div>
          </div>
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">City</th>
                <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Job</th>
                <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Error</th>
                <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Time</th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <%= for issue <- @recent_issues do %>
                <tr class="hover:bg-red-50">
                  <td class="px-4 py-3 whitespace-nowrap">
                    <.status_badge state={issue.state} />
                  </td>
                  <td class="px-4 py-3 whitespace-nowrap">
                    <span class="text-sm font-medium text-gray-900"><%= issue.city_slug %></span>
                  </td>
                  <td class="px-4 py-3 whitespace-nowrap">
                    <span class="text-sm text-gray-600"><%= short_worker_name(issue.worker) %></span>
                  </td>
                  <td class="px-4 py-3 max-w-xs">
                    <span class="text-sm text-red-600 truncate block" title={extract_error_message(issue)}>
                      <%= truncate_error(extract_error_message(issue), 60) %>
                    </span>
                  </td>
                  <td class="px-4 py-3 whitespace-nowrap text-sm text-gray-500">
                    <%= time_ago_in_words(issue.attempted_at) %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
          <div class="px-4 py-3 bg-gray-50 text-sm text-gray-500">
            <.link navigate={~p"/admin/job-executions"} class="text-blue-600 hover:text-blue-800">
              View all job executions →
            </.link>
          </div>
        </div>
      <% end %>

      <!-- Legend -->
      <div class="mt-6 bg-white shadow rounded-lg p-5">
        <h3 class="text-sm font-medium text-gray-700 mb-2">Health Score Formula</h3>
        <p class="text-sm text-gray-600 mb-3">
          Health scores are calculated using a 4-component weighted formula:
        </p>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
          <div class="text-sm">
            <span class="font-medium text-gray-900">Event Coverage (40%)</span>
            <p class="text-gray-500">Days with events in last 14 days</p>
          </div>
          <div class="text-sm">
            <span class="font-medium text-gray-900">Source Activity (30%)</span>
            <p class="text-gray-500">Sync job success rate</p>
          </div>
          <div class="text-sm">
            <span class="font-medium text-gray-900">Data Quality (20%)</span>
            <p class="text-gray-500">Events with complete metadata</p>
          </div>
          <div class="text-sm">
            <span class="font-medium text-gray-900">Venue Health (10%)</span>
            <p class="text-gray-500">Venues with complete info</p>
          </div>
        </div>
        <h3 class="text-sm font-medium text-gray-700 mb-2">Status Thresholds</h3>
        <div class="flex flex-wrap gap-4 text-sm text-gray-600">
          <span>🟢 <strong>Healthy:</strong> ≥80% health score</span>
          <span>🟡 <strong>Warning:</strong> 50-79% health score</span>
          <span>🔴 <strong>Critical:</strong> &lt;50% health score</span>
          <span>⚪ <strong>Disabled:</strong> No events or venues</span>
        </div>
      </div>
    </div>
    """
  end
end
