defmodule EventasaurusWeb.Components.Events.EventCardBadges do
  use EventasaurusWeb, :live_component

  alias EventasaurusWeb.Helpers.EventStatusHelpers

  attr :event, :map, required: true
  attr :context, :atom, required: true, values: [:user_dashboard, :group_events, :profile]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="contents">
      <%= if @context in [:user_dashboard, :profile] && Map.get(@event, :user_role) do %>
        <span class={[
          "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium",
          role_badge_class(Map.get(@event, :user_role), @context)
        ]}>
          <%= role_badge_text(Map.get(@event, :user_role), @context) %>
        </span>
      <% end %>

      <span class={[
        "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium",
        EventStatusHelpers.status_css_class(@event)
      ]}>
        <%= EventStatusHelpers.status_icon(@event) %> <%= EventStatusHelpers.friendly_status_message(@event, :badge) %>
      </span>

      <%= if Map.get(@event, :taxation_type) == "ticketed_event" do %>
        <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800">
          🎫 Ticketed
        </span>
      <% end %>

      <%= if Map.get(@event, :poll_count, 0) > 0 do %>
        <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-orange-100 text-orange-800">
          <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01" />
          </svg>
          <%= if @event.poll_count == 1 do %>
            1 Poll
          <% else %>
            <%= @event.poll_count %> Polls
          <% end %>
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

  # Profile context uses blue for organizer (Hosted), green for participant (Attended)
  defp role_badge_class("organizer", :profile), do: "bg-blue-100 text-blue-800"
  defp role_badge_class("participant", :profile), do: "bg-green-100 text-green-800"
  defp role_badge_class(_, :profile), do: "bg-gray-100 text-gray-800"

  # Dashboard context uses green for organizer, blue for participant
  defp role_badge_class("organizer", _context), do: "bg-green-100 text-green-800"
  defp role_badge_class("participant", _context), do: "bg-blue-100 text-blue-800"
  defp role_badge_class(_, _context), do: "bg-gray-100 text-gray-800"

  # Profile context uses past tense (Hosted/Attended)
  defp role_badge_text("organizer", :profile), do: "Hosted"
  defp role_badge_text("participant", :profile), do: "Attended"
  defp role_badge_text(role, :profile), do: String.capitalize(role)

  # Dashboard context uses present tense (Organizer/Attending)
  defp role_badge_text("organizer", _context), do: "Organizer"
  defp role_badge_text("participant", _context), do: "Attending"
  defp role_badge_text(role, _context), do: String.capitalize(role)
end
