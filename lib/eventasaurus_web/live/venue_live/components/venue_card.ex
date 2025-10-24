defmodule EventasaurusWeb.VenueLive.Components.VenueCard do
  @moduledoc """
  Venue card component for displaying venues in grid layouts.

  Displays:
  - Venue image (if available) or placeholder
  - Venue name
  - City and country
  - Link to venue page
  """
  use Phoenix.Component
  use Phoenix.VerifiedRoutes,
    endpoint: EventasaurusWeb.Endpoint,
    router: EventasaurusWeb.Router,
    statics: EventasaurusWeb.static_paths()

  attr :venue, :map, required: true, doc: "Venue struct with preloaded city_ref"
  attr :class, :string, default: "", doc: "Additional CSS classes"

  def venue_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/venues/#{@venue.slug}"}
      class={[
        "block bg-white rounded-lg shadow-md overflow-hidden hover:shadow-lg transition-shadow",
        @class
      ]}
    >
      <!-- Venue Image -->
      <div class="relative h-48 bg-gray-200">
        <%= if has_image?(@venue) do %>
          <img
            src={get_image_url(@venue)}
            alt={"#{@venue.name}"}
            class="w-full h-full object-cover"
            loading="lazy"
          />
        <% else %>
          <div class="w-full h-full flex items-center justify-center bg-gradient-to-br from-gray-100 to-gray-200">
            <svg class="h-16 w-16 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4"
              />
            </svg>
          </div>
        <% end %>
      </div>
      <!-- Venue Details -->
      <div class="p-4">
        <h3 class="text-lg font-semibold text-gray-900 line-clamp-2 hover:text-indigo-600 transition-colors">
          <%= @venue.name %>
        </h3>
        <%= if @venue.city_ref do %>
          <p class="mt-1 text-sm text-gray-600">
            <%= @venue.city_ref.name %><%= if @venue.city_ref.country,
              do: ", #{@venue.city_ref.country.name}",
              else: "" %>
          </p>
        <% end %>
        <%= if @venue.address do %>
          <p class="mt-1 text-xs text-gray-500 line-clamp-1">
            <%= @venue.address %>
          </p>
        <% end %>
      </div>
    </.link>
    """
  end

  # Helper functions

  defp has_image?(%{venue_images: images}) when is_list(images) and length(images) > 0, do: true
  defp has_image?(_), do: false

  defp get_image_url(%{venue_images: [first | _]}) when is_map(first) do
    Map.get(first, "url") || "/images/venue-placeholder.png"
  end

  defp get_image_url(_), do: "/images/venue-placeholder.png"
end
