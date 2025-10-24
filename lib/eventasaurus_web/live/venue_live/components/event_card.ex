defmodule EventasaurusWeb.VenueLive.Components.EventCard do
  @moduledoc """
  Event card component for venue pages.

  Displays event information including:
  - Event title with link to event page
  - Date and time
  - Ticket status (Free/Ticketed)
  - Event status badge (if applicable)
  - Cover image (if available)
  """
  use Phoenix.Component
  use Phoenix.VerifiedRoutes,
    endpoint: EventasaurusWeb.Endpoint,
    router: EventasaurusWeb.Router,
    statics: EventasaurusWeb.static_paths()

  attr :event, :map, required: true, doc: "Event struct with preloaded associations"
  attr :class, :string, default: "", doc: "Additional CSS classes"

  def event_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/events/#{@event.slug}"}
      class={[
        "block border border-gray-200 rounded-lg overflow-hidden hover:shadow-md transition-shadow",
        @class
      ]}
    >
      <div class="flex">
        <!-- Cover Image -->
        <%= if has_image?(@event) do %>
          <div class="flex-shrink-0 w-32 h-32">
            <img
              src={get_image_url(@event)}
              alt={"#{@event.title} cover"}
              class="w-full h-full object-cover"
              loading="lazy"
            />
          </div>
        <% end %>
        <!-- Event Details -->
        <div class="flex-1 p-4">
          <div class="flex items-start justify-between gap-2">
            <div class="flex-1">
              <h4 class="text-base font-semibold text-gray-900 hover:text-indigo-600 transition-colors">
                <%= @event.title %>
              </h4>
              <%= if @event.tagline do %>
                <p class="text-sm text-gray-600 mt-1 line-clamp-1"><%= @event.tagline %></p>
              <% end %>
            </div>
            <!-- Status Badge -->
            <%= if show_status_badge?(@event) do %>
              <span class={[
                "px-2 py-1 text-xs font-medium rounded-full whitespace-nowrap",
                status_badge_class(@event.status)
              ]}>
                <%= format_status(@event.status) %>
              </span>
            <% end %>
          </div>

          <div class="mt-3 space-y-1">
            <!-- Date/Time -->
            <div class="flex items-center text-sm text-gray-600">
              <svg class="h-4 w-4 mr-1.5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
                />
              </svg>
              <span><%= format_date_time(@event.start_at) %></span>
            </div>
            <!-- Ticket Status -->
            <div class="flex items-center text-sm text-gray-600">
              <svg class="h-4 w-4 mr-1.5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M15 5v2m0 4v2m0 4v2M5 5a2 2 0 00-2 2v3a2 2 0 110 4v3a2 2 0 002 2h14a2 2 0 002-2v-3a2 2 0 110-4V7a2 2 0 00-2-2H5z"
                />
              </svg>
              <span><%= if @event.is_ticketed, do: "Ticketed Event", else: "Free Event" %></span>
            </div>
            <!-- Virtual Event Indicator -->
            <%= if @event.is_virtual do %>
              <div class="flex items-center text-sm text-gray-600">
                <svg
                  class="h-4 w-4 mr-1.5 text-gray-400"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"
                  />
                </svg>
                <span>Virtual Event</span>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  # Helper functions

  defp has_image?(%{cover_image_url: url}) when is_binary(url) and url != "", do: true

  defp has_image?(%{external_image_data: %{"url" => url}}) when is_binary(url) and url != "",
    do: true

  defp has_image?(_), do: false

  defp get_image_url(%{cover_image_url: url}) when is_binary(url) and url != "", do: url

  defp get_image_url(%{external_image_data: %{"url" => url}}) when is_binary(url) and url != "",
    do: url

  defp get_image_url(_), do: nil

  defp show_status_badge?(%{status: status}) when status in [:draft, :polling, :threshold, :canceled],
    do: true

  defp show_status_badge?(_), do: false

  defp status_badge_class(:draft), do: "bg-gray-100 text-gray-800"
  defp status_badge_class(:polling), do: "bg-blue-100 text-blue-800"
  defp status_badge_class(:threshold), do: "bg-yellow-100 text-yellow-800"
  defp status_badge_class(:confirmed), do: "bg-green-100 text-green-800"
  defp status_badge_class(:canceled), do: "bg-red-100 text-red-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp format_status(:draft), do: "Draft"
  defp format_status(:polling), do: "Polling"
  defp format_status(:threshold), do: "Threshold"
  defp format_status(:confirmed), do: "Confirmed"
  defp format_status(:canceled), do: "Canceled"
  defp format_status(status), do: status |> to_string() |> String.capitalize()

  defp format_date_time(nil), do: "Date TBD"

  defp format_date_time(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%B %d, %Y at %I:%M %p")
  end

  defp format_date_time(%Date{} = date) do
    Calendar.strftime(date, "%B %d, %Y")
  end
end
