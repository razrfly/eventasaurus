defmodule EventasaurusWeb.ConnectionTestComponent do
  @moduledoc """
  Simple test component to verify real-time connections are working.
  Add this to any poll page to see live update indicators.
  """
  use EventasaurusWeb, :live_component

  @impl true
  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Eventasaurus.PubSub, "connection_test")
      # Send a test message every 5 seconds
      Process.send_after(self(), :test_broadcast, 5000)
    end

    {:ok, assign(socket, :last_update, DateTime.utc_now())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed top-4 right-4 bg-blue-500 text-white px-4 py-2 rounded-lg shadow-lg z-50">
      <div class="text-sm font-semibold">Real-time Connection Test</div>
      <div class="text-xs">
        Last update: <%= Calendar.strftime(@last_update, "%H:%M:%S") %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_info(:test_broadcast, socket) do
    Phoenix.PubSub.broadcast(Eventasaurus.PubSub, "connection_test", {:test_update, DateTime.utc_now()})
    Process.send_after(self(), :test_broadcast, 5000)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:test_update, timestamp}, socket) do
    {:noreply, assign(socket, :last_update, timestamp)}
  end
end