defmodule EventasaurusWeb.ConnectWithContextModalComponent do
  @moduledoc """
  A modal component for adding context when connecting with another user.

  This component is triggered when a user wants to connect with another user.
  It prompts for context about how they know each other, with optional
  suggested context based on shared events.

  ## Features

  - Text input for relationship context
  - Pre-filled suggestion based on shared event
  - Quick context options for common scenarios
  - Validates context is not empty
  - Loading state during connection creation

  ## Required Assigns

  - `id` - Unique identifier for the component
  - `other_user` - The user to connect with
  - `current_user` - The current logged-in user
  - `show` - Whether the modal is visible

  ## Optional Assigns

  - `suggested_context` - Pre-filled context suggestion
  - `event` - The event where they met (for event-based connections)

  ## Events

  When the user submits, this component sends the context back to the parent
  and triggers the relationship creation through the RelationshipButtonComponent.
  """

  use EventasaurusWeb, :live_component

  import EventasaurusWeb.Helpers.AvatarHelper

  alias EventasaurusApp.Events
  alias EventasaurusApp.Relationships

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:show, false)
     |> assign(:loading, false)
     |> assign(:error, nil)
     |> assign(:context, "")}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:show, fn -> false end)
      |> assign_new(:suggested_context, fn -> "" end)
      |> assign_new(:event, fn -> nil end)
      |> assign_new(:loading, fn -> false end)
      |> assign_new(:error, fn -> nil end)

    # Pre-fill context with suggestion if it's a fresh open
    socket =
      if assigns[:show] && !socket.assigns[:show] do
        assign(socket, :context, assigns[:suggested_context] || "")
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("close", _params, socket) do
    send(self(), :close_connect_modal)
    {:noreply, assign(socket, show: false, context: "", error: nil)}
  end

  @impl true
  def handle_event("update_context", %{"context" => context}, socket) do
    {:noreply, assign(socket, :context, context)}
  end

  @impl true
  def handle_event("use_suggestion", %{"suggestion" => suggestion}, socket) do
    {:noreply, assign(socket, :context, suggestion)}
  end

  @impl true
  def handle_event("connect", _params, socket) do
    context = String.trim(socket.assigns.context)

    if context == "" do
      {:noreply, assign(socket, :error, "Please add some context about how you know each other")}
    else
      socket = assign(socket, loading: true, error: nil)

      current_user = socket.assigns.current_user
      other_user = socket.assigns.other_user
      event = socket.assigns.event

      # Validate both users are participants of the event
      cond do
        is_nil(event) ->
          # No event context - allow manual relationship (this shouldn't happen in attendees modal)
          create_relationship(socket, current_user, other_user, nil, context)

        not Events.user_is_participant?(event, current_user) ->
          {:noreply,
           assign(socket,
             loading: false,
             error: "You must be attending this event to stay in touch with other attendees"
           )}

        not Events.user_is_participant?(event, other_user) ->
          {:noreply,
           assign(socket,
             loading: false,
             error: "#{other_user.name} is not attending this event"
           )}

        true ->
          # Both users are participants - allow relationship creation
          create_relationship(socket, current_user, other_user, event, context)
      end
    end
  end

  defp create_relationship(socket, current_user, other_user, event, context) do
    result =
      if event do
        Relationships.create_from_shared_event(current_user, other_user, event, context)
      else
        Relationships.create_manual(current_user, other_user, context)
      end

    case result do
      {:ok, {_relationship, _reverse}} ->
        # Notify parent of success
        send(self(), {:connection_created, other_user})

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:show, false)
         |> assign(:context, "")
         |> assign(:error, nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        error_message = format_changeset_error(changeset)
        {:noreply, assign(socket, loading: false, error: error_message)}

      {:error, _reason} ->
        {:noreply, assign(socket, loading: false, error: "Could not connect. Please try again.")}
    end
  end

  defp format_changeset_error(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%= if @show do %>
        <!-- Modal Backdrop -->
        <div
          class="fixed inset-0 z-50 overflow-y-auto"
          aria-labelledby="connect-modal-title"
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
            <div class="inline-block align-bottom bg-white rounded-lg px-4 pt-5 pb-4 text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-md sm:w-full sm:p-6">
              <!-- Header -->
              <div class="flex items-center justify-between mb-4">
                <h3 class="text-lg font-semibold text-gray-900" id="connect-modal-title">
                  <Heroicons.user_plus class="w-5 h-5 inline-block mr-2 text-teal-500" />
                  Stay in touch with <%= @other_user.name %>
                </h3>
                <button
                  type="button"
                  phx-click="close"
                  phx-target={@myself}
                  class="text-gray-400 hover:text-gray-500 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-teal-500 rounded-full p-1"
                >
                  <span class="sr-only">Close</span>
                  <Heroicons.x_mark class="h-6 w-6" />
                </button>
              </div>

              <!-- User preview -->
              <div class="flex items-center gap-3 mb-6 p-3 bg-gray-50 rounded-lg">
                <%= avatar_img_size(@other_user, :lg, class: "rounded-full") %>
                <div>
                  <p class="font-medium text-gray-900"><%= @other_user.name %></p>
                  <%= if @event do %>
                    <p class="text-sm text-gray-500">
                      via <%= @event.title %>
                    </p>
                  <% end %>
                </div>
              </div>

              <!-- Context input -->
              <div class="mb-4">
                <label for="context-input" class="block text-sm font-medium text-gray-700 mb-2">
                  How do you know each other?
                </label>
                <textarea
                  id="context-input"
                  name="context"
                  rows="2"
                  phx-change="update_context"
                  phx-target={@myself}
                  value={@context}
                  placeholder="e.g., Met at Jazz Night, Friends from work..."
                  class="block w-full rounded-md border-gray-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
                  disabled={@loading}
                ><%= @context %></textarea>

                <%= if @error do %>
                  <p class="mt-2 text-sm text-red-600"><%= @error %></p>
                <% end %>
              </div>

              <!-- Quick suggestions -->
              <div class="mb-6">
                <p class="text-xs text-gray-500 mb-2">Quick options:</p>
                <div class="flex flex-wrap gap-2">
                  <%= if @suggested_context && @suggested_context != "" do %>
                    <button
                      type="button"
                      phx-click="use_suggestion"
                      phx-value-suggestion={@suggested_context}
                      phx-target={@myself}
                      class="inline-flex items-center px-3 py-1 rounded-full text-sm bg-teal-50 text-teal-700 hover:bg-teal-100 border border-teal-200"
                      disabled={@loading}
                    >
                      <Heroicons.sparkles class="w-3 h-3 mr-1" />
                      <%= @suggested_context %>
                    </button>
                  <% end %>
                  <button
                    type="button"
                    phx-click="use_suggestion"
                    phx-value-suggestion="Friends"
                    phx-target={@myself}
                    class="inline-flex items-center px-3 py-1 rounded-full text-sm bg-gray-100 text-gray-700 hover:bg-gray-200"
                    disabled={@loading}
                  >
                    Friends
                  </button>
                  <button
                    type="button"
                    phx-click="use_suggestion"
                    phx-value-suggestion="Colleagues"
                    phx-target={@myself}
                    class="inline-flex items-center px-3 py-1 rounded-full text-sm bg-gray-100 text-gray-700 hover:bg-gray-200"
                    disabled={@loading}
                  >
                    Colleagues
                  </button>
                  <button
                    type="button"
                    phx-click="use_suggestion"
                    phx-value-suggestion="Met at an event"
                    phx-target={@myself}
                    class="inline-flex items-center px-3 py-1 rounded-full text-sm bg-gray-100 text-gray-700 hover:bg-gray-200"
                    disabled={@loading}
                  >
                    Met at an event
                  </button>
                </div>
              </div>

              <!-- Actions -->
              <div class="flex justify-end gap-3">
                <button
                  type="button"
                  phx-click="close"
                  phx-target={@myself}
                  class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-teal-500"
                  disabled={@loading}
                >
                  Cancel
                </button>
                <button
                  type="button"
                  phx-click="connect"
                  phx-target={@myself}
                  class="inline-flex items-center px-4 py-2 text-sm font-medium text-white bg-teal-600 border border-transparent rounded-md hover:bg-teal-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-teal-500 disabled:opacity-50 disabled:cursor-not-allowed"
                  disabled={@loading || String.trim(@context) == ""}
                >
                  <%= if @loading do %>
                    <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white" fill="none" viewBox="0 0 24 24">
                      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    Saving...
                  <% else %>
                    <Heroicons.user_plus class="w-4 h-4 mr-2" />
                    Add to my people
                  <% end %>
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
