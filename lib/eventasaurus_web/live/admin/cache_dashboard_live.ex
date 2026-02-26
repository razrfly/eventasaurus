defmodule EventasaurusWeb.Admin.CacheDashboardLive do
  @moduledoc """
  Admin dashboard for cache management.

  Provides emergency controls for cache operations:
  - Clear Cache for City
  - Clear All Caches
  - Cache Health Report (cache vs direct query comparison)

  This provides an emergency escape hatch for ops when automated systems fail.
  """
  use EventasaurusWeb, :live_view

  require Logger

  alias EventasaurusDiscovery.Admin.DiscoveryConfigManager
  alias EventasaurusWeb.Cache.CityEventsMv
  alias EventasaurusWeb.Cache.CityPageCache
  alias EventasaurusWeb.Cache.LiveQueryCircuitBreaker
  alias EventasaurusApp.Repo

  @type socket :: Phoenix.LiveView.Socket.t()

  @spec mount(map(), map(), socket()) :: {:ok, socket()}
  @impl true
  def mount(_params, _session, socket) do
    cities = DiscoveryConfigManager.list_discovery_enabled_cities()

    cb_state = LiveQueryCircuitBreaker.state()

    socket =
      socket
      |> assign(:page_title, "Cache Management")
      |> assign(:cities, cities)
      |> assign(:selected_city_slug, nil)
      |> assign(:flash_message, nil)
      |> assign(:health_report, nil)
      |> assign(:health_loading, false)
      |> assign(:circuit_breaker, cb_state)
      |> assign(:mv_status, nil)
      |> assign(:mv_refreshing, false)

    {:ok, socket}
  end

  @spec handle_event(String.t(), map() | nil, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  @impl true
  def handle_event("select_city", %{"city_slug" => city_slug}, socket) do
    slug = if city_slug == "", do: nil, else: city_slug
    {:noreply, assign(socket, :selected_city_slug, slug)}
  end

  @impl true
  def handle_event("clear_city_cache", _params, socket) do
    case socket.assigns.selected_city_slug do
      nil ->
        {:noreply, assign(socket, :flash_message, {:error, "Please select a city first"})}

      city_slug ->
        # Clear all caches for this city
        CityPageCache.invalidate_base_events(city_slug)
        CityPageCache.invalidate_aggregated_events(city_slug)
        CityPageCache.invalidate_date_counts(city_slug)
        CityPageCache.invalidate_city_stats(city_slug)
        CityPageCache.invalidate_languages(city_slug)

        Logger.info("[CacheDashboard] Cleared all caches for city=#{city_slug}")

        socket =
          socket
          |> assign(:flash_message, {:info, "Cleared all caches for #{city_slug}"})

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_all_caches", _params, socket) do
    CityPageCache.clear_all()
    CityPageCache.invalidate_categories()

    Logger.warning("[CacheDashboard] CLEARED ALL CACHES (nuclear option)")

    socket =
      socket
      |> assign(
        :flash_message,
        {:warning, "All caches cleared! Pages will reload from database."}
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("load_health_report", _params, socket) do
    socket = assign(socket, :health_loading, true)

    # Load health report for first 10 discovery-enabled cities
    cities = Enum.take(socket.assigns.cities, 10)

    report =
      Enum.map(cities, fn city ->
        cache_count = get_cache_count(city.slug)
        direct_count = get_direct_count(city.slug)

        %{
          city_slug: city.slug,
          city_name: city.name,
          cache_count: cache_count,
          mv_count: get_mv_count(city.slug),
          direct_count: direct_count,
          status: determine_health_status(cache_count, direct_count)
        }
      end)

    socket =
      socket
      |> assign(:health_loading, false)
      |> assign(:health_report, report)

    {:noreply, socket}
  end

  @impl true
  def handle_event("cb_force_open", _params, socket) do
    LiveQueryCircuitBreaker.force_open()
    Logger.warning("[CacheDashboard] Circuit breaker FORCE OPENED by admin")

    socket =
      socket
      |> assign(:circuit_breaker, LiveQueryCircuitBreaker.state())
      |> assign(
        :flash_message,
        {:warning, "Circuit breaker forced OPEN — live queries are disabled"}
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("cb_force_close", _params, socket) do
    LiveQueryCircuitBreaker.force_close()
    Logger.info("[CacheDashboard] Circuit breaker FORCE CLOSED by admin")

    socket =
      socket
      |> assign(:circuit_breaker, LiveQueryCircuitBreaker.state())
      |> assign(:flash_message, {:info, "Circuit breaker forced CLOSED — live queries resumed"})

    {:noreply, socket}
  end

  @impl true
  def handle_event("cb_refresh", _params, socket) do
    {:noreply, assign(socket, :circuit_breaker, LiveQueryCircuitBreaker.state())}
  end

  @impl true
  def handle_event("dismiss_flash", _params, socket) do
    {:noreply, assign(socket, :flash_message, nil)}
  end

  @impl true
  def handle_event("load_mv_status", _params, socket) do
    row_count =
      case CityEventsMv.row_count() do
        {:ok, n} -> n
        _ -> nil
      end

    socket =
      assign(socket, :mv_status, %{
        row_count: row_count,
        last_refresh: CityEventsMv.last_refresh_info(),
        next_refresh: next_scheduled_refresh()
      })

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh_mv_now", _params, socket) do
    pid = self()

    Task.Supervisor.start_child(Eventasaurus.TaskSupervisor, fn ->
      result = CityEventsMv.refresh()
      send(pid, {:mv_refresh_result, result})
    end)

    {:noreply, assign(socket, :mv_refreshing, true)}
  end

  @impl true
  def handle_info({:mv_refresh_result, {:ok, row_count}}, socket) do
    socket =
      assign(socket,
        mv_refreshing: false,
        mv_status: %{
          row_count: row_count,
          last_refresh: CityEventsMv.last_refresh_info(),
          next_refresh: next_scheduled_refresh()
        }
      )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:mv_refresh_result, {:error, reason}}, socket) do
    socket =
      assign(socket,
        mv_refreshing: false,
        flash_message: {:error, "MV refresh failed: #{inspect(reason)}"}
      )

    {:noreply, socket}
  end

  # Get count from Cachex cache for a city (read-only peek, no refresh triggers)
  defp get_cache_count(city_slug) do
    # Use peek_base_events to avoid triggering refresh jobs on miss/stale
    case CityPageCache.peek_base_events(city_slug, 50) do
      {:ok, %{events: events}} when is_list(events) -> length(events)
      {:ok, _} -> nil
      {:miss, nil} -> nil
    end
  end

  # Get count from materialized view for a city (read-only, uses replica)
  defp get_mv_count(city_slug) do
    query = """
    SELECT COUNT(*) FROM city_events_mv WHERE city_slug = $1
    """

    case Repo.replica().query(query, [city_slug], timeout: :timer.seconds(10)) do
      {:ok, %{rows: [[count]]}} -> count
      _ -> nil
    end
  end

  # Get count from direct database query for a city (bypasses MV, read-only, uses replica)
  defp get_direct_count(city_slug) do
    query = """
    SELECT COUNT(DISTINCT pe.id)
    FROM public_events pe
    JOIN venues v ON v.id = pe.venue_id
    JOIN cities c ON c.id = v.city_id
    WHERE c.slug = $1
      AND pe.starts_at >= NOW()
    """

    case Repo.replica().query(query, [city_slug], timeout: :timer.seconds(10)) do
      {:ok, %{rows: [[count]]}} -> count
      _ -> nil
    end
  end

  # Determine health status based on precomputed counts
  defp determine_health_status(cache_count, direct_count) do
    cond do
      is_nil(cache_count) and is_nil(direct_count) -> :critical
      is_nil(direct_count) -> :direct_failed
      is_nil(cache_count) -> :warning
      cache_count == 0 and direct_count == 0 -> :empty
      cache_count == 0 and direct_count > 0 -> :cache_miss
      abs(cache_count - direct_count) > 10 -> :mismatch
      true -> :healthy
    end
  end

  defp status_badge(:healthy), do: {"bg-green-100 text-green-800", "Healthy"}
  defp status_badge(:warning), do: {"bg-yellow-100 text-yellow-800", "Warning"}
  defp status_badge(:direct_failed), do: {"bg-red-100 text-red-800", "Direct Failed"}
  defp status_badge(:critical), do: {"bg-red-100 text-red-800", "Critical"}
  defp status_badge(:empty), do: {"bg-gray-100 text-gray-800", "Empty"}
  defp status_badge(:cache_miss), do: {"bg-orange-100 text-orange-800", "Cache Miss"}
  defp status_badge(:mismatch), do: {"bg-purple-100 text-purple-800", "Mismatch"}
  defp status_badge(_), do: {"bg-gray-100 text-gray-800", "Unknown"}

  defp format_count(nil), do: "—"
  defp format_count(count), do: Integer.to_string(count)

  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Header -->
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900">Cache Management</h1>
        <p class="text-gray-600 mt-1">
          Emergency controls for cache management
        </p>
      </div>

      <!-- Flash Messages -->
      <%= if @flash_message do %>
        <% {type, message} = @flash_message %>
        <div class={"mb-6 p-4 rounded-lg flex justify-between items-center #{flash_classes(type)}"}>
          <span><%= message %></span>
          <button phx-click="dismiss_flash" class="text-sm underline">Dismiss</button>
        </div>
      <% end %>

      <!-- Clear Cache for City -->
      <div class="bg-white shadow rounded-lg p-6 mb-6">
        <h2 class="text-xl font-semibold text-gray-900 mb-4">Clear Cache for City</h2>
        <p class="text-sm text-gray-600 mb-4">
          Invalidates all Cachex entries for a specific city. Use when a city has stale data.
        </p>

        <div class="flex items-center gap-4">
          <select
            phx-change="select_city"
            name="city_slug"
            class="rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 flex-1"
          >
            <option value="">Select a city...</option>
            <%= for city <- @cities do %>
              <option value={city.slug} selected={@selected_city_slug == city.slug}>
                <%= city.name %> (<%= city.slug %>)
              </option>
            <% end %>
          </select>

          <button
            phx-click="clear_city_cache"
            disabled={is_nil(@selected_city_slug)}
            class={"px-4 py-2 rounded-md text-white font-medium #{if is_nil(@selected_city_slug), do: "bg-gray-400 cursor-not-allowed", else: "bg-orange-600 hover:bg-orange-700"}"}
          >
            Clear City Cache
          </button>
        </div>
      </div>

      <!-- Clear All Caches (Nuclear Option) -->
      <div class="bg-white shadow rounded-lg p-6 mb-6 border-l-4 border-red-500">
        <h2 class="text-xl font-semibold text-gray-900 mb-2">Clear All Caches</h2>
        <p class="text-sm text-red-600 mb-4">
          <strong>Nuclear option!</strong> Clears ALL Cachex entries. All city pages will need to reload from database.
          Use only in emergencies.
        </p>

        <button
          phx-click="clear_all_caches"
          data-confirm="Are you sure? This will clear ALL caches and may temporarily slow down the site."
          class="px-4 py-2 rounded-md text-white font-medium bg-red-600 hover:bg-red-700"
        >
          Clear All Caches
        </button>
      </div>

      <!-- Circuit Breaker Status (Issue #3686 Phase 4) -->
      <div class="bg-white shadow rounded-lg p-6 mb-6">
        <div class="flex items-center justify-between mb-4">
          <div>
            <h2 class="text-xl font-semibold text-gray-900">Live Query Circuit Breaker</h2>
            <p class="text-sm text-gray-600">
              Protects against database slowness by skipping live queries when failures accumulate.
            </p>
          </div>
          <button
            phx-click="cb_refresh"
            class="px-3 py-1 text-sm text-gray-600 bg-gray-100 rounded-md hover:bg-gray-200"
          >
            Refresh
          </button>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-4">
          <!-- State -->
          <div class="bg-gray-50 rounded-lg p-4">
            <p class="text-xs text-gray-500 uppercase mb-1">State</p>
            <span class={"inline-flex px-3 py-1 text-sm font-bold rounded-full " <> cb_admin_badge(@circuit_breaker[:state])}>
              <%= cb_admin_label(@circuit_breaker[:state]) %>
            </span>
          </div>

          <!-- Failure Count -->
          <div class="bg-gray-50 rounded-lg p-4">
            <p class="text-xs text-gray-500 uppercase mb-1">Failures</p>
            <p class="text-2xl font-bold text-gray-900">
              <%= @circuit_breaker[:failure_count] || 0 %><span class="text-sm text-gray-500">/<%= @circuit_breaker[:failure_threshold] || 3 %></span>
            </p>
          </div>

          <!-- Cooldown -->
          <div class="bg-gray-50 rounded-lg p-4">
            <p class="text-xs text-gray-500 uppercase mb-1">Cooldown</p>
            <p class="text-lg font-medium text-gray-900">
              <%= div(@circuit_breaker[:cooldown_ms] || 30_000, 1000) %>s
            </p>
          </div>

          <!-- Last Failure -->
          <div class="bg-gray-50 rounded-lg p-4">
            <p class="text-xs text-gray-500 uppercase mb-1">Last Failure</p>
            <p class="text-sm text-gray-700 truncate" title={@circuit_breaker[:last_failure_reason]}>
              <%= @circuit_breaker[:last_failure_reason] || "—" %>
            </p>
          </div>
        </div>

        <div class="flex items-center gap-3">
          <%= if @circuit_breaker[:state] != :open do %>
            <button
              phx-click="cb_force_open"
              data-confirm="Force the circuit breaker OPEN? All live queries will be skipped until manually closed."
              class="px-4 py-2 rounded-md text-white font-medium bg-red-600 hover:bg-red-700"
            >
              Force Open
            </button>
          <% end %>
          <%= if @circuit_breaker[:state] != :closed do %>
            <button
              phx-click="cb_force_close"
              class="px-4 py-2 rounded-md text-white font-medium bg-green-600 hover:bg-green-700"
            >
              Force Close
            </button>
          <% end %>
        </div>
      </div>

      <!-- Materialized View Panel -->
      <div class="bg-white shadow rounded-lg p-6 mb-6">
        <div class="flex items-center justify-between mb-4">
          <div>
            <h2 class="text-xl font-semibold text-gray-900">Materialized View</h2>
            <p class="text-sm text-gray-600">
              Refreshed hourly at :15 (Tier 3 fallback). Serves when Cachex misses.
            </p>
          </div>
          <button
            phx-click="load_mv_status"
            class="px-3 py-1 text-sm text-gray-600 bg-gray-100 rounded-md hover:bg-gray-200"
          >
            Load Status
          </button>
        </div>

        <%= if @mv_status do %>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
            <div class="bg-gray-50 rounded-lg p-4">
              <p class="text-xs text-gray-500 uppercase mb-1">Row Count</p>
              <p class="text-2xl font-bold text-gray-900">
                <%= if @mv_status.row_count, do: format_count(@mv_status.row_count), else: "—" %>
              </p>
            </div>
            <div class="bg-gray-50 rounded-lg p-4">
              <p class="text-xs text-gray-500 uppercase mb-1">Next Scheduled</p>
              <p class="text-sm font-medium text-gray-900">
                <%= Calendar.strftime(@mv_status.next_refresh, "%H:%M:%S UTC") %>
              </p>
            </div>
          </div>

          <%= if @mv_status.last_refresh do %>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
              <div class="bg-gray-50 rounded-lg p-4">
                <p class="text-xs text-gray-500 uppercase mb-1">Last Refresh</p>
                <p class="text-sm text-gray-900">
                  <%= format_relative_time(@mv_status.last_refresh.at) %>
                  (<%= Calendar.strftime(DateTime.truncate(@mv_status.last_refresh.at, :second), "%H:%M:%S UTC") %>)
                </p>
              </div>
              <div class="bg-gray-50 rounded-lg p-4">
                <p class="text-xs text-gray-500 uppercase mb-1">Refresh Duration</p>
                <p class="text-sm font-medium text-gray-900">
                  <%= format_duration_ms(@mv_status.last_refresh.duration_ms) %>
                </p>
              </div>
            </div>
          <% else %>
            <p class="text-sm text-gray-500 mb-4">No refresh data available (server may have just started).</p>
          <% end %>

          <button
            phx-click="refresh_mv_now"
            disabled={@mv_refreshing}
            class={"px-4 py-2 rounded-md text-white font-medium #{if @mv_refreshing, do: "bg-gray-400 cursor-not-allowed", else: "bg-blue-600 hover:bg-blue-700"}"}
          >
            <%= if @mv_refreshing do %>
              Refreshing...
            <% else %>
              Refresh Now
            <% end %>
          </button>
        <% else %>
          <div class="text-center py-4 text-gray-500">
            Click "Load Status" to view materialized view info.
          </div>
        <% end %>
      </div>

      <!-- Cache Health Report -->
      <div class="bg-white shadow rounded-lg p-6">
        <div class="flex items-center justify-between mb-4">
          <div>
            <h2 class="text-xl font-semibold text-gray-900">Cache Health Report</h2>
            <p class="text-sm text-gray-600">
              Compares event counts across: Cachex cache, MV (read-only diagnostic), Direct Query
            </p>
          </div>
          <button
            phx-click="load_health_report"
            disabled={@health_loading}
            class={"px-4 py-2 rounded-md text-white font-medium #{if @health_loading, do: "bg-gray-400 cursor-not-allowed", else: "bg-green-600 hover:bg-green-700"}"}
          >
            <%= if @health_loading do %>
              Loading...
            <% else %>
              Load Health Report
            <% end %>
          </button>
        </div>

        <%= if @health_report do %>
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">City</th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">Cache</th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">MV</th>
                  <th class="px-4 py-3 text-right text-xs font-medium text-gray-500 uppercase">Direct</th>
                  <th class="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">Status</th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= for row <- @health_report do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-4 py-3 whitespace-nowrap">
                      <div class="font-medium text-gray-900"><%= row.city_name %></div>
                      <div class="text-sm text-gray-500"><%= row.city_slug %></div>
                    </td>
                    <td class="px-4 py-3 text-right text-sm text-gray-900">
                      <%= format_count(row.cache_count) %>
                    </td>
                    <td class="px-4 py-3 text-right text-sm text-gray-900">
                      <%= format_count(row.mv_count) %>
                    </td>
                    <td class="px-4 py-3 text-right text-sm text-gray-900">
                      <%= format_count(row.direct_count) %>
                    </td>
                    <td class="px-4 py-3 text-center">
                      <% {badge_class, badge_text} = status_badge(row.status) %>
                      <span class={"inline-flex px-2 py-1 text-xs font-medium rounded-full #{badge_class}"}>
                        <%= badge_text %>
                      </span>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <div class="mt-4 text-sm text-gray-600 space-y-1">
            <strong>Legend:</strong>
            <div class="flex flex-wrap gap-x-4 gap-y-1 mt-1">
              <span><span class="px-2 py-0.5 bg-green-100 text-green-800 rounded">Healthy</span> = Cache and direct query counts match</span>
              <span><span class="px-2 py-0.5 bg-yellow-100 text-yellow-800 rounded">Warning</span> = Cache empty, direct query unavailable</span>
              <span><span class="px-2 py-0.5 bg-orange-100 text-orange-800 rounded">Cache Miss</span> = Cache empty but direct query has data</span>
              <span><span class="px-2 py-0.5 bg-purple-100 text-purple-800 rounded">Mismatch</span> = Cache and direct query counts differ by &gt;10</span>
              <span><span class="px-2 py-0.5 bg-red-100 text-red-800 rounded">Direct Failed</span> = Direct query failed (cache still available)</span>
              <span><span class="px-2 py-0.5 bg-red-100 text-red-800 rounded">Critical</span> = Both cache and direct query unavailable</span>
              <span><span class="px-2 py-0.5 bg-gray-100 text-gray-800 rounded">Empty</span> = No events in cache or direct query</span>
            </div>
            <p class="text-xs text-gray-500 mt-1">MV column is diagnostic only and does not affect status.</p>
          </div>
        <% else %>
          <div class="text-center py-8 text-gray-500">
            Click "Load Health Report" to compare cache vs MV vs direct query counts.
          </div>
        <% end %>
      </div>

      <!-- Documentation -->
      <div class="mt-6 bg-blue-50 border border-blue-200 rounded-lg p-4">
        <h3 class="text-sm font-medium text-blue-800 mb-2">How Caching Works</h3>
        <ul class="text-sm text-blue-700 space-y-1">
          <li><strong>Cachex</strong>: In-memory cache for city page events, warmed on startup and refreshed by scraper completions</li>
          <li><strong>Live Query</strong>: On cache miss, runs full aggregation query directly against the database</li>
          <li><strong>This Page</strong>: Manual controls for ops intervention (clear city/all caches)</li>
        </ul>
      </div>
    </div>
    """
  end

  defp flash_classes(:info), do: "bg-blue-50 text-blue-800 border border-blue-200"
  defp flash_classes(:warning), do: "bg-yellow-50 text-yellow-800 border border-yellow-200"
  defp flash_classes(:error), do: "bg-red-50 text-red-800 border border-red-200"
  defp flash_classes(_), do: "bg-gray-50 text-gray-800 border border-gray-200"

  # Circuit breaker admin helpers
  defp cb_admin_badge(:closed), do: "bg-green-100 text-green-800"
  defp cb_admin_badge(:open), do: "bg-red-100 text-red-800"
  defp cb_admin_badge(:half_open), do: "bg-yellow-100 text-yellow-800"
  defp cb_admin_badge(_), do: "bg-gray-100 text-gray-800"

  defp cb_admin_label(:closed), do: "CLOSED"
  defp cb_admin_label(:open), do: "OPEN"
  defp cb_admin_label(:half_open), do: "HALF_OPEN"
  defp cb_admin_label(_), do: "UNKNOWN"

  # Compute the next :15 minute mark after UTC now
  defp next_scheduled_refresh do
    epoch_seconds = DateTime.to_unix(DateTime.utc_now())
    current_hour_start = epoch_seconds - rem(epoch_seconds, 3600)
    next_15 = current_hour_start + 15 * 60
    next_15 = if epoch_seconds >= next_15, do: next_15 + 3600, else: next_15
    DateTime.from_unix!(next_15)
  end

  defp format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "#{diff} seconds ago"
      diff < 3600 -> "#{div(diff, 60)} minutes ago"
      true -> "#{div(diff, 3600)} hours ago"
    end
  end

  defp format_duration_ms(ms) when is_integer(ms) do
    if ms < 1000, do: "#{ms}ms", else: "#{Float.round(ms / 1000, 1)}s"
  end

  defp format_duration_ms(_), do: "—"
end
