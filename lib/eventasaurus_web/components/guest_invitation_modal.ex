defmodule EventasaurusWeb.Components.GuestInvitationModal do
  use EventasaurusWeb, :html
  import EventasaurusWeb.CoreComponents
  import EventasaurusWeb.Components.IndividualEmailInput
  alias EventasaurusWeb.Utils.TimeUtils

  @doc """
  Renders a guest invitation modal with toggle between invitation and direct add modes.

  ## Examples

      <.guest_invitation_modal
        id="guest-invitation-modal"
        show={@show_guest_invitation_modal}
        event={@event}
        organizer={@user}
        suggestions={@historical_suggestions}
        suggestions_loading={@suggestions_loading}
        invitation_message={@invitation_message}
        manual_emails={@manual_emails}
        add_mode={@add_mode}
        on_close="close_guest_invitation_modal"
        on_mode_change="toggle_add_mode"
        on_invite_selected="send_invitations"
        on_add_directly="add_guests_directly"
      />
  """

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :event, :map, required: true
  attr :organizer, :map, required: true
  attr :suggestions, :list, default: []
  attr :suggestions_loading, :boolean, default: false
  attr :invitation_message, :string, default: ""
  attr :manual_emails, :list, default: []
  attr :current_email_input, :string, default: ""
  attr :bulk_email_input, :string, default: ""
  attr :selected_suggestions, :list, default: []
  # "invite" or "direct"
  attr :add_mode, :string, default: "invite"
  attr :on_close, :any, required: true
  attr :on_invite_selected, :any, default: nil
  attr :on_add_directly, :any, default: nil
  attr :on_search_suggestions, :any, default: nil
  attr :on_mode_change, :any, default: nil

  def guest_invitation_modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div
        id={"#{@id}-overlay"}
        class="fixed inset-0 bg-black bg-opacity-50 z-50 flex items-center justify-center p-4"
        phx-window-keydown={@on_close}
        phx-key="escape"
        phx-click={@on_close}
      >
        <div
          id={"#{@id}-container"}
          class="bg-white rounded-xl max-w-4xl w-full max-h-[90vh] flex flex-col shadow-2xl"
          phx-click-away={@on_close}
          phx-click="stop_propagation"
        >
          <!-- Modal Header -->
          <div class="flex items-center justify-between p-6 border-b border-gray-200">
            <div>
              <h2 class="text-xl font-semibold text-gray-900">
                <%= if @add_mode == "direct", do: "Add Guests", else: "Invite Guests" %>
              </h2>
              <p class="text-sm text-gray-500 mt-1">
                <%= if @add_mode == "direct" do %>
                  Add people directly to <%= @event.title %>
                <% else %>
                  Send invitations to people for <%= @event.title %>
                <% end %>
              </p>
            </div>
            <button
              type="button"
              phx-click={@on_close}
              class="text-gray-400 hover:text-gray-600 transition-colors p-2 rounded-lg hover:bg-gray-100"
              aria-label="Close modal"
            >
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <!-- Modal Content -->
          <div class="flex-1 overflow-y-auto">
            <div class="p-6 space-y-6">

              <!-- Mode Toggle -->
              <%= if @on_mode_change do %>
                <div class="flex items-center justify-center">
                  <div class="bg-gray-100 p-1 rounded-lg flex">
                    <button
                      type="button"
                      phx-click={@on_mode_change}
                      phx-value-mode="invite"
                      class={[
                        "px-4 py-2 text-sm font-medium rounded-md transition-colors",
                        if(@add_mode == "invite", do: "bg-white text-gray-900 shadow-sm", else: "text-gray-500 hover:text-gray-700")
                      ]}
                    >
                      📧 Send Invitations
                    </button>
                    <button
                      type="button"
                      phx-click={@on_mode_change}
                      phx-value-mode="direct"
                      class={[
                        "px-4 py-2 text-sm font-medium rounded-md transition-colors",
                        if(@add_mode == "direct", do: "bg-white text-gray-900 shadow-sm", else: "text-gray-500 hover:text-gray-700")
                      ]}
                    >
                      ➕ Add Directly
                    </button>
                  </div>
                </div>

                <!-- Mode Description -->
                <div class="text-center">
                  <%= if @add_mode == "direct" do %>
                    <div class="bg-green-50 border border-green-200 rounded-lg p-4">
                      <div class="flex items-center justify-center space-x-2">
                        <svg class="w-5 h-5 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                        </svg>
                        <span class="text-sm font-medium text-green-800">Direct Add Mode</span>
                      </div>
                      <p class="text-sm text-green-700 mt-1">
                        Users will be added directly to your event without sending email invitations.
                      </p>
                    </div>
                  <% else %>
                    <div class="bg-blue-50 border border-blue-200 rounded-lg p-4">
                      <div class="flex items-center justify-center space-x-2">
                        <svg class="w-5 h-5 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 4.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                        </svg>
                        <span class="text-sm font-medium text-blue-800">Invitation Mode</span>
                      </div>
                      <p class="text-sm text-blue-700 mt-1">
                        Email invitations will be sent to selected users with your personal message.
                      </p>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <!-- Historical Participant Suggestions -->
              <div>
                <div class="flex items-center justify-between mb-4">
                  <div>
                    <h3 class="text-lg font-medium text-gray-900">People from your past events</h3>
                    <p class="text-sm text-gray-500">
                      <%= if @add_mode == "direct" do %>
                        Select people to add directly to your event
                      <% else %>
                        Select people who have attended your previous events
                      <% end %>
                    </p>
                  </div>
                  <%= if @on_search_suggestions do %>
                    <button
                      type="button"
                      phx-click={@on_search_suggestions}
                      class="text-sm text-blue-600 hover:text-blue-700 font-medium"
                      disabled={@suggestions_loading}
                    >
                      <%= if @suggestions_loading, do: "Loading...", else: "Refresh suggestions" %>
                    </button>
                  <% end %>
                </div>

                <%= if @suggestions_loading do %>
                  <!-- Loading State -->
                  <div class="flex justify-center py-8">
                    <div class="w-8 h-8 border-t-2 border-b-2 border-blue-500 rounded-full animate-spin"></div>
                  </div>
                <% end %>

                <%= if not @suggestions_loading and length(@suggestions) > 0 do %>
                  <!-- Suggestions List -->
                  <div class="bg-gray-50 rounded-lg border border-gray-200 max-h-60 overflow-y-auto">
                    <%= for suggestion <- @suggestions do %>
                      <div class="flex items-center justify-between p-3 border-b border-gray-200 last:border-0 hover:bg-gray-100">
                        <div class="flex items-center space-x-3">
                          <input
                            type="checkbox"
                            id={"suggestion-#{suggestion.user_id}"}
                            name="selected_suggestions[]"
                            value={suggestion.user_id}
                            checked={suggestion.user_id in @selected_suggestions}
                            class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
                            phx-click="toggle_suggestion"
                            phx-value-user_id={suggestion.user_id}
                          />
                          <!-- User Avatar -->
                          <div class="flex-shrink-0">
                            <img
                              src={get_user_avatar_url(suggestion)}
                              alt={"#{suggestion.name} avatar"}
                              class="h-10 w-10 rounded-full object-cover"
                            />
                          </div>
                          <div class="flex-1">
                            <div class="flex items-center space-x-2">
                              <label for={"suggestion-#{suggestion.user_id}"} class="font-medium text-gray-900 cursor-pointer">
                                <%= suggestion.name %>
                              </label>
                              <%= if suggestion.recommendation_level != :suggested do %>
                                <span class={[
                                  "inline-flex items-center px-2 py-1 rounded-full text-xs font-medium",
                                  case suggestion.recommendation_level do
                                    :highly_recommended -> "bg-green-100 text-green-800"
                                    :recommended -> "bg-blue-100 text-blue-800"
                                    _ -> "bg-gray-100 text-gray-800"
                                  end
                                ]}>
                                  <%= String.replace(to_string(suggestion.recommendation_level), "_", " ") |> String.capitalize() %>
                                </span>
                              <% end %>
                            </div>
                            <div class="text-sm text-gray-500">
                              <%= suggestion.email %>
                              • Attended <%= suggestion.participation_count %> events
                              <%= if suggestion.last_participation do %>
                                • Last event <%= DateTime.diff(DateTime.utc_now(), suggestion.last_participation, :day) %> days ago
                              <% end %>
                            </div>
                          </div>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% end %>

                <%= if not @suggestions_loading and length(@suggestions) == 0 do %>
                  <!-- No Suggestions State -->
                  <div class="text-center py-8 bg-gray-50 rounded-lg border border-gray-200">
                    <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM9 5a2 2 0 11-4 0 2 2 0 014 0z" />
                    </svg>
                    <h3 class="mt-2 text-sm font-medium text-gray-900">No previous attendees found</h3>
                    <p class="mt-1 text-sm text-gray-500">
                      People from your past events will appear here for easy re-invitation.
                    </p>
                  </div>
                <% end %>
              </div>

              <!-- Individual Email Entry -->
              <div>
                <div class="mb-4">
                  <h3 class="text-lg font-medium text-gray-900">
                    <%= if @add_mode == "direct", do: "Add by email", else: "Invite by email" %>
                  </h3>
                  <p class="text-sm text-gray-500">Add email addresses one by one</p>
                </div>

                <.individual_email_input
                  id="manual-email-input"
                  emails={@manual_emails}
                  current_input={@current_email_input}
                  bulk_input={@bulk_email_input}
                  on_add_email="add_email"
                  on_remove_email="remove_email"
                  on_input_change="email_input_change"
                  placeholder="Enter email address"
                />
              </div>

              <!-- Invitation Message (only in invite mode) -->
              <%= if @add_mode == "invite" do %>
                <div>
                  <div class="mb-4">
                    <h3 class="text-lg font-medium text-gray-900">Personal message (optional)</h3>
                    <p class="text-sm text-gray-500">Add a personal note to your invitation</p>
                  </div>

                  <.input
                    type="textarea"
                    name="invitation_message"
                    value={@invitation_message}
                    placeholder="Hi! I'd love for you to join me at this event..."
                    rows="3"
                    class="block w-full"
                    phx-change="invitation_message"
                    phx-debounce="300"
                  />
                </div>

                <!-- Email Preview Section (Mock) -->
                <div>
                  <div class="mb-4">
                    <h3 class="text-lg font-medium text-gray-900">Email preview</h3>
                    <p class="text-sm text-gray-500">Here's what your invitation will look like</p>
                  </div>

                  <div class="bg-white border border-gray-200 rounded-lg p-4 max-h-60 overflow-y-auto shadow-sm">
                    <div class="space-y-3">
                      <!-- Email Header -->
                      <div class="text-sm text-gray-500 border-b border-gray-100 pb-2">
                        <div class="flex justify-between">
                          <span><strong>From:</strong> <%= @organizer.name %> &lt;<%= @organizer.email %>&gt;</span>
                        </div>
                        <div><strong>Subject:</strong> You're invited to <%= @event.title %></div>
                      </div>

                      <!-- Email Content -->
                      <div class="prose prose-sm max-w-none">
                        <p>Hi there,</p>

                        <%= if @invitation_message && String.trim(@invitation_message) != "" do %>
                          <div class="bg-blue-50 border-l-4 border-blue-200 p-3 my-3">
                            <p class="text-gray-700 italic"><%= @invitation_message %></p>
                          </div>
                        <% end %>

                        <p>You're invited to join:</p>

                        <div class="bg-gray-50 border border-gray-200 rounded-lg p-4 my-4">
                          <h4 class="font-semibold text-gray-900 mb-2"><%= @event.title %></h4>
                          <%= if @event.tagline do %>
                            <p class="text-gray-600 mb-2"><%= @event.tagline %></p>
                          <% end %>
                          <div class="text-sm text-gray-500">
                            <div>📅 Date: <%= if @event.start_at, do: "#{Calendar.strftime(@event.start_at, "%A, %B %d, %Y")} at #{TimeUtils.format_time(@event.start_at)}", else: "To be announced" %></div>
                            <%= if @event.venue do %>
                              <div>📍 Location: <%= @event.venue.name %></div>
                            <% end %>
                          </div>
                        </div>

                        <p>
                          <strong>👉 <a href="#" class="text-blue-600 underline">Click here to view details and RSVP</a></strong>
                        </p>

                        <p class="text-sm text-gray-500">
                          This invitation was sent by <%= @organizer.name %> via Eventasaurus.
                        </p>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Modal Footer -->
          <div class="flex items-center justify-between px-6 py-4 border-t border-gray-200 bg-gray-50">
            <div class="text-sm text-gray-500">
              <span id="invitation-count"><%= calculate_invitation_count(@selected_suggestions, @manual_emails) %></span>
              <%= if @add_mode == "direct", do: "people will be added", else: "people will be invited" %>
            </div>
            <div class="flex space-x-3">
              <button
                type="button"
                phx-click={@on_close}
                class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
              >
                Cancel
              </button>

              <%= if @add_mode == "direct" do %>
                <%= if @on_add_directly do %>
                  <button
                    type="button"
                    phx-click={@on_add_directly}
                    class="px-4 py-2 text-sm font-medium text-white bg-green-600 border border-transparent rounded-md hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                    disabled={length(@selected_suggestions) == 0 && length(@manual_emails) == 0}
                  >
                    ➕ Add to Event
                  </button>
                <% end %>
              <% else %>
                <%= if @on_invite_selected do %>
                  <button
                    type="button"
                    phx-click={@on_invite_selected}
                    class="px-4 py-2 text-sm font-medium text-white bg-blue-600 border border-transparent rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                    disabled={length(@selected_suggestions) == 0 && length(@manual_emails) == 0}
                  >
                    📧 Send Invitations
                  </button>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </div>


    <% end %>
    """
  end

  # Helper function to calculate invitation count server-side
  defp calculate_invitation_count(selected_suggestions, manual_emails) do
    selected_count = length(selected_suggestions || [])
    email_count = length(manual_emails || [])
    selected_count + email_count
  end

  # Helper function to generate user avatar URL using dicebear
  defp get_user_avatar_url(user, size \\ 40) do
    EventasaurusApp.Avatars.generate_user_avatar(user, size: size)
  end
end
