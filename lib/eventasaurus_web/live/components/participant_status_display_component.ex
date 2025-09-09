defmodule EventasaurusWeb.ParticipantStatusDisplayComponent do
  @moduledoc """
  A reusable LiveView component for displaying participant counts and avatars in a unified display.

  Shows a unified "X Attendees" section with sample avatars and progressive disclosure 
  to show detailed status breakdown. Declined participants are hidden from public view.

  ## Attributes:
  - participants: List of participant structs with user and status data
  - show_avatars: Whether to show participant avatars (default: true)
  - max_avatars: Maximum avatars to show before overflow (default: 10)
  - avatar_size: Size of avatars (:sm, :md, :lg) (default: :md)
  - show_expanded: Whether to show detailed status breakdown (default: false)
  - class: Additional CSS classes
  - layout: Display layout (:horizontal, :vertical, :stacked) (default: :horizontal)

  ## Usage:
      <.live_component
        module={EventasaurusWeb.ParticipantStatusDisplayComponent}
        id="participant-display"
        participants={@participants}
        show_avatars={true}
        max_avatars={10}
        avatar_size={:md}
        show_expanded={false}
      />
  """

  use EventasaurusWeb, :live_component

  import EventasaurusWeb.Helpers.AvatarHelper

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:show_avatars, fn -> true end)
     |> assign_new(:max_avatars, fn -> 10 end)
     |> assign_new(:avatar_size, fn -> :md end)
     |> assign_new(:show_expanded, fn -> false end)
     |> assign_new(:class, fn -> "" end)
     |> assign_new(:layout, fn -> :horizontal end)
     |> assign_participant_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={["participant-status-display", @layout_classes, @class]}>
      <%= if @total_attendees > 0 do %>
        <div class="space-y-4">
          <!-- Unified attendee display -->
          <div class="unified-attendee-section flex items-center space-x-4">
            <div class="attendee-info">
              <span class="font-semibold text-lg text-gray-900">
                <%= @total_attendees %>
              </span>
              <span class="text-sm text-gray-600 ml-1">
                <%= if @total_attendees == 1, do: "Attendee", else: "Attendees" %>
              </span>
            </div>

            <%= if @show_avatars && length(@display_participants) > 0 do %>
              <div class="participant-avatars flex-1">
                <.unified_avatar_stack
                  participants={@display_participants}
                  max_avatars={@max_avatars}
                  avatar_size={@avatar_size}
                />
              </div>
            <% end %>

            <%= if @has_breakdown do %>
              <button
                type="button"
                phx-click="toggle_expanded"
                phx-target={@myself}
                class="text-sm text-blue-600 hover:text-blue-800 font-medium focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 rounded-md px-2 py-1"
              >
                <%= if @show_expanded, do: "Hide details", else: "Show details" %>
              </button>
            <% end %>
          </div>

          <!-- Expanded status breakdown -->
          <%= if @show_expanded && @has_breakdown do %>
            <div class="expanded-breakdown border-t border-gray-200 pt-4 space-y-3">
              <%= for {status, group} <- @participant_groups do %>
                <.status_section
                  status={status}
                  group={group}
                  avatar_size={:sm}
                  max_avatars={5}
                  show_avatars={true}
                />
              <% end %>
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="text-sm text-gray-500">
          No attendees yet
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_expanded", _params, socket) do
    {:noreply, assign(socket, :show_expanded, !socket.assigns.show_expanded)}
  end

  # Private function components

  defp status_section(assigns) do
    assigns = assigns |> assign_new(:show_counts, fn -> true end) |> assign_new(:show_status_labels, fn -> true end)
    ~H"""
    <div class="status-section flex items-center space-x-3">
      <div class="status-info">
        <span class={["font-semibold", status_count_color(@status)]}>
          <%= @group.count %>
        </span>
        <span class={["text-sm ml-1", status_label_color(@status)]}>
          <%= status_label(@status) %>
        </span>
      </div>

      <%= if @show_avatars && @group.count > 0 do %>
        <div class="participant-avatars">
          <.avatar_stack
            participants={@group.participants}
            max_avatars={@max_avatars}
            avatar_size={@avatar_size}
            status={@status}
          />
        </div>
      <% end %>
    </div>
    """
  end

  defp unified_avatar_stack(assigns) do
    ~H"""
    <div class="flex items-center flex-wrap">
      <%= for {participant, index} <- Enum.with_index(@participants) |> Enum.take(@max_avatars) do %>
        <div
          class={[
            "relative group",
            if(index > 0, do: "-ml-2", else: "")
          ]}
          role="img"
          aria-label={get_participant_name(participant)}
          aria-describedby={"tooltip-#{participant.id}"}
          tabindex="0"
          style={"z-index: #{@max_avatars - index}"}
        >
          <.link navigate={EventasaurusApp.Accounts.User.profile_url(participant.user)} 
                class="block hover:opacity-80 transition-opacity">
            <%= avatar_img_size(participant.user, @avatar_size,
                  class: "border-2 border-white rounded-full shadow-sm hover:scale-110 transition-transform duration-200 cursor-pointer relative"
                ) %>
          </.link>

          <!-- Tooltip on hover -->
          <div class="absolute bottom-full left-1/2 transform -translate-x-1/2 mb-2 px-3 py-2 bg-white text-gray-900 text-xs rounded-md shadow-lg border border-gray-200 opacity-0 group-hover:opacity-100 group-focus:opacity-100 transition-opacity duration-200 pointer-events-none whitespace-nowrap z-50"
               role="tooltip"
               id={"tooltip-#{participant.id}"}
               aria-hidden="true">
            <%= get_participant_name(participant) %>
            <div class="absolute top-full left-1/2 transform -translate-x-1/2 w-0 h-0 border-l-4 border-r-4 border-t-4 border-transparent border-t-white"></div>
          </div>
        </div>
      <% end %>

      <%= if length(@participants) > @max_avatars do %>
        <div
          class={[
            "relative -ml-2 flex items-center justify-center text-sm font-medium text-gray-600 shadow-sm bg-gray-100 rounded-full border-2 border-white",
            avatar_overflow_size(@avatar_size)
          ]}
          style="z-index: 0"
          title={"#{length(@participants) - @max_avatars} more"}
        >
          +<%= length(@participants) - @max_avatars %>
        </div>
      <% end %>
    </div>
    """
  end

  defp avatar_stack(assigns) do
    ~H"""
    <div class="flex items-center">
      <%= for {participant, index} <- Enum.with_index(@participants) |> Enum.take(@max_avatars) do %>
        <div
          class={[
            "relative group",
            if(index > 0, do: "-ml-2", else: "")
          ]}
          role="img"
          aria-label={get_participant_name(participant)}
          aria-describedby={"tooltip-#{participant.id}"}
          tabindex="0"
          style={"z-index: #{@max_avatars - index}"}
        >
          <.link navigate={EventasaurusApp.Accounts.User.profile_url(participant.user)} 
                class="block hover:opacity-80 transition-opacity">
            <%= avatar_img_size(participant.user, @avatar_size,
                  class: "border-2 border-white rounded-full shadow-sm hover:scale-110 transition-transform duration-200 cursor-pointer relative"
                ) %>
          </.link>

          <!-- Tooltip on hover -->
          <div class="absolute bottom-full left-1/2 transform -translate-x-1/2 mb-2 px-3 py-2 bg-white text-gray-900 text-xs rounded-md shadow-lg border border-gray-200 opacity-0 group-hover:opacity-100 group-focus:opacity-100 transition-opacity duration-200 pointer-events-none whitespace-nowrap z-50"
               role="tooltip"
               id={"tooltip-#{participant.id}"}
               aria-hidden="true">
            <%= get_participant_name(participant) %>
            <div class="absolute top-full left-1/2 transform -translate-x-1/2 w-0 h-0 border-l-4 border-r-4 border-t-4 border-transparent border-t-white"></div>
          </div>
        </div>
      <% end %>

      <%= if length(@participants) > @max_avatars do %>
        <div
          class={[
            "relative -ml-2 flex items-center justify-center text-sm font-medium text-gray-600 shadow-sm bg-gray-100 rounded-full border-2 border-white",
            avatar_overflow_size(@avatar_size)
          ]}
          style="z-index: 0"
          title={"#{length(@participants) - @max_avatars} more"}
        >
          +<%= length(@participants) - @max_avatars %>
        </div>
      <% end %>
    </div>
    """
  end

  # Private functions

  defp assign_participant_data(socket) do
    participants = socket.assigns.participants || []

    # Filter out declined and cancelled participants for public display
    public_participants = participants
    |> Enum.filter(&(&1.user && &1.user.name)) # Only include participants with valid user data
    |> Enum.filter(&(&1.status not in [:declined, :cancelled]))

    # Group participants by status (for expanded view)
    groups = public_participants
    |> Enum.group_by(&(&1.status))
    |> Enum.map(fn {status, participants} ->
      {status, %{participants: participants, count: length(participants)}}
    end)
    |> Enum.sort_by(fn {status, _group} -> status_priority(status) end)

    # Prioritize going/confirmed first, then interested, then pending for avatar display
    display_participants = public_participants
    |> Enum.sort_by(fn participant ->
      {status_priority(participant.status), participant.id}
    end)

    total_attendees = length(public_participants)
    has_breakdown = length(groups) > 1
    layout_classes = get_layout_classes(socket.assigns.layout)

    socket
    |> assign(:participant_groups, groups)
    |> assign(:display_participants, display_participants)
    |> assign(:total_attendees, total_attendees)
    |> assign(:has_breakdown, has_breakdown)
    |> assign(:layout_classes, layout_classes)
  end

  defp status_priority(:accepted), do: 1
  defp status_priority(:interested), do: 2
  defp status_priority(:pending), do: 3
  defp status_priority(:declined), do: 4
  defp status_priority(:cancelled), do: 5
  defp status_priority(:confirmed_with_order), do: 0
  defp status_priority(_), do: 99

  defp status_label(:accepted), do: "Going"
  defp status_label(:interested), do: "Interested"
  defp status_label(:pending), do: "Pending"
  defp status_label(:declined), do: "Declined"
  defp status_label(:cancelled), do: "Cancelled"
  defp status_label(:confirmed_with_order), do: "Confirmed"
  defp status_label(_), do: "Unknown"

  defp status_count_color(:accepted), do: "text-blue-600"
  defp status_count_color(:interested), do: "text-red-500"
  defp status_count_color(:pending), do: "text-yellow-600"
  defp status_count_color(:declined), do: "text-gray-500"
  defp status_count_color(:cancelled), do: "text-gray-500"
  defp status_count_color(:confirmed_with_order), do: "text-green-600"
  defp status_count_color(_), do: "text-gray-600"

  defp status_label_color(:accepted), do: "text-blue-500"
  defp status_label_color(:interested), do: "text-red-400"
  defp status_label_color(:pending), do: "text-yellow-500"
  defp status_label_color(:declined), do: "text-gray-400"
  defp status_label_color(:cancelled), do: "text-gray-400"
  defp status_label_color(:confirmed_with_order), do: "text-green-500"
  defp status_label_color(_), do: "text-gray-400"

  # Removed unused avatar styling functions since we're using the original white border styling

  defp get_layout_classes(:horizontal), do: "flex items-center"
  defp get_layout_classes(:vertical), do: "flex flex-col space-y-4"
  defp get_layout_classes(:stacked), do: "space-y-6"


  defp get_participant_name(participant) do
    case participant.user do
      %{name: name} when is_binary(name) and name != "" -> name
      _ -> "Anonymous User"
    end
  end

  defp avatar_overflow_size(:sm), do: "w-8 h-8 text-xs"
  defp avatar_overflow_size(:md), do: "w-10 h-10 text-sm"
  defp avatar_overflow_size(:lg), do: "w-12 h-12 text-base"
  defp avatar_overflow_size(_), do: "w-10 h-10 text-sm"
end
