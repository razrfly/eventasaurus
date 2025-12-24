defmodule EventasaurusWeb.EventAttendeesModalComponent do
  @moduledoc """
  A modal component for displaying event attendees with connect functionality.

  This component shows all attendees at an event and allows authenticated users
  to connect with fellow attendees. When connecting, it suggests context based
  on the shared event.

  ## Features

  - Full list of event attendees with avatars and names
  - Connect button for each attendee (for authenticated users)
  - Shows existing relationship status
  - Filters out the current user from the list
  - Mobile-friendly modal design

  ## Required Assigns

  - `id` - Unique identifier for the component
  - `event` - The event struct
  - `participants` - List of event participants with preloaded users
  - `current_user` - The current user struct (nil if not logged in)

  ## Usage

      <.live_component
        module={EventasaurusWeb.EventAttendeesModalComponent}
        id="event-attendees-modal"
        event={@event}
        participants={@participants}
        current_user={@current_user}
        show={@show_attendees_modal}
      />

  ## Events

  When the connect button is clicked and context is needed, this component sends
  `{:show_connect_modal, other_user, suggested_context, event}` to the parent.
  """

  use EventasaurusWeb, :live_component

  import EventasaurusWeb.Helpers.AvatarHelper

  alias EventasaurusApp.Events
  alias EventasaurusWeb.RelationshipButtonComponent

  @impl true
  def mount(socket) do
    {:ok, assign(socket, show: false)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:show, fn -> false end)
      |> assign_filtered_participants()
      |> assign_current_user_participant_status()

    {:ok, socket}
  end

  defp assign_current_user_participant_status(socket) do
    current_user = socket.assigns[:current_user]
    event = socket.assigns[:event]

    is_participant =
      cond do
        is_nil(current_user) -> false
        is_nil(event) -> false
        true -> Events.user_is_participant?(event, current_user)
      end

    assign(socket, :current_user_is_participant, is_participant)
  end

  defp assign_filtered_participants(socket) do
    participants = socket.assigns[:participants] || []
    current_user = socket.assigns[:current_user]

    # Filter out:
    # - Declined/cancelled participants
    # - The current user themselves
    # - Participants without valid user data
    filtered =
      participants
      |> Enum.filter(fn p ->
        p.user &&
          p.user.name &&
          p.status not in [:declined, :cancelled] &&
          (is_nil(current_user) || p.user.id != current_user.id)
      end)
      |> Enum.sort_by(fn p ->
        {status_priority(p.status), String.downcase(p.user.name || "")}
      end)

    assign(socket, :filtered_participants, filtered)
  end

  defp status_priority(:accepted), do: 1
  defp status_priority(:confirmed_with_order), do: 0
  defp status_priority(:interested), do: 2
  defp status_priority(:pending), do: 3
  defp status_priority(_), do: 99

  @impl true
  def handle_event("close", _params, socket) do
    send(self(), :close_attendees_modal)
    {:noreply, assign(socket, :show, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%= if @show do %>
        <!-- Modal Backdrop -->
        <div
          class="fixed inset-0 z-50 overflow-y-auto"
          aria-labelledby="attendees-modal-title"
          role="dialog"
          aria-modal="true"
        >
          <div class="flex min-h-screen items-end justify-center px-4 pt-4 pb-20 text-center sm:block sm:p-0">
            <!-- Background overlay -->
            <div
              class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"
              phx-click="close"
              phx-target={@myself}
            ></div>

            <!-- Modal panel -->
            <div class="inline-block align-bottom bg-white rounded-lg px-4 pt-5 pb-4 text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full sm:p-6">
              <!-- Header -->
              <div class="flex items-center justify-between mb-4">
                <h3 class="text-lg font-semibold text-gray-900" id="attendees-modal-title">
                  <Heroicons.users class="w-5 h-5 inline-block mr-2 text-gray-500" />
                  Who's Going
                </h3>
                <button
                  type="button"
                  phx-click="close"
                  phx-target={@myself}
                  class="text-gray-400 hover:text-gray-500 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 rounded-full p-1"
                >
                  <span class="sr-only">Close</span>
                  <Heroicons.x_mark class="h-6 w-6" />
                </button>
              </div>

              <!-- Event context -->
              <div class="mb-4 p-3 bg-gray-50 rounded-lg">
                <p class="text-sm text-gray-600">
                  <span class="font-medium"><%= @event.title %></span>
                  <%= if @event.start_at do %>
                    <span class="text-gray-400 mx-1">·</span>
                    <span><%= format_event_date(@event.start_at) %></span>
                  <% end %>
                </p>
              </div>

              <!-- Attendee list -->
              <div class="max-h-96 overflow-y-auto">
                <%= if length(@filtered_participants) == 0 do %>
                  <p class="text-center text-gray-500 py-8">
                    <%= if @current_user do %>
                      You're the only one here so far!
                    <% else %>
                      No attendees yet. Be the first to join!
                    <% end %>
                  </p>
                <% else %>
                  <ul class="divide-y divide-gray-100">
                    <%= for participant <- @filtered_participants do %>
                      <li class="py-4 flex items-center justify-between gap-4">
                        <!-- User info -->
                        <div class="flex items-center gap-3 min-w-0">
                          <.link
                            navigate={EventasaurusApp.Accounts.User.profile_url(participant.user)}
                            class="flex-shrink-0"
                          >
                            <%= avatar_img_size(participant.user, :md,
                              class: "rounded-full hover:ring-2 hover:ring-blue-300 transition-all"
                            ) %>
                          </.link>
                          <div class="min-w-0">
                            <.link
                              navigate={EventasaurusApp.Accounts.User.profile_url(participant.user)}
                              class="font-medium text-gray-900 hover:text-blue-600 truncate block"
                            >
                              <%= participant.user.name %>
                            </.link>
                            <p class="text-sm text-gray-500">
                              <%= status_label(participant.status) %>
                            </p>
                          </div>
                        </div>

                        <!-- Connect button (only for authenticated participants of the event) -->
                        <%= if @current_user && @current_user_is_participant do %>
                          <div class="flex-shrink-0">
                            <.live_component
                              module={RelationshipButtonComponent}
                              id={"connect-attendee-#{participant.user.id}"}
                              other_user={participant.user}
                              current_user={@current_user}
                              event={@event}
                              size="sm"
                              variant="primary"
                            />
                          </div>
                        <% end %>
                      </li>
                    <% end %>
                  </ul>
                <% end %>
              </div>

              <!-- Footer -->
              <%= if length(@filtered_participants) > 0 do %>
                <%= cond do %>
                  <% is_nil(@current_user) -> %>
                    <div class="mt-4 pt-4 border-t border-gray-200">
                      <p class="text-sm text-gray-600 text-center">
                        <a href="/auth/login" class="text-blue-600 hover:text-blue-800 font-medium">
                          Sign in
                        </a>
                        to stay in touch with other attendees
                      </p>
                    </div>
                  <% @current_user && !@current_user_is_participant -> %>
                    <div class="mt-4 pt-4 border-t border-gray-200">
                      <p class="text-sm text-gray-600 text-center">
                        Join this event to stay in touch with other attendees
                      </p>
                    </div>
                  <% true -> %>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_event_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%B %d, %Y")
  end

  defp format_event_date(%NaiveDateTime{} = ndt) do
    Calendar.strftime(ndt, "%B %d, %Y")
  end

  defp format_event_date(_), do: ""

  defp status_label(:accepted), do: "Going"
  defp status_label(:confirmed_with_order), do: "Confirmed"
  defp status_label(:interested), do: "Interested"
  defp status_label(:pending), do: "Pending"
  defp status_label(_), do: ""
end
