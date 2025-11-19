defmodule EventasaurusWeb.Components.FeaturedEventCard do
  use Phoenix.Component
  use EventasaurusWeb, :verified_routes
  alias Eventasaurus.CDN

  attr :event, :map, required: true
  attr :rank, :integer, required: true
  attr :badge_text, :string, default: nil

  def featured_event_card(assigns) do
    ~H"""
    <.link navigate={~p"/activities/#{@event.slug}"} class="block group h-full">
      <div class="relative h-80 rounded-lg overflow-hidden shadow-lg hover:shadow-xl transition-shadow w-64 flex-shrink-0">
        <!-- Event Image -->
        <img
          src={CDN.url(@event.cover_image_url, width: 400, height: 600, fit: "cover")}
          alt={@event.title}
          class="w-full h-full object-cover"
        />
        <!-- Rank Badge -->
        <div class="absolute top-4 left-4 bg-white text-gray-900 rounded-full w-12 h-12 flex items-center justify-center font-bold text-xl shadow-lg z-10">
          <%= @rank %>
        </div>
        <!-- Content -->
        <div class="absolute bottom-0 left-0 right-0 p-6 bg-gradient-to-t from-black/90 to-transparent text-white">
          <div class="mb-2">
            <span class="inline-block bg-blue-600 px-3 py-1 rounded text-xs font-medium">
              <%= @event.category_name %>
            </span>
          </div>
          <h3 class="text-xl font-bold mb-2 line-clamp-2">
            <%= @event.title %>
          </h3>
          <div class="flex items-center text-sm">
            <Heroicons.map_pin class="w-4 h-4 mr-1" />
            <span class="truncate"><%= @event.city_name %></span>
            <%= if @badge_text do %>
              <span class="ml-3 flex-shrink-0">• <%= @badge_text %></span>
            <% end %>
          </div>
        </div>
      </div>
    </.link>
    """
  end
end
