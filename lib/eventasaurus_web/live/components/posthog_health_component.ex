defmodule EventasaurusWeb.Live.Components.PosthogHealthComponent do
  @moduledoc """
  Displays PostHog service health status and monitoring metrics.
  """
  
  use EventasaurusWeb, :live_component
  require Logger
  
  @refresh_interval 30_000  # Refresh every 30 seconds
  
  def mount(socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh_health, @refresh_interval)
    end
    
    {:ok, assign_health_data(socket)}
  end
  
  def handle_event("refresh", _params, socket) do
    {:noreply, assign_health_data(socket)}
  end
  
  def handle_info(:refresh_health, socket) do
    Process.send_after(self(), :refresh_health, @refresh_interval)
    {:noreply, assign_health_data(socket)}
  end
  
  defp assign_health_data(socket) do
    # Get monitoring stats
    stats = Eventasaurus.Services.PosthogMonitor.get_stats()
    {status, message} = Eventasaurus.Services.PosthogMonitor.health_check()
    
    # Check configuration
    tracking_configured = Eventasaurus.Services.PosthogService.configured?()
    analytics_configured = Eventasaurus.Services.PosthogService.analytics_configured?()
    
    socket
    |> assign(:health_status, status)
    |> assign(:health_message, message)
    |> assign(:stats, stats)
    |> assign(:tracking_configured, tracking_configured)
    |> assign(:analytics_configured, analytics_configured)
  end
  
  def render(assigns) do
    ~H"""
    <div class="bg-white shadow rounded-lg p-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-medium text-gray-900">PostHog Service Health</h3>
        <button
          phx-click="refresh"
          phx-target={@myself}
          class="text-sm text-blue-600 hover:text-blue-800"
        >
          Refresh
        </button>
      </div>
      
      <div class="space-y-4">
        <!-- Overall Status -->
        <div class="flex items-center">
          <div class={["w-3 h-3 rounded-full mr-2", status_color(@health_status)]}></div>
          <span class="text-sm font-medium text-gray-700">
            Status: <%= format_status(@health_status) %>
          </span>
          <span class="text-sm text-gray-500 ml-2">
            <%= @health_message %>
          </span>
        </div>
        
        <!-- Configuration Status -->
        <div class="grid grid-cols-2 gap-4 text-sm">
          <div class="flex items-center">
            <div class={["w-2 h-2 rounded-full mr-2", if(@tracking_configured, do: "bg-green-500", else: "bg-red-500")]}></div>
            <span>Event Tracking: <%= if @tracking_configured, do: "Configured", else: "Not Configured" %></span>
          </div>
          <div class="flex items-center">
            <div class={["w-2 h-2 rounded-full mr-2", if(@analytics_configured, do: "bg-green-500", else: "bg-yellow-500")]}></div>
            <span>Analytics API: <%= if @analytics_configured, do: "Configured", else: "Not Configured" %></span>
          </div>
        </div>
        
        <!-- Metrics -->
        <div class="space-y-3">
          <!-- Analytics API Stats -->
          <div class="border-t pt-3">
            <h4 class="text-sm font-medium text-gray-700 mb-2">Analytics API</h4>
            <div class="grid grid-cols-2 gap-2 text-xs text-gray-600">
              <div>Requests: <%= @stats.analytics.total_requests %></div>
              <div>Success Rate: <%= format_percentage(@stats.analytics.success_rate) %></div>
              <div>Cache Hit Rate: <%= format_percentage(@stats.analytics.cache_hit_rate) %></div>
              <div>Avg Response: <%= format_duration(@stats.analytics.avg_duration) %></div>
              <%= if @stats.analytics.timeout_rate > 0 do %>
                <div class="col-span-2 text-yellow-600">
                  Timeout Rate: <%= format_percentage(@stats.analytics.timeout_rate) %>
                </div>
              <% end %>
            </div>
          </div>
          
          <!-- Event Tracking Stats -->
          <div class="border-t pt-3">
            <h4 class="text-sm font-medium text-gray-700 mb-2">Event Tracking</h4>
            <div class="grid grid-cols-2 gap-2 text-xs text-gray-600">
              <div>Events Sent: <%= @stats.events.total_requests %></div>
              <div>Success Rate: <%= format_percentage(@stats.events.success_rate) %></div>
              <%= if @stats.events.failure_count > 0 do %>
                <div class="col-span-2 text-red-600">
                  Failed Events: <%= @stats.events.failure_count %>
                </div>
              <% end %>
            </div>
          </div>
          
          <!-- Period Info -->
          <div class="text-xs text-gray-500 pt-2 border-t">
            Stats period: <%= @stats.period_duration_minutes %> minutes
          </div>
        </div>
      </div>
    </div>
    """
  end
  
  defp status_color(:healthy), do: "bg-green-500"
  defp status_color(:degraded), do: "bg-yellow-500"
  defp status_color(:unhealthy), do: "bg-red-500"
  
  defp format_status(:healthy), do: "Healthy"
  defp format_status(:degraded), do: "Degraded"
  defp format_status(:unhealthy), do: "Unhealthy"
  
  defp format_percentage(rate) when is_float(rate) do
    "#{Float.round(rate * 100, 1)}%"
  end
  defp format_percentage(_), do: "0%"
  
  defp format_duration(0), do: "N/A"
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"
end