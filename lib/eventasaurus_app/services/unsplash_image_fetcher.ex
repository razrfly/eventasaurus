defmodule EventasaurusApp.Services.UnsplashImageFetcher do
  @moduledoc """
  Service for fetching and storing Unsplash image galleries in the database.
  Fetches landscape-oriented city images sorted by popularity.

  Only works with active cities (discovery_enabled = true).
  """

  require Logger
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City

  # Number of images to store per city
  @max_images 10

  @doc """
  Fetch and store images for a city.
  Only works for cities with discovery_enabled = true.

  Returns {:ok, gallery} or {:error, reason}.
  """
  @spec fetch_and_store_city_images(String.t()) :: {:ok, map()} | {:error, atom()}
  def fetch_and_store_city_images(city_name) do
    Logger.info("Fetching images for city: #{city_name}")

    # Verify city exists and is active
    city = Repo.get_by(City, name: city_name)

    cond do
      is_nil(city) ->
        Logger.warning("City not found: #{city_name}")
        {:error, :not_found}

      !city.discovery_enabled ->
        Logger.warning("City #{city_name} is not active (discovery_enabled = false)")
        {:error, :inactive_city}

      true ->
        # Fetch images from Unsplash
        case fetch_city_images(city_name) do
          {:ok, images} -> create_gallery(city, images)
          error -> error
        end
    end
  end

  @doc """
  Fetch images from Unsplash API for a specific category.
  Uses landscape orientation and sorts by popularity (likes).

  ## Parameters
    - city_name: Name of the city
    - category_name: Category identifier (e.g., "general", "architecture")
    - search_terms: List of search terms for this category (e.g., ["warsaw architecture", "warsaw buildings"])

  Returns {:ok, category_data} with structure:
    %{
      "collection_id" => nil,
      "search_terms" => [...],
      "images" => [...],
      "last_refreshed_at" => "2025-11-03T..."
    }
  """
  @spec fetch_category_images(String.t(), String.t(), list(String.t())) ::
          {:ok, map()} | {:error, atom()}
  def fetch_category_images(city_name, category_name, search_terms)
      when is_binary(city_name) and is_binary(category_name) and is_list(search_terms) do
    Logger.info("Fetching category '#{category_name}' images for city: #{city_name}")

    # Verify city exists and is active
    city = Repo.get_by(City, name: city_name)

    cond do
      is_nil(city) ->
        Logger.warning("City not found: #{city_name}")
        {:error, :not_found}

      !city.discovery_enabled ->
        Logger.warning("City #{city_name} is not active (discovery_enabled = false)")
        {:error, :inactive_city}

      Enum.empty?(search_terms) ->
        Logger.warning("No search terms provided for category '#{category_name}'")
        {:error, :no_search_terms}

      true ->
        # Try each search term in order until one returns results
        try_search_terms(search_terms)
    end
  end

  @doc """
  Fetch and store all 5 category images for a city in one operation.

  This is the primary method for populating a city's Unsplash gallery.
  It fetches all categories (general, architecture, historic, old_town, city_landmarks)
  and stores them in the categorized format.

  ## Parameters
    - city: City struct (must have discovery_enabled = true)

  ## Returns
    - {:ok, updated_city} - Successfully fetched and stored all categories
    - {:error, reason} - Failed to fetch or store images

  ## Examples

      iex> city = Repo.get_by(City, slug: "warsaw")
      iex> UnsplashImageFetcher.fetch_and_store_all_categories(city)
      {:ok, %City{unsplash_gallery: %{"active_category" => "general", "categories" => %{...}}}}
  """
  @spec fetch_and_store_all_categories(City.t()) :: {:ok, City.t()} | {:error, any()}
  def fetch_and_store_all_categories(%City{} = city) do
    Logger.info("Fetching all categories for city: #{city.name}")

    if !city.discovery_enabled do
      Logger.warning("City #{city.name} is not active (discovery_enabled = false)")
      {:error, :inactive_city}
    else

    # Define all 5 categories with their search terms
    categories_to_fetch = [
      {"general", [city.name, "#{city.name} cityscape", "#{city.name} skyline"]},
      {"architecture", ["#{city.name} architecture", "#{city.name} modern buildings", "#{city.name} buildings"]},
      {"historic", ["#{city.name} historic buildings", "#{city.name} monuments", "#{city.name} old architecture"]},
      {"old_town", ["#{city.name} old town", "#{city.name} medieval", "#{city.name} historic center"]},
      {"city_landmarks", ["#{city.name} landmarks", "#{city.name} famous places", "#{city.name} attractions"]}
    ]

    # Fetch and store each category - continue even if some fail
    # IMPORTANT: Use reduce to reload city after each store to prevent overwriting categories
    {results, _final_city} = Enum.reduce(categories_to_fetch, {[], city}, fn {category_name, search_terms}, {acc_results, current_city} ->
      case fetch_category_images(city.name, category_name, search_terms) do
        {:ok, category_data} ->
          case store_category(current_city, category_name, category_data) do
            {:ok, _updated_gallery} ->
              # Reload city from database to get latest data for next category
              fresh_city = Repo.get!(City, city.id)
              Logger.info("  ✓ Successfully fetched #{category_name} for #{city.name}")
              {[{:ok, category_name} | acc_results], fresh_city}
            {:error, reason} ->
              Logger.warning("  ✗ Failed to store #{category_name} for #{city.name}: #{inspect(reason)}")
              {[{:error, category_name, reason} | acc_results], current_city}
          end
        {:error, reason} ->
          Logger.warning("  ✗ Failed to fetch #{category_name} for #{city.name}: #{inspect(reason)}")
          {[{:error, category_name, reason} | acc_results], current_city}
      end
    end)

    # Reverse results to restore original order
    results = Enum.reverse(results)

    # Count successes and failures
    successes = Enum.filter(results, &match?({:ok, _}, &1))
    failures = Enum.filter(results, &match?({:error, _, _}, &1))

    cond do
      length(successes) == 5 ->
        # All categories fetched successfully
        updated_city = Repo.get!(City, city.id)
        Logger.info("Successfully fetched all 5 categories for #{city.name}")
        {:ok, updated_city}

      length(successes) > 0 ->
        # Partial success - some categories fetched
        updated_city = Repo.get!(City, city.id)
        Logger.info("Fetched #{length(successes)}/5 categories for #{city.name} (#{length(failures)} failed)")
        {:ok, updated_city}

      true ->
        # All categories failed
        Logger.error("Failed to fetch any categories for #{city.name}")
        {:error, :all_categories_failed}
    end
    end
  end

  @doc """
  Fetch images from Unsplash API for a city.
  Uses landscape orientation and sorts by popularity (likes).

  Returns {:ok, images_list} or {:error, reason}.
  """
  @spec fetch_city_images(String.t()) :: {:ok, list(map())} | {:error, atom()}
  def fetch_city_images(city_name) do
    case System.get_env("UNSPLASH_ACCESS_KEY") do
      nil ->
        Logger.error("UNSPLASH_ACCESS_KEY not set")
        {:error, :no_api_key}

      access_key ->
        # Simple city name query with landscape orientation
        query = URI.encode(city_name)
        # Random page (1-5) for variety
        page = :rand.uniform(5)

        url =
          "https://api.unsplash.com/search/photos" <>
            "?query=#{query}" <>
            "&orientation=landscape" <>
            "&per_page=15" <>
            "&page=#{page}" <>
            "&client_id=#{access_key}"

        Logger.info("Fetching from Unsplash: #{city_name} (page #{page})")

        fetch_with_retry(url, city_name)
    end
  end

  # Private functions

  # Try each search term in order until one returns images
  defp try_search_terms([]), do: {:error, :no_images}

  defp try_search_terms([search_term | remaining_terms]) do
    Logger.info("  Trying search term: '#{search_term}'")

    case fetch_images_by_search_term(search_term) do
      {:ok, images} ->
        Logger.info("  ✓ Found #{length(images)} images for '#{search_term}'")

        category_data = %{
          "collection_id" => nil,
          "search_terms" => [search_term | remaining_terms],
          "images" => images,
          "last_refreshed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        {:ok, category_data}

      {:error, :no_images} ->
        Logger.info("  ✗ No images for '#{search_term}', trying next term...")
        try_search_terms(remaining_terms)

      error ->
        # For other errors (API errors, rate limits, etc.), stop trying
        error
    end
  end

  defp fetch_images_by_search_term(search_term) do
    case System.get_env("UNSPLASH_ACCESS_KEY") do
      nil ->
        Logger.error("UNSPLASH_ACCESS_KEY not set")
        {:error, :no_api_key}

      access_key ->
        query = URI.encode(search_term)
        # Random page (1-5) for variety
        page = :rand.uniform(5)

        url =
          "https://api.unsplash.com/search/photos" <>
            "?query=#{query}" <>
            "&orientation=landscape" <>
            "&per_page=15" <>
            "&page=#{page}" <>
            "&client_id=#{access_key}"

        Logger.info("Fetching from Unsplash: #{search_term} (page #{page})")

        fetch_with_retry(url, search_term)
    end
  end

  defp fetch_with_retry(url, city_name, attempt \\ 1) do
    max_attempts = 3

    case HTTPoison.get(url, [], follow_redirect: true) do
      {:ok, %{status_code: 200, body: body}} ->
        parse_response(body)

      {:ok, %{status_code: 403, body: body}} ->
        if String.contains?(body, "Rate Limit Exceeded") do
          if attempt < max_attempts do
            # 1.5s, 3s, 4.5s
            backoff = attempt * 1500

            Logger.warning(
              "Rate limited for #{city_name}, retrying in #{backoff}ms (attempt #{attempt}/#{max_attempts})"
            )

            Process.sleep(backoff)
            fetch_with_retry(url, city_name, attempt + 1)
          else
            Logger.error("Max retries exceeded for #{city_name}")
            {:error, :max_retries_exceeded}
          end
        else
          Logger.error("Access forbidden: #{body}")
          {:error, :forbidden}
        end

      {:ok, %{status_code: 429}} ->
        if attempt < max_attempts do
          # 2s, 4s, 6s
          backoff = attempt * 2000

          Logger.warning(
            "Rate limited (429) for #{city_name}, retrying in #{backoff}ms (attempt #{attempt}/#{max_attempts})"
          )

          Process.sleep(backoff)
          fetch_with_retry(url, city_name, attempt + 1)
        else
          Logger.error("Max retries exceeded for #{city_name}")
          {:error, :rate_limited}
        end

      {:ok, %{status_code: status_code, body: body}} ->
        Logger.error("Unsplash API error #{status_code}: #{body}")
        {:error, :api_error}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP request failed: #{inspect(reason)}")
        {:error, :request_failed}
    end
  end

  defp parse_response(body) do
    case Jason.decode(body) do
      {:ok, %{"results" => results}} when is_list(results) and length(results) > 0 ->
        # Sort by likes (popularity) descending and take top 10
        images =
          results
          |> Enum.sort_by(fn r -> Map.get(r, "likes", 0) end, :desc)
          |> Enum.take(@max_images)
          |> Enum.map(&format_image/1)

        {:ok, images}

      {:ok, %{"results" => _}} ->
        Logger.warning("No images found in Unsplash results")
        {:error, :no_images}

      {:ok, data} ->
        Logger.error("Unexpected Unsplash API response format: #{inspect(data)}")
        {:error, :invalid_response}

      {:error, error} ->
        Logger.error("Failed to parse Unsplash response: #{inspect(error)}")
        {:error, :parse_error}
    end
  end

  defp format_image(result) do
    %{
      "id" => get_in(result, ["id"]),
      "url" => get_in(result, ["urls", "regular"]),
      "thumb_url" => get_in(result, ["urls", "thumb"]),
      "download_url" => get_in(result, ["links", "download"]),
      "download_location" => get_in(result, ["links", "download_location"]),
      "color" => get_in(result, ["color"]),
      "width" => get_in(result, ["width"]),
      "height" => get_in(result, ["height"]),
      "attribution" => %{
        "photographer_name" => get_in(result, ["user", "name"]),
        "photographer_username" => get_in(result, ["user", "username"]),
        "photographer_url" =>
          "#{get_in(result, ["user", "links", "html"])}?utm_source=eventasaurus&utm_medium=referral",
        "unsplash_url" =>
          "#{get_in(result, ["links", "html"])}?utm_source=eventasaurus&utm_medium=referral"
      },
      "fetched_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp create_gallery(city, images) do
    gallery = %{
      "images" => images,
      "current_index" => 0,
      "last_refreshed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Logger.info("Storing gallery with #{length(images)} images for city: #{city.name}")

    case Repo.update(City.gallery_changeset(city, gallery)) do
      {:ok, updated_city} ->
        Logger.info("Successfully stored gallery for city: #{city.name}")
        {:ok, updated_city.unsplash_gallery}

      {:error, changeset} ->
        Logger.error("Failed to store gallery for #{city.name}: #{inspect(changeset.errors)}")
        {:error, :store_failed}
    end
  end

  @doc """
  Store or update a category in a city's gallery.
  Creates categorized structure if needed, or adds/updates a category.

  ## Parameters
    - city: City struct
    - category_name: Category identifier (e.g., "general", "architecture")
    - category_data: Map containing "search_terms", "images", "last_refreshed_at"

  Returns {:ok, updated_gallery} or {:error, reason}
  """
  @spec store_category(City.t(), String.t(), map()) :: {:ok, map()} | {:error, atom()}
  def store_category(city, category_name, category_data) do
    Logger.info("Storing category '#{category_name}' for city: #{city.name}")

    # Get existing gallery or create new categorized structure
    current_gallery = city.unsplash_gallery || %{}

    updated_gallery =
      if Map.has_key?(current_gallery, "categories") do
        # Update existing categorized gallery
        put_in(current_gallery, ["categories", category_name], category_data)
      else
        # Create new categorized gallery (migration from legacy format)
        %{
          "active_category" => category_name,
          "categories" => %{
            category_name => category_data
          }
        }
      end

    case Repo.update(City.gallery_changeset(city, updated_gallery)) do
      {:ok, updated_city} ->
        Logger.info(
          "Successfully stored category '#{category_name}' for city: #{city.name} (#{length(category_data["images"])} images)"
        )

        {:ok, updated_city.unsplash_gallery}

      {:error, changeset} ->
        Logger.error(
          "Failed to store category '#{category_name}' for #{city.name}: #{inspect(changeset.errors)}"
        )

        {:error, :store_failed}
    end
  end
end
