defmodule EventasaurusWeb.Components.Invitations.InvitationMessageComponent do
  @moduledoc """
  Component for composing personalized invitation messages.
  Includes character count and template suggestions.
  """
  use EventasaurusWeb, :live_component

  @max_length 500
  @templates [
    {"Casual", "Hi! I'd love for you to join me at this event. It's going to be fun!"},
    {"Formal", "You're cordially invited to join us for this special event. We would be delighted to have you attend."},
    {"Excited", "Hey! I found this amazing event and immediately thought of you. Let's go together!"},
    {"Group", "Hey everyone! Let's all go to this event together. It'll be a great time to catch up!"}
  ]

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:message, "")
     |> assign(:show_templates, false)
     |> assign(:char_count, 0)
     |> assign(:max_length, @max_length)
     |> assign(:templates, @templates)}
  end

  @impl true
  def update(assigns, socket) do
    message = assigns[:invitation_message] || ""

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:message, message)
     |> assign(:char_count, String.length(message))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="invitation-message-component">
      <div class="mb-4">
        <div class="flex justify-between items-center mb-2">
          <label for={@id <> "_message"} class="block text-sm font-medium text-gray-700">
            Personal message (optional)
          </label>
          <button
            type="button"
            phx-target={@myself}
            phx-click="toggle_templates"
            class="text-xs text-green-600 hover:text-green-700 font-medium"
          >
            <%= if @show_templates do %>
              Hide templates ↑
            <% else %>
              Use template ↓
            <% end %>
          </button>
        </div>

        <%= if @show_templates do %>
          <div class="mb-3 p-3 bg-gray-50 rounded-lg">
            <p class="text-xs text-gray-600 mb-2">Choose a template:</p>
            <div class="space-y-2">
              <%= for {name, template} <- @templates do %>
                <button
                  type="button"
                  phx-target={@myself}
                  phx-click="use_template"
                  phx-value-template={template}
                  class="w-full text-left p-2 text-sm bg-white border border-gray-200 rounded hover:bg-gray-50 transition-colors"
                >
                  <span class="font-medium text-gray-700"><%= name %>:</span>
                  <span class="text-gray-600 text-xs block mt-1"><%= template %></span>
                </button>
              <% end %>
            </div>
          </div>
        <% end %>

        <p class="text-sm text-gray-500 mb-2">
          Add a personal note to your invitation
        </p>
        <div class="relative">
          <textarea
            id={@id <> "_message"}
            name="message"
            rows="4"
            value={@message}
            phx-target={@myself}
            phx-change="update_message"
            maxlength={@max_length}
            placeholder="Hi! I'd love for you to join me at this event..."
            class={[
              "w-full px-3 py-2 border rounded-md focus:outline-none focus:ring-2 focus:ring-green-500",
              @char_count > @max_length * 0.9 && "border-yellow-300"
            ]}
          />
          <div class="absolute bottom-2 right-2 text-xs text-gray-400">
            <%= @char_count %>/<%= @max_length %>
          </div>
        </div>
        <%= if @char_count > @max_length * 0.9 do %>
          <p class="mt-1 text-xs text-yellow-600">
            Message is getting long. Keep it concise!
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("update_message", %{"message" => message}, socket) do
    # Truncate if over max length
    message = String.slice(message, 0, @max_length)

    # Send update to parent
    send(self(), {:message_updated, message})

    {:noreply,
     socket
     |> assign(:message, message)
     |> assign(:char_count, String.length(message))}
  end

  @impl true
  def handle_event("toggle_templates", _, socket) do
    {:noreply, assign(socket, :show_templates, !socket.assigns.show_templates)}
  end

  @impl true
  def handle_event("use_template", %{"template" => template}, socket) do
    send(self(), {:message_updated, template})

    {:noreply,
     socket
     |> assign(:message, template)
     |> assign(:char_count, String.length(template))
     |> assign(:show_templates, false)}
  end
end