defmodule EventasaurusApp.Services.UnsplashImageFetcher do
  @moduledoc """
  Service for fetching and storing Unsplash image galleries in the database.
  Fetches landscape-oriented city images sorted by popularity.

  Only works with active cities (discovery_enabled = true).
  """

  require Logger
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City

  @max_images 10  # Number of images to store per city

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
        page = :rand.uniform(5)  # Random page (1-5) for variety

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

  defp fetch_with_retry(url, city_name, attempt \\ 1) do
    max_attempts = 3

    case HTTPoison.get(url, [], follow_redirect: true) do
      {:ok, %{status_code: 200, body: body}} ->
        parse_response(body)

      {:ok, %{status_code: 403, body: body}} ->
        if String.contains?(body, "Rate Limit Exceeded") do
          if attempt < max_attempts do
            backoff = attempt * 1500  # 1.5s, 3s, 4.5s
            Logger.warning("Rate limited for #{city_name}, retrying in #{backoff}ms (attempt #{attempt}/#{max_attempts})")
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
          backoff = attempt * 2000  # 2s, 4s, 6s
          Logger.warning("Rate limited (429) for #{city_name}, retrying in #{backoff}ms (attempt #{attempt}/#{max_attempts})")
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
      "color" => get_in(result, ["color"]),
      "width" => get_in(result, ["width"]),
      "height" => get_in(result, ["height"]),
      "attribution" => %{
        "photographer_name" => get_in(result, ["user", "name"]),
        "photographer_username" => get_in(result, ["user", "username"]),
        "photographer_url" => "#{get_in(result, ["user", "links", "html"])}?utm_source=eventasaurus&utm_medium=referral",
        "unsplash_url" => "#{get_in(result, ["links", "html"])}?utm_source=eventasaurus&utm_medium=referral"
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

    case Repo.update(City.changeset(city, %{unsplash_gallery: gallery})) do
      {:ok, updated_city} ->
        Logger.info("Successfully stored gallery for city: #{city.name}")
        {:ok, updated_city.unsplash_gallery}

      {:error, changeset} ->
        Logger.error("Failed to store gallery for #{city.name}: #{inspect(changeset.errors)}")
        {:error, :store_failed}
    end
  end
end
