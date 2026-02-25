defmodule EventasaurusWeb.VenueLive.Components.EventCard do
  @moduledoc """
  Event card component for venue pages.

  Displays event information including:
  - Event title with link to event page
  - Date and time
  - Cover image (if available)

  Note: Simplified for public_events which don't have status/ticket fields.
  """
  use EventasaurusWeb, :html
  import EventasaurusWeb.Helpers.PublicEventDisplayHelpers, only: [format_local_datetime: 3]

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
            </div>
          </div>

          <div class="mt-3">
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
              <span><%= format_date_time(@event) %></span>
            </div>
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

  defp format_date_time(%{starts_at: nil}), do: "Date TBD"

  defp format_date_time(%{starts_at: starts_at, venue: venue}) do
    format_local_datetime(starts_at, venue, :full)
  end

  defp format_date_time(%{starts_at: starts_at}) do
    format_local_datetime(starts_at, nil, :full)
  end
end
