defmodule EventasaurusWeb.Components.Events.TimelineDateMarker do
  use EventasaurusWeb, :live_component

  attr :date, :any, required: true
  attr :is_last, :boolean, default: false

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-shrink-0 w-24 text-right">
      <%= if @date == :no_date do %>
        <div class="text-sm font-semibold text-gray-900">Date</div>
        <div class="text-xs text-gray-500">TBD</div>
      <% else %>
        <div class="text-lg font-semibold text-gray-900">
          <%= Calendar.strftime(@date, "%b %d") %>
        </div>
        <div class="text-sm text-gray-500">
          <%= Calendar.strftime(@date, "%A") %>
        </div>
      <% end %>
    </div>
    """
  end
end