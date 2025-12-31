defmodule EventasaurusWeb.Admin.MovieMatchingLive do
  @moduledoc """
  Movie Database Dashboard - Provider Analytics & Match Visibility

  Provides observability into the movie matching system:
  - Provider breakdown (TMDB/OMDb/IMDB success rates)
  - Confidence distribution visualization
  - Failure analysis with error categorization
  - Unified movie status table with sorting/filtering
  - Real-time activity feed

  Part of Phase 3 of Epic #3077: Cinema City Scraper Reliability
  UI/UX improvements per Issue #3094
  """

  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Movies.MatchingStats

  @refresh_interval 30_000
  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh, @refresh_interval)
    end

    # Initialize with defaults - handle_params will apply URL state
    socket =
      socket
      |> assign(:page_title, "Movie Matching Dashboard")
      |> assign(:time_range, "24h")
      |> assign(:loading, true)
      |> assign(:sort_by, "status")
      |> assign(:sort_dir, "asc")
      |> assign(:status_filter, "all")
      |> assign(:selected_movie, nil)
      |> assign(:show_detail_modal, false)
      |> assign(:page, 1)
      |> assign(:per_page, @per_page)
      |> assign(:total_count, 0)
      |> assign(:total_pages, 1)
      # Initialize data with empty defaults for first render
      |> assign(:overview, %{
        total_lookups: 0,
        successful_matches: 0,
        pending: 0,
        success_rate: 0.0
      })
      |> assign(:providers, [])
      |> assign(:confidence_distribution, %{})
      |> assign(:failures, [])
      |> assign(:failure_analysis, [])
      |> assign(:recent_matches, [])
      |> assign(:hourly_counts, [])
      |> assign(:total_movies, 0)
      |> assign(:duplicate_count, 0)
      |> assign(:unmatched_movies, [])
      |> assign(:showtime_impact, %{})
      |> assign(:last_updated, DateTime.utc_now())

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    # Parse URL params and apply state
    socket =
      socket
      |> assign(:page, parse_page(params["page"]))
      |> assign(:status_filter, params["status"] || "all")
      |> assign(:sort_by, params["sort_by"] || "status")
      |> assign(:sort_dir, params["sort_dir"] || "asc")
      |> assign(:time_range, params["range"] || "24h")
      |> assign(:loading, true)
      |> load_data()

    {:noreply, socket}
  end

  defp parse_page(nil), do: 1

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {p, _} when p > 0 -> p
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

  # Build URL params from current socket state + updates
  # Following CityIndexLive pattern for clean URL state management
  defp build_params(socket, updates) do
    page = updates[:page] || socket.assigns.page

    %{
      page: if(page > 1, do: page, else: nil),
      status: updates[:status] || socket.assigns.status_filter,
      sort_by: updates[:sort_by] || socket.assigns.sort_by,
      sort_dir: updates[:sort_dir] || socket.assigns.sort_dir,
      range: updates[:range] || socket.assigns.time_range
    }
    # Remove nil values and defaults to keep URLs clean
    |> Enum.reject(fn {k, v} ->
      is_nil(v) ||
        (k == :status && v == "all") ||
        (k == :sort_by && v == "status") ||
        (k == :sort_dir && v == "asc") ||
        (k == :range && v == "24h")
    end)
    |> Map.new()
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("change_time_range", %{"range" => range}, socket) do
    # Reset to page 1 when time range changes
    params = build_params(socket, %{range: range, page: 1})
    {:noreply, push_patch(socket, to: ~p"/admin/movies?#{params}")}
  end

  @impl true
  def handle_event("sort", %{"column" => column}, socket) do
    {sort_by, sort_dir} =
      if socket.assigns.sort_by == column do
        # Toggle direction
        new_dir = if socket.assigns.sort_dir == "asc", do: "desc", else: "asc"
        {column, new_dir}
      else
        # New column, default to asc (except status which defaults desc for unmatched first)
        {column, if(column == "status", do: "asc", else: "desc")}
      end

    # Reset to page 1 when sort changes
    params = build_params(socket, %{sort_by: sort_by, sort_dir: sort_dir, page: 1})
    {:noreply, push_patch(socket, to: ~p"/admin/movies?#{params}")}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    # Reset to page 1 when filter changes
    params = build_params(socket, %{status: status, page: 1})
    {:noreply, push_patch(socket, to: ~p"/admin/movies?#{params}")}
  end

  @impl true
  def handle_event("go_to_page", %{"page" => page_str}, socket) do
    page = String.to_integer(page_str)

    # Calculate total_pages fresh since render-time assigns don't persist to socket
    unified_movies = build_unified_movie_list(socket.assigns)
    filtered = filter_movies(unified_movies, socket.assigns.status_filter)
    total_count = length(filtered)
    total_pages = max(1, ceil(total_count / socket.assigns.per_page))

    page = max(1, min(page, total_pages))
    params = build_params(socket, %{page: page})
    {:noreply, push_patch(socket, to: ~p"/admin/movies?#{params}")}
  end

  @impl true
  def handle_event("show_detail", %{"index" => index_str}, socket) do
    local_index = String.to_integer(index_str)
    # Get the movie from the current unified list
    unified_movies = build_unified_movie_list(socket.assigns)
    filtered = filter_movies(unified_movies, socket.assigns.status_filter)
    sorted = sort_movies(filtered, socket.assigns.sort_by, socket.assigns.sort_dir)

    # Adjust index for pagination offset
    offset = (socket.assigns.page - 1) * socket.assigns.per_page
    global_index = offset + local_index
    movie = Enum.at(sorted, global_index)

    {:noreply,
     socket
     |> assign(:selected_movie, movie)
     |> assign(:show_detail_modal, true)}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_movie, nil)
     |> assign(:show_detail_modal, false)}
  end

  @impl true
  def handle_event("retry_job", %{"job-id" => job_id_str}, socket) do
    job_id = String.to_integer(job_id_str)

    case retry_failed_job(job_id) do
      :ok ->
        {:noreply,
         socket
         |> assign(:show_detail_modal, false)
         |> assign(:selected_movie, nil)
         |> put_flash(:info, "Job #{job_id} has been queued for retry")
         |> load_data()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to retry job: #{reason}")}
    end
  end

  defp retry_failed_job(job_id) do
    # Use Oban to retry the discarded job
    case EventasaurusApp.Repo.get(Oban.Job, job_id) do
      nil ->
        {:error, :not_found}

      job ->
        # Retry by inserting a new job with the same args
        case Oban.retry_job(job) do
          {:ok, _} -> :ok
          :ok -> :ok
          error -> {:error, inspect(error)}
        end
    end
  end

  # Max concurrency reduced to 2 to avoid exhausting the connection pool
  # (replica pool is only 5 connections, matching MonitoringDashboardLive pattern)
  @max_concurrency 2
  @task_timeout 15_000

  defp load_data(socket) do
    hours = time_range_to_hours(socket.assigns.time_range)

    # Phase 1: Load independent data in parallel
    # These queries don't depend on each other
    independent_loaders = [
      {:overview, fn -> MatchingStats.get_overview_stats(hours) end},
      {:confidence, fn -> MatchingStats.get_confidence_distribution(hours) end},
      {:failures, fn -> MatchingStats.get_recent_failures(20) end},
      {:failure_analysis, fn -> MatchingStats.get_failure_analysis(hours) end},
      {:recent_matches, fn -> MatchingStats.get_recent_matches(10) end},
      {:hourly, fn -> MatchingStats.get_hourly_counts(min(hours, 48)) end},
      {:total_movies, fn -> MatchingStats.get_total_movie_count() end},
      {:duplicates, fn -> MatchingStats.get_duplicate_film_id_count() end},
      {:unmatched_movies, fn -> MatchingStats.get_unmatched_movies_blocking_showtimes(hours) end}
    ]

    phase1_results =
      independent_loaders
      |> Task.async_stream(
        fn {key, loader} -> {key, loader.()} end,
        max_concurrency: @max_concurrency,
        timeout: @task_timeout,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, {key, value}} -> {key, value}
        {:exit, _reason} -> {nil, nil}
      end)
      |> Enum.reject(fn {key, _} -> is_nil(key) end)
      |> Map.new()

    # Phase 2: Derive dependent data from phase 1 results (no additional queries)
    # Pass pre-computed data to avoid duplicate queries
    overview = phase1_results[:overview]
    unmatched_movies = phase1_results[:unmatched_movies] || []

    providers = MatchingStats.get_provider_stats(hours, overview)
    showtime_impact = MatchingStats.get_showtime_impact_metrics(hours, unmatched_movies)

    socket
    |> assign(:loading, false)
    |> assign(:overview, overview)
    |> assign(:providers, providers)
    |> assign(:confidence_distribution, phase1_results[:confidence])
    |> assign(:failures, phase1_results[:failures])
    |> assign(:failure_analysis, phase1_results[:failure_analysis])
    |> assign(:recent_matches, phase1_results[:recent_matches])
    |> assign(:hourly_counts, phase1_results[:hourly])
    |> assign(:total_movies, phase1_results[:total_movies])
    |> assign(:duplicate_count, phase1_results[:duplicates])
    |> assign(:unmatched_movies, unmatched_movies)
    |> assign(:showtime_impact, showtime_impact)
    |> assign(:last_updated, DateTime.utc_now())
  end

  defp time_range_to_hours("1h"), do: 1
  defp time_range_to_hours("6h"), do: 6
  defp time_range_to_hours("24h"), do: 24
  defp time_range_to_hours("7d"), do: 168
  defp time_range_to_hours("30d"), do: 720
  defp time_range_to_hours(_), do: 24

  @impl true
  def render(assigns) do
    # Build unified movie list combining matched and unmatched movies
    unified_movies = build_unified_movie_list(assigns)
    filtered_movies = filter_movies(unified_movies, assigns.status_filter)
    sorted_movies = sort_movies(filtered_movies, assigns.sort_by, assigns.sort_dir)

    # Pagination calculations
    total_count = length(sorted_movies)
    total_pages = max(1, ceil(total_count / assigns.per_page))
    page = min(assigns.page, total_pages)
    offset = (page - 1) * assigns.per_page
    paginated_movies = Enum.slice(sorted_movies, offset, assigns.per_page)

    # Count by status for filter badges
    status_counts = %{
      all: length(unified_movies),
      unmatched: Enum.count(unified_movies, &(&1.status == :unmatched)),
      low_confidence: Enum.count(unified_movies, &(&1.status == :low_confidence)),
      matched: Enum.count(unified_movies, &(&1.status == :matched)),
      job_error: Enum.count(unified_movies, &(&1.status == :job_error))
    }

    # Filter providers to only show those with activity
    active_providers =
      Enum.filter(assigns.providers, fn p -> p.successes > 0 || p.failures > 0 end)

    # Calculate failure summary (job processing errors from Oban)
    failure_summary = summarize_failures(assigns.failure_analysis)

    # Calculate "Needs Attention" totals - combines ALL issue types
    # This gives a unified view of everything that needs action
    # Note: job_errors count comes from status_counts now (derived from unified_movies)
    needs_attention = %{
      unmatched: status_counts.unmatched,
      low_confidence: status_counts.low_confidence,
      job_errors: status_counts.job_error,
      total: status_counts.unmatched + status_counts.low_confidence + status_counts.job_error,
      blocked_events: calculate_total_blocked(unified_movies)
    }

    assigns =
      assigns
      |> assign(:unified_movies, paginated_movies)
      |> assign(:status_counts, status_counts)
      |> assign(:active_providers, active_providers)
      |> assign(:failure_summary, failure_summary)
      |> assign(:needs_attention, needs_attention)
      |> assign(:total_count, total_count)
      |> assign(:total_pages, total_pages)
      |> assign(:page, page)

    ~H"""
    <div class="min-h-screen p-6">
      <div class="max-w-7xl mx-auto">
        <!-- Header -->
        <div class="flex justify-between items-center mb-6">
          <div>
            <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Movie Matching Dashboard</h1>
            <p class="text-gray-500 dark:text-gray-400 text-sm">Provider analytics and match visibility</p>
          </div>

          <div class="flex items-center gap-4">
            <!-- Time Range Selector -->
            <div class="flex bg-gray-100 dark:bg-gray-800 rounded-lg p-1">
              <%= for range <- ["1h", "6h", "24h", "7d", "30d"] do %>
                <button
                  phx-click="change_time_range"
                  phx-value-range={range}
                  class={"px-3 py-1 rounded text-sm transition-colors #{if @time_range == range, do: "bg-blue-600 text-white", else: "text-gray-500 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white"}"}
                >
                  {range}
                </button>
              <% end %>
            </div>

            <!-- Last Updated -->
            <div class="text-xs text-gray-500 dark:text-gray-400">
              {format_time(@last_updated)}
            </div>
          </div>
        </div>

        <%= if @loading do %>
          <div class="flex justify-center items-center h-64">
            <div class="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-blue-500"></div>
          </div>
        <% else %>
          <!-- Summary Cards - Compact -->
          <div class="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
            <.summary_card
              title="Total Lookups"
              value={@overview.total_lookups}
              subtitle={"#{@overview.pending} pending"}
              color="blue"
            />
            <.summary_card
              title="Successful Matches"
              value={@overview.successful_matches}
              subtitle={"#{format_rate(@overview.success_rate)}% success rate"}
              color="green"
            />
            <!-- Needs Attention Card - Unified view of all issue types -->
            <.needs_attention_card needs_attention={@needs_attention} />
            <.summary_card
              title="Movies in DB"
              value={@total_movies}
              subtitle={"#{@duplicate_count} duplicates"}
              color={if @duplicate_count > 0, do: "yellow", else: "purple"}
            />
          </div>

          <!-- Compact 2-Column Analytics Row -->
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
            <!-- Provider Breakdown - Only active providers -->
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
              <h2 class="text-sm font-semibold text-gray-900 dark:text-white mb-3">Provider Breakdown</h2>
              <div class="space-y-2">
                <%= if Enum.empty?(@active_providers) do %>
                  <div class="text-sm text-gray-500 dark:text-gray-400 text-center py-2">
                    No provider activity
                  </div>
                <% else %>
                  <%= for provider <- @active_providers do %>
                    <.provider_row provider={provider} />
                  <% end %>
                <% end %>
              </div>
            </div>

            <!-- Confidence Distribution - Compact Horizontal -->
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
              <h2 class="text-sm font-semibold text-gray-900 dark:text-white mb-3">Confidence Distribution</h2>
              <.confidence_chart_compact distribution={@confidence_distribution} />
            </div>
          </div>

          <!-- Unified Movie Status Table -->
          <div class="bg-white dark:bg-gray-800 rounded-lg shadow">
            <!-- Table Header with Filters -->
            <div class="p-4 border-b border-gray-200 dark:border-gray-700">
              <div class="flex justify-between items-center">
                <h2 class="text-lg font-semibold text-gray-900 dark:text-white">Movie Status</h2>

                <!-- Status Filter Pills -->
                <div class="flex gap-2 flex-wrap">
                  <button
                    phx-click="filter_status"
                    phx-value-status="all"
                    class={"px-3 py-1 rounded-full text-xs font-medium transition-colors #{if @status_filter == "all", do: "bg-gray-900 dark:bg-white text-white dark:text-gray-900", else: "bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-600"}"}
                  >
                    All ({@status_counts.all})
                  </button>
                  <button
                    phx-click="filter_status"
                    phx-value-status="job_error"
                    class={"px-3 py-1 rounded-full text-xs font-medium transition-colors #{if @status_filter == "job_error", do: "bg-orange-600 text-white", else: "bg-orange-100 dark:bg-orange-500/20 text-orange-600 dark:text-orange-400 hover:bg-orange-200 dark:hover:bg-orange-500/30"}"}
                  >
                    Job Errors ({@status_counts.job_error})
                  </button>
                  <button
                    phx-click="filter_status"
                    phx-value-status="unmatched"
                    class={"px-3 py-1 rounded-full text-xs font-medium transition-colors #{if @status_filter == "unmatched", do: "bg-red-600 text-white", else: "bg-red-100 dark:bg-red-500/20 text-red-600 dark:text-red-400 hover:bg-red-200 dark:hover:bg-red-500/30"}"}
                  >
                    Unmatched ({@status_counts.unmatched})
                  </button>
                  <button
                    phx-click="filter_status"
                    phx-value-status="low_confidence"
                    class={"px-3 py-1 rounded-full text-xs font-medium transition-colors #{if @status_filter == "low_confidence", do: "bg-yellow-600 text-white", else: "bg-yellow-100 dark:bg-yellow-500/20 text-yellow-600 dark:text-yellow-400 hover:bg-yellow-200 dark:hover:bg-yellow-500/30"}"}
                  >
                    Low Conf ({@status_counts.low_confidence})
                  </button>
                  <button
                    phx-click="filter_status"
                    phx-value-status="matched"
                    class={"px-3 py-1 rounded-full text-xs font-medium transition-colors #{if @status_filter == "matched", do: "bg-green-600 text-white", else: "bg-green-100 dark:bg-green-500/20 text-green-600 dark:text-green-400 hover:bg-green-200 dark:hover:bg-green-500/30"}"}
                  >
                    Matched ({@status_counts.matched})
                  </button>
                </div>
              </div>
            </div>

            <!-- Table -->
            <div class="overflow-x-auto">
              <table class="w-full">
                <thead class="text-left text-xs text-gray-500 dark:text-gray-400 bg-gray-50 dark:bg-gray-700/50">
                  <tr>
                    <th class="py-3 px-4">
                      <button phx-click="sort" phx-value-column="status" class="flex items-center gap-1 hover:text-gray-900 dark:hover:text-white">
                        Status
                        <.sort_indicator column="status" sort_by={@sort_by} sort_dir={@sort_dir} />
                      </button>
                    </th>
                    <th class="py-3 px-4">
                      <button phx-click="sort" phx-value-column="title" class="flex items-center gap-1 hover:text-gray-900 dark:hover:text-white">
                        Movie
                        <.sort_indicator column="title" sort_by={@sort_by} sort_dir={@sort_dir} />
                      </button>
                    </th>
                    <th class="py-3 px-4">Source Title</th>
                    <th class="py-3 px-4">TMDB ID</th>
                    <th class="py-3 px-4">
                      <button phx-click="sort" phx-value-column="confidence" class="flex items-center gap-1 hover:text-gray-900 dark:hover:text-white">
                        Confidence
                        <.sort_indicator column="confidence" sort_by={@sort_by} sort_dir={@sort_dir} />
                      </button>
                    </th>
                    <th class="py-3 px-4">
                      <button phx-click="sort" phx-value-column="blocked" class="flex items-center gap-1 hover:text-gray-900 dark:hover:text-white">
                        Impact
                        <.sort_indicator column="blocked" sort_by={@sort_by} sort_dir={@sort_dir} />
                      </button>
                    </th>
                    <th class="py-3 px-4">
                      <button phx-click="sort" phx-value-column="time" class="flex items-center gap-1 hover:text-gray-900 dark:hover:text-white">
                        Time
                        <.sort_indicator column="time" sort_by={@sort_by} sort_dir={@sort_dir} />
                      </button>
                    </th>
                    <th class="py-3 px-4">Actions</th>
                  </tr>
                </thead>
                <tbody class="text-sm">
                  <%= if Enum.empty?(@unified_movies) do %>
                    <tr>
                      <td colspan="8" class="py-8 text-center text-gray-500 dark:text-gray-400">
                        No movies to display
                      </td>
                    </tr>
                  <% else %>
                    <%= for {movie, index} <- Enum.with_index(@unified_movies) do %>
                      <.unified_movie_row movie={movie} index={index} />
                    <% end %>
                  <% end %>
                </tbody>
              </table>
            </div>

            <!-- Pagination -->
            <%= if @total_pages > 1 do %>
              <div class="p-4 border-t border-gray-200 dark:border-gray-700">
                <div class="flex items-center justify-between">
                  <div class="text-sm text-gray-500 dark:text-gray-400">
                    Showing {(@page - 1) * @per_page + 1} to {min(@page * @per_page, @total_count)} of {@total_count}
                  </div>
                  <div class="flex items-center gap-1">
                    <!-- Previous button -->
                    <button
                      phx-click="go_to_page"
                      phx-value-page={@page - 1}
                      disabled={@page == 1}
                      class={"px-3 py-1.5 rounded text-sm #{if @page == 1, do: "text-gray-400 dark:text-gray-600 cursor-not-allowed", else: "text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700"}"}
                    >
                      ←
                    </button>

                    <!-- Page numbers -->
                    <%= for p <- pagination_range(@page, @total_pages) do %>
                      <%= if p == :ellipsis do %>
                        <span class="px-2 text-gray-400 dark:text-gray-500">...</span>
                      <% else %>
                        <button
                          phx-click="go_to_page"
                          phx-value-page={p}
                          class={"px-3 py-1.5 rounded text-sm #{if p == @page, do: "bg-blue-600 text-white", else: "text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700"}"}
                        >
                          {p}
                        </button>
                      <% end %>
                    <% end %>

                    <!-- Next button -->
                    <button
                      phx-click="go_to_page"
                      phx-value-page={@page + 1}
                      disabled={@page == @total_pages}
                      class={"px-3 py-1.5 rounded text-sm #{if @page == @total_pages, do: "text-gray-400 dark:text-gray-600 cursor-not-allowed", else: "text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700"}"}
                    >
                      →
                    </button>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <!-- Movie Detail Modal -->
      <%= if @show_detail_modal && @selected_movie do %>
        <.movie_detail_modal movie={@selected_movie} />
      <% end %>
    </div>
    """
  end

  # Movie Detail Modal Component
  defp movie_detail_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 overflow-y-auto" aria-labelledby="modal-title" role="dialog" aria-modal="true">
      <!-- Background overlay -->
      <div class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity" phx-click="close_modal"></div>

      <!-- Modal panel -->
      <div class="flex min-h-full items-center justify-center p-4">
        <div class="relative transform overflow-hidden rounded-lg bg-white dark:bg-gray-800 shadow-xl transition-all w-full max-w-2xl">
          <!-- Header -->
          <div class="bg-gray-50 dark:bg-gray-700 px-4 py-3 flex items-center justify-between border-b border-gray-200 dark:border-gray-600">
            <h3 class="text-lg font-semibold text-gray-900 dark:text-white" id="modal-title">
              Movie Details
            </h3>
            <button
              phx-click="close_modal"
              class="text-gray-400 hover:text-gray-500 dark:hover:text-gray-300"
            >
              <span class="sr-only">Close</span>
              <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <!-- Content -->
          <div class="px-4 py-4 space-y-4">
            <!-- Status Badge -->
            <div class="flex items-center gap-3">
              <.detail_status_badge status={@movie.status} />
              <%= if @movie.status == :job_error && @movie.error_category do %>
                <span class="text-sm text-orange-600 dark:text-orange-400">
                  {@movie.error_category}
                </span>
              <% end %>
            </div>

            <!-- Movie Info -->
            <div class="grid grid-cols-2 gap-4 text-sm">
              <!-- Title -->
              <div>
                <div class="font-medium text-gray-500 dark:text-gray-400">Title</div>
                <div class="text-gray-900 dark:text-white">{@movie.title}</div>
              </div>

              <!-- Source Title -->
              <%= if @movie.source_title do %>
                <div>
                  <div class="font-medium text-gray-500 dark:text-gray-400">Source Title</div>
                  <div class="text-gray-900 dark:text-white">{@movie.source_title}</div>
                </div>
              <% end %>

              <!-- Polish Title -->
              <%= if @movie.polish_title do %>
                <div>
                  <div class="font-medium text-gray-500 dark:text-gray-400">Polish Title</div>
                  <div class="text-gray-900 dark:text-white">{@movie.polish_title}</div>
                </div>
              <% end %>

              <!-- Original Title -->
              <%= if @movie.original_title do %>
                <div>
                  <div class="font-medium text-gray-500 dark:text-gray-400">Original Title</div>
                  <div class="text-gray-900 dark:text-white">{@movie.original_title}</div>
                </div>
              <% end %>

              <!-- TMDB ID -->
              <%= if @movie.tmdb_id do %>
                <div>
                  <div class="font-medium text-gray-500 dark:text-gray-400">TMDB ID</div>
                  <a
                    href={"https://www.themoviedb.org/movie/#{@movie.tmdb_id}"}
                    target="_blank"
                    class="text-blue-600 dark:text-blue-400 hover:underline"
                  >
                    {@movie.tmdb_id}
                  </a>
                </div>
              <% end %>

              <!-- Provider -->
              <%= if @movie.provider do %>
                <div>
                  <div class="font-medium text-gray-500 dark:text-gray-400">Provider</div>
                  <div class="text-gray-900 dark:text-white uppercase">{@movie.provider}</div>
                </div>
              <% end %>

              <!-- Confidence -->
              <%= if @movie.confidence && @movie.confidence > 0 do %>
                <div>
                  <div class="font-medium text-gray-500 dark:text-gray-400">Confidence</div>
                  <div class="text-gray-900 dark:text-white">{trunc(@movie.confidence * 100)}%</div>
                </div>
              <% end %>

              <!-- Blocked Count -->
              <%= if @movie.blocked_count && @movie.blocked_count > 0 do %>
                <div>
                  <div class="font-medium text-gray-500 dark:text-gray-400">Blocked Showtimes</div>
                  <div class="text-orange-600 dark:text-orange-400">{@movie.blocked_count}</div>
                </div>
              <% end %>

              <!-- Cinema City Film ID -->
              <%= if @movie.cinema_city_film_id do %>
                <div>
                  <div class="font-medium text-gray-500 dark:text-gray-400">Cinema City Film ID</div>
                  <div class="text-gray-900 dark:text-white font-mono text-xs">{@movie.cinema_city_film_id}</div>
                </div>
              <% end %>

              <!-- Job ID (for errors) -->
              <%= if @movie.job_id do %>
                <div>
                  <div class="font-medium text-gray-500 dark:text-gray-400">Oban Job ID</div>
                  <div class="text-gray-900 dark:text-white font-mono">{@movie.job_id}</div>
                </div>
              <% end %>

              <!-- Attempts (for errors) -->
              <%= if @movie.attempts do %>
                <div>
                  <div class="font-medium text-gray-500 dark:text-gray-400">Attempts</div>
                  <div class="text-gray-900 dark:text-white">{@movie.attempts}</div>
                </div>
              <% end %>

              <!-- Timestamp -->
              <div>
                <div class="font-medium text-gray-500 dark:text-gray-400">Timestamp</div>
                <div class="text-gray-900 dark:text-white">{format_datetime(@movie.timestamp)}</div>
              </div>
            </div>

            <!-- Error Message (for job errors) -->
            <%= if @movie.error_message do %>
              <div>
                <div class="font-medium text-gray-500 dark:text-gray-400 mb-1">Error Message</div>
                <div class="bg-red-50 dark:bg-red-500/10 border border-red-200 dark:border-red-500/30 rounded p-3">
                  <pre class="text-xs text-red-600 dark:text-red-400 whitespace-pre-wrap break-words font-mono">{@movie.error_message}</pre>
                </div>
              </div>
            <% end %>
          </div>

          <!-- Footer Actions -->
          <div class="bg-gray-50 dark:bg-gray-700 px-4 py-3 flex justify-between items-center border-t border-gray-200 dark:border-gray-600">
            <div class="flex gap-2">
              <!-- Search links -->
              <a
                href={"https://www.themoviedb.org/search?query=#{URI.encode(@movie.polish_title || @movie.title || "")}"}
                target="_blank"
                class="px-3 py-1.5 bg-blue-100 dark:bg-blue-500/20 text-blue-600 dark:text-blue-400 text-sm rounded hover:bg-blue-200 dark:hover:bg-blue-500/30"
              >
                Search TMDB
              </a>
              <a
                href={"https://www.imdb.com/find?q=#{URI.encode(@movie.original_title || @movie.polish_title || @movie.title || "")}"}
                target="_blank"
                class="px-3 py-1.5 bg-yellow-100 dark:bg-yellow-500/20 text-yellow-600 dark:text-yellow-400 text-sm rounded hover:bg-yellow-200 dark:hover:bg-yellow-500/30"
              >
                Search IMDB
              </a>
            </div>

            <div class="flex gap-2">
              <!-- Retry button for job errors -->
              <%= if @movie.status == :job_error && @movie.job_id do %>
                <button
                  phx-click="retry_job"
                  phx-value-job-id={@movie.job_id}
                  class="px-3 py-1.5 bg-orange-600 text-white text-sm rounded hover:bg-orange-700"
                >
                  Retry Job
                </button>
              <% end %>
              <button
                phx-click="close_modal"
                class="px-3 py-1.5 bg-gray-200 dark:bg-gray-600 text-gray-700 dark:text-gray-300 text-sm rounded hover:bg-gray-300 dark:hover:bg-gray-500"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp detail_status_badge(assigns) do
    {label, classes} =
      case assigns.status do
        :job_error ->
          {"JOB ERROR",
           "bg-orange-100 dark:bg-orange-500/20 text-orange-600 dark:text-orange-400"}

        :unmatched ->
          {"UNMATCHED", "bg-red-100 dark:bg-red-500/20 text-red-600 dark:text-red-400"}

        :low_confidence ->
          {"LOW CONFIDENCE",
           "bg-yellow-100 dark:bg-yellow-500/20 text-yellow-600 dark:text-yellow-400"}

        :matched ->
          {"MATCHED", "bg-green-100 dark:bg-green-500/20 text-green-600 dark:text-green-400"}
      end

    assigns = assign(assigns, :label, label) |> assign(:classes, classes)

    ~H"""
    <span class={"px-3 py-1 rounded-full text-sm font-medium #{@classes}"}>
      {@label}
    </span>
    """
  end

  defp format_datetime(nil), do: "-"

  defp format_datetime(%NaiveDateTime{} = ndt) do
    Calendar.strftime(ndt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  # Unified Movie List Building Functions

  defp build_unified_movie_list(assigns) do
    # Convert unmatched movies
    unmatched =
      Enum.map(assigns.unmatched_movies, fn movie ->
        %{
          status: :unmatched,
          title: movie.polish_title || movie.original_title || "Unknown",
          source_title: movie.original_title,
          tmdb_id: nil,
          provider: nil,
          confidence: 0.0,
          blocked_count: movie.blocked_count || 0,
          timestamp: movie.first_seen,
          poster_url: nil,
          polish_title: movie.polish_title,
          original_title: movie.original_title,
          # Extra fields for detail modal
          job_id: nil,
          error_message: nil,
          error_category: nil,
          attempts: nil,
          cinema_city_film_id: nil,
          movie_id: nil
        }
      end)

    # Convert matched movies
    matched =
      Enum.map(assigns.recent_matches, fn match ->
        status =
          cond do
            match.confidence < 0.70 -> :low_confidence
            true -> :matched
          end

        %{
          status: status,
          title: match.title,
          source_title: match.source_title,
          tmdb_id: match.tmdb_id,
          provider: match.provider,
          confidence: match.confidence || 0.0,
          blocked_count: 0,
          timestamp: match.inserted_at,
          poster_url: match.poster_url,
          polish_title: nil,
          original_title: nil,
          # Extra fields for detail modal
          job_id: nil,
          error_message: nil,
          error_category: nil,
          attempts: nil,
          cinema_city_film_id: nil,
          movie_id: match.id
        }
      end)

    # Convert job errors (failed MovieDetailJob executions)
    job_errors =
      Enum.map(assigns.failures || [], fn failure ->
        %{
          status: :job_error,
          title: failure.polish_title || failure.original_title || "Unknown",
          source_title: failure.original_title,
          tmdb_id: nil,
          provider: nil,
          confidence: 0.0,
          blocked_count: 0,
          timestamp: failure.discarded_at,
          poster_url: nil,
          polish_title: failure.polish_title,
          original_title: failure.original_title,
          # Extra fields for job errors
          job_id: failure.id,
          error_message: failure.error,
          error_category: categorize_error_message(failure.error),
          attempts: failure.attempts,
          cinema_city_film_id: failure.cinema_city_film_id,
          movie_id: nil
        }
      end)

    unmatched ++ matched ++ job_errors
  end

  # Categorize error message for display
  defp categorize_error_message(msg) when is_binary(msg) do
    cond do
      String.contains?(msg, "movie_not_ready") or String.contains?(msg, "snooze") ->
        "Movie Not Ready"

      String.contains?(msg, "duplicate") or String.contains?(msg, "already exists") ->
        "Duplicate"

      String.contains?(msg, "no results") or String.contains?(msg, "not found") or
        String.contains?(msg, "No movie found") or String.contains?(msg, "tmdb_no_results") ->
        "No Results"

      String.contains?(msg, "needs_review") or String.contains?(msg, "tmdb_needs_review") or
        String.contains?(msg, "low_confidence") or String.contains?(msg, "tmdb_low_confidence") ->
        "Low Confidence"

      String.contains?(msg, "timeout") or String.contains?(msg, "HTTPoison") or
          String.contains?(msg, "connection") ->
        "API Timeout"

      String.contains?(msg, "is invalid") or String.contains?(msg, "validation: :cast") or
        String.contains?(msg, "changeset") or String.contains?(msg, "Ecto.Changeset") ->
        "Validation Error"

      true ->
        "Unknown"
    end
  end

  defp categorize_error_message(_), do: "Unknown"

  defp filter_movies(movies, "all"), do: movies
  defp filter_movies(movies, "unmatched"), do: Enum.filter(movies, &(&1.status == :unmatched))

  defp filter_movies(movies, "low_confidence"),
    do: Enum.filter(movies, &(&1.status == :low_confidence))

  defp filter_movies(movies, "matched"), do: Enum.filter(movies, &(&1.status == :matched))
  defp filter_movies(movies, "job_error"), do: Enum.filter(movies, &(&1.status == :job_error))
  defp filter_movies(movies, _), do: movies

  defp sort_movies(movies, sort_by, sort_dir) do
    sorter =
      case sort_by do
        "status" ->
          # Sort order: job_error first, then unmatched, then low_confidence, then matched
          fn m ->
            case m.status do
              :job_error -> 0
              :unmatched -> 1
              :low_confidence -> 2
              :matched -> 3
            end
          end

        "title" ->
          fn m -> String.downcase(m.title || "") end

        "confidence" ->
          fn m -> m.confidence || 0.0 end

        "blocked" ->
          fn m -> m.blocked_count || 0 end

        "time" ->
          fn m -> m.timestamp end

        _ ->
          fn m -> m.status end
      end

    sorted = Enum.sort_by(movies, sorter)

    if sort_dir == "desc" do
      Enum.reverse(sorted)
    else
      sorted
    end
  end

  defp summarize_failures(failure_analysis) do
    total_today = Enum.reduce(failure_analysis, 0, fn a, acc -> acc + a.today end)
    total_week_avg = Enum.reduce(failure_analysis, 0.0, fn a, acc -> acc + a.week_avg end)

    top_category =
      failure_analysis
      |> Enum.filter(fn a -> a.today > 0 end)
      |> Enum.max_by(fn a -> a.today end, fn -> nil end)

    %{
      total_today: total_today,
      total_week_avg: total_week_avg,
      top_category: top_category
    }
  end

  # Calculate total blocked showtimes from unmatched movies
  defp calculate_total_blocked(unified_movies) do
    unified_movies
    |> Enum.filter(&(&1.status == :unmatched))
    |> Enum.reduce(0, fn movie, acc -> acc + (movie.blocked_count || 0) end)
  end

  # Component Functions

  defp summary_card(assigns) do
    color_classes = %{
      "blue" => "border-blue-500 bg-blue-50 dark:bg-blue-500/10",
      "green" => "border-green-500 bg-green-50 dark:bg-green-500/10",
      "red" => "border-red-500 bg-red-50 dark:bg-red-500/10",
      "yellow" => "border-yellow-500 bg-yellow-50 dark:bg-yellow-500/10",
      "purple" => "border-purple-500 bg-purple-50 dark:bg-purple-500/10"
    }

    assigns =
      assign(assigns, :color_class, Map.get(color_classes, assigns.color, color_classes["blue"]))

    ~H"""
    <div class={"rounded-lg p-6 border-l-4 shadow #{@color_class}"}>
      <div class="text-sm text-gray-500 dark:text-gray-400">{@title}</div>
      <div class="text-3xl font-bold text-gray-900 dark:text-white mt-1">{format_number(@value)}</div>
      <div class="text-sm text-gray-500 dark:text-gray-400 mt-1">{@subtitle}</div>
    </div>
    """
  end

  # Unified "Needs Attention" card showing all issue types
  defp needs_attention_card(assigns) do
    na = assigns.needs_attention
    # Determine color based on severity
    border_color =
      cond do
        na.total == 0 -> "border-green-500"
        na.unmatched > 0 -> "border-red-500"
        na.job_errors > 0 -> "border-orange-500"
        na.low_confidence > 0 -> "border-yellow-500"
        true -> "border-gray-500"
      end

    bg_color =
      cond do
        na.total == 0 -> "bg-green-50 dark:bg-green-500/10"
        na.unmatched > 0 -> "bg-red-50 dark:bg-red-500/10"
        na.job_errors > 0 -> "bg-orange-50 dark:bg-orange-500/10"
        na.low_confidence > 0 -> "bg-yellow-50 dark:bg-yellow-500/10"
        true -> "bg-gray-50 dark:bg-gray-500/10"
      end

    assigns =
      assigns
      |> assign(:border_color, border_color)
      |> assign(:bg_color, bg_color)
      |> assign(:na, na)

    ~H"""
    <div class={"rounded-lg p-4 border-l-4 shadow #{@border_color} #{@bg_color}"}>
      <div class="text-sm text-gray-500 dark:text-gray-400">Needs Attention</div>
      <div class="text-3xl font-bold text-gray-900 dark:text-white mt-1">{@na.total}</div>
      <!-- Breakdown -->
      <div class="mt-2 space-y-0.5 text-xs">
        <%= if @na.unmatched > 0 do %>
          <div class="flex items-center gap-1">
            <span class="w-2 h-2 rounded-full bg-red-500"></span>
            <span class="text-gray-600 dark:text-gray-400">{@na.unmatched} unmatched</span>
          </div>
        <% end %>
        <%= if @na.low_confidence > 0 do %>
          <div class="flex items-center gap-1">
            <span class="w-2 h-2 rounded-full bg-yellow-500"></span>
            <span class="text-gray-600 dark:text-gray-400">{@na.low_confidence} low confidence</span>
          </div>
        <% end %>
        <%= if @na.job_errors > 0 do %>
          <div class="flex items-center gap-1">
            <span class="w-2 h-2 rounded-full bg-orange-500"></span>
            <span class="text-gray-600 dark:text-gray-400">{@na.job_errors} job errors</span>
          </div>
        <% end %>
        <%= if @na.total == 0 do %>
          <div class="text-green-600 dark:text-green-400">All clear!</div>
        <% end %>
      </div>
      <!-- Blocked showtimes impact -->
      <%= if @na.blocked_events > 0 do %>
        <div class="mt-2 pt-2 border-t border-gray-200 dark:border-gray-700 text-xs text-orange-600 dark:text-orange-400">
          {format_number(@na.blocked_events)} showtimes blocked
        </div>
      <% end %>
    </div>
    """
  end

  defp provider_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between py-2">
      <div class="flex items-center gap-3">
        <div class="w-3 h-3 rounded-full" style={"background-color: #{@provider.color}"}></div>
        <span class="font-medium text-gray-900 dark:text-white">{@provider.name}</span>
      </div>
      <div class="flex items-center gap-4">
        <div class="text-sm">
          <span class="text-green-600 dark:text-green-400">{@provider.successes}</span>
          <span class="text-gray-400 dark:text-gray-500">/</span>
          <span class="text-red-600 dark:text-red-400">{@provider.failures}</span>
        </div>
        <div class="text-sm font-medium" style={"color: #{success_rate_color(@provider.success_rate)}"}>
          {format_rate(@provider.success_rate)}%
        </div>
      </div>
    </div>
    """
  end

  # Compact confidence chart (horizontal bars inline)
  defp confidence_chart_compact(assigns) do
    buckets = ["≥95%", "85-94%", "70-84%", "50-69%", "<50%"]
    total = assigns.distribution |> Map.values() |> Enum.sum()
    assigns = assign(assigns, :buckets, buckets) |> assign(:total, max(total, 1))

    ~H"""
    <div class="space-y-1">
      <%= for bucket <- @buckets do %>
        <% count = Map.get(@distribution, bucket, 0) %>
        <% pct = count / @total * 100 %>
        <div class="flex items-center gap-2 text-xs">
          <div class="w-12 text-gray-500 dark:text-gray-400">{bucket}</div>
          <div class="flex-1 bg-gray-200 dark:bg-gray-700 rounded h-2 overflow-hidden">
            <div
              class={"h-full rounded #{confidence_bar_color(bucket)}"}
              style={"width: #{pct}%"}
            />
          </div>
          <div class="w-6 text-right text-gray-500 dark:text-gray-400">{count}</div>
        </div>
      <% end %>
    </div>
    """
  end

  # Sort indicator for table headers
  defp sort_indicator(assigns) do
    ~H"""
    <span class="text-gray-400">
      <%= if @sort_by == @column do %>
        <%= if @sort_dir == "asc" do %>
          ↑
        <% else %>
          ↓
        <% end %>
      <% else %>
        ↕
      <% end %>
    </span>
    """
  end

  # Unified movie table row
  defp unified_movie_row(assigns) do
    status_badge =
      case assigns.movie.status do
        :job_error ->
          {"🟠", "JOB ERROR",
           "bg-orange-100 dark:bg-orange-500/20 text-orange-600 dark:text-orange-400"}

        :unmatched ->
          {"🔴", "UNMATCHED", "bg-red-100 dark:bg-red-500/20 text-red-600 dark:text-red-400"}

        :low_confidence ->
          {"🟡", "LOW CONF",
           "bg-yellow-100 dark:bg-yellow-500/20 text-yellow-600 dark:text-yellow-400"}

        :matched ->
          {"🟢", "MATCHED", "bg-green-100 dark:bg-green-500/20 text-green-600 dark:text-green-400"}
      end

    assigns = assign(assigns, :status_badge, status_badge)

    ~H"""
    <tr
      class="border-t border-gray-200 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-700/30 cursor-pointer"
      phx-click="show_detail"
      phx-value-index={@index}
    >
      <!-- Status -->
      <td class="py-3 px-4">
        <% {_emoji, label, classes} = @status_badge %>
        <span class={"px-2 py-0.5 rounded text-xs font-medium #{classes}"}>
          {label}
        </span>
      </td>

      <!-- Movie Title -->
      <td class="py-3 px-4">
        <div class="flex items-center gap-2">
          <%= if @movie.poster_url do %>
            <img src={@movie.poster_url} class="w-6 h-9 rounded object-cover" alt="" />
          <% else %>
            <div class="w-6 h-9 rounded bg-gray-200 dark:bg-gray-700 flex items-center justify-center">
              <span class="text-gray-400 text-xs">?</span>
            </div>
          <% end %>
          <span class="font-medium text-gray-900 dark:text-white truncate max-w-48" title={@movie.title}>
            {@movie.title}
          </span>
        </div>
      </td>

      <!-- Source Title -->
      <td class="py-3 px-4 text-gray-500 dark:text-gray-400 text-sm truncate max-w-32">
        {@movie.source_title || "-"}
      </td>

      <!-- TMDB ID -->
      <td class="py-3 px-4">
        <%= if @movie.tmdb_id do %>
          <a
            href={"https://www.themoviedb.org/movie/#{@movie.tmdb_id}"}
            target="_blank"
            class="text-blue-400 hover:underline text-sm"
          >
            {@movie.tmdb_id}
          </a>
        <% else %>
          <span class="text-gray-400">-</span>
        <% end %>
      </td>

      <!-- Confidence -->
      <td class="py-3 px-4">
        <%= if @movie.status != :unmatched do %>
          <.confidence_badge confidence={@movie.confidence} />
        <% else %>
          <span class="text-gray-400">-</span>
        <% end %>
      </td>

      <!-- Impact (blocked showtimes or error category) -->
      <td class="py-3 px-4">
        <%= if @movie.status == :job_error do %>
          <span class="text-orange-600 dark:text-orange-400 text-sm" title={@movie.error_message}>
            {@movie.error_category}
          </span>
        <% else %>
          <%= if @movie.blocked_count > 0 do %>
            <span class="text-orange-600 dark:text-orange-400 font-medium">
              {@movie.blocked_count} blocked
            </span>
          <% else %>
            <span class="text-gray-400">-</span>
          <% end %>
        <% end %>
      </td>

      <!-- Time -->
      <td class="py-3 px-4 text-gray-500 dark:text-gray-400 text-sm">
        {format_relative_time(@movie.timestamp)}
      </td>

      <!-- Actions -->
      <td class="py-3 px-4">
        <div class="flex gap-1">
          <%= if @movie.status == :job_error do %>
            <button
              phx-click="retry_job"
              phx-value-job-id={@movie.job_id}
              class="px-2 py-0.5 bg-orange-100 dark:bg-orange-500/20 text-orange-600 dark:text-orange-400 text-xs rounded hover:bg-orange-200 dark:hover:bg-orange-500/30"
              title="Retry this job"
            >
              Retry
            </button>
            <a
              href={"https://www.themoviedb.org/search?query=#{URI.encode(@movie.polish_title || @movie.title || "")}"}
              target="_blank"
              class="px-2 py-0.5 bg-blue-100 dark:bg-blue-500/20 text-blue-600 dark:text-blue-400 text-xs rounded hover:bg-blue-200 dark:hover:bg-blue-500/30"
              title="Search TMDB"
            >
              TMDB
            </a>
          <% else %>
            <%= if @movie.status == :unmatched do %>
              <a
                href={"https://www.themoviedb.org/search?query=#{URI.encode(@movie.polish_title || @movie.title || "")}"}
                target="_blank"
                class="px-2 py-0.5 bg-blue-100 dark:bg-blue-500/20 text-blue-600 dark:text-blue-400 text-xs rounded hover:bg-blue-200 dark:hover:bg-blue-500/30"
                title="Search TMDB"
              >
                TMDB
              </a>
              <a
                href={"https://www.imdb.com/find?q=#{URI.encode(@movie.original_title || @movie.polish_title || @movie.title || "")}"}
                target="_blank"
                class="px-2 py-0.5 bg-yellow-100 dark:bg-yellow-500/20 text-yellow-600 dark:text-yellow-400 text-xs rounded hover:bg-yellow-200 dark:hover:bg-yellow-500/30"
                title="Search IMDB"
              >
                IMDB
              </a>
            <% else %>
              <%= if @movie.tmdb_id do %>
                <a
                  href={"https://www.themoviedb.org/movie/#{@movie.tmdb_id}"}
                  target="_blank"
                  class="px-2 py-0.5 bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400 text-xs rounded hover:bg-gray-200 dark:hover:bg-gray-600"
                >
                  View
                </a>
              <% end %>
            <% end %>
          <% end %>
        </div>
      </td>
    </tr>
    """
  end

  defp confidence_badge(assigns) do
    {color, label} =
      cond do
        assigns.confidence >= 0.95 -> {"bg-green-500/20 text-green-400", "Excellent"}
        assigns.confidence >= 0.85 -> {"bg-blue-500/20 text-blue-400", "Good"}
        assigns.confidence >= 0.70 -> {"bg-yellow-500/20 text-yellow-400", "Fair"}
        true -> {"bg-red-500/20 text-red-400", "Low"}
      end

    assigns = assign(assigns, :color, color) |> assign(:label, label)

    ~H"""
    <span class={"px-2 py-0.5 rounded text-xs #{@color}"}>
      {trunc(@confidence * 100)}%
    </span>
    """
  end

  # Helper Functions

  defp format_number(n) when is_integer(n) and n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  defp format_number(n) when is_integer(n) and n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}K"
  end

  defp format_number(n), do: to_string(n)

  defp format_rate(rate) when is_float(rate), do: :erlang.float_to_binary(rate, decimals: 1)
  defp format_rate(rate), do: to_string(rate)

  defp format_time(nil), do: "-"

  defp format_time(dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_relative_time(nil), do: "-"

  defp format_relative_time(%NaiveDateTime{} = ndt) do
    # Convert NaiveDateTime to DateTime (assuming UTC)
    {:ok, dt} = DateTime.from_naive(ndt, "Etc/UTC")
    format_relative_time(dt)
  end

  defp format_relative_time(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  defp success_rate_color(rate) when rate >= 95, do: "#22c55e"
  defp success_rate_color(rate) when rate >= 80, do: "#3b82f6"
  defp success_rate_color(rate) when rate >= 60, do: "#eab308"
  defp success_rate_color(_), do: "#ef4444"

  # 5 buckets per Issue #3083 spec
  defp confidence_bar_color("≥95%"), do: "bg-green-500"
  defp confidence_bar_color("85-94%"), do: "bg-blue-500"
  defp confidence_bar_color("70-84%"), do: "bg-yellow-500"
  defp confidence_bar_color("50-69%"), do: "bg-orange-500"
  defp confidence_bar_color("<50%"), do: "bg-red-500"
  defp confidence_bar_color(_), do: "bg-gray-500"

  # Pagination range helper - returns page numbers with ellipsis for large page counts
  # Following CityIndexLive pattern
  defp pagination_range(_current_page, total_pages) when total_pages <= 7 do
    Enum.to_list(1..total_pages)
  end

  defp pagination_range(current_page, total_pages) do
    # Show: 1 ... (current-1) current (current+1) ... last
    cond do
      current_page <= 4 ->
        # Near the start: 1 2 3 4 5 ... last
        Enum.to_list(1..5) ++ [:ellipsis, total_pages]

      current_page >= total_pages - 3 ->
        # Near the end: 1 ... (last-4) (last-3) (last-2) (last-1) last
        [1, :ellipsis] ++ Enum.to_list((total_pages - 4)..total_pages)

      true ->
        # In the middle: 1 ... (current-1) current (current+1) ... last
        [1, :ellipsis] ++
          Enum.to_list((current_page - 1)..(current_page + 1)) ++ [:ellipsis, total_pages]
    end
  end
end
