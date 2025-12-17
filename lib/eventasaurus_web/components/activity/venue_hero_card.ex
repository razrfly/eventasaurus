defmodule EventasaurusWeb.Components.Activity.VenueHeroCard do
  @moduledoc """
  Hero card for venue pages.

  Displays venue information with a prominent background image,
  matching the visual style of activity hero cards (TriviaHeroCard,
  AggregatedHeroCard, etc.)

  ## Features

  - Rounded card design matching activity pages
  - Background image from venue images with fallback chain
  - Gradient overlay for text readability
  - Venue name and address display
  - City and country context
  - Upcoming event count badge
  - Action buttons for directions
  """
  use Phoenix.Component
  use Gettext, backend: EventasaurusWeb.Gettext

  alias Eventasaurus.CDN
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusWeb.Components.Activity.HeroCardHelpers

  @doc """
  Renders the venue hero card.

  ## Attributes

    * `:venue` - Required. The venue struct with name, address, coordinates, etc.
    * `:upcoming_event_count` - Required. Number of upcoming events at this venue.
    * `:class` - Optional. Additional CSS classes for the container.
  """
  attr :venue, :map, required: true, doc: "Venue struct with name, address, city_ref, etc."
  attr :upcoming_event_count, :integer, required: true, doc: "Number of upcoming events"
  attr :class, :string, default: "", doc: "Additional CSS classes"

  def venue_hero_card(assigns) do
    # Get cover image using the venue's fallback chain
    {image_url, image_source} = get_venue_cover_image(assigns.venue)

    assigns =
      assigns
      |> assign(:cover_image_url, image_url)
      |> assign(:image_source, image_source)
      |> assign(:city_name, HeroCardHelpers.get_city_name(assigns.venue))
      |> assign(:country_name, get_country_name(assigns.venue))
      |> assign(:has_coordinates, has_coordinates?(assigns.venue))

    ~H"""
    <div class={"relative rounded-xl overflow-hidden #{@class}"}>
      <!-- Background Image or Gradient -->
      <%= if @cover_image_url do %>
        <div class="absolute inset-0">
          <img
            src={CDN.url(@cover_image_url, width: 1200, quality: 85)}
            alt=""
            class="w-full h-full object-cover"
            aria-hidden="true"
          />
          <!-- Gradient overlay for text readability -->
          <div class="absolute inset-0 bg-gradient-to-r from-slate-900/95 via-slate-900/85 to-slate-800/70" />
        </div>
      <% else %>
        <!-- Fallback gradient when no image available -->
        <div class="absolute inset-0 bg-gradient-to-r from-slate-900 via-slate-800 to-slate-700" />
      <% end %>

      <!-- Content -->
      <div class="relative p-6 md:p-8">
        <div class="max-w-3xl">
          <!-- Badges Row -->
          <div class="flex flex-wrap items-center gap-2 mb-4">
            <!-- Venue Badge -->
            <span class="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-indigo-500/20 text-indigo-100">
              <Heroicons.building_storefront class="w-4 h-4 mr-1.5" />
              <%= gettext("Venue") %>
            </span>

            <!-- Event Count Badge -->
            <%= if @upcoming_event_count > 0 do %>
              <span class="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-green-500/20 text-green-100">
                <Heroicons.calendar class="w-4 h-4 mr-1.5" />
                <%= ngettext("%{count} upcoming event", "%{count} upcoming events", @upcoming_event_count, count: @upcoming_event_count) %>
              </span>
            <% end %>
          </div>

          <!-- Venue Name -->
          <h1 class="text-2xl md:text-4xl font-bold text-white tracking-tight mb-3">
            <%= @venue.name %>
          </h1>

          <!-- Address -->
          <%= if @venue.address do %>
            <div class="flex items-start text-white/90 mb-2">
              <Heroicons.map_pin class="w-5 h-5 mr-2 mt-0.5 flex-shrink-0" />
              <span class="text-lg"><%= @venue.address %></span>
            </div>
          <% end %>

          <!-- City & Country -->
          <%= if @city_name || @country_name do %>
            <div class="flex items-center text-white/70 mb-6">
              <Heroicons.globe_alt class="w-5 h-5 mr-2" />
              <span>
                <%= [@city_name, @country_name] |> Enum.filter(& &1) |> Enum.join(", ") %>
              </span>
            </div>
          <% end %>

          <!-- Action Buttons -->
          <div class="flex flex-wrap items-center gap-3">
            <%= if @has_coordinates do %>
              <a
                href={google_maps_directions_url(@venue)}
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center px-5 py-2.5 bg-white text-slate-900 text-sm font-semibold rounded-lg hover:bg-gray-100 transition shadow-md"
              >
                <Heroicons.arrow_top_right_on_square class="w-5 h-5 mr-2" />
                <%= gettext("Get Directions") %>
              </a>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Private helpers

  defp get_venue_cover_image(venue) do
    case Venue.get_cover_image(venue, width: 1200, height: 630, quality: 85) do
      {:ok, url, source} -> {url, source}
      {:error, :no_image} -> {nil, nil}
    end
  end

  defp get_country_name(%{city_ref: %{country: %{name: name}}}) when is_binary(name), do: name
  defp get_country_name(_), do: nil

  defp has_coordinates?(%{latitude: lat, longitude: lon})
       when is_number(lat) and is_number(lon),
       do: true

  defp has_coordinates?(_), do: false

  defp google_maps_directions_url(%{latitude: lat, longitude: lon})
       when is_number(lat) and is_number(lon) do
    "https://www.google.com/maps/dir/?api=1&destination=#{lat},#{lon}"
  end

  defp google_maps_directions_url(%{address: address, name: name}) when is_binary(address) do
    query = URI.encode("#{name}, #{address}")
    "https://www.google.com/maps/dir/?api=1&destination=#{query}"
  end

  defp google_maps_directions_url(_), do: "#"
end
