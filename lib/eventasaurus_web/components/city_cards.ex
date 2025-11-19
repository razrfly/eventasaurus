defmodule EventasaurusWeb.Components.CityCards do
  use Phoenix.Component
  use EventasaurusWeb, :verified_routes
  alias Eventasaurus.CDN

  attr :city, :map, required: true
  attr :event_count, :integer, required: true

  def city_card(assigns) do
    ~H"""
    <.link navigate={~p"/c/#{@city.slug}"} class="block group">
      <div class="relative h-64 rounded-lg overflow-hidden shadow-lg hover:shadow-xl transition-shadow">
        <!-- Background Image -->
        <img
          src={get_city_image(@city)}
          alt={@city.name}
          class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
        />
        <!-- Overlay Gradient -->
        <div class="absolute inset-0 bg-gradient-to-t from-black/70 to-transparent"></div>
        <!-- Content -->
        <div class="absolute bottom-0 left-0 right-0 p-6 text-white">
          <h3 class="text-2xl font-bold mb-2">
            <%= @city.name %>
          </h3>
          <div class="flex items-center text-sm">
            <Heroicons.calendar class="w-4 h-4 mr-1" />
            <%= @event_count %> events
          </div>
        </div>
      </div>
    </.link>
    """
  end

  defp get_city_image(city) do
    # Extract category image from city's unsplash_gallery map
    with %{"categories" => categories} <- Map.get(city, :unsplash_gallery),
         %{"images" => images} when images != [] <- Map.get(categories, "general"),
         [image | _] <- images do
      CDN.url(image["url"], width: 600, height: 400, fit: "cover")
    else
      _ ->
        # Fallback image or placeholder
        "https://images.unsplash.com/photo-1449824913929-4bca4280d991?ixlib=rb-4.0.3&auto=format&fit=crop&w=600&q=80"
    end
  end
end
