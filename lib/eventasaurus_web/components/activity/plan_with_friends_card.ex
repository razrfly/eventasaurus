defmodule EventasaurusWeb.Components.Activity.PlanWithFriendsCard do
  @moduledoc """
  Sidebar component for the "Plan with Friends" social planning CTA.

  Displays a card encouraging users to create a private event for group planning.
  Handles different states: logged out, new plan, existing plan, past event.
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext

  alias EventasaurusWeb.Helpers.SourceAttribution

  @doc """
  Renders the plan with friends card for the sidebar.

  ## Attributes

    * `:existing_plan` - The user's existing plan for this event (or nil).
    * `:is_past_event` - Whether the event has already occurred.
    * `:class` - Optional. Additional CSS classes for the container.

  ## Examples

      <PlanWithFriendsCard.plan_with_friends_card
        existing_plan={@existing_plan}
        is_past_event={false}
      />
  """
  attr :existing_plan, :map, default: nil
  attr :is_past_event, :boolean, default: false
  attr :class, :string, default: ""

  def plan_with_friends_card(assigns) do
    ~H"""
    <%= unless @is_past_event do %>
      <div class={[
        "bg-gradient-to-br from-indigo-50 to-purple-50 rounded-xl border border-indigo-100 p-5",
        @class
      ]}>
        <%= if @existing_plan do %>
          <!-- Existing Plan State -->
          <div class="flex items-start gap-3 mb-4">
            <div class="flex-shrink-0 w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
              <Heroicons.check_circle class="w-5 h-5 text-green-600" />
            </div>
            <div>
              <h3 class="font-semibold text-gray-900">
                <%= gettext("You have a plan!") %>
              </h3>
              <p class="text-sm text-gray-600 mt-0.5">
                <%= gettext("Created %{date}", date: format_plan_date(@existing_plan.inserted_at)) %>
              </p>
            </div>
          </div>

          <button
            phx-click="view_existing_plan"
            class="w-full inline-flex items-center justify-center px-4 py-2.5 bg-indigo-600 text-white font-medium rounded-lg hover:bg-indigo-700 transition-colors"
          >
            <Heroicons.eye class="w-5 h-5 mr-2" />
            <%= gettext("View Your Event") %>
          </button>
        <% else %>
          <!-- New Plan State -->
          <div class="flex items-start gap-3 mb-4">
            <div class="flex-shrink-0 w-10 h-10 bg-indigo-100 rounded-lg flex items-center justify-center">
              <Heroicons.user_group class="w-5 h-5 text-indigo-600" />
            </div>
            <div>
              <h3 class="font-semibold text-gray-900">
                <%= gettext("Planning a night out?") %>
              </h3>
              <p class="text-sm text-gray-600 mt-0.5">
                <%= gettext("Coordinate with friends to pick the best time.") %>
              </p>
            </div>
          </div>

          <button
            id="plan-with-friends-btn"
            phx-hook="AuthProtectedAction"
            data-auth-event="open_plan_modal"
            data-auth-redirect="/auth/login"
            class="w-full inline-flex items-center justify-center px-4 py-2.5 bg-indigo-600 text-white font-medium rounded-lg hover:bg-indigo-700 transition-colors"
          >
            <Heroicons.user_group class="w-5 h-5 mr-2" />
            <%= gettext("Plan with Friends") %>
          </button>
        <% end %>
      </div>
    <% end %>
    """
  end

  # Private helpers

  defp format_plan_date(datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, dt} -> SourceAttribution.format_relative_time(dt)
      {:error, _} -> gettext("recently")
    end
  end
end
