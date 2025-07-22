defmodule EventasaurusWeb.Components.Events.EventCardBadges do
  use EventasaurusWeb, :live_component

  attr :event, :map, required: true
  attr :context, :atom, required: true, values: [:user_dashboard, :group_events]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="contents">
      <%= if @context == :user_dashboard && @event.user_role do %>
        <span class={[
          "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium",
          role_badge_class(@event.user_role)
        ]}>
          <%= role_badge_text(@event.user_role) %>
        </span>
      <% end %>

      <span class={[
        "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium",
        status_badge_class(@event.status)
      ]}>
        <%= status_badge_text(@event.status) %>
      </span>
    </div>
    """
  end

  # Helper functions

  defp role_badge_class("organizer"), do: "bg-green-100 text-green-800"
  defp role_badge_class("participant"), do: "bg-blue-100 text-blue-800"
  defp role_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp role_badge_text("organizer"), do: "Organizer"
  defp role_badge_text("participant"), do: "Attending"
  defp role_badge_text(role), do: String.capitalize(role)

  defp status_badge_class(:polling), do: "bg-yellow-100 text-yellow-800"
  defp status_badge_class(:confirmed), do: "bg-green-100 text-green-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp status_badge_text(:polling), do: "📊 Polling"
  defp status_badge_text(:confirmed), do: "✓ Confirmed"
  defp status_badge_text(status) when is_atom(status), do: String.capitalize(Atom.to_string(status))
  defp status_badge_text(status) when is_binary(status), do: String.capitalize(status)
  defp status_badge_text(_), do: "Unknown"
end