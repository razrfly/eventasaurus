defmodule EventasaurusWeb.ParticipantStatusDisplayComponent do
  @moduledoc """
  A reusable LiveView component for displaying participant counts and avatars.

  Shows participant counts and avatars grouped by status (going/interested) with
  support for overflow indicators and responsive design.

  ## Attributes:
  - participants: List of participant structs with user and status data
  - show_avatars: Whether to show participant avatars (default: true)
  - max_avatars: Maximum avatars to show before overflow (default: 10)
  - avatar_size: Size of avatars (:sm, :md, :lg) (default: :md)
  - show_counts: Whether to show participant counts (default: true)
  - show_status_labels: Whether to show status labels (default: true)
  - class: Additional CSS classes
  - layout: Display layout (:horizontal, :vertical, :stacked) (default: :horizontal)

  ## Usage:
      <.live_component
        module={EventasaurusWeb.ParticipantStatusDisplayComponent}
        id="participant-display"
        participants={@participants}
        show_avatars={true}
        max_avatars={8}
        avatar_size={:md}
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
     |> assign_new(:show_counts, fn -> true end)
     |> assign_new(:show_status_labels, fn -> true end)
     |> assign_new(:class, fn -> "" end)
     |> assign_new(:layout, fn -> :horizontal end)
     |> assign_participant_groups()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class={["participant-status-display", @layout_classes, @class]}>
      <%= if @layout == :stacked do %>
        <div class="space-y-4">
          <%= for {status, group} <- @participant_groups do %>
            <.status_section
              status={status}
              group={group}
              avatar_size={@avatar_size}
              max_avatars={@max_avatars}
              show_avatars={@show_avatars}
              show_counts={@show_counts}
              show_status_labels={@show_status_labels}
            />
          <% end %>
        </div>
      <% else %>
        <div class={@content_classes}>
          <%= for {status, group} <- @participant_groups do %>
            <.status_section
              status={status}
              group={group}
              avatar_size={@avatar_size}
              max_avatars={@max_avatars}
              show_avatars={@show_avatars}
              show_counts={@show_counts}
              show_status_labels={@show_status_labels}
            />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # Private function components

  defp status_section(assigns) do
    ~H"""
    <div class="status-section flex items-center space-x-3">
      <%= if @show_status_labels || @show_counts do %>
        <div class="status-info">
          <%= if @show_counts do %>
            <span class={["font-semibold", status_count_color(@status)]}>
              <%= @group.count %>
            </span>
          <% end %>
          <%= if @show_status_labels do %>
            <span class={["text-sm", status_label_color(@status)]}>
              <%= status_label(@status) %>
            </span>
          <% end %>
        </div>
      <% end %>

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
          <%= avatar_img_size(participant.user, @avatar_size,
                class: "border-2 border-white rounded-full shadow-sm hover:scale-110 transition-transform duration-200 cursor-pointer relative"
              ) %>

          <!-- Tooltip on hover -->
          <div class="absolute bottom-full left-1/2 transform -translate-x-1/2 mb-2 px-2 py-1 bg-gray-900 text-white text-xs rounded-md opacity-0 group-hover:opacity-100 group-focus:opacity-100 transition-opacity duration-200 pointer-events-none whitespace-nowrap z-50"
               role="tooltip"
               id={"tooltip-#{participant.id}"}
               aria-hidden="true">
            <%= get_participant_name(participant) %>
            <div class="absolute top-full left-1/2 transform -translate-x-1/2 w-0 h-0 border-l-4 border-r-4 border-t-4 border-transparent border-t-gray-900"></div>
          </div>
        </div>
      <% end %>

      <%= if length(@participants) > @max_avatars do %>
        <div
          class={[
            "relative -ml-2 w-10 h-10 bg-gray-100 rounded-full border-2 border-white flex items-center justify-center text-sm font-medium text-gray-600 shadow-sm"
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

  defp assign_participant_groups(socket) do
    participants = socket.assigns.participants || []

    # Group participants by status
    groups = participants
    |> Enum.filter(&(&1.user && &1.user.name)) # Only include participants with valid user data
    |> Enum.group_by(&(&1.status))
    |> Enum.map(fn {status, participants} ->
      {status, %{participants: participants, count: length(participants)}}
    end)
    |> Enum.sort_by(fn {status, _group} -> status_priority(status) end)

    layout_classes = get_layout_classes(socket.assigns.layout)
    content_classes = get_content_classes(socket.assigns.layout)

    socket
    |> assign(:participant_groups, groups)
    |> assign(:layout_classes, layout_classes)
    |> assign(:content_classes, content_classes)
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

  defp get_content_classes(:horizontal), do: "flex items-center space-x-6"
  defp get_content_classes(:vertical), do: "space-y-4"
  defp get_content_classes(:stacked), do: ""

  defp get_participant_name(participant) do
    case participant.user do
      %{name: name} when is_binary(name) and name != "" -> name
      _ -> "Anonymous User"
    end
  end
end
