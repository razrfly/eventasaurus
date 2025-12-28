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

  alias EventasaurusApp.Images.VenueImages

  alias EventasaurusWeb.Components.Activity.{
    HeroCardBadge,
    HeroCardBackground,
    HeroCardHelpers,
    HeroCardIcons,
    HeroCardTheme
  }

  import HeroCardHelpers,
    only: [get_city_name: 1, has_coordinates?: 1, google_maps_directions_url: 1]

  @doc """
  Renders the venue hero card.

  ## Attributes

    * `:venue` - Required. The venue struct with name, address, coordinates, etc.
    * `:upcoming_event_count` - Required. Number of upcoming events at this venue.
    * `:class` - Optional. Additional CSS classes for the container.

  ## Slots

    * `:actions` - Optional. Action buttons to display (e.g., follow button).
  """
  attr :venue, :map, required: true, doc: "Venue struct with name, address, city_ref, etc."
  attr :upcoming_event_count, :integer, required: true, doc: "Number of upcoming events"
  attr :class, :string, default: "", doc: "Additional CSS classes"
  slot :actions, doc: "Optional action buttons (e.g., follow button)"

  def venue_hero_card(assigns) do
    # Get cover image using the venue's fallback chain
    {image_url, image_source} = get_venue_cover_image(assigns.venue)

    assigns =
      assigns
      |> assign(:cover_image_url, image_url)
      |> assign(:image_source, image_source)
      |> assign(:city_name, get_city_name(assigns.venue))
      |> assign(:country_name, HeroCardHelpers.get_country_name(assigns.venue))
      |> assign(:has_coordinates, has_coordinates?(assigns.venue))

    ~H"""
    <div class={"relative rounded-xl overflow-hidden #{@class}"}>
      <!-- Background -->
      <HeroCardBackground.background image_url={@cover_image_url} theme={:venue} />

      <!-- Content -->
      <div class="relative p-6 md:p-8">
        <div class="max-w-3xl">
          <!-- Badges Row -->
          <div class="flex flex-wrap items-center gap-2 mb-4">
            <!-- Venue Badge -->
            <span class={["inline-flex items-center px-3 py-1 rounded-full text-sm font-medium", HeroCardTheme.badge_class(:venue)]}>
              <HeroCardIcons.icon type={:venue} class="w-4 h-4 mr-1.5" />
              <%= HeroCardTheme.label(:venue) %>
            </span>

            <!-- Event Count Badge -->
            <%= if @upcoming_event_count > 0 do %>
              <HeroCardBadge.success_badge>
                <Heroicons.calendar class="w-4 h-4 mr-1.5" />
                <%= ngettext("%{count} upcoming event", "%{count} upcoming events", @upcoming_event_count, count: @upcoming_event_count) %>
              </HeroCardBadge.success_badge>
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
            <!-- Custom Actions Slot (e.g., Follow Button) -->
            <%= render_slot(@actions) %>

            <%= if @has_coordinates do %>
              <a
                href={google_maps_directions_url(@venue)}
                target="_blank"
                rel="noopener noreferrer"
                class={["inline-flex items-center px-5 py-2.5 text-sm font-semibold rounded-lg transition shadow-md", HeroCardTheme.button_class(:venue)]}
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

  # Get cover image using VenueImages with proper layered fallback:
  # 1. R2 cached venue image → CDN transformation (our CDN)
  # 2. City Unsplash gallery → raw Unsplash URLs (Unsplash's CDN, not ours)
  # 3. nil → placeholder icon
  defp get_venue_cover_image(venue) do
    city = Map.get(venue, :city_ref)
    url = VenueImages.get_image(venue, city, width: 1200, height: 630, quality: 85)

    if url do
      # Determine source based on URL pattern
      source =
        cond do
          String.contains?(url || "", "cdn.wombie.com") -> :venue
          String.contains?(url || "", "unsplash.com") -> :city_gallery
          true -> :unknown
        end

      {url, source}
    else
      {nil, nil}
    end
  end
end
