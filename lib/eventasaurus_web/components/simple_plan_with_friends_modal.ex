defmodule EventasaurusWeb.Components.SimplePlanWithFriendsModal do
  @moduledoc """
  A simplified modal for creating private events from public events.
  This is a minimal implementation that just works without complex dependencies.
  """
  use Phoenix.Component

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :public_event, :map, required: true
  attr :emails_input, :string, default: ""
  attr :invitation_message, :string, default: ""
  attr :on_close, :string, default: "close_plan_modal"
  attr :on_submit, :string, default: "submit_plan_with_friends"

  def modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div
        id={@id}
        class="fixed inset-0 z-50 overflow-y-auto"
        phx-window-keydown={@on_close}
        phx-key="escape"
      >
        <!-- Backdrop -->
        <div class="fixed inset-0 bg-black bg-opacity-50" phx-click={@on_close}></div>

        <!-- Modal Content -->
        <div class="relative min-h-screen flex items-center justify-center p-4">
          <div class="relative bg-white rounded-lg max-w-2xl w-full p-6" phx-click-away={@on_close}>
            <!-- Header -->
            <div class="mb-6">
              <h2 class="text-2xl font-bold text-gray-900">
                Plan with Friends
              </h2>
              <p class="mt-2 text-gray-600">
                Create a private event for '<%= @public_event.title %>' and invite your friends
              </p>
              <button
                type="button"
                phx-click={@on_close}
                class="absolute top-6 right-6 text-gray-400 hover:text-gray-500"
              >
                <span class="sr-only">Close</span>
                <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

            <!-- Form -->
            <form phx-submit={@on_submit}>
              <!-- Email Input -->
              <div class="mb-6">
                <label for="emails" class="block text-sm font-medium text-gray-700 mb-2">
                  Email addresses
                </label>
                <p class="text-sm text-gray-500 mb-2">
                  Enter email addresses separated by commas
                </p>
                <textarea
                  id="emails"
                  name="emails"
                  rows="3"
                  value={@emails_input}
                  phx-change="update_emails"
                  placeholder="friend1@example.com, friend2@example.com"
                  class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-green-500"
                />
              </div>

              <!-- Invitation Message -->
              <div class="mb-6">
                <label for="message" class="block text-sm font-medium text-gray-700 mb-2">
                  Personal message (optional)
                </label>
                <p class="text-sm text-gray-500 mb-2">
                  Add a personal note to your invitation
                </p>
                <textarea
                  id="message"
                  name="message"
                  rows="4"
                  value={@invitation_message}
                  phx-change="update_message"
                  placeholder="Hi! I'd love for you to join me at this event..."
                  class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-green-500"
                />
              </div>

              <!-- Event Details Preview -->
              <div class="mb-6 p-4 bg-gray-50 rounded-lg">
                <h3 class="font-medium text-gray-900 mb-2">
                  Event Details
                </h3>
                <p class="text-sm text-gray-600">
                  <strong>Event:</strong> <%= @public_event.title %>
                </p>
                <%= if @public_event.starts_at do %>
                  <p class="text-sm text-gray-600">
                    <strong>Date:</strong>
                    <%= Calendar.strftime(@public_event.starts_at, "%B %d, %Y at %I:%M %p") %>
                  </p>
                <% end %>
              </div>

              <!-- Actions -->
              <div class="flex justify-end gap-4">
                <button
                  type="button"
                  phx-click={@on_close}
                  class="px-4 py-2 text-gray-700 bg-gray-200 rounded-md hover:bg-gray-300"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="px-4 py-2 text-white bg-green-600 rounded-md hover:bg-green-700"
                >
                  Create Private Event & Send Invites
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
