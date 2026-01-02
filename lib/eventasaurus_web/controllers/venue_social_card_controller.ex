defmodule EventasaurusWeb.VenueSocialCardController do
  @moduledoc """
  Controller for generating branded social card PNG images for venue pages.

  This controller generates social cards with Wombie branding for venue pages,
  showing venue name, city, event count, and venue image.

  Issue #3143: Simplified to match flat /venues/:slug route structure.
  Route: GET /social-cards/venue/:venue_slug/:hash/*rest
  """
  use EventasaurusWeb.SocialCardController, type: :venue

  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues
  alias EventasaurusApp.Images.VenueImages
  import EventasaurusWeb.SocialCardView, only: [sanitize_venue: 1, render_venue_card_svg: 1]

  @impl true
  def lookup_entity(%{"venue_slug" => venue_slug}) do
    case Venues.get_venue_by_slug(venue_slug) do
      nil ->
        {:error, :not_found, "Venue not found for slug: #{venue_slug}"}

      venue ->
        # Preload city_ref for building card data
        venue = Repo.preload(venue, :city_ref)
        {:ok, venue}
    end
  end

  @impl true
  def build_card_data(venue) do
    event_count = Venues.count_upcoming_events(venue.id)
    cover_image = get_venue_cover_image(venue)

    %{
      name: venue.name,
      slug: venue.slug,
      city_ref:
        if(venue.city_ref,
          do: %{
            name: venue.city_ref.name,
            slug: venue.city_ref.slug
          },
          else: %{name: "", slug: ""}
        ),
      address: venue.address,
      event_count: event_count,
      cover_image_url: cover_image,
      updated_at: venue.updated_at
    }
  end

  @impl true
  def build_slug(%{"venue_slug" => venue_slug}, _data) do
    venue_slug
  end

  @impl true
  def sanitize(data), do: sanitize_venue(data)

  @impl true
  def render_svg(data), do: render_venue_card_svg(data)

  # Get cover image using VenueImages with proper layered fallback:
  # 1. R2 cached venue image → CDN transformation (our CDN)
  # 2. City Unsplash gallery → raw Unsplash URLs (Unsplash's CDN, not ours)
  # 3. nil → placeholder
  defp get_venue_cover_image(venue) do
    city = Map.get(venue, :city_ref)
    VenueImages.get_image(venue, city, width: 800, height: 419, quality: 85)
  end
end
