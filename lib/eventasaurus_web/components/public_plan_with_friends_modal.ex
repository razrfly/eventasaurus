defmodule EventasaurusWeb.Components.PublicPlanWithFriendsModal do
  @moduledoc """
  Enhanced modal for creating private events from public events.
  Uses shared components and supports both user selection and email invitations.
  Does NOT include direct add functionality (invitation only).
  """
  use Phoenix.Component
  import EventasaurusWeb.Helpers.PublicEventDisplayHelpers

  alias EventasaurusWeb.Components.Invitations.{
    HistoricalParticipantsComponent,
    SelectedParticipantsComponent,
    InvitationMessageComponent
  }

  import EventasaurusWeb.Components.IndividualEmailInput

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :public_event, :map, required: true
  attr :selected_occurrence, :map, default: nil
  attr :selected_users, :list, default: []
  attr :selected_emails, :list, default: []
  attr :current_email_input, :string, default: ""
  attr :bulk_email_input, :string, default: ""
  attr :invitation_message, :string, default: ""
  attr :organizer, :map, required: true
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
          <div class="relative bg-white rounded-lg max-w-3xl w-full max-h-[90vh] overflow-hidden" phx-click-away={@on_close}>
            <!-- Header -->
            <div class="sticky top-0 bg-white border-b border-gray-200 px-6 py-4 z-10">
              <div class="flex items-center justify-between">
                <div>
                  <h2 class="text-2xl font-bold text-gray-900">
                    Plan with Friends
                  </h2>
                  <p class="mt-1 text-sm text-gray-600">
                    Create a private event for '<%= @public_event.title %>' and invite your friends
                  </p>
                </div>
                <button
                  type="button"
                  phx-click={@on_close}
                  class="text-gray-400 hover:text-gray-500"
                >
                  <span class="sr-only">Close</span>
                  <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
            </div>

            <!-- Form Content (Scrollable) -->
            <div class="overflow-y-auto max-h-[calc(90vh-140px)] px-6 py-4">
              <form phx-submit={@on_submit} class="space-y-6">
                <!-- Historical Participants -->
                <.live_component
                  module={HistoricalParticipantsComponent}
                  id={@id <> "_historical"}
                  organizer={@organizer}
                  selected_users={@selected_users}
                  exclude_event_ids={[@public_event.id]}
                  display_mode="list"
                />

                <!-- Unified Email Input -->
                <div class="border-t pt-6">
                  <div class="mb-4">
                    <h3 class="text-lg font-medium text-gray-900">Invite friends and contacts</h3>
                    <p class="text-sm text-gray-500">Add email addresses to invite people to this event</p>
                  </div>

                  <.individual_email_input
                    id="unified-email-input"
                    emails={@selected_emails}
                    current_input={@current_email_input}
                    bulk_input={@bulk_email_input}
                    on_add_email="add_email"
                    on_remove_email="remove_email"
                    on_input_change="email_input_change"
                    placeholder="Enter email address"
                  />
                </div>

                <!-- Selected Participants -->
                <div class="border-t pt-6">
                  <.live_component
                    module={SelectedParticipantsComponent}
                    id={@id <> "_selected"}
                    selected_users={@selected_users}
                    selected_emails={@selected_emails}
                  />
                </div>

                <!-- Invitation Message -->
                <div class="border-t pt-6">
                  <.live_component
                    module={InvitationMessageComponent}
                    id={@id <> "_message"}
                    invitation_message={@invitation_message}
                  />
                </div>

                <!-- Event Details Preview -->
                <div class="border-t pt-6">
                  <div class="p-4 bg-gray-50 rounded-lg">
                    <h3 class="font-medium text-gray-900 mb-2">
                      Event Details
                    </h3>
                    <p class="text-sm text-gray-600">
                      <strong>Event:</strong> <%= @public_event.title %>
                    </p>
                    <p class="text-sm text-gray-600">
                      <strong>Date:</strong>
                      <%= if @selected_occurrence do %>
                        <%= format_occurrence_datetime(@selected_occurrence) %>
                      <% else %>
                        <%= format_local_datetime(@public_event.starts_at, @public_event.venue, :full) %>
                      <% end %>
                    </p>
                    <%= if @public_event.venue do %>
                      <p class="text-sm text-gray-600">
                        <strong>Location:</strong> <%= @public_event.venue.name %>
                      </p>
                    <% end %>
                  </div>
                </div>

                <!-- Actions -->
                <div class="flex justify-end gap-4 pt-4 border-t">
                  <button
                    type="button"
                    phx-click={@on_close}
                    class="px-4 py-2 text-gray-700 bg-gray-200 rounded-md hover:bg-gray-300"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={!has_participants?(assigns)}
                    class={[
                      "px-4 py-2 rounded-md",
                      if(has_participants?(assigns),
                        do: "text-white bg-green-600 hover:bg-green-700",
                        else: "text-gray-400 bg-gray-100 cursor-not-allowed"
                      )
                    ]}
                  >
                    <%= if has_participants?(assigns) do %>
                      Create Private Event & Send Invites (<%= participant_count(assigns) %>)
                    <% else %>
                      Select participants to continue
                    <% end %>
                  </button>
                </div>
              </form>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # Helper functions

  defp has_participants?(assigns) do
    user_count = length(assigns[:selected_users] || [])
    email_count = length(assigns[:selected_emails] || [])
    user_count + email_count > 0
  end

  defp participant_count(assigns) do
    length(assigns[:selected_users] || []) + length(assigns[:selected_emails] || [])
  end

  defp format_occurrence_datetime(%{datetime: datetime}) do
    Calendar.strftime(datetime, "%B %d, %Y at %I:%M %p")
  end

  defp format_occurrence_datetime(_), do: "TBD"
end
