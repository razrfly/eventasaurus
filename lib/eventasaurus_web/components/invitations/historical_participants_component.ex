defmodule EventasaurusWeb.Components.Invitations.HistoricalParticipantsComponent do
  @moduledoc """
  Component showing "People from your past events" with smart recommendations.
  Uses participant scoring and ranking to suggest the most relevant users.
  """
  use EventasaurusWeb, :live_component

  alias EventasaurusApp.Events

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:participants, [])
     |> assign(:loading, false)
     |> assign(:expanded, false)
     |> assign(:selected_ids, MapSet.new())
     # "grid" or "list"
     |> assign(:display_mode, "grid")}
  end

  @impl true
  def update(assigns, socket) do
    selected_ids =
      case assigns[:selected_users] do
        nil -> MapSet.new()
        users -> MapSet.new(users, & &1.id)
      end

    # Allow display_mode to be passed in as an assign
    display_mode = assigns[:display_mode] || socket.assigns[:display_mode] || "grid"

    socket =
      socket
      |> assign(assigns)
      |> assign(:selected_ids, selected_ids)
      |> assign(:display_mode, display_mode)

    # Load participants synchronously if we have an organizer and haven't loaded yet
    socket =
      if assigns[:organizer] && Enum.empty?(socket.assigns.participants) &&
           !socket.assigns.loading do
        exclude_event_ids = assigns[:exclude_event_ids] || []
        exclude_user_ids = MapSet.to_list(selected_ids)

        # Load the participants directly (synchronously) since LiveComponents don't support handle_info
        participants =
          try do
            Events.get_participant_suggestions(
              assigns[:organizer],
              exclude_event_ids: exclude_event_ids,
              exclude_user_ids: exclude_user_ids,
              limit: 30
            )
          rescue
            _ -> []
          end

        socket
        |> assign(:participants, participants)
        |> assign(:loading, false)
      else
        # Keep all participants visible - selected state shown via checkmarks
        socket
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="historical-participants-component">
      <div class="mb-4">
        <h3 class="text-lg font-medium text-gray-900 mb-2">
          People from your past events
        </h3>
        <p class="text-sm text-gray-500 mb-4">
          Select people who have attended your previous events
        </p>

        <%= if @loading do %>
          <div class="flex items-center justify-center py-8">
            <div class="animate-spin h-8 w-8 border-4 border-green-500 rounded-full border-t-transparent"></div>
          </div>
        <% else %>
          <%= if length(@participants) > 0 do %>
            <%= if @display_mode == "list" do %>
              <!-- List View (Manager Style) -->
              <div class="bg-gray-50 rounded-lg border border-gray-200 max-h-60 overflow-y-auto">
                <%= for participant <- display_participants(@participants, @expanded) do %>
                  <div class="flex items-center justify-between p-3 border-b border-gray-200 last:border-0 hover:bg-gray-100">
                    <div class="flex items-center space-x-3">
                      <input
                        type="checkbox"
                        id={"participant-#{participant.user_id}"}
                        name="selected_participants[]"
                        value={participant.user_id}
                        checked={MapSet.member?(@selected_ids, participant.user_id)}
                        class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
                        phx-target={@myself}
                        phx-click="toggle_participant"
                        phx-value-user-id={participant.user_id}
                      />
                      <!-- User Avatar -->
                      <div class="flex-shrink-0">
                        <img
                          src={get_participant_avatar(participant)}
                          alt={participant.name || participant.username}
                          class="h-10 w-10 rounded-full object-cover"
                        />
                      </div>
                      <div class="flex-1">
                        <div class="flex items-center space-x-2">
                          <label for={"participant-#{participant.user_id}"} class="font-medium text-gray-900 cursor-pointer">
                            <%= participant.name || participant.username %>
                          </label>
                          <%= if Map.get(participant, :recommendation_level) && participant.recommendation_level != :suggested do %>
                            <span class={[
                              "inline-flex items-center px-2 py-1 rounded-full text-xs font-medium",
                              case participant.recommendation_level do
                                :highly_recommended -> "bg-green-100 text-green-800"
                                :recommended -> "bg-blue-100 text-blue-800"
                                _ -> "bg-gray-100 text-gray-800"
                              end
                            ]}>
                              <%= String.replace(to_string(participant.recommendation_level), "_", " ") |> String.capitalize() %>
                            </span>
                          <% end %>
                        </div>
                        <div class="text-sm text-gray-500">
                          <%= participant.email %>
                          • <%= participation_text(participant) %>
                          <%= if Map.get(participant, :last_participation) do %>
                            • Last event <%= days_since_last_participation(participant.last_participation) %> days ago
                          <% end %>
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <!-- Grid View (Current/Default) -->
              <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3">
                <%= for participant <- display_participants(@participants, @expanded) do %>
                  <button
                    type="button"
                    phx-target={@myself}
                    phx-click="toggle_participant"
                    phx-value-user-id={participant.user_id}
                    class={[
                      "relative p-3 rounded-lg border-2 transition-all",
                      if(MapSet.member?(@selected_ids, participant.user_id),
                        do: "border-green-500 bg-green-50",
                        else: "border-gray-200 hover:border-gray-300 bg-white"
                      )
                    ]}
                  >
                    <div class="flex flex-col items-center">
                      <div class="relative mb-2">
                        <img
                          src={get_participant_avatar(participant)}
                          alt={participant.name || participant.username}
                          class="w-12 h-12 rounded-full"
                        />
                        <%= if MapSet.member?(@selected_ids, participant.user_id) do %>
                          <div class="absolute -bottom-1 -right-1 bg-green-500 rounded-full p-0.5">
                            <svg class="w-3 h-3 text-white" fill="currentColor" viewBox="0 0 20 20">
                              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                            </svg>
                          </div>
                        <% end %>
                      </div>
                      <div class="text-center">
                        <div class="text-sm font-medium text-gray-900 truncate max-w-full">
                          <%= participant.name || participant.username %>
                        </div>
                        <div class="text-xs text-gray-500">
                          <%= participation_text(participant) %>
                        </div>
                      </div>
                    </div>
                  </button>
                <% end %>
              </div>
            <% end %>

            <%= if length(@participants) > 10 && !@expanded do %>
              <button
                type="button"
                phx-target={@myself}
                phx-click="toggle_expand"
                class="mt-4 text-sm text-green-600 hover:text-green-700 font-medium"
              >
                Show <%= length(@participants) - 10 %> more →
              </button>
            <% end %>

            <%= if @expanded && length(@participants) > 10 do %>
              <button
                type="button"
                phx-target={@myself}
                phx-click="toggle_expand"
                class="mt-4 text-sm text-green-600 hover:text-green-700 font-medium"
              >
                Show less ←
              </button>
            <% end %>
          <% else %>
            <div class="text-center py-8 text-gray-500">
              <p>No previous participants to suggest</p>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_participant", %{"user-id" => user_id}, socket) do
    user_id = String.to_integer(user_id)
    participant = Enum.find(socket.assigns.participants, &(&1.user_id == user_id))

    if participant do
      # Convert participant data to user struct format
      user = %{
        id: participant.user_id,
        name: participant.name,
        email: participant.email,
        username: participant.username,
        avatar_url: Map.get(participant, :avatar_url)
      }

      send(self(), {:user_selected, user})
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_expand", _, socket) do
    {:noreply, assign(socket, :expanded, !socket.assigns.expanded)}
  end

  # Helper functions

  defp display_participants(participants, expanded) do
    if expanded do
      participants
    else
      Enum.take(participants, 10)
    end
  end

  defp participation_text(participant) do
    count = participant[:participation_count] || participant[:events_count] || 0

    case count do
      0 -> "New"
      1 -> "1 event"
      n -> "#{n} events"
    end
  end

  defp days_since_last_participation(last_participation) when is_nil(last_participation), do: nil

  defp days_since_last_participation(last_participation) do
    case last_participation do
      %DateTime{} = dt ->
        DateTime.diff(DateTime.utc_now(), dt, :day)

      _ ->
        nil
    end
  end

  defp get_participant_avatar(participant) do
    # Use DiceBear avatar generation with participant info
    EventasaurusApp.Avatars.generate_user_avatar(participant, size: 40)
  end
end
