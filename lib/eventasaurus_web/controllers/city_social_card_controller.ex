defmodule EventasaurusWeb.CitySocialCardController do
  @moduledoc """
  Controller for generating branded social card PNG images for city pages.

  Route: GET /social-cards/city/:slug/:hash/*rest
  """
  use EventasaurusWeb.SocialCardController, type: :city

  import Ecto.Query, only: [from: 2]

  alias EventasaurusDiscovery.Locations
  alias EventasaurusDiscovery.PublicEventsEnhanced
  alias EventasaurusDiscovery.Categories
  import EventasaurusWeb.SocialCardView, only: [sanitize_city: 1, render_city_card_svg: 2]

  # Keep the old function name for route compatibility
  def generate_card_by_slug(conn, params) do
    generate_card(conn, params)
  end

  @impl true
  def lookup_entity(%{"slug" => slug}) do
    case Locations.get_city_by_slug(slug) do
      nil -> {:error, :not_found, "City not found for slug: #{slug}"}
      city -> {:ok, city}
    end
  end

  @impl true
  def build_card_data(city) do
    stats = fetch_city_stats(city)
    Map.put(city, :stats, stats)
  end

  @impl true
  def build_slug(%{"slug" => slug}, _data), do: slug

  @impl true
  def sanitize(city_with_stats) do
    sanitize_city(city_with_stats)
  end

  @impl true
  def render_svg(sanitized_city) do
    # City card needs stats passed separately
    stats = Map.get(sanitized_city, :stats, %{})
    render_city_card_svg(sanitized_city, stats)
  end

  # Fetch city stats for the card
  defp fetch_city_stats(city) do
    lat = city.latitude && Decimal.to_float(city.latitude)
    lng = city.longitude && Decimal.to_float(city.longitude)

    default_radius_km = 50

    events_count =
      if lat && lng do
        PublicEventsEnhanced.count_events(%{
          center_lat: lat,
          center_lng: lng,
          radius_km: default_radius_km,
          show_past: false
        })
      else
        0
      end

    venues_count =
      EventasaurusApp.Repo.aggregate(
        from(v in EventasaurusApp.Venues.Venue, where: v.city_id == ^city.id),
        :count
      )

    categories_count = length(Categories.list_categories())

    %{
      events_count: events_count,
      venues_count: venues_count,
      categories_count: categories_count
    }
  end
end
