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
  alias EventasaurusApp.Venues.FixVenueNamesJob
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Sources.SourceRegistry
  alias EventasaurusDiscovery.Locations.CityHierarchy

  alias EventasaurusDiscovery.Admin.{
    DiscoveryStatsCollector,
    SourceHealthCalculator,
    EventChangeTracker,
    DataQualityChecker,
    TrendAnalyzer,
    SourceStatsCollector
  }

  alias EventasaurusDiscovery.Services.FreshnessHealthChecker

  import Ecto.Query
  require Logger

  # 5 minutes (reduced from 30s to lower query load on job_execution_summaries)
  @refresh_interval 300_000

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
          |> assign(:category_sort, :count)
          |> assign(:venue_sort, :count)
          |> assign(:show_occurrence_details, false)
          |> assign(:show_category_details, false)
          |> assign(:show_venue_details, false)
          |> assign(:loading, true)
          # Phase 3: Job history filtering and expansion
          |> assign(:job_history_filter, :all)
          |> assign(:expanded_job_ids, MapSet.new())
          |> assign(:expanded_metro_areas, MapSet.new())
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

    success_chart_data =
      TrendAnalyzer.format_for_chartjs(
        success_rate_trend,
        :success_rate,
        "Success Rate",
        "#10B981"
      )

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

  @impl true
  def handle_event("toggle_occurrence_details", _params, socket) do
    {:noreply, assign(socket, :show_occurrence_details, !socket.assigns.show_occurrence_details)}
  end

  @impl true
  def handle_event("toggle_category_details", _params, socket) do
    {:noreply, assign(socket, :show_category_details, !socket.assigns.show_category_details)}
  end

  @impl true
  def handle_event("toggle_venue_details", _params, socket) do
    {:noreply, assign(socket, :show_venue_details, !socket.assigns.show_venue_details)}
  end

  @impl true
  def handle_event("sort_categories", %{"by" => sort_by}, socket) do
    sort_atom = safe_sort_atom(sort_by, :category)
    categories = sort_categories(socket.assigns.comprehensive_stats.top_categories, sort_atom)

    comprehensive_stats = Map.put(socket.assigns.comprehensive_stats, :top_categories, categories)

    socket =
      socket
      |> assign(:category_sort, sort_atom)
      |> assign(:comprehensive_stats, comprehensive_stats)

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort_venues", %{"by" => sort_by}, socket) do
    sort_atom = safe_sort_atom(sort_by, :venue)
    venues = sort_venues(socket.assigns.comprehensive_stats.venue_stats.top_venues, sort_atom)

    venue_stats = Map.put(socket.assigns.comprehensive_stats.venue_stats, :top_venues, venues)
    comprehensive_stats = Map.put(socket.assigns.comprehensive_stats, :venue_stats, venue_stats)

    socket =
      socket
      |> assign(:venue_sort, sort_atom)
      |> assign(:comprehensive_stats, comprehensive_stats)

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_job_history", %{"filter" => filter}, socket) do
    filter_atom =
      case filter do
        "all" -> :all
        "successes" -> :successes
        "failures" -> :failures
        _ -> :all
      end

    {:noreply, assign(socket, :job_history_filter, filter_atom)}
  end

  @impl true
  def handle_event("toggle_job_details", %{"job_id" => job_id}, socket) do
    expanded_ids = socket.assigns.expanded_job_ids

    new_expanded_ids =
      if MapSet.member?(expanded_ids, job_id) do
        MapSet.delete(expanded_ids, job_id)
      else
        MapSet.put(expanded_ids, job_id)
      end

    {:noreply, assign(socket, :expanded_job_ids, new_expanded_ids)}
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

  @impl true
  def handle_event("fix_venue_names", _params, socket) do
    source_slug = socket.assigns.source_slug

    # Find all cities that have venues from this source with low quality names
    affected_cities = find_cities_with_venue_quality_issues(source_slug)

    # Enqueue a job for each affected city
    results =
      Enum.map(affected_cities, fn city_id ->
        %{city_id: city_id, severity: "all"}
        |> FixVenueNamesJob.new()
        |> Oban.insert()
      end)

    {successful, failed} = Enum.split_with(results, &match?({:ok, _}, &1))
    jobs_enqueued = length(successful)
    jobs_failed = length(failed)

    # Log failures for debugging
    Enum.each(failed, fn {:error, reason} ->
      Logger.error("Failed to enqueue FixVenueNamesJob: #{inspect(reason)}")
    end)

    socket =
      cond do
        # No cities found with quality issues
        Enum.empty?(affected_cities) ->
          put_flash(
            socket,
            :warning,
            "⚠️ No cities found with venues that have quality issues."
          )

        # All jobs failed to enqueue
        jobs_enqueued == 0 and jobs_failed > 0 ->
          put_flash(
            socket,
            :error,
            "❌ Failed to enqueue #{jobs_failed} job(s). Check server logs for details."
          )

        # Partial success
        jobs_failed > 0 ->
          put_flash(
            socket,
            :warning,
            "⚠️ Enqueued #{jobs_enqueued} job(s) successfully, but #{jobs_failed} failed. Check logs for details."
          )

        # All successful
        true ->
          put_flash(
            socket,
            :info,
            "✅ Enqueued #{jobs_enqueued} venue name fix job(s) for #{jobs_enqueued} #{if jobs_enqueued == 1, do: "city", else: "cities"}. Jobs will process in the background."
          )
      end

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

    # Get detailed stats for the source using detail workers and metadata
    # Use nil for city_id to aggregate across all cities for accurate global stats
    # This ensures we query detail workers with meta->>'status' instead of sync workers
    stats = DiscoveryStatsCollector.get_detailed_source_stats(nil, source_slug)

    # Calculate health and success rate
    health_status = SourceHealthCalculator.calculate_health_score(stats)
    success_rate = SourceHealthCalculator.success_rate_percentage(stats)

    # Get complete run history (last 20 runs - successes AND failures)
    run_history = DiscoveryStatsCollector.get_complete_run_history(source_slug, 20)

    # Get average runtime (uses date_range)
    avg_runtime = DiscoveryStatsCollector.get_average_runtime(source_slug, date_range)

    # Get events by city (if city-scoped source)
    events_by_city =
      if scope == :city do
        raw_city_data = DiscoveryStatsCollector.get_events_by_city_for_source(source_slug, 20)

        # Load city slugs separately since raw data doesn't include them
        city_ids = Enum.map(raw_city_data, & &1.city_id)
        city_slugs = load_city_slugs(city_ids)

        # Transform to format expected by clustering (with :count field)
        city_stats =
          Enum.map(raw_city_data, fn city ->
            %{
              city_id: city.city_id,
              city_name: city.city_name,
              city_slug: Map.get(city_slugs, city.city_id),
              count: city.event_count,
              new_this_week: city.new_this_week
            }
          end)

        # Create a lookup map for new_this_week values by city_id
        new_this_week_map = Map.new(city_stats, fn stat -> {stat.city_id, stat.new_this_week} end)

        # Apply geographic clustering
        clustered = CityHierarchy.aggregate_stats_by_cluster(city_stats, 20.0)

        # Transform back to expected format with event_count and aggregate new_this_week
        Enum.map(clustered, fn city ->
          # Sum new_this_week for primary city and all subcities
          primary_new = Map.get(new_this_week_map, city.city_id, 0)

          subcities_new =
            Enum.reduce(city.subcities, 0, fn sub, acc ->
              acc + Map.get(new_this_week_map, sub.city_id, 0)
            end)

          %{
            city_id: city.city_id,
            city_name: city.city_name,
            city_slug: city.city_slug,
            event_count: city.count,
            new_this_week: primary_new + subcities_new,
            subcities: city.subcities || []
          }
        end)
      else
        []
      end

    # Get total event count
    total_events = count_events_for_source(source_slug)

    # Get source coverage description
    coverage = get_coverage_description(source_slug, scope)

    # Get change tracking data (Phase 3)
    # Pass nil for city_id to aggregate across all cities for source-wide stats
    # Use configured window values to ensure labels match actual timeframes
    new_events_window = get_new_events_window()
    dropped_events_window = get_dropped_events_window()
    new_events = EventChangeTracker.calculate_new_events(source_slug, new_events_window)

    dropped_events =
      EventChangeTracker.calculate_dropped_events(source_slug, dropped_events_window)

    percentage_change = EventChangeTracker.calculate_percentage_change(source_slug, nil)

    {trend_emoji, trend_text, trend_class} =
      EventChangeTracker.get_trend_indicator(percentage_change)

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
            missing_categories: 0,
            category_specificity: 0,
            specificity_metrics: %{
              generic_event_count: 0,
              diversity_score: 0,
              total_categories: 0
            },
            price_completeness: 0,
            price_metrics: %{
              events_with_price_info: 0,
              events_free: 0,
              events_paid: 0,
              events_with_currency: 0,
              events_with_price_range: 0,
              unique_prices: 0,
              price_diversity_score: 0,
              price_diversity_warning: nil
            },
            description_quality: 0,
            description_metrics: %{
              has_description: 0,
              short_descriptions: 0,
              adequate_descriptions: 0,
              detailed_descriptions: 0,
              avg_length: 0
            },
            performer_completeness: 0,
            performer_metrics: %{
              events_with_performers: 0,
              events_single_performer: 0,
              events_multiple_performers: 0,
              total_performers: 0,
              avg_performers_per_event: 0.0
            }
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

    success_chart_data =
      TrendAnalyzer.format_for_chartjs(
        success_rate_trend,
        :success_rate,
        "Success Rate",
        "#10B981"
      )

    # Get comprehensive stats from Phase 1 (occurrence types, categories, translations, images, venues)
    comprehensive_stats = SourceStatsCollector.get_comprehensive_stats(source_slug)

    # Format chart data for pie charts
    occurrence_chart_data = format_occurrence_pie_chart(comprehensive_stats.occurrence_types)
    category_chart_data = format_category_pie_chart(comprehensive_stats.top_categories)

    # Get freshness health check
    source =
      Repo.replica().one(
        from(s in EventasaurusDiscovery.Sources.Source,
          where: s.slug == ^source_slug,
          select: s
        )
      )

    freshness_health =
      if source do
        FreshnessHealthChecker.check_health(source.id)
      else
        %{
          total_events: 0,
          threshold_hours: 168,
          status: :no_data,
          diagnosis: "Source not found",
          # New execution-rate fields expected by the UI
          detail_jobs_executed: 0,
          expected_jobs: 0,
          processing_rate: 0.0,
          runs_in_period: 0,
          execution_multiplier: 0.0
        }
      end

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
    |> assign(:new_events_window, new_events_window)
    |> assign(:dropped_events_window, dropped_events_window)
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
    |> assign(:comprehensive_stats, comprehensive_stats)
    |> assign(:occurrence_chart_data, Jason.encode!(occurrence_chart_data))
    |> assign(:category_chart_data, Jason.encode!(category_chart_data))
    |> assign(:freshness_health, freshness_health)
  end

  # Get configured window for new events detection
  defp get_new_events_window do
    config = Application.get_env(:eventasaurus, :change_tracking, [])
    Keyword.get(config, :new_events_window_hours, 24)
  end

  # Get configured window for dropped events detection
  defp get_dropped_events_window do
    config = Application.get_env(:eventasaurus, :change_tracking, [])
    Keyword.get(config, :dropped_events_window_hours, 48)
  end

  defp count_events_for_source(source_slug) do
    query =
      from(pes in EventasaurusDiscovery.PublicEvents.PublicEventSource,
        join: s in EventasaurusDiscovery.Sources.Source,
        on: s.id == pes.source_id,
        where: s.slug == ^source_slug,
        select: count(pes.id)
      )

    Repo.replica().one(query) || 0
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

      :unknown ->
        "Unknown coverage (not registered)"
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
                  <p class="text-xs text-green-600 mt-1">Last <%= @new_events_window %> hours</p>
                </div>
              </div>

              <!-- Dropped Events -->
              <div class="flex items-center p-4 bg-red-50 rounded-lg">
                <div class="flex-shrink-0">
                  <span class="text-3xl">➖</span>
                </div>
                <div class="ml-4">
                  <p class="text-sm font-medium text-red-900">Dropped Events</p>
                  <p class="text-2xl font-semibold text-red-700">
                    <%= if @dropped_events == 0 do %>
                      0
                    <% else %>
                      -<%= @dropped_events %>
                    <% end %>
                  </p>
                  <p class="text-xs text-red-600 mt-1">Not seen (<%= @dropped_events_window %>h)</p>
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
                    <%= if @percentage_change == :first_scrape do %>
                      N/A
                    <% else %>
                      <%= if @percentage_change > 0 do %>+<% end %><%= @percentage_change %>%
                    <% end %>
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
            <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-6">
              <!-- Venue Coverage & Quality (split view) -->
              <div class="p-4 border rounded-lg">
                <!-- Header -->
                <div class="flex items-center justify-between mb-3">
                  <p class="text-sm font-medium text-gray-700">Venue Data</p>
                  <span class="text-lg font-bold text-gray-900"><%= @quality_data.venue_quality %>%</span>
                </div>

                <!-- Coverage Bar -->
                <div class="mb-3">
                  <div class="flex items-center justify-between mb-1">
                    <span class="text-xs text-gray-600">Coverage</span>
                    <span class="text-xs font-semibold text-gray-700"><%= @quality_data.venue_coverage %>%</span>
                  </div>
                  <div class="w-full bg-gray-200 rounded-full h-2">
                    <div class="bg-green-600 h-2 rounded-full" style={"width: #{@quality_data.venue_coverage}%"}></div>
                  </div>
                  <p class="mt-1 text-xs text-gray-500">
                    <%= @quality_data.missing_venues %> events missing venues
                  </p>
                </div>

                <!-- Name Quality Bar -->
                <div>
                  <div class="flex items-center justify-between mb-1">
                    <span class="text-xs text-gray-600">
                      Name Quality
                      <span class="text-gray-400 cursor-help" title="Compares scraped names vs geocoding provider names using similarity scoring">ⓘ</span>
                    </span>
                    <span class="text-xs font-semibold text-gray-700"><%= @quality_data.venue_name_quality %>%</span>
                  </div>
                  <div class="w-full bg-gray-200 rounded-full h-2">
                    <% quality_color = cond do
                      @quality_data.venue_name_quality >= 80 -> "bg-green-600"
                      @quality_data.venue_name_quality >= 60 -> "bg-yellow-600"
                      true -> "bg-red-600"
                    end %>
                    <div class={"#{quality_color} h-2 rounded-full"} style={"width: #{@quality_data.venue_name_quality}%"}></div>
                  </div>
                  <%= if @quality_data.venues_with_low_quality_names > 0 do %>
                    <p class="mt-1 text-xs text-orange-600">
                      ⚠️ <%= @quality_data.venues_with_low_quality_names %> venues with low similarity to geocoded names
                    </p>
                    <%= if length(@quality_data.low_quality_venue_examples) > 0 do %>
                      <details class="mt-2 text-xs">
                        <summary class="cursor-pointer text-gray-600 hover:text-gray-900 font-medium">
                          Show examples
                        </summary>
                        <ul class="mt-2 space-y-2 pl-3">
                          <%= for example <- @quality_data.low_quality_venue_examples do %>
                            <li class="border-l-2 border-orange-400 pl-2">
                              <p class="text-red-600 font-medium">Scraped: "<%= example.venue_name %>"</p>
                              <p class="text-green-600">Geocoded: "<%= example.geocoded_name %>"</p>
                              <p class="text-gray-500">
                                Similarity: <%= Float.round(example.similarity, 2) %>
                                <%= if Map.get(example, :severity) == :moderate do %>
                                  <span class="text-yellow-600">(moderate)</span>
                                <% else %>
                                  <span class="text-red-600">(severe)</span>
                                <% end %>
                              </p>
                            </li>
                          <% end %>
                        </ul>
                      </details>
                    <% end %>
                  <% else %>
                    <p class="mt-1 text-xs text-green-600">
                      ✓ All venue names match geocoding data
                    </p>
                  <% end %>
                </div>
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

              <!-- Category Specificity (Phase 1.7) -->
              <div class="p-4 border rounded-lg">
                <div class="flex items-center justify-between mb-2">
                  <p class="text-sm font-medium text-gray-700">Cat. Specificity</p>
                  <span class="text-lg font-bold text-gray-900"><%= @quality_data.category_specificity %>%</span>
                </div>
                <div class="w-full bg-gray-200 rounded-full h-2.5">
                  <div class="bg-indigo-600 h-2.5 rounded-full" style={"width: #{@quality_data.category_specificity}%"}></div>
                </div>
                <%= if @quality_data.specificity_metrics do %>
                  <p class="mt-2 text-xs text-gray-500">
                    <%= @quality_data.specificity_metrics.generic_event_count %> events in generic categories
                  </p>
                  <div class="mt-2 pt-2 border-t border-gray-200">
                    <div class="flex items-center justify-between text-xs">
                      <span class="text-gray-600">Diversity: <%= @quality_data.specificity_metrics.diversity_score %>%</span>
                      <span class="text-gray-600"><%= @quality_data.specificity_metrics.total_categories %> cats</span>
                    </div>
                  </div>
                  <%= if @quality_data.specificity_metrics.generic_event_count > 0 do %>
                    <div class="mt-2 pt-2 border-t border-gray-200">
                      <.link
                        navigate={~p"/admin/discovery/category-analysis/#{@source_slug}"}
                        class="text-xs text-indigo-600 hover:text-indigo-900 font-medium"
                      >
                        → Analyze "Other" events
                      </.link>
                    </div>
                  <% end %>
                <% end %>
              </div>

              <!-- Price Completeness Card (Phase 2A.4) -->
              <div class="p-4 border rounded-lg">
                <div class="flex items-center justify-between mb-2">
                  <p class="text-sm font-medium text-gray-700">Price Data</p>
                  <span class="text-lg font-bold text-gray-900"><%= @quality_data.price_completeness %>%</span>
                </div>
                <div class="w-full bg-gray-200 rounded-full h-2.5">
                  <div class="bg-green-600 h-2.5 rounded-full" style={"width: #{@quality_data.price_completeness}%"}></div>
                </div>
                <p class="mt-2 text-xs text-gray-500">
                  <%= @quality_data.price_metrics.events_with_price_info %> / <%= @quality_data.total_events %> events with pricing
                </p>
                <div class="mt-1 flex items-center justify-between text-xs text-gray-500">
                  <span>Free: <%= @quality_data.price_metrics.events_free %></span>
                  <span>Paid: <%= @quality_data.price_metrics.events_paid %></span>
                </div>
                <%= if @quality_data.price_metrics.events_with_currency > 0 do %>
                  <p class="mt-1 text-xs text-gray-500">
                    <%= @quality_data.price_metrics.events_with_currency %> with currency info
                  </p>
                <% end %>
                <%= if @quality_data.price_metrics.events_paid > 0 do %>
                  <div class="mt-2 pt-2 border-t border-gray-200">
                    <div class="flex items-center justify-between text-xs">
                      <span class="text-gray-600">Diversity: <%= @quality_data.price_metrics.price_diversity_score %>%</span>
                      <span class="text-gray-600"><%= @quality_data.price_metrics.unique_prices %> prices</span>
                    </div>
                  </div>
                <% end %>
              </div>

              <!-- Description Quality Card (Phase 2B.4) -->
              <div class="p-4 border rounded-lg">
                <div class="flex items-center justify-between mb-2">
                  <p class="text-sm font-medium text-gray-700">Description Quality</p>
                  <span class="text-lg font-bold text-gray-900"><%= @quality_data.description_quality %>%</span>
                </div>
                <div class="w-full bg-gray-200 rounded-full h-2.5">
                  <div class="bg-purple-600 h-2.5 rounded-full" style={"width: #{@quality_data.description_quality}%"}></div>
                </div>
                <p class="mt-2 text-xs text-gray-500">
                  <%= @quality_data.description_metrics.has_description %> / <%= @quality_data.total_events %> have descriptions
                </p>
                <div class="mt-1 flex items-center justify-between text-xs text-gray-500">
                  <span>Short: <%= @quality_data.description_metrics.short_descriptions %></span>
                  <span>Adequate: <%= @quality_data.description_metrics.adequate_descriptions %></span>
                  <span>Detailed: <%= @quality_data.description_metrics.detailed_descriptions %></span>
                </div>
                <p class="mt-1 text-xs text-gray-500">
                  Avg length: <%= @quality_data.description_metrics.avg_length %> chars
                </p>
              </div>

              <!-- Performer Completeness Card (Phase 2D.4) -->
              <div class="p-4 border rounded-lg">
                <div class="flex items-center justify-between mb-2">
                  <p class="text-sm font-medium text-gray-700">Performer Data</p>
                  <span class="text-lg font-bold text-gray-900"><%= @quality_data.performer_completeness %>%</span>
                </div>
                <div class="w-full bg-gray-200 rounded-full h-2.5">
                  <div class="bg-pink-600 h-2.5 rounded-full" style={"width: #{@quality_data.performer_completeness}%"}></div>
                </div>
                <p class="mt-2 text-xs text-gray-500">
                  <%= @quality_data.performer_metrics.events_with_performers %> / <%= @quality_data.total_events %> have performers
                </p>
                <div class="mt-1 flex items-center justify-between text-xs text-gray-500">
                  <span>Single: <%= @quality_data.performer_metrics.events_single_performer %></span>
                  <span>Multiple: <%= @quality_data.performer_metrics.events_multiple_performers %></span>
                </div>
                <p class="mt-1 text-xs text-gray-500">
                  Total: <%= @quality_data.performer_metrics.total_performers %> performers (avg: <%= @quality_data.performer_metrics.avg_performers_per_event %>)
                </p>
              </div>

              <!-- Occurrence Richness Card (Phase 2C.4) -->
              <div class="p-4 border rounded-lg">
                <div class="flex items-center justify-between mb-2">
                  <p class="text-sm font-medium text-gray-700">Occurrence Data</p>
                  <span class="text-lg font-bold text-gray-900"><%= @quality_data.occurrence_richness %>%</span>
                </div>
                <div class="w-full bg-gray-200 rounded-full h-2.5">
                  <div class="bg-amber-600 h-2.5 rounded-full" style={"width: #{@quality_data.occurrence_richness}%"}></div>
                </div>
                <p class="mt-2 text-xs text-gray-500">
                  <%= @quality_data.occurrence_metrics.events_with_occurrences %> / <%= @quality_data.total_events %> have occurrences
                </p>
                <div class="mt-1 flex items-center justify-between text-xs text-gray-500">
                  <span>Single: <%= @quality_data.occurrence_metrics.events_single_date %></span>
                  <span>Multiple: <%= @quality_data.occurrence_metrics.events_multiple_dates %></span>
                </div>
                <p class="mt-1 text-xs text-gray-500">
                  Avg: <%= @quality_data.occurrence_metrics.avg_dates_per_event %> dates | Validity: <%= @quality_data.occurrence_metrics.validity_score %>%
                </p>
                <%= if @quality_data.occurrence_metrics.validation_issues.total_validity_issues > 0 do %>
                  <div class="mt-2 pt-2 border-t border-gray-200">
                    <p class="text-xs text-orange-600">
                      ⚠️ <%= @quality_data.occurrence_metrics.validation_issues.total_validity_issues %> structural issues
                    </p>
                  </div>
                <% end %>

                <!-- Time Quality Metrics -->
                <%= if @quality_data.occurrence_metrics.time_quality_metrics do %>
                  <div class="mt-2 pt-2 border-t border-gray-200">
                    <p class="text-xs font-medium text-gray-700 mb-1">Time Quality: <%= @quality_data.occurrence_metrics.time_quality_metrics.time_quality %>%</p>

                    <!-- Always show variance metrics -->
                    <div class="space-y-1">
                      <!-- Same time percentage -->
                      <%= if @quality_data.occurrence_metrics.time_quality_metrics.same_time_percentage > 80 do %>
                        <p class="text-xs text-orange-600 font-medium">
                          WARNING: <%= :erlang.float_to_binary(@quality_data.occurrence_metrics.time_quality_metrics.same_time_percentage * 1.0, decimals: 1) %>% of events at <%= @quality_data.occurrence_metrics.time_quality_metrics.most_common_time %>
                        </p>
                      <% else %>
                        <p class={"text-xs #{if @quality_data.occurrence_metrics.time_quality_metrics.same_time_percentage < 50, do: "text-green-600", else: "text-gray-600"}"}>
                          <%= :erlang.float_to_binary(@quality_data.occurrence_metrics.time_quality_metrics.same_time_percentage * 1.0, decimals: 1) %>% of events at <%= @quality_data.occurrence_metrics.time_quality_metrics.most_common_time %>
                        </p>
                      <% end %>

                      <!-- Time diversity score -->
                      <p class={"text-xs #{if @quality_data.occurrence_metrics.time_quality_metrics.time_diversity_score < 50, do: "text-orange-600", else: "text-gray-600"}"}>
                        Time diversity: <%= @quality_data.occurrence_metrics.time_quality_metrics.time_diversity_score %>%
                      </p>

                      <!-- Midnight warning -->
                      <%= if @quality_data.occurrence_metrics.time_quality_metrics.midnight_percentage > 30 do %>
                        <p class="text-xs text-orange-600">
                          WARNING: <%= :erlang.float_to_binary(@quality_data.occurrence_metrics.time_quality_metrics.midnight_percentage * 1.0, decimals: 1) %>% at midnight (00:00)
                        </p>
                      <% end %>
                    </div>

                    <p class="mt-1 text-xs text-gray-500">
                      <%= @quality_data.occurrence_metrics.time_quality_metrics.total_occurrences %> occurrences analyzed
                    </p>
                  </div>
                <% end %>
              </div>

              <!-- Translation Completeness (conditionally displayed) -->
              <%= if @quality_data.supports_translations do %>
                <div class="p-4 border rounded-lg">
                  <div class="flex items-center justify-between mb-2">
                    <p class="text-sm font-medium text-gray-700">Translations</p>
                    <span class="text-lg font-bold text-gray-900"><%= @quality_data.translation_completeness %>%</span>
                  </div>
                  <div class="w-full bg-gray-200 rounded-full h-2.5">
                    <div class="bg-orange-600 h-2.5 rounded-full" style={"width: #{@quality_data.translation_completeness}%"}></div>
                  </div>
                  <p class="mt-2 text-xs text-gray-500">
                    <%= @quality_data.missing_translations %> events missing translations
                  </p>
                  <%= if @quality_data.genuine_translations && @quality_data.duplicate_translations do %>
                    <div class="mt-2 pt-2 border-t border-gray-200">
                      <div class="flex items-center justify-between text-xs">
                        <span class="text-green-600">✓ <%= @quality_data.genuine_translations %> genuine</span>
                        <%= if @quality_data.duplicate_translations > 0 do %>
                          <span class="text-orange-600">⚠ <%= @quality_data.duplicate_translations %> duplicates</span>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
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

                <%= if @quality_data.venues_with_low_quality_names > 0 do %>
                  <li class="flex items-start">
                    <span class="flex-shrink-0 w-1.5 h-1.5 mt-2 bg-orange-600 rounded-full mr-3"></span>
                    <div class="text-sm text-gray-700 flex items-center gap-2">
                      <span>
                        <%= @quality_data.venues_with_low_quality_names %> venues have low-quality names (current quality: <%= @quality_data.venue_name_quality %>%).
                      </span>
                      <button
                        phx-click="fix_venue_names"
                        class="inline-flex items-center px-3 py-1 border border-transparent text-xs font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                      >
                        🔧 Fix Venue Names
                      </button>
                    </div>
                  </li>
                <% end %>
              </ul>
            </div>
          </div>
        </div>

        <!-- Freshness Health Monitor -->
        <div class="bg-white rounded-lg shadow mb-8">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">🔄 Freshness Health Monitor</h2>
            <p class="mt-1 text-sm text-gray-500">Event freshness checking effectiveness (<%= @freshness_health.threshold_hours %>h threshold)</p>
          </div>
          <div class="p-6">
            <!-- Overall Status -->
            <div class={["mb-6 p-4 rounded-lg border", freshness_status_bg(@freshness_health.status), freshness_status_border(@freshness_health.status)]}>
              <div class="flex items-center justify-between">
                <div class="flex-1">
                  <div class="flex items-center">
                    <span class="text-4xl mr-3"><%= freshness_status_emoji(@freshness_health.status) %></span>
                    <div>
                      <p class={"text-lg font-semibold #{freshness_status_text_color(@freshness_health.status)}"}>
                        <%= freshness_status_label(@freshness_health.status) %>
                      </p>
                      <p class={"text-sm #{freshness_status_text_color(@freshness_health.status)} mt-1"}>
                        Processing <%= Float.round(@freshness_health.processing_rate * 100, 1) %>% per run
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Metrics -->
            <div class="grid grid-cols-4 gap-4 mb-6">
              <div class="p-4 bg-blue-50 rounded-lg text-center">
                <p class="text-2xl font-bold text-blue-900"><%= format_number(@freshness_health.total_events) %></p>
                <p class="text-xs text-blue-700 mt-1">Total Events</p>
              </div>
              <div class="p-4 bg-purple-50 rounded-lg text-center">
                <p class="text-2xl font-bold text-purple-900"><%= format_number(@freshness_health.detail_jobs_executed) %></p>
                <p class="text-xs text-purple-700 mt-1">Detail Jobs</p>
                <p class="text-xs text-purple-600 mt-1">(last 7 days)</p>
              </div>
              <div class="p-4 bg-green-50 rounded-lg text-center">
                <p class="text-2xl font-bold text-green-900"><%= format_number(@freshness_health.expected_jobs) %></p>
                <p class="text-xs text-green-700 mt-1">Expected Jobs</p>
                <p class="text-xs text-green-600 mt-1">(if working)</p>
              </div>
              <div class="p-4 bg-orange-50 rounded-lg text-center">
                <p class="text-2xl font-bold text-orange-900"><%= Float.round(@freshness_health.processing_rate * 100, 1) %>%</p>
                <p class="text-xs text-orange-700 mt-1">Processing Rate</p>
                <p class="text-xs text-orange-600 mt-1">(per run)</p>
              </div>
            </div>

            <!-- Diagnosis -->
            <div class="border-t pt-4">
              <h3 class="text-sm font-semibold text-gray-900 mb-3">📋 Diagnosis</h3>
              <div class="text-sm text-gray-700 whitespace-pre-line">
                <%= @freshness_health.diagnosis %>
              </div>
            </div>
          </div>
        </div>

        <!-- Occurrence Type Distribution (Phase 1-3) -->
        <div class="bg-white rounded-lg shadow mb-8">
          <div class="px-6 py-4 border-b border-gray-200 flex items-center justify-between">
            <div>
              <h2 class="text-lg font-semibold text-gray-900">🎭 Occurrence Type Distribution</h2>
              <p class="mt-1 text-sm text-gray-500">Breakdown of event occurrence patterns</p>
            </div>
            <button
              phx-click="toggle_occurrence_details"
              class="text-sm px-3 py-1 bg-gray-100 hover:bg-gray-200 rounded-md transition-colors"
            >
              <%= if @show_occurrence_details, do: "Hide Details", else: "Show Details" %>
            </button>
          </div>
          <div class="p-6">
            <!-- Pie Chart (only show if 2+ occurrence types) -->
            <%= if length(@comprehensive_stats.occurrence_types) >= 2 do %>
              <div class="mb-6">
                <div style="height: 300px; max-width: 500px; margin: 0 auto;">
                  <canvas
                    id="occurrence-type-chart"
                    phx-hook="ChartHook"
                    phx-update="ignore"
                    data-chart-data={@occurrence_chart_data}
                    data-chart-type="pie"
                  ></canvas>
                </div>
              </div>
            <% end %>

            <!-- Detailed Breakdown -->
            <div class="space-y-4">
              <%= for occurrence <- @comprehensive_stats.occurrence_types do %>
                <% {emoji, color} = case occurrence.type do
                  "explicit" -> {"🎯", "#3B82F6"}
                  "pattern" -> {"🔄", "#8B5CF6"}
                  "exhibition" -> {"🖼️", "#EC4899"}
                  "recurring" -> {"📅", "#10B981"}
                  _ -> {"❓", "#6B7280"}
                end %>
                <div class="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                  <div class="flex items-center flex-1">
                    <span class="text-2xl mr-3"><%= emoji %></span>
                    <div class="flex-1">
                      <p class="text-sm font-medium text-gray-900 capitalize"><%= occurrence.type %></p>
                      <%= if @show_occurrence_details do %>
                        <div class="mt-1 w-full bg-gray-200 rounded-full h-2">
                          <div class="h-2 rounded-full" style={"width: #{occurrence.percentage}%; background-color: #{color}"}></div>
                        </div>
                      <% end %>
                    </div>
                  </div>
                  <div class="ml-4 text-right">
                    <p class="text-lg font-bold text-gray-900"><%= occurrence.count %></p>
                    <%= if @show_occurrence_details do %>
                      <p class="text-xs text-gray-500"><%= occurrence.percentage %>%</p>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Category Breakdown (Phase 1-3) -->
        <div class="bg-white rounded-lg shadow mb-8">
          <div class="px-6 py-4 border-b border-gray-200 flex items-center justify-between">
            <div>
              <h2 class="text-lg font-semibold text-gray-900">📁 Category Breakdown</h2>
              <p class="mt-1 text-sm text-gray-500">Top 10 categories by event count</p>
            </div>
            <div class="flex items-center gap-2">
              <button
                phx-click="toggle_category_details"
                class="text-sm px-3 py-1 bg-gray-100 hover:bg-gray-200 rounded-md transition-colors"
              >
                <%= if @show_category_details, do: "Hide Details", else: "Show Details" %>
              </button>
              <form phx-change="sort_categories" class="flex items-center gap-1">
                <label class="text-xs text-gray-600">Sort:</label>
                <select
                  name="by"
                  class="text-xs border-gray-300 rounded-md"
                >
                  <option value="count" selected={@category_sort == :count}>Count</option>
                  <option value="name" selected={@category_sort == :name}>Name</option>
                  <option value="percentage" selected={@category_sort == :percentage}>Percentage</option>
                </select>
              </form>
            </div>
          </div>
          <div class="p-6">
            <!-- Pie Chart (Top 5 + Other) - only show if 2+ categories -->
            <%= if @comprehensive_stats.category_stats.total_categories >= 2 do %>
              <div class="mb-6">
                <div style="height: 300px; max-width: 500px; margin: 0 auto;">
                  <canvas
                    id="category-pie-chart"
                    phx-hook="ChartHook"
                    phx-update="ignore"
                    data-chart-data={@category_chart_data}
                    data-chart-type="pie"
                  ></canvas>
                </div>
              </div>
            <% end %>

            <!-- Category Stats Summary -->
            <div class="grid grid-cols-3 gap-4 mb-6">
              <div class="p-4 bg-blue-50 rounded-lg text-center">
                <p class="text-2xl font-bold text-blue-900"><%= @comprehensive_stats.category_stats.total_categories %></p>
                <p class="text-xs text-blue-700 mt-1">Unique Categories</p>
              </div>
              <div class="p-4 bg-green-50 rounded-lg text-center">
                <p class="text-2xl font-bold text-green-900"><%= @comprehensive_stats.category_stats.events_with_category %></p>
                <p class="text-xs text-green-700 mt-1">Categorized Events</p>
              </div>
              <div class="p-4 bg-purple-50 rounded-lg text-center">
                <p class="text-2xl font-bold text-purple-900"><%= Float.round(@comprehensive_stats.category_stats.coverage_percentage, 1) %>%</p>
                <p class="text-xs text-purple-700 mt-1">Coverage</p>
              </div>
            </div>

            <!-- Top Categories List -->
            <%= if @show_category_details do %>
              <div class="space-y-3">
                <%= for category <- @comprehensive_stats.top_categories do %>
                  <% color = get_category_color(@comprehensive_stats.top_categories, category.category_name) %>
                  <div class="flex items-center justify-between p-3 border rounded-lg hover:bg-gray-50">
                    <div class="flex items-center flex-1">
                      <div class="w-4 h-4 rounded-full mr-3 flex-shrink-0" style={"background-color: #{color}"}></div>
                      <div class="flex-1">
                        <p class="text-sm font-medium text-gray-900">
                          <%= if category.category_name do %>
                            <%= category.category_name %>
                          <% else %>
                            <span class="text-gray-400 italic">Uncategorized</span>
                          <% end %>
                        </p>
                        <div class="mt-1 w-full bg-gray-200 rounded-full h-1.5">
                          <div class="h-1.5 rounded-full" style={"width: #{category.percentage}%; background-color: #{color}"}></div>
                        </div>
                      </div>
                    </div>
                    <div class="ml-4 text-right">
                      <p class="text-lg font-bold text-gray-900"><%= category.count %></p>
                      <p class="text-xs text-gray-500"><%= category.percentage %>%</p>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Venue Statistics (Phase 1-3) -->
        <div class="bg-white rounded-lg shadow mb-8">
          <div class="px-6 py-4 border-b border-gray-200 flex items-center justify-between">
            <div>
              <h2 class="text-lg font-semibold text-gray-900">📍 Venue Statistics</h2>
              <p class="mt-1 text-sm text-gray-500">Top 10 venues and coverage metrics</p>
            </div>
            <div class="flex items-center gap-2">
              <button
                phx-click="toggle_venue_details"
                class="text-sm px-3 py-1 bg-gray-100 hover:bg-gray-200 rounded-md transition-colors"
              >
                <%= if @show_venue_details, do: "Collapse", else: "Expand" %>
              </button>
              <form phx-change="sort_venues" class="flex items-center gap-1">
                <label class="text-xs text-gray-600">Sort:</label>
                <select
                  name="by"
                  class="text-xs border-gray-300 rounded-md"
                >
                  <option value="count" selected={@venue_sort == :count}>Event Count</option>
                  <option value="name" selected={@venue_sort == :name}>Name</option>
                </select>
              </form>
            </div>
          </div>
          <div class="p-6">
            <!-- Venue Stats Summary -->
            <div class="grid grid-cols-3 gap-4 mb-6">
              <div class="p-4 bg-blue-50 rounded-lg text-center">
                <p class="text-2xl font-bold text-blue-900"><%= @comprehensive_stats.venue_stats.unique_venues %></p>
                <p class="text-xs text-blue-700 mt-1">Unique Venues</p>
              </div>
              <div class="p-4 bg-green-50 rounded-lg text-center">
                <p class="text-2xl font-bold text-green-900"><%= @comprehensive_stats.venue_stats.events_with_venues %></p>
                <p class="text-xs text-green-700 mt-1">Events with Venues</p>
              </div>
              <div class="p-4 bg-purple-50 rounded-lg text-center">
                <p class="text-2xl font-bold text-purple-900"><%= Float.round(@comprehensive_stats.venue_stats.venue_coverage, 1) %>%</p>
                <p class="text-xs text-purple-700 mt-1">Coverage</p>
              </div>
            </div>

            <!-- Top Venues List -->
            <%= if @show_venue_details do %>
              <div class="space-y-3">
                <%= for venue <- @comprehensive_stats.venue_stats.top_venues do %>
                  <div class="p-4 border rounded-lg hover:bg-gray-50 space-y-2">
                    <!-- Venue Name & Event Count -->
                    <div class="flex items-center justify-between">
                      <div class="flex-1">
                        <p class="text-sm font-medium text-gray-900"><%= venue.venue_name %></p>
                        <!-- Quality Badges -->
                        <div class="flex items-center gap-2 mt-1 flex-wrap">
                          <%= if venue.address do %>
                            <span class="text-xs bg-green-100 text-green-800 px-2 py-0.5 rounded" title="Address available">✅ Address</span>
                          <% end %>
                          <%= if venue.source do %>
                            <span class="text-xs bg-gray-100 text-gray-800 px-2 py-0.5 rounded" title="Data source">
                              🔍 <%= venue.source %>
                            </span>
                          <% end %>
                        </div>
                      </div>
                      <div class="ml-4 text-right flex-shrink-0">
                        <p class="text-lg font-bold text-gray-900"><%= venue.event_count %></p>
                        <p class="text-xs text-gray-500">events</p>
                      </div>
                    </div>

                    <!-- Venue Details -->
                    <div class="text-xs text-gray-600 space-y-1 pt-2 border-t">
                      <%= if venue.address do %>
                        <div class="flex items-start">
                          <span class="font-medium w-24 flex-shrink-0">Address:</span>
                          <span class="flex-1"><%= venue.address %></span>
                        </div>
                      <% end %>
                      <%= if venue.latitude && venue.longitude do %>
                        <div class="flex items-start">
                          <span class="font-medium w-24 flex-shrink-0">GPS:</span>
                          <span class="flex-1"><%= Float.round(venue.latitude, 6) %>, <%= Float.round(venue.longitude, 6) %></span>
                        </div>
                      <% end %>
                      <%= if venue.geocoding_performance do %>
                        <div class="flex items-start">
                          <span class="font-medium w-24 flex-shrink-0">Geocoding:</span>
                          <span class="flex-1">
                            <%= case venue.geocoding_performance do %>
                              <% %{"match_type" => match_type} -> %>
                                <span class="text-xs bg-gray-100 px-1.5 py-0.5 rounded"><%= match_type %></span>
                              <% _ -> %>
                                <span class="text-gray-400">N/A</span>
                            <% end %>
                          </span>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="text-center text-gray-500 text-sm py-4">
                Click "Expand" to see top venues
              </div>
            <% end %>
          </div>
        </div>

        <!-- Image Statistics (Phase 1-3) -->
        <div class="bg-white rounded-lg shadow mb-8">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">🖼️ Image Statistics</h2>
            <p class="mt-1 text-sm text-gray-500">Image coverage and distribution metrics</p>
          </div>
          <div class="p-6">
            <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div class="p-4 bg-blue-50 rounded-lg text-center">
                <p class="text-2xl font-bold text-blue-900"><%= @comprehensive_stats.image_stats.total_images %></p>
                <p class="text-xs text-blue-700 mt-1">Total Images</p>
              </div>
              <div class="p-4 bg-green-50 rounded-lg text-center">
                <p class="text-2xl font-bold text-green-900"><%= Float.round(@comprehensive_stats.image_stats.coverage_percentage, 1) %>%</p>
                <p class="text-xs text-green-700 mt-1">Coverage</p>
              </div>
              <div class="p-4 bg-purple-50 rounded-lg text-center">
                <p class="text-2xl font-bold text-purple-900"><%= @comprehensive_stats.image_stats.events_with_images %></p>
                <p class="text-xs text-purple-700 mt-1">With Images</p>
              </div>
              <div class="p-4 bg-orange-50 rounded-lg text-center">
                <p class="text-2xl font-bold text-orange-900"><%= Float.round(@comprehensive_stats.image_stats.average_per_event, 1) %></p>
                <p class="text-xs text-orange-700 mt-1">Avg per Event</p>
              </div>
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

        <!-- Run History (Phase 3) -->
        <div class="bg-white rounded-lg shadow mb-8">
          <div class="px-6 py-4 border-b border-gray-200 flex items-center justify-between">
            <div class="flex-1">
              <h2 class="text-lg font-semibold text-gray-900">Recent Job History (Last 20)</h2>
              <p class="mt-1 text-sm text-gray-500">
                Complete job execution history showing both successes and failures for accurate context.
              </p>
            </div>
            <div class="flex items-center gap-2">
              <label class="text-xs text-gray-600">Filter:</label>
              <form phx-change="filter_job_history">
                <select
                  name="filter"
                  class="text-xs border-gray-300 rounded-md"
                >
                  <option value="all" selected={@job_history_filter == :all}>All</option>
                  <option value="successes" selected={@job_history_filter == :successes}>Successes</option>
                  <option value="failures" selected={@job_history_filter == :failures}>Failures</option>
                </select>
              </form>
            </div>
          </div>
          <div class="overflow-x-auto">
            <% filtered_history = case @job_history_filter do
              :successes -> Enum.filter(@run_history, fn run -> run.state == "success" end)
              :failures -> Enum.filter(@run_history, fn run -> run.state != "success" end)
              _ -> @run_history
            end %>
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Time</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Duration</th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Summary</th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for run <- filtered_history do %>
                  <% job_id = "job-#{run.id}" %>
                  <% is_expanded = MapSet.member?(@expanded_job_ids, job_id) %>
                  <% is_failure = run.state != "success" %>

                  <tr class={[
                    if(run.state == "success", do: "bg-green-50", else: ""),
                    if(is_failure && run.errors, do: "cursor-pointer", else: "")
                  ]}>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      <%= format_datetime(run.completed_at) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <%= if run.state == "success" do %>
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
                    <td class="px-6 py-4 text-sm">
                      <%= if run.state == "success" do %>
                        <span class="text-gray-600">Job completed successfully</span>
                      <% else %>
                        <%= if run.errors do %>
                          <div class="flex items-center justify-between">
                            <span class="text-red-600 text-xs truncate max-w-md"><%= run.errors %></span>
                            <button
                              phx-click="toggle_job_details"
                              phx-value-job_id={job_id}
                              class="ml-2 text-blue-600 hover:text-blue-800 text-xs font-medium flex-shrink-0"
                            >
                              <%= if is_expanded, do: "Hide Details ▲", else: "Show Details ▼" %>
                            </button>
                          </div>
                        <% else %>
                          <span class="text-orange-600">Failed with warnings</span>
                        <% end %>
                      <% end %>
                    </td>
                  </tr>

                  <%= if is_expanded && is_failure && run.errors do %>
                    <tr class="bg-red-50">
                      <td colspan="4" class="px-6 py-4">
                        <div class="space-y-3">
                          <div>
                            <h4 class="text-xs font-semibold text-gray-700 mb-1">Full Error Message:</h4>
                            <p class="text-xs text-red-700 font-mono bg-red-100 p-2 rounded whitespace-pre-wrap"><%= run.errors %></p>
                          </div>
                          <%= if run.meta do %>
                            <div>
                              <h4 class="text-xs font-semibold text-gray-700 mb-1">Job Metadata:</h4>
                              <pre class="text-xs text-gray-700 bg-gray-100 p-2 rounded overflow-x-auto"><%= format_json(run.meta) %></pre>
                            </div>
                          <% end %>
                          <%= if run.args do %>
                            <div>
                              <h4 class="text-xs font-semibold text-gray-700 mb-1">Job Arguments:</h4>
                              <pre class="text-xs text-gray-700 bg-gray-100 p-2 rounded overflow-x-auto"><%= format_json(run.args) %></pre>
                            </div>
                          <% end %>
                        </div>
                      </td>
                    </tr>
                  <% end %>
                <% end %>
                <%= if Enum.empty?(filtered_history) do %>
                  <tr>
                    <td colspan="4" class="px-6 py-4 text-center text-sm text-gray-500">
                      <%= case @job_history_filter do %>
                        <% :successes -> %> No successful jobs found
                        <% :failures -> %> No failed jobs found
                        <% _ -> %> No run history available
                      <% end %>
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
              <p class="text-sm text-gray-500 mt-1">Total events: <%= format_number(@total_events) %> (metro areas aggregated)</p>
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
                    <!-- Primary City Row -->
                    <tr class="hover:bg-gray-50">
                      <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                        <%= if length(city.subcities) > 0 do %>
                          <button
                            type="button"
                            phx-click="toggle_metro_area"
                            phx-value-city-id={city.city_id}
                            aria-expanded={to_string(MapSet.member?(@expanded_metro_areas, city.city_id))}
                            class="mr-2 text-gray-600 hover:text-gray-900"
                          >
                            <span class="sr-only">Toggle subcities for <%= city.city_name %></span>
                            <%= if MapSet.member?(@expanded_metro_areas, city.city_id), do: "▼", else: "▶" %>
                          </button>
                        <% end %>
                        <%= city.city_name %>
                        <%= if length(city.subcities) > 0 do %>
                          <span class="text-xs text-gray-500 ml-1">(<%= length(city.subcities) %> areas)</span>
                        <% end %>
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

                    <!-- Subcity Rows (Expandable) -->
                    <%= if MapSet.member?(@expanded_metro_areas, city.city_id) do %>
                      <%= for subcity <- city.subcities do %>
                        <tr class="bg-gray-50">
                          <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-600 pl-12">
                            ↳ <%= subcity.city_name %>
                          </td>
                          <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                            <%= format_number(subcity.count) %>
                          </td>
                          <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-400">
                            —
                          </td>
                          <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-400">
                            —
                          </td>
                        </tr>
                      <% end %>
                    <% end %>
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

  defp format_occurrence_pie_chart(occurrence_types) do
    # Color palette for occurrence types (4 valid types)
    colors = %{
      # Blue - One-time events with specific date/time
      "explicit" => "#3B82F6",
      # Purple - Recurring events with strict schedule
      "pattern" => "#8B5CF6",
      # Pink - Open-ended periods with continuous access
      "exhibition" => "#EC4899",
      # Green - Recurring events without strict pattern
      "recurring" => "#10B981"
    }

    labels =
      Enum.map(occurrence_types, fn occ ->
        String.capitalize(occ.type)
      end)

    data = Enum.map(occurrence_types, & &1.count)

    background_colors =
      Enum.map(occurrence_types, fn occ ->
        Map.get(colors, occ.type, "#6B7280")
      end)

    %{
      labels: labels,
      datasets: [
        %{
          data: data,
          backgroundColor: background_colors,
          borderWidth: 2,
          borderColor: "#FFFFFF"
        }
      ]
    }
  end

  defp format_category_pie_chart(top_categories) do
    # Filter out uncategorized entries (nil category_id)
    categorized_only = Enum.filter(top_categories, fn cat -> cat.category_id != nil end)
    uncategorized = Enum.find(top_categories, fn cat -> cat.category_id == nil end)

    # Take top 5 CATEGORIZED events only
    {top_5, rest} = Enum.split(categorized_only, 5)

    # Build labels and data from top 5 categorized
    labels = Enum.map(top_5, fn cat -> cat.category_name end)
    data = Enum.map(top_5, & &1.count)

    # Add "Other" for remaining categorized events
    {labels, data} =
      if length(rest) > 0 do
        other_count = Enum.reduce(rest, 0, fn cat, acc -> acc + cat.count end)
        {labels ++ ["Other Categories"], data ++ [other_count]}
      else
        {labels, data}
      end

    # Optionally add "Uncategorized" as final slice to show full picture
    {labels, data} =
      if uncategorized do
        {labels ++ ["Uncategorized"], data ++ [uncategorized.count]}
      else
        {labels, data}
      end

    # Color palette (extended to include gray for uncategorized)
    colors = ["#3B82F6", "#8B5CF6", "#EC4899", "#F59E0B", "#10B981", "#D1D5DB", "#9CA3AF"]

    %{
      labels: labels,
      datasets: [
        %{
          data: data,
          backgroundColor: colors,
          borderWidth: 2,
          borderColor: "#FFFFFF"
        }
      ]
    }
  end

  # Get the color for a category based on its position in the sorted list
  # This ensures the list colors match the pie chart colors
  defp get_category_color(categories, category_name) do
    # Filter out uncategorized entries
    categorized_only = Enum.filter(categories, fn cat -> cat.category_id != nil end)

    # Take top 5 categorized
    {top_5, rest} = Enum.split(categorized_only, 5)

    # Color palette matching the pie chart
    colors = ["#3B82F6", "#8B5CF6", "#EC4899", "#F59E0B", "#10B981", "#D1D5DB", "#9CA3AF"]

    # Find the index of this category in the top 5
    top_5_names = Enum.map(top_5, & &1.category_name)

    cond do
      # Check if it's in the top 5
      category_name in top_5_names ->
        index = Enum.find_index(top_5_names, &(&1 == category_name))
        Enum.at(colors, index, "#9CA3AF")

      # Check if it's "Other Categories" (categories beyond top 5)
      category_name == "Other Categories" && length(rest) > 0 ->
        # Use the 6th color (gray)
        "#D1D5DB"

      # Uncategorized
      category_name == nil ->
        # Use the 7th color (darker gray)
        "#9CA3AF"

      # Default fallback
      true ->
        "#9CA3AF"
    end
  end

  defp sort_categories(categories, :count) do
    Enum.sort_by(categories, & &1.count, :desc)
  end

  defp sort_categories(categories, :name) do
    Enum.sort_by(categories, &(&1.category_name || ""), :asc)
  end

  defp sort_categories(categories, :percentage) do
    Enum.sort_by(categories, & &1.percentage, :desc)
  end

  defp sort_venues(venues, :count) do
    Enum.sort_by(venues, & &1.event_count, :desc)
  end

  defp sort_venues(venues, :name) do
    Enum.sort_by(venues, & &1.venue_name, :asc)
  end

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

  # Format JSON data for display (handles both maps and strings)
  defp format_json(data) when is_map(data) do
    Jason.encode!(data, pretty: true)
  end

  defp format_json(data) when is_binary(data) do
    # If it's already a JSON string, try to decode and re-encode it pretty
    case Jason.decode(data) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      {:error, _} -> data
    end
  end

  defp format_json(nil), do: "null"
  defp format_json(_), do: "N/A"

  # Safe atom conversion for sort parameters
  # Prevents LiveView crashes from unexpected client input
  defp safe_sort_atom("count", _), do: :count
  defp safe_sort_atom("name", _), do: :name
  defp safe_sort_atom("percentage", :category), do: :percentage
  # Default fallback
  defp safe_sort_atom(_, _), do: :count

  # Load city slugs from database for given city IDs
  # Returns a map of city_id => city_slug
  defp load_city_slugs([]), do: %{}

  defp load_city_slugs(city_ids) do
    query =
      from(c in EventasaurusDiscovery.Locations.City,
        where: c.id in ^city_ids,
        select: {c.id, c.slug}
      )

    query
    |> Repo.replica().all()
    |> Map.new()
  end

  # Freshness health status helpers
  defp freshness_status_bg(:broken), do: "bg-red-50"
  defp freshness_status_bg(:warning), do: "bg-orange-50"
  defp freshness_status_bg(:degraded), do: "bg-yellow-50"
  defp freshness_status_bg(:healthy), do: "bg-green-50"
  defp freshness_status_bg(:no_data), do: "bg-gray-50"

  defp freshness_status_border(:broken), do: "border-red-200"
  defp freshness_status_border(:warning), do: "border-orange-200"
  defp freshness_status_border(:degraded), do: "border-yellow-200"
  defp freshness_status_border(:healthy), do: "border-green-200"
  defp freshness_status_border(:no_data), do: "border-gray-200"

  defp freshness_status_emoji(:broken), do: "🔴"
  defp freshness_status_emoji(:warning), do: "⚠️"
  defp freshness_status_emoji(:degraded), do: "⚡"
  defp freshness_status_emoji(:healthy), do: "✅"
  defp freshness_status_emoji(:no_data), do: "⚪"

  defp freshness_status_label(:broken), do: "CRITICAL - Freshness Checking Broken"
  defp freshness_status_label(:warning), do: "WARNING - Mostly Not Working"
  defp freshness_status_label(:degraded), do: "DEGRADED - Partially Working"
  defp freshness_status_label(:healthy), do: "HEALTHY - Working Correctly"
  defp freshness_status_label(:no_data), do: "NO DATA - No Events Yet"

  defp freshness_status_text_color(:broken), do: "text-red-900"
  defp freshness_status_text_color(:warning), do: "text-orange-900"
  defp freshness_status_text_color(:degraded), do: "text-yellow-900"
  defp freshness_status_text_color(:healthy), do: "text-green-900"
  defp freshness_status_text_color(:no_data), do: "text-gray-900"

  # Find all cities that have venues from this source with venue name quality issues
  defp find_cities_with_venue_quality_issues(source_slug) do
    # Get the source
    source =
      Repo.replica().one(
        from(s in EventasaurusDiscovery.Sources.Source,
          where: s.slug == ^source_slug,
          select: s
        )
      )

    if source do
      # Find all cities with venues from this source that have metadata
      # The job will filter by actual quality on execution
      from(v in Venue,
        join: pe in EventasaurusDiscovery.PublicEvents.PublicEvent,
        on: pe.venue_id == v.id,
        join: pes in EventasaurusDiscovery.PublicEvents.PublicEventSource,
        on: pes.event_id == pe.id,
        where: pes.source_id == ^source.id,
        where: not is_nil(v.metadata),
        where: not is_nil(v.city_id),
        select: v.city_id,
        distinct: true
      )
      |> Repo.replica().all()
    else
      []
    end
  end
end
