defmodule EventasaurusWeb.Admin.MovieMatchingLive do
  @moduledoc """
  Movie Database Dashboard - Provider Analytics & Match Visibility

  Provides observability into the movie matching system:
  - Provider breakdown (TMDB/OMDb/IMDB success rates)
  - Confidence distribution visualization
  - Failure analysis with error categorization
  - Movies needing review queue
  - Real-time activity feed

  Part of Phase 3 of Epic #3077: Cinema City Scraper Reliability
  """

  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Movies.MatchingStats

  @refresh_interval 30_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh, @refresh_interval)
    end

    socket =
      socket
      |> assign(:page_title, "Movie Matching Dashboard")
      |> assign(:time_range, "24h")
      |> assign(:loading, true)
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("change_time_range", %{"range" => range}, socket) do
    socket =
      socket
      |> assign(:time_range, range)
      |> assign(:loading, true)
      |> load_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("confirm_match", %{"id" => id}, socket) do
    case MatchingStats.confirm_movie_match(String.to_integer(id)) do
      {:ok, _movie} ->
        socket =
          socket
          |> put_flash(:info, "Movie match confirmed!")
          |> load_data()

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to confirm movie match")}
    end
  end

  @impl true
  def handle_event("reject_match", %{"id" => id}, socket) do
    case MatchingStats.reject_movie_match(String.to_integer(id)) do
      {:ok, _movie} ->
        socket =
          socket
          |> put_flash(:info, "Movie marked for re-matching")
          |> load_data()

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to reject movie match")}
    end
  end

  # Max concurrency reduced to 2 to avoid exhausting the connection pool
  # (replica pool is only 5 connections, matching MonitoringDashboardLive pattern)
  @max_concurrency 2
  @task_timeout 15_000

  defp load_data(socket) do
    hours = time_range_to_hours(socket.assigns.time_range)

    # Load all data with controlled concurrency to avoid connection pool exhaustion
    data_loaders = [
      {:overview, fn -> MatchingStats.get_overview_stats(hours) end},
      {:providers, fn -> MatchingStats.get_provider_stats(hours) end},
      {:confidence, fn -> MatchingStats.get_confidence_distribution(hours) end},
      {:failures, fn -> MatchingStats.get_recent_failures(20) end},
      {:failure_analysis, fn -> MatchingStats.get_failure_analysis(hours) end},
      {:needs_review, fn -> MatchingStats.get_movies_needing_review(20) end},
      {:recent_matches, fn -> MatchingStats.get_recent_matches(10) end},
      {:hourly, fn -> MatchingStats.get_hourly_counts(min(hours, 48)) end},
      {:total_movies, fn -> MatchingStats.get_total_movie_count() end},
      {:duplicates, fn -> MatchingStats.get_duplicate_film_id_count() end}
    ]

    results =
      data_loaders
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

    socket
    |> assign(:loading, false)
    |> assign(:overview, results[:overview])
    |> assign(:providers, results[:providers])
    |> assign(:confidence_distribution, results[:confidence])
    |> assign(:failures, results[:failures])
    |> assign(:failure_analysis, results[:failure_analysis])
    |> assign(:needs_review, results[:needs_review])
    |> assign(:recent_matches, results[:recent_matches])
    |> assign(:hourly_counts, results[:hourly])
    |> assign(:total_movies, results[:total_movies])
    |> assign(:duplicate_count, results[:duplicates])
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
    ~H"""
    <div class="min-h-screen p-6">
      <div class="max-w-7xl mx-auto">
        <!-- Header -->
        <div class="flex justify-between items-center mb-8">
          <div>
            <h1 class="text-3xl font-bold text-gray-900 dark:text-white">Movie Matching Dashboard</h1>
            <p class="text-gray-500 dark:text-gray-400 mt-1">Provider analytics and match visibility</p>
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
            <div class="text-sm text-gray-500 dark:text-gray-400">
              Updated: {format_time(@last_updated)}
            </div>
          </div>
        </div>

        <%= if @loading do %>
          <div class="flex justify-center items-center h-64">
            <div class="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-blue-500"></div>
          </div>
        <% else %>
          <!-- Summary Cards -->
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
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
            <.summary_card
              title="Failed Matches"
              value={@overview.failed_matches}
              subtitle="Need investigation"
              color="red"
            />
            <.summary_card
              title="Movies in DB"
              value={@total_movies}
              subtitle={"#{@duplicate_count} duplicates"}
              color={if @duplicate_count > 0, do: "yellow", else: "purple"}
            />
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-8">
            <!-- Provider Breakdown -->
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white mb-4">Provider Breakdown</h2>
              <div class="space-y-4">
                <%= for provider <- @providers do %>
                  <.provider_row provider={provider} />
                <% end %>
              </div>
            </div>

            <!-- Confidence Distribution -->
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white mb-4">Confidence Distribution</h2>
              <.confidence_chart distribution={@confidence_distribution} />
            </div>

            <!-- Activity Sparkline -->
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white mb-4">Match Activity</h2>
              <.sparkline_chart counts={@hourly_counts} />
              <div class="mt-4 text-sm text-gray-500 dark:text-gray-400">
                <span class="font-medium text-gray-900 dark:text-white">{sum_counts(@hourly_counts)}</span> matches in period
              </div>
            </div>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
            <!-- Failure Analysis Panel -->
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white mb-4 flex items-center gap-2">
                <span class="text-red-400">●</span>
                Failure Analysis
                <span class="text-sm font-normal text-gray-500 dark:text-gray-400">(7-day trend)</span>
              </h2>

              <!-- Header Row -->
              <div class="grid grid-cols-4 gap-2 text-xs text-gray-500 dark:text-gray-400 mb-2 px-2">
                <div>Category</div>
                <div class="text-right">Today</div>
                <div class="text-right">7d Avg</div>
                <div class="text-right">Trend</div>
              </div>

              <div class="space-y-2">
                <%= if Enum.all?(@failure_analysis, fn a -> a.today == 0 and a.week_avg == 0 end) do %>
                  <div class="text-gray-500 dark:text-gray-400 text-center py-8">
                    No failures to analyze 🎉
                  </div>
                <% else %>
                  <%= for analysis <- @failure_analysis do %>
                    <.failure_analysis_row analysis={analysis} />
                  <% end %>
                <% end %>
              </div>

              <!-- Recent Failures Expandable -->
              <%= if length(@failures) > 0 do %>
                <div class="mt-4 pt-4 border-t border-gray-200 dark:border-gray-700">
                  <details class="group">
                    <summary class="cursor-pointer text-sm text-gray-500 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white flex items-center gap-2">
                      <span class="group-open:rotate-90 transition-transform">▶</span>
                      Recent Failures ({length(@failures)})
                    </summary>
                    <div class="mt-3 space-y-2 max-h-48 overflow-y-auto">
                      <%= for failure <- Enum.take(@failures, 5) do %>
                        <.failure_row failure={failure} />
                      <% end %>
                    </div>
                  </details>
                </div>
              <% end %>
            </div>

            <!-- Movies Needing Review -->
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white mb-4 flex items-center gap-2">
                <span class="text-yellow-400">●</span>
                Needs Review
                <span class="text-sm font-normal text-gray-500 dark:text-gray-400">({length(@needs_review)})</span>
              </h2>
              <div class="space-y-3 max-h-96 overflow-y-auto">
                <%= if Enum.empty?(@needs_review) do %>
                  <div class="text-gray-500 dark:text-gray-400 text-center py-8">
                    All movies look good! ✓
                  </div>
                <% else %>
                  <%= for movie <- @needs_review do %>
                    <.review_row movie={movie} />
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Recent Matches Activity Feed -->
          <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white mb-4 flex items-center gap-2">
              <span class="text-green-400">●</span>
              Recent Matches
            </h2>
            <div class="overflow-x-auto">
              <table class="w-full">
                <thead class="text-left text-gray-500 dark:text-gray-400 text-sm">
                  <tr>
                    <th class="pb-3 pr-4">Movie</th>
                    <th class="pb-3 pr-4">Source Title</th>
                    <th class="pb-3 pr-4">TMDB ID</th>
                    <th class="pb-3 pr-4">Provider</th>
                    <th class="pb-3 pr-4">Confidence</th>
                    <th class="pb-3">Time</th>
                  </tr>
                </thead>
                <tbody class="text-sm">
                  <%= for match <- @recent_matches do %>
                    <tr class="border-t border-gray-200 dark:border-gray-700">
                      <td class="py-3 pr-4">
                        <div class="flex items-center gap-3">
                          <%= if match.poster_url do %>
                            <img src={match.poster_url} class="w-8 h-12 rounded object-cover" alt="" />
                          <% else %>
                            <div class="w-8 h-12 rounded bg-gray-200 dark:bg-gray-700 flex items-center justify-center">
                              <span class="text-gray-500 text-xs">?</span>
                            </div>
                          <% end %>
                          <span class="font-medium text-gray-900 dark:text-white">{match.title}</span>
                        </div>
                      </td>
                      <td class="py-3 pr-4 text-gray-500 dark:text-gray-400">
                        {match.source_title || "-"}
                      </td>
                      <td class="py-3 pr-4">
                        <a
                          href={"https://www.themoviedb.org/movie/#{match.tmdb_id}"}
                          target="_blank"
                          class="text-blue-400 hover:underline"
                        >
                          {match.tmdb_id}
                        </a>
                      </td>
                      <td class="py-3 pr-4">
                        <span class={"px-2 py-0.5 rounded text-xs #{provider_badge_class(match.provider)}"}>
                          {String.upcase(to_string(match.provider))}
                        </span>
                      </td>
                      <td class="py-3 pr-4">
                        <.confidence_badge confidence={match.confidence} />
                      </td>
                      <td class="py-3 text-gray-500 dark:text-gray-400">
                        {format_relative_time(match.inserted_at)}
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
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

  defp confidence_chart(assigns) do
    # 5 buckets per Issue #3083 spec: ≥95%, 85-94%, 70-84%, 50-69%, <50%
    buckets = ["≥95%", "85-94%", "70-84%", "50-69%", "<50%"]
    max_count = assigns.distribution |> Map.values() |> Enum.max(fn -> 1 end)
    assigns = assign(assigns, :buckets, buckets) |> assign(:max_count, max_count)

    ~H"""
    <div class="space-y-2">
      <%= for bucket <- @buckets do %>
        <% count = Map.get(@distribution, bucket, 0) %>
        <% width = if @max_count > 0, do: count / @max_count * 100, else: 0 %>
        <div class="flex items-center gap-2">
          <div class="w-16 text-xs text-gray-500 dark:text-gray-400">{bucket}</div>
          <div class="flex-1 bg-gray-200 dark:bg-gray-700 rounded-full h-4 overflow-hidden">
            <div
              class={"h-full rounded-full #{confidence_bar_color(bucket)}"}
              style={"width: #{width}%"}
            >
            </div>
          </div>
          <div class="w-8 text-xs text-right text-gray-500 dark:text-gray-400">{count}</div>
        </div>
      <% end %>
    </div>
    """
  end

  defp sparkline_chart(assigns) do
    counts = assigns.counts |> Enum.map(& &1.count)
    max_val = Enum.max(counts, fn -> 1 end)
    assigns = assign(assigns, :values, counts) |> assign(:max_val, max_val)

    ~H"""
    <div class="h-16 flex items-end gap-0.5">
      <%= for val <- @values do %>
        <% height = if @max_val > 0, do: val / @max_val * 100, else: 0 %>
        <div
          class="flex-1 bg-blue-500 rounded-t opacity-75 hover:opacity-100 transition-opacity"
          style={"height: #{max(height, 2)}%"}
          title={"#{val} matches"}
        >
        </div>
      <% end %>
    </div>
    """
  end

  defp failure_analysis_row(assigns) do
    ~H"""
    <div class="grid grid-cols-4 gap-2 items-center py-2 px-2 rounded hover:bg-gray-100 dark:hover:bg-gray-700/50 transition-colors">
      <!-- Category with color indicator -->
      <div class="flex items-center gap-2">
        <div class="w-2 h-2 rounded-full" style={"background-color: #{@analysis.color}"}></div>
        <span class="text-sm text-gray-900 dark:text-white truncate" title={@analysis.label}>{@analysis.label}</span>
      </div>

      <!-- Today count -->
      <div class="text-right text-sm font-medium text-gray-900 dark:text-white">
        {@analysis.today}
      </div>

      <!-- 7-day average -->
      <div class="text-right text-sm text-gray-500 dark:text-gray-400">
        {format_avg(@analysis.week_avg)}
      </div>

      <!-- Trend indicator -->
      <div class="text-right">
        <.trend_indicator trend={@analysis.trend} pct={@analysis.trend_pct} />
      </div>
    </div>
    """
  end

  defp trend_indicator(assigns) do
    {arrow, color} =
      case assigns.trend do
        :up -> {"↑", "text-red-500 dark:text-red-400"}
        :down -> {"↓", "text-green-500 dark:text-green-400"}
        :stable -> {"→", "text-gray-500 dark:text-gray-400"}
      end

    assigns = assign(assigns, :arrow, arrow) |> assign(:color, color)

    ~H"""
    <span class={"text-sm font-medium #{@color}"} title={"#{@pct}% vs 7d avg"}>
      {@arrow}
      <span class="text-xs ml-0.5">
        <%= if @pct > 0 do %>
          {trunc(@pct)}%
        <% end %>
      </span>
    </span>
    """
  end

  defp format_avg(avg) when avg == 0.0, do: "0"
  defp format_avg(avg), do: :erlang.float_to_binary(avg, decimals: 1)

  defp failure_row(assigns) do
    ~H"""
    <div class="bg-gray-100 dark:bg-gray-700/50 rounded-lg p-3">
      <div class="flex justify-between items-start">
        <div>
          <div class="font-medium text-gray-900 dark:text-white">{@failure.polish_title}</div>
          <%= if @failure.original_title do %>
            <div class="text-sm text-gray-500 dark:text-gray-400">{@failure.original_title}</div>
          <% end %>
        </div>
        <span class="text-xs text-gray-500">{format_relative_time(@failure.discarded_at)}</span>
      </div>
      <div class="mt-2 text-sm text-red-600 dark:text-red-400 font-mono truncate">
        {truncate_error(@failure.error)}
      </div>
      <div class="mt-1 text-xs text-gray-500">
        Film ID: {@failure.cinema_city_film_id} · Attempts: {@failure.attempts}
      </div>
    </div>
    """
  end

  defp review_row(assigns) do
    ~H"""
    <div class="bg-gray-100 dark:bg-gray-700/50 rounded-lg p-3">
      <div class="flex justify-between items-start">
        <div class="flex items-center gap-3">
          <%= if @movie.poster_url do %>
            <img src={@movie.poster_url} class="w-10 h-14 rounded object-cover" alt="" />
          <% else %>
            <div class="w-10 h-14 rounded bg-gray-200 dark:bg-gray-600 flex items-center justify-center">
              <span class="text-gray-500 dark:text-gray-400 text-xs">?</span>
            </div>
          <% end %>
          <div>
            <div class="font-medium text-gray-900 dark:text-white">{@movie.title}</div>
            <a
              href={"https://www.themoviedb.org/movie/#{@movie.tmdb_id}"}
              target="_blank"
              class="text-sm text-blue-600 dark:text-blue-400 hover:underline"
            >
              TMDB #{@movie.tmdb_id}
            </a>
          </div>
        </div>
      </div>
      <div class="mt-2 flex flex-wrap gap-2">
        <%= for issue <- @movie.issues do %>
          <span class="px-2 py-0.5 bg-yellow-100 dark:bg-yellow-500/20 text-yellow-700 dark:text-yellow-400 rounded text-xs">
            {issue}
          </span>
        <% end %>
      </div>
      <div class="mt-3 flex items-center gap-2 border-t border-gray-200 dark:border-gray-600 pt-3">
        <button
          phx-click="confirm_match"
          phx-value-id={@movie.id}
          class="px-3 py-1 bg-green-600 hover:bg-green-500 text-white text-sm rounded transition-colors"
        >
          ✓ Confirm
        </button>
        <button
          phx-click="reject_match"
          phx-value-id={@movie.id}
          class="px-3 py-1 bg-red-600 hover:bg-red-500 text-white text-sm rounded transition-colors"
        >
          ✗ Reject
        </button>
        <a
          href={"https://www.themoviedb.org/search?query=#{URI.encode(@movie.title || "")}"}
          target="_blank"
          class="px-3 py-1 bg-gray-200 dark:bg-gray-600 hover:bg-gray-300 dark:hover:bg-gray-500 text-gray-700 dark:text-white text-sm rounded transition-colors"
        >
          Search TMDB
        </a>
      </div>
    </div>
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

  defp sum_counts(counts) do
    counts |> Enum.map(& &1.count) |> Enum.sum()
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

  defp provider_badge_class("tmdb"), do: "bg-blue-100 dark:bg-blue-500/20 text-blue-600 dark:text-blue-400"
  defp provider_badge_class("omdb"), do: "bg-yellow-100 dark:bg-yellow-500/20 text-yellow-600 dark:text-yellow-400"
  defp provider_badge_class("imdb"), do: "bg-amber-100 dark:bg-amber-500/20 text-amber-600 dark:text-amber-400"
  defp provider_badge_class(_), do: "bg-gray-100 dark:bg-gray-500/20 text-gray-600 dark:text-gray-400"

  defp truncate_error(nil), do: "Unknown error"

  defp truncate_error(error) when is_binary(error) do
    if String.length(error) > 80 do
      String.slice(error, 0, 77) <> "..."
    else
      error
    end
  end

  defp truncate_error(error), do: inspect(error) |> truncate_error()
end
