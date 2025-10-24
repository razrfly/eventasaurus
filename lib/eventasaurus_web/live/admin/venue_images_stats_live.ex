defmodule EventasaurusWeb.Admin.VenueImagesStatsLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.VenueImages.{Monitor, Stats, CleanupScheduler}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Refresh every 10 seconds
      :timer.send_interval(10_000, self(), :refresh)
    end

    {:ok, load_stats(socket)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_stats(socket)}
  end

  @impl true
  def handle_event("enqueue_enrichment", _params, socket) do
    case EventasaurusDiscovery.VenueImages.EnrichmentJob.enqueue() do
      {:ok, _job} ->
        socket =
          socket
          |> put_flash(:info, "✅ Venue enrichment job enqueued successfully")
          |> load_stats()

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> put_flash(:error, "❌ Failed to enqueue job: #{inspect(reason)}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("retry_failed_uploads", _params, socket) do
    case CleanupScheduler.enqueue() do
      {:ok, _job} ->
        socket =
          socket
          |> put_flash(:info, "✅ Cleanup job enqueued - will scan venues and retry failed uploads")
          |> load_stats()

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> put_flash(:error, "❌ Failed to enqueue cleanup job: #{inspect(reason)}")

        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6">
      <div class="mb-6">
        <div class="flex justify-between items-start">
          <div>
            <h1 class="text-2xl font-bold">Venue Image Provider Statistics</h1>
            <p class="text-gray-600 mt-2">Real-time monitoring of image provider usage and rate limits</p>
          </div>
          <div class="flex gap-3">
            <button
              phx-click="retry_failed_uploads"
              class="px-4 py-2 bg-orange-600 text-white rounded-lg hover:bg-orange-700 transition-colors"
              title="Retry transient failed uploads without calling provider APIs"
            >
              🔄 Retry Failed Uploads
            </button>
            <button
              phx-click="enqueue_enrichment"
              class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
            >
              🖼️ Enqueue Enrichment
            </button>
          </div>
        </div>
      </div>

      <!-- Failed Upload Summary -->
      <%= if @failure_summary.total_venues_with_failures > 0 do %>
        <div class="mb-6 bg-orange-50 border border-orange-200 rounded-lg p-4">
          <div class="flex justify-between items-start">
            <div>
              <h2 class="text-lg font-semibold text-orange-900 mb-2">📊 Failed Upload Summary</h2>
              <div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                <div>
                  <p class="text-orange-700">Venues with Failures</p>
                  <p class="text-2xl font-bold text-orange-900"><%= @failure_summary.total_venues_with_failures %></p>
                </div>
                <div>
                  <p class="text-orange-700">Failed Images</p>
                  <p class="text-2xl font-bold text-orange-900"><%= @failure_summary.total_failed_images %></p>
                </div>
                <div>
                  <p class="text-orange-700">Transient Failures</p>
                  <p class="text-2xl font-bold text-green-700"><%= @failure_summary.venues_with_transient %></p>
                  <p class="text-xs text-gray-600">Can be retried</p>
                </div>
                <div>
                  <p class="text-orange-700">Permanent Failures</p>
                  <p class="text-2xl font-bold text-red-700"><%= @failure_summary.venues_with_permanent %></p>
                  <p class="text-xs text-gray-600">Need manual review</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Alerts Section -->
      <%= if length(@alerts) > 0 do %>
        <div class="mb-6">
          <h2 class="text-xl font-semibold mb-3">⚠️ Active Alerts</h2>
          <div class="space-y-2">
            <%= for alert <- @alerts do %>
              <div class={"p-4 rounded-lg border-l-4 " <> alert_class(alert.severity)}>
                <div class="flex justify-between items-start">
                  <div>
                    <p class="font-semibold"><%= alert.provider %></p>
                    <p class="text-sm"><%= alert.message %></p>
                  </div>
                  <span class={"px-2 py-1 text-xs rounded " <> severity_badge(alert.severity)}>
                    <%= alert.severity %>
                  </span>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <!-- Provider Stats Grid -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <%= for stat <- @stats do %>
          <div class="bg-white border rounded-lg p-4 shadow-sm">
            <div class="flex justify-between items-start mb-3">
              <h3 class="text-lg font-semibold"><%= stat.name %></h3>
              <%= if stat.is_active do %>
                <span class="px-2 py-1 text-xs bg-green-100 text-green-800 rounded">Active</span>
              <% else %>
                <span class="px-2 py-1 text-xs bg-gray-100 text-gray-800 rounded">Inactive</span>
              <% end %>
            </div>

            <div class="space-y-2 text-sm">
              <div class="flex justify-between">
                <span class="text-gray-600">Priority:</span>
                <span class="font-medium"><%= stat.priority %></span>
              </div>

              <div class="border-t pt-2">
                <p class="text-gray-600 font-medium mb-1">Rate Limit Usage:</p>
                <div class="ml-2 space-y-1">
                  <div class="flex justify-between">
                    <span>Last Second:</span>
                    <span class="font-mono"><%= stat.rate_limit_stats.last_second %></span>
                  </div>
                  <div class="flex justify-between">
                    <span>Last Minute:</span>
                    <span class="font-mono"><%= stat.rate_limit_stats.last_minute %></span>
                  </div>
                  <div class="flex justify-between">
                    <span>Last Hour:</span>
                    <span class="font-mono"><%= stat.rate_limit_stats.last_hour %></span>
                  </div>
                </div>
              </div>

              <%= if cost = get_in(stat.metadata, ["cost_per_image"]) do %>
                <div class="border-t pt-2 flex justify-between">
                  <span class="text-gray-600">Cost per Image:</span>
                  <span class="font-medium">$<%= :erlang.float_to_binary(cost, decimals: 4) %></span>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>

      <!-- Metadata Section -->
      <div class="mt-6 text-sm text-gray-500">
        <p>Last updated: <%= Calendar.strftime(@updated_at, "%Y-%m-%d %H:%M:%S UTC") %></p>
        <p>Auto-refresh: every 10 seconds</p>
      </div>
    </div>
    """
  end

  defp load_stats(socket) do
    stats = Monitor.get_all_stats()
    alerts = Monitor.check_alerts()
    failure_summary = Stats.summary_stats()

    socket
    |> assign(:stats, stats)
    |> assign(:alerts, alerts)
    |> assign(:failure_summary, failure_summary)
    |> assign(:updated_at, DateTime.utc_now())
  end

  defp alert_class(:critical), do: "bg-red-50 border-red-500"
  defp alert_class(:error), do: "bg-orange-50 border-orange-500"
  defp alert_class(:warning), do: "bg-yellow-50 border-yellow-500"
  defp alert_class(_), do: "bg-blue-50 border-blue-500"

  defp severity_badge(:critical), do: "bg-red-600 text-white"
  defp severity_badge(:error), do: "bg-orange-600 text-white"
  defp severity_badge(:warning), do: "bg-yellow-600 text-white"
  defp severity_badge(_), do: "bg-blue-600 text-white"
end
