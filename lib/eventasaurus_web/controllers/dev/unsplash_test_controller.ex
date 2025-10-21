defmodule EventasaurusWeb.Dev.UnsplashTestController do
  @moduledoc """
  Development-only controller for visualizing Unsplash city image integration.

  This page shows:
  - All active cities with cached image galleries
  - Current daily rotation status
  - Sample images from each city's gallery
  - Gallery metadata and refresh status

  Access at: /dev/unsplash (dev environment only)
  """
  use EventasaurusWeb, :controller

  alias EventasaurusApp.Services.UnsplashService
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  import Ecto.Query

  def index(conn, _params) do
    # Get all active cities with their galleries
    cities_with_galleries = get_cities_with_galleries()

    # Calculate daily rotation info
    day_of_year = Date.utc_today() |> Date.day_of_year()
    today = Date.utc_today()

    # Check if Unsplash API key is configured
    api_key_configured = System.get_env("UNSPLASH_ACCESS_KEY") != nil

    # Get total active cities count (discovery_enabled = true)
    total_active_cities = count_active_cities()

    # Get total stats
    cities_with_galleries_count = length(cities_with_galleries)
    total_images =
      Enum.reduce(cities_with_galleries, 0, fn city, acc ->
        acc + length(city.images)
      end)

    render(conn, :index,
      cities: cities_with_galleries,
      day_of_year: day_of_year,
      today: today,
      api_key_configured: api_key_configured,
      total_active_cities: total_active_cities,
      cities_with_galleries_count: cities_with_galleries_count,
      total_images: total_images
    )
  end

  defp count_active_cities do
    query =
      from c in City,
        where: c.discovery_enabled == true,
        select: count(c.id)

    Repo.one(query)
  end

  defp get_cities_with_galleries do
    query =
      from c in City,
        where: c.discovery_enabled == true and not is_nil(c.unsplash_gallery),
        order_by: c.name,
        select: %{
          id: c.id,
          name: c.name,
          slug: c.slug,
          gallery: c.unsplash_gallery
        }

    Repo.all(query)
    |> Enum.map(&enrich_city_data/1)
  end

  defp enrich_city_data(city) do
    gallery = city.gallery || %{}
    images = Map.get(gallery, "images", [])
    last_refreshed = Map.get(gallery, "last_refreshed_at")

    # Get current daily image
    current_image_index = if length(images) > 0 do
      UnsplashService.get_daily_image_index(length(images))
    else
      0
    end

    current_image = if length(images) > 0, do: Enum.at(images, current_image_index), else: nil

    %{
      id: city.id,
      name: city.name,
      slug: city.slug,
      images: images,
      image_count: length(images),
      current_image: current_image,
      current_index: current_image_index,
      last_refreshed: last_refreshed
    }
  end
end
