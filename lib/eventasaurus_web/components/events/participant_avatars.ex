defmodule EventasaurusWeb.Components.Events.ParticipantAvatars do
  use EventasaurusWeb, :live_component

  attr :event, :map, required: true

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :participant_data, calculate_participant_data(assigns.event))

    ~H"""
    <div class="flex items-center">
      <%= if @participant_data.actual_count > 0 || length(@participant_data.participants_list) > 0 do %>
        <%= if length(@participant_data.participants_list) > 0 do %>
          <div class="flex -space-x-1.5 mr-2">
            <%= for {participant, _index} <- Enum.with_index(Enum.take(@participant_data.participants_list, 3)) do %>
              <%= if participant.user do %>
                <div class="relative group/avatar">
                  <img 
                    src={generate_avatar_url(participant.user)}
                    alt={participant.user.name || participant.user.email}
                    class="w-10 h-10 rounded-full border-2 border-white hover:z-20 hover:scale-110 transition-transform cursor-pointer relative"
                  >
                  <div class="absolute bottom-full left-1/2 transform -translate-x-1/2 mb-2 px-2 py-1 bg-gray-900 text-white text-xs rounded whitespace-nowrap opacity-0 invisible group-hover/avatar:opacity-100 group-hover/avatar:visible transition-all duration-200 z-50 pointer-events-none">
                    <%= participant.user.name || participant.user.email %>
                    <div class="absolute top-full left-1/2 transform -translate-x-1/2 -mt-1 border-4 border-transparent border-t-gray-900"></div>
                  </div>
                </div>
              <% end %>
            <% end %>
            
            <%= if @participant_data.more_count > 0 do %>
              <div class="relative group/more">
                <div class="w-10 h-10 rounded-full bg-gray-200 flex items-center justify-center text-gray-600 text-xs font-medium border-2 border-white hover:z-20 hover:scale-110 transition-transform cursor-pointer">
                  +<%= @participant_data.more_count %>
                </div>
                <div class="absolute bottom-full left-1/2 transform -translate-x-1/2 mb-2 px-2 py-1 bg-gray-900 text-white text-xs rounded whitespace-nowrap opacity-0 invisible group-hover/more:opacity-100 group-hover/more:visible transition-all duration-200 z-50 pointer-events-none">
                  <%= @participant_data.more_count %> more participants
                  <div class="absolute top-full left-1/2 transform -translate-x-1/2 -mt-1 border-4 border-transparent border-t-gray-900"></div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
        
        <span class="text-sm text-gray-600">
          <%= @participant_data.actual_count %> attending
        </span>
      <% else %>
        <svg class="w-4 h-4 mr-1.5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197m13.5-9a2.25 2.25 0 11-4.5 0 2.25 2.25 0 014.5 0z" />
        </svg>
        <span class="text-sm text-gray-600">0 attending</span>
      <% end %>
    </div>
    """
  end

  # Helper functions

  defp calculate_participant_data(event) do
    # Calculate the actual participant count from available data
    actual_count =
      cond do
        # If we have participant_count, use it as the source of truth
        is_integer(Map.get(event, :participant_count)) && Map.get(event, :participant_count) >= 0 ->
          Map.get(event, :participant_count)

        # If we have participants array, use its length as fallback
        is_list(Map.get(event, :participants)) ->
          length(Map.get(event, :participants, []))

        # Otherwise default to 0
        true ->
          0
      end

    # Determine how many more participants there are beyond what's shown
    participants_list = Map.get(event, :participants, [])
    shown_count = min(length(participants_list), 3)
    more_count = max(actual_count - shown_count, 0)

    %{
      actual_count: actual_count,
      participants_list: participants_list,
      more_count: more_count
    }
  end

  defp generate_avatar_url(user) do
    # Use the existing avatar generation system from the app
    EventasaurusApp.Avatars.generate_user_avatar(user, size: 40)
  end
end
