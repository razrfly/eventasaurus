defmodule EventasaurusWeb.VenueSocialCardController do
  @moduledoc """
  Controller for generating branded social card PNG images for venue pages.

  This controller generates social cards with Wombie branding for venue pages,
  showing venue name, city, event count, and venue image.

  Route: GET /social-cards/venue/:city_slug/:venue_slug/:hash/*rest
  """
  use EventasaurusWeb.SocialCardController, type: :venue

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Locations
  import EventasaurusWeb.SocialCardView, only: [sanitize_venue: 1, render_venue_card_svg: 1]

  @impl true
  def lookup_entity(%{"city_slug" => city_slug, "venue_slug" => venue_slug}) do
    case Locations.get_city_by_slug(city_slug) do
      nil ->
        {:error, :not_found, "City not found for slug: #{city_slug}"}

      city ->
        case Venues.get_venue_by_slug(venue_slug) do
          nil ->
            {:error, :not_found, "Venue not found for slug: #{venue_slug}"}

          venue ->
            # Verify venue belongs to the specified city
            if venue.city_id != city.id do
              {:error, :not_found,
               "Venue #{venue_slug} belongs to city_id=#{venue.city_id}, not #{city_slug} (id=#{city.id})"}
            else
              {:ok, {venue, city}}
            end
        end
    end
  end

  @impl true
  def build_card_data({venue, city}) do
    # Preload city_ref for the fallback image chain (venue images → city gallery → general)
    venue = Repo.preload(venue, :city_ref)

    event_count = Venues.count_upcoming_events(venue.id)
    cover_image = get_venue_cover_image(venue)

    %{
      name: venue.name,
      slug: venue.slug,
      city_ref: %{
        name: city.name,
        slug: city.slug
      },
      address: venue.address,
      event_count: event_count,
      cover_image_url: cover_image,
      updated_at: venue.updated_at
    }
  end

  @impl true
  def build_slug(%{"city_slug" => city_slug, "venue_slug" => venue_slug}, _data) do
    "#{city_slug}_#{venue_slug}"
  end

  @impl true
  def sanitize(data), do: sanitize_venue(data)

  @impl true
  def render_svg(data), do: render_venue_card_svg(data)

  # Get cover image using the venue's full fallback chain
  # This matches the same logic used by VenueHeroCard in the venue page:
  # 1. Venue's cached images from R2
  # 2. City's categorized gallery (e.g., "cinema" for Cinema City)
  # 3. City's "general" category (Unsplash city images)
  defp get_venue_cover_image(venue) do
    case Venue.get_cover_image(venue, width: 800, height: 419, quality: 85) do
      {:ok, url, _source} -> url
      {:error, :no_image} -> nil
    end
  end
end
