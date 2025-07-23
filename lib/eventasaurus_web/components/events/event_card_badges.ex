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

      <%= if @event.taxation_type == "ticketed_event" do %>
        <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800">
          🎫 Ticketed
        </span>
      <% end %>

      <%= if @context == :user_dashboard && group_loaded?(@event) && @event.group && @event.group.slug do %>
        <a 
          href={"/groups/#{@event.group.slug}"} 
          class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800 hover:bg-purple-200 transition-colors relative z-10" 
          onclick="event.stopPropagation()"
        >
          <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
          </svg>
          <%= @event.group.name || "Group" %>
        </a>
      <% end %>
    </div>
    """
  end

  # Helper functions

  defp group_loaded?(event) do
    case event.group do
      %Ecto.Association.NotLoaded{} -> false
      _ -> true
    end
  end

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