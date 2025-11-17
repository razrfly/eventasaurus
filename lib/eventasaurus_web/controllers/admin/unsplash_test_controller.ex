defmodule EventasaurusWeb.Admin.UnsplashTestController do
  @moduledoc """
  Admin controller for visualizing Unsplash city and country image integration.

  This page shows:
  - All cities with cached image galleries (venue_count >= 3)
  - All countries with cached image galleries
  - Current daily rotation status
  - Sample images from each location's gallery
  - Gallery metadata and refresh status
  - Bulk refresh controls for cities and countries

  Access at: /admin/unsplash (dev environment only)
  """
  use EventasaurusWeb, :controller

  alias EventasaurusApp.Services.UnsplashService
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.{City, Country}
  import Ecto.Query

  def index(conn, _params) do
    # Get all cities and countries with their galleries
    cities_with_galleries = get_cities_with_galleries()
    countries_with_galleries = get_countries_with_galleries()

    # Calculate daily rotation info
    day_of_year = Date.utc_today() |> Date.day_of_year()
    today = Date.utc_today()

    # Check if Unsplash API key is configured
    api_key_configured = System.get_env("UNSPLASH_ACCESS_KEY") != nil

    # Get counts for bulk refresh buttons (matching coordinator logic)
    cities_for_refresh_count = count_cities_for_refresh()
    countries_for_refresh_count = count_countries_for_refresh()

    # Get total stats
    total_active_cities = count_active_cities()
    cities_with_galleries_count = length(cities_with_galleries)
    countries_with_galleries_count = length(countries_with_galleries)

    total_city_images =
      Enum.reduce(cities_with_galleries, 0, fn city, acc ->
        acc + (city.image_count || 0)
      end)

    total_country_images =
      Enum.reduce(countries_with_galleries, 0, fn country, acc ->
        acc + (country.image_count || 0)
      end)

    render(conn, :index,
      cities: cities_with_galleries,
      countries: countries_with_galleries,
      day_of_year: day_of_year,
      today: today,
      api_key_configured: api_key_configured,
      cities_for_refresh_count: cities_for_refresh_count,
      countries_for_refresh_count: countries_for_refresh_count,
      total_active_cities: total_active_cities,
      cities_with_galleries_count: cities_with_galleries_count,
      countries_with_galleries_count: countries_with_galleries_count,
      total_city_images: total_city_images,
      total_country_images: total_country_images
    )
  end

  defp count_cities_for_refresh do
    # Match coordinator logic: cities with venue_count >= 3
    # Use subquery to count cities that meet the criteria
    subquery =
      from(c in City,
        join: v in assoc(c, :venues),
        group_by: c.id,
        having: count(v.id) >= 3,
        select: c.id
      )

    query = from(c in subquery(subquery), select: count())
    Repo.one(query) || 0
  end

  defp count_countries_for_refresh do
    # Match coordinator logic: countries with at least 1 city
    # Count distinct countries that have at least one city
    query =
      from(co in Country,
        join: ci in assoc(co, :cities),
        select: count(co.id, :distinct)
      )

    Repo.one(query) || 0
  end

  defp count_active_cities do
    # Count cities with discovery_enabled = true
    query =
      from(c in City,
        where: c.discovery_enabled == true,
        select: count(c.id)
      )

    Repo.one(query) || 0
  end

  defp get_cities_with_galleries do
    # Show all cities with galleries (for display), not just those eligible for refresh
    query =
      from(c in City,
        where: not is_nil(c.unsplash_gallery),
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

  defp get_countries_with_galleries do
    query =
      from(co in Country,
        where: not is_nil(co.unsplash_gallery),
        order_by: co.name,
        select: %{
          id: co.id,
          name: co.name,
          slug: co.slug,
          code: co.code,
          gallery: co.unsplash_gallery
        }
      )

    Repo.all(query)
    |> Enum.map(&enrich_country_data/1)
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

    # All categories including general (all shown as tabs now)
    # Order matters: general first, then others
    tab_category_names = ["general", "architecture", "historic", "old_town", "city_landmarks"]

    # Keep as list of tuples to preserve order
    tab_categories =
      tab_category_names
      |> Enum.filter(fn name -> Map.has_key?(categories, name) end)
      |> Enum.map(fn category_name ->
        category_data = Map.get(categories, category_name)
        {category_name, enrich_category.(category_data)}
      end)

    # Also create a map for easy lookup
    tab_categories_map = Enum.into(tab_categories, %{})

    # Get first available tab category for active selection (finds first category that actually exists)
    active_tab_category =
      Enum.find(tab_category_names, fn name -> Map.has_key?(tab_categories_map, name) end)

    # Calculate total images across all categories
    total_images =
      Enum.reduce(tab_categories, 0, fn {_name, data}, acc ->
        acc + data.image_count
      end)

    %{
      id: city.id,
      name: city.name,
      slug: city.slug,
      format: :categorized,
      tab_categories: tab_categories,  # List of tuples preserves order
      active_tab_category: active_tab_category,
      category_count: map_size(categories),
      image_count: total_images,
      # For backward compatibility
      categories: tab_categories_map,
      images: nil,
      last_refreshed: nil
    }
  end

  defp enrich_country_data(country) do
    gallery = country.gallery || %{}

    # Countries always use categorized format
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

    # Country categories: general, architecture, historic, landmarks, nature
    tab_category_names = ["general", "architecture", "historic", "landmarks", "nature"]

    # Keep as list of tuples to preserve order
    tab_categories =
      tab_category_names
      |> Enum.filter(fn name -> Map.has_key?(categories, name) end)
      |> Enum.map(fn category_name ->
        category_data = Map.get(categories, category_name)
        {category_name, enrich_category.(category_data)}
      end)

    # Also create a map for easy lookup
    tab_categories_map = Enum.into(tab_categories, %{})

    # Get first available tab category for active selection
    active_tab_category =
      Enum.find(tab_category_names, fn name -> Map.has_key?(tab_categories_map, name) end)

    # Calculate total images across all categories
    total_images =
      Enum.reduce(tab_categories, 0, fn {_name, data}, acc ->
        acc + data.image_count
      end)

    %{
      id: country.id,
      name: country.name,
      slug: country.slug,
      code: country.code,
      format: :categorized,
      tab_categories: tab_categories,
      active_tab_category: active_tab_category,
      category_count: map_size(categories),
      image_count: total_images,
      categories: tab_categories_map
    }
  end

  @doc """
  Fetch all 5 categorized images for a city
  """
  def fetch_images(conn, %{"city_id" => city_id}) do
    alias EventasaurusApp.Workers.UnsplashCityRefreshWorker

    city = Repo.get!(City, city_id)

    # Queue background job to fetch all categories
    case UnsplashCityRefreshWorker.new(%{city_id: city.id}) |> Oban.insert() do
      {:ok, _job} ->
        conn
        |> put_flash(:info, "✓ Queued refresh job for #{city.name}. Images will update in a few moments.")
        |> redirect(to: ~p"/admin/unsplash")

      {:error, changeset} ->
        conn
        |> put_flash(:error, "Failed to queue refresh job: #{inspect(changeset.errors)}")
        |> redirect(to: ~p"/admin/unsplash")
    end
  end

  @doc """
  Bulk refresh all cities matching coordinator criteria (venue_count >= 3)
  """
  def refresh_all_cities(conn, _params) do
    alias EventasaurusApp.Workers.UnsplashCityRefreshWorker

    # Get cities matching coordinator criteria: venue_count >= 3
    query =
      from(c in City,
        join: v in assoc(c, :venues),
        group_by: c.id,
        having: count(v.id) >= 3,
        select: c
      )

    cities = Repo.all(query)

    # Queue jobs for all eligible cities
    jobs =
      Enum.map(cities, fn city ->
        UnsplashCityRefreshWorker.new(%{city_id: city.id})
      end)

    inserted_jobs = Oban.insert_all(jobs)
    count = length(inserted_jobs)

    conn
    |> put_flash(:info, "✓ Queued #{count} city refresh jobs. Staleness checks will prevent unnecessary API calls.")
    |> redirect(to: ~p"/admin/unsplash")
  end

  @doc """
  Bulk refresh all countries with at least 1 city
  """
  def refresh_all_countries(conn, _params) do
    alias EventasaurusApp.Workers.UnsplashCountryRefreshWorker

    # Get countries with at least 1 city
    query =
      from(co in Country,
        join: ci in assoc(co, :cities),
        group_by: co.id,
        select: co
      )

    countries = Repo.all(query)

    # Queue jobs for all eligible countries
    jobs =
      Enum.map(countries, fn country ->
        UnsplashCountryRefreshWorker.new(%{country_id: country.id})
      end)

    inserted_jobs = Oban.insert_all(jobs)
    count = length(inserted_jobs)

    conn
    |> put_flash(:info, "✓ Queued #{count} country refresh jobs. Staleness checks will prevent unnecessary API calls.")
    |> redirect(to: ~p"/admin/unsplash")
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
            |> redirect(to: ~p"/admin/unsplash")

          {:error, reason} ->
            conn
            |> put_flash(:error, "Failed to store #{category_name}: #{inspect(reason)}")
            |> redirect(to: ~p"/admin/unsplash")
        end

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to fetch #{category_name}: #{inspect(reason)}")
        |> redirect(to: ~p"/admin/unsplash")
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
