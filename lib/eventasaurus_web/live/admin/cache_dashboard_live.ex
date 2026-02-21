defmodule EventasaurusWeb.Admin.CacheDashboardLive do
  @moduledoc """
  Admin dashboard for cache and materialized view management.

  Layer 3 of the self-healing cache strategy (Issue #3493):
  - Refresh Materialized View button
  - Clear Cache for City
  - Clear All Caches
  - Cache Health Report (cache vs MV vs direct query comparison)

  This provides an emergency escape hatch for ops when automated systems fail.
  """
  use EventasaurusWeb, :live_view

  require Logger

  alias EventasaurusDiscovery.Admin.DiscoveryConfigManager
  alias EventasaurusWeb.Cache.CityPageCache
  alias EventasaurusWeb.Cache.CityEventsMvInitializer
  alias EventasaurusApp.Repo

  @type socket :: Phoenix.LiveView.Socket.t()

  @spec mount(map(), map(), socket()) :: {:ok, socket()}
  @impl true
  def mount(_params, _session, socket) do
    cities = DiscoveryConfigManager.list_discovery_enabled_cities()

    socket =
      socket
      |> assign(:page_title, "Cache Management")
      |> assign(:cities, cities)
      |> assign(:selected_city_slug, nil)
      |> assign(:mv_status, nil)
      |> assign(:mv_refreshing, false)
      |> assign(:mv_refresh_start_time, nil)
      |> assign(:flash_message, nil)
      |> assign(:health_report, nil)
      |> assign(:health_loading, false)
      |> load_mv_status()

    {:ok, socket}
  end

  @impl true
  def handle_event("refresh_mv", _params, socket) do
    # Run asynchronously so we don't block the LiveView process
    start_time = System.monotonic_time(:millisecond)
    lv_pid = self()

    Task.start(fn ->
      result = CityEventsMvInitializer.refresh_view()
      send(lv_pid, {:mv_refresh_result, result, start_time})
    end)

    socket =
      socket
      |> assign(:mv_refreshing, true)
      |> assign(:mv_refresh_start_time, start_time)

    {:noreply, socket}
  end

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
        %{
          city_slug: city.slug,
          city_name: city.name,
          cache_count: get_cache_count(city.slug),
          mv_count: get_mv_count(city.slug),
          direct_count: get_direct_count(city.slug),
          status: determine_health_status(city.slug)
        }
      end)

    socket =
      socket
      |> assign(:health_loading, false)
      |> assign(:health_report, report)

    {:noreply, socket}
  end

  @impl true
  def handle_event("dismiss_flash", _params, socket) do
    {:noreply, assign(socket, :flash_message, nil)}
  end

  @impl true
  def handle_info({:mv_refresh_result, result, start_time}, socket) do
    duration_ms = System.monotonic_time(:millisecond) - start_time

    socket =
      case result do
        {:ok, row_count} ->
          Logger.info(
            "[CacheDashboard] MV refreshed manually in #{duration_ms}ms - #{row_count} rows"
          )

          socket
          |> assign(:mv_refreshing, false)
          |> assign(:mv_refresh_start_time, nil)
          |> assign(
            :flash_message,
            {:info, "Materialized view refreshed: #{row_count} rows in #{duration_ms}ms"}
          )
          |> load_mv_status()

        {:error, reason} ->
          Logger.error("[CacheDashboard] MV refresh failed: #{inspect(reason)}")

          socket
          |> assign(:mv_refreshing, false)
          |> assign(:mv_refresh_start_time, nil)
          |> assign(:flash_message, {:error, "MV refresh failed: #{inspect(reason)}"})
      end

    {:noreply, socket}
  end

  defp load_mv_status(socket) do
    case CityEventsMvInitializer.get_row_count() do
      {:ok, count} ->
        assign(socket, :mv_status, %{row_count: count, status: :ok})

      {:error, :view_not_found} ->
        assign(socket, :mv_status, %{row_count: 0, status: :missing})

      {:error, reason} ->
        assign(socket, :mv_status, %{row_count: 0, status: :error, error: reason})
    end
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

  # Determine health status based on counts
  defp determine_health_status(city_slug) do
    cache = get_cache_count(city_slug)
    mv = get_mv_count(city_slug)
    direct = get_direct_count(city_slug)

    cond do
      is_nil(cache) and is_nil(mv) -> :critical
      is_nil(cache) -> :warning
      cache == 0 and mv == 0 and direct == 0 -> :empty
      cache == 0 and (mv || 0) > 0 -> :cache_miss
      abs((cache || 0) - (mv || 0)) > 10 -> :mismatch
      true -> :healthy
    end
  end

  defp status_badge(:healthy), do: {"bg-green-100 text-green-800", "Healthy"}
  defp status_badge(:warning), do: {"bg-yellow-100 text-yellow-800", "Warning"}
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
          Layer 3 emergency controls for cache and materialized view management (Issue #3493)
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

      <!-- Materialized View Status -->
      <div class="bg-white shadow rounded-lg p-6 mb-6">
        <div class="flex items-center justify-between mb-4">
          <div>
            <h2 class="text-xl font-semibold text-gray-900">Materialized View Status</h2>
            <p class="text-sm text-gray-600">city_events_mv - Fast fallback data source</p>
          </div>
          <button
            phx-click="refresh_mv"
            disabled={@mv_refreshing}
            class={"px-4 py-2 rounded-md text-white font-medium #{if @mv_refreshing, do: "bg-gray-400 cursor-not-allowed", else: "bg-blue-600 hover:bg-blue-700"}"}
          >
            <%= if @mv_refreshing do %>
              <span class="flex items-center gap-2">
                <svg class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
                </svg>
                Refreshing...
              </span>
            <% else %>
              Refresh Materialized View
            <% end %>
          </button>
        </div>

        <%= if @mv_status do %>
          <div class="grid grid-cols-3 gap-4">
            <div class="bg-gray-50 rounded-lg p-4">
              <div class="text-2xl font-bold text-gray-900"><%= @mv_status.row_count %></div>
              <div class="text-sm text-gray-600">Rows in MV</div>
            </div>
            <div class="bg-gray-50 rounded-lg p-4">
              <div class={"text-lg font-semibold #{mv_status_color(@mv_status.status)}"}>
                <%= mv_status_label(@mv_status.status) %>
              </div>
              <div class="text-sm text-gray-600">Status</div>
            </div>
            <div class="bg-gray-50 rounded-lg p-4">
              <div class="text-sm text-gray-700">
                <code>REFRESH MATERIALIZED VIEW CONCURRENTLY city_events_mv</code>
              </div>
              <div class="text-sm text-gray-600 mt-1">Command (runs non-blocking)</div>
            </div>
          </div>
        <% end %>
      </div>

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

      <!-- Cache Health Report -->
      <div class="bg-white shadow rounded-lg p-6">
        <div class="flex items-center justify-between mb-4">
          <div>
            <h2 class="text-xl font-semibold text-gray-900">Cache Health Report</h2>
            <p class="text-sm text-gray-600">
              Compares event counts across: Cachex cache, Materialized View, Direct Query
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

          <div class="mt-4 text-sm text-gray-600">
            <strong>Legend:</strong>
            <span class="ml-2 px-2 py-0.5 bg-green-100 text-green-800 rounded">Healthy</span> = All sources match
            <span class="ml-2 px-2 py-0.5 bg-orange-100 text-orange-800 rounded">Cache Miss</span> = Cache empty but MV has data
            <span class="ml-2 px-2 py-0.5 bg-purple-100 text-purple-800 rounded">Mismatch</span> = Counts differ by >10
            <span class="ml-2 px-2 py-0.5 bg-red-100 text-red-800 rounded">Critical</span> = Both cache and MV empty
          </div>
        <% else %>
          <div class="text-center py-8 text-gray-500">
            Click "Load Health Report" to compare cache vs MV vs direct query counts.
          </div>
        <% end %>
      </div>

      <!-- Documentation -->
      <div class="mt-6 bg-blue-50 border border-blue-200 rounded-lg p-4">
        <h3 class="text-sm font-medium text-blue-800 mb-2">How the 3-Layer Cache Works</h3>
        <ul class="text-sm text-blue-700 space-y-1">
          <li><strong>Layer 1 (Startup)</strong>: MV is refreshed on app boot if empty</li>
          <li><strong>Layer 2 (Fallback)</strong>: If Cachex misses, query MV instead of direct DB</li>
          <li><strong>Layer 3 (This Page)</strong>: Manual controls for ops intervention</li>
        </ul>
        <p class="text-sm text-blue-600 mt-2">
          See: <a href="https://github.com/anthropics/eventasaurus/issues/3493" class="underline" target="_blank">Issue #3493</a>
        </p>
      </div>
    </div>
    """
  end

  defp flash_classes(:info), do: "bg-blue-50 text-blue-800 border border-blue-200"
  defp flash_classes(:warning), do: "bg-yellow-50 text-yellow-800 border border-yellow-200"
  defp flash_classes(:error), do: "bg-red-50 text-red-800 border border-red-200"
  defp flash_classes(_), do: "bg-gray-50 text-gray-800 border border-gray-200"

  defp mv_status_color(:ok), do: "text-green-600"
  defp mv_status_color(:missing), do: "text-red-600"
  defp mv_status_color(:error), do: "text-red-600"
  defp mv_status_color(_), do: "text-gray-600"

  defp mv_status_label(:ok), do: "OK"
  defp mv_status_label(:missing), do: "View Missing"
  defp mv_status_label(:error), do: "Error"
  defp mv_status_label(_), do: "Unknown"
end
