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
        acc + (city.image_count || 0)
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
      from(c in City,
        where: c.discovery_enabled == true,
        select: count(c.id)
      )

    Repo.one(query)
  end

  defp get_cities_with_galleries do
    query =
      from(c in City,
        where: c.discovery_enabled == true and not is_nil(c.unsplash_gallery),
        order_by: c.name,
        select: %{
          id: c.id,
          name: c.name,
          slug: c.slug,
          gallery: c.unsplash_gallery
        }
      )

    Repo.all(query)
    |> Enum.map(&enrich_city_data/1)
  end

  defp enrich_city_data(city) do
    gallery = city.gallery || %{}

    # Detect format: categorized vs legacy
    is_categorized = Map.has_key?(gallery, "categories")

    if is_categorized do
      enrich_categorized_gallery(city, gallery)
    else
      enrich_legacy_gallery(city, gallery)
    end
  end

  defp enrich_legacy_gallery(city, gallery) do
    images = Map.get(gallery, "images", [])
    last_refreshed = Map.get(gallery, "last_refreshed_at")

    # Get current daily image
    current_image_index =
      if length(images) > 0 do
        UnsplashService.get_daily_image_index(length(images))
      else
        0
      end

    current_image = if length(images) > 0, do: Enum.at(images, current_image_index), else: nil

    %{
      id: city.id,
      name: city.name,
      slug: city.slug,
      format: :legacy,
      images: images,
      image_count: length(images),
      current_image: current_image,
      current_index: current_image_index,
      last_refreshed: last_refreshed,
      categories: nil,
      active_category: nil
    }
  end

  defp enrich_categorized_gallery(city, gallery) do
    categories = Map.get(gallery, "categories", %{})

    # Helper function to enrich a single category
    enrich_category = fn category_data ->
      images = Map.get(category_data, "images", [])
      last_refreshed = Map.get(category_data, "last_refreshed_at")
      search_terms = Map.get(category_data, "search_terms", [])

      current_image_index =
        if length(images) > 0 do
          UnsplashService.get_daily_image_index(length(images))
        else
          0
        end

      current_image = if length(images) > 0, do: Enum.at(images, current_image_index), else: nil

      %{
        images: images,
        image_count: length(images),
        current_image: current_image,
        current_index: current_image_index,
        last_refreshed: last_refreshed,
        search_terms: search_terms
      }
    end

    # Separate general category (for hero section) from tab categories
    general_category_data =
      case Map.get(categories, "general") do
        nil -> nil
        data -> enrich_category.(data)
      end

    # Tab categories: architecture, historic, old_town, city_landmarks
    tab_category_names = ["architecture", "historic", "old_town", "city_landmarks"]

    tab_categories =
      tab_category_names
      |> Enum.filter(fn name -> Map.has_key?(categories, name) end)
      |> Enum.map(fn category_name ->
        category_data = Map.get(categories, category_name)
        {category_name, enrich_category.(category_data)}
      end)
      |> Enum.into(%{})

    # Get first available tab category for active selection
    active_tab_category =
      if map_size(tab_categories) > 0 do
        Enum.at(tab_category_names, 0)
      else
        nil
      end

    # Calculate total images across all categories
    total_images =
      (if general_category_data, do: general_category_data.image_count, else: 0) +
      Enum.reduce(tab_categories, 0, fn {_name, data}, acc ->
        acc + data.image_count
      end)

    %{
      id: city.id,
      name: city.name,
      slug: city.slug,
      format: :categorized,
      general_category: general_category_data,
      tab_categories: tab_categories,
      active_tab_category: active_tab_category,
      category_count: map_size(categories),
      image_count: total_images,
      # For backward compatibility
      categories: Map.merge(
        (if general_category_data, do: %{"general" => general_category_data}, else: %{}),
        tab_categories
      ),
      images: nil,
      last_refreshed: nil
    }
  end

  @doc """
  Fetch all 5 categorized images for a city
  """
  def fetch_images(conn, %{"city_id" => city_id}) do
    alias EventasaurusApp.Services.UnsplashImageFetcher

    city = Repo.get!(City, city_id)

    case UnsplashImageFetcher.fetch_and_store_all_categories(city) do
      {:ok, _updated_city} ->
        conn
        |> put_flash(:info, "✓ Successfully fetched categories for #{city.name}")
        |> redirect(to: ~p"/dev/unsplash")

      {:error, :all_categories_failed} ->
        conn
        |> put_flash(:error, "Failed to fetch any categories for #{city.name}")
        |> redirect(to: ~p"/dev/unsplash")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to fetch images: #{inspect(reason)}")
        |> redirect(to: ~p"/dev/unsplash")
    end
  end

  @doc """
  Refresh a specific category for a city
  """
  def refresh_category(conn, %{"city_id" => city_id, "category" => category_name}) do
    alias EventasaurusApp.Services.UnsplashImageFetcher

    city = Repo.get!(City, city_id)

    # Get search terms for this category
    search_terms = get_search_terms_for_category(city.name, category_name)

    case UnsplashImageFetcher.fetch_category_images(city.name, category_name, search_terms) do
      {:ok, category_data} ->
        case UnsplashImageFetcher.store_category(city, category_name, category_data) do
          {:ok, _updated_city} ->
            conn
            |> put_flash(:info, "✓ Refreshed #{category_name} category for #{city.name}")
            |> redirect(to: ~p"/dev/unsplash")

          {:error, reason} ->
            conn
            |> put_flash(:error, "Failed to store #{category_name}: #{inspect(reason)}")
            |> redirect(to: ~p"/dev/unsplash")
        end

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to fetch #{category_name}: #{inspect(reason)}")
        |> redirect(to: ~p"/dev/unsplash")
    end
  end

  defp get_search_terms_for_category(city_name, category) do
    case category do
      "general" -> [city_name, "#{city_name} cityscape", "#{city_name} skyline"]
      "architecture" -> ["#{city_name} architecture", "#{city_name} modern buildings", "#{city_name} buildings"]
      "historic" -> ["#{city_name} historic buildings", "#{city_name} monuments", "#{city_name} old architecture"]
      "old_town" -> ["#{city_name} old town", "#{city_name} medieval", "#{city_name} historic center"]
      "city_landmarks" -> ["#{city_name} landmarks", "#{city_name} famous places", "#{city_name} attractions"]
      _ -> [city_name]
    end
  end
end
