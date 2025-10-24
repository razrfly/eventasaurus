defmodule EventasaurusApp.Services.UnsplashService do
  @moduledoc """
  Service for accessing cached Unsplash city images with daily rotation.

  This service provides access to pre-fetched Unsplash images stored in the
  cities table. Images rotate daily based on day of year.

  Only works with active cities (discovery_enabled = true).
  """

  require Logger
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  import Ecto.Query

  @doc """
  Get the current daily image for a city.
  Returns the image URL and attribution info, or nil if not found.

  Only works for cities with discovery_enabled = true.

  ## Examples

      iex> get_city_image("London")
      {:ok, %{
        url: "https://images.unsplash.com/...",
        thumb_url: "https://images.unsplash.com/...",
        color: "#c0d5e8",
        attribution: %{
          photographer_name: "John Doe",
          photographer_url: "https://unsplash.com/@johndoe?utm_source=eventasaurus...",
          unsplash_url: "https://unsplash.com/photos/abc123?utm_source=eventasaurus..."
        }
      }}

      iex> get_city_image("InactiveCity")
      {:error, :inactive_city}
  """
  @spec get_city_image(String.t()) :: {:ok, map()} | {:error, atom()}
  def get_city_image(city_name) do
    query =
      from(c in City,
        where: c.name == ^city_name and c.discovery_enabled == true,
        select: c.unsplash_gallery
      )

    case Repo.one(query) do
      nil ->
        Logger.warning("City not found or not active: #{city_name}")
        {:error, :not_found}

      gallery when is_map(gallery) ->
        get_daily_image_from_gallery(gallery)

      _ ->
        Logger.warning("No gallery data for city: #{city_name}")
        {:error, :no_gallery}
    end
  end

  @doc """
  Get current daily images for multiple cities in a single query.
  Prevents N+1 queries when displaying multiple cities.

  Only returns images for cities with discovery_enabled = true.

  ## Examples

      iex> get_city_images_batch(["London", "Paris", "Kraków"])
      %{
        "London" => %{url: "...", attribution: %{}},
        "Paris" => %{url: "...", attribution: %{}},
        "Kraków" => %{url: "...", attribution: %{}}
      }
  """
  @spec get_city_images_batch([String.t()]) :: map()
  def get_city_images_batch(city_names) when is_list(city_names) do
    query =
      from(c in City,
        where: c.name in ^city_names and c.discovery_enabled == true,
        select: {c.name, c.unsplash_gallery}
      )

    Repo.all(query)
    |> Enum.reduce(%{}, fn {city_name, gallery}, acc ->
      case get_daily_image_from_gallery(gallery) do
        {:ok, image} -> Map.put(acc, city_name, image)
        {:error, _} -> acc
      end
    end)
  end

  @doc """
  Refresh images for a specific city by fetching new ones from Unsplash.

  Only works for cities with discovery_enabled = true.

  Returns {:ok, gallery} or {:error, reason}.
  """
  @spec refresh_city_images(String.t()) :: {:ok, map()} | {:error, atom()}
  def refresh_city_images(city_name) do
    alias EventasaurusApp.Services.UnsplashImageFetcher
    UnsplashImageFetcher.fetch_and_store_city_images(city_name)
  end

  @doc """
  Get all active cities that have cached image galleries.

  Returns a list of city names (discovery_enabled = true only).
  """
  @spec cities_with_galleries() :: [String.t()]
  def cities_with_galleries do
    query =
      from(c in City,
        where: c.discovery_enabled == true and not is_nil(c.unsplash_gallery),
        select: c.name
      )

    Repo.all(query)
  end

  # Private functions

  defp get_daily_image_from_gallery(nil), do: {:error, :no_gallery}

  defp get_daily_image_from_gallery(gallery) when is_map(gallery) do
    images = Map.get(gallery, "images", [])

    if Enum.empty?(images) do
      {:error, :no_images}
    else
      index = get_daily_image_index(length(images))
      image = Enum.at(images, index)
      {:ok, image}
    end
  end

  defp get_daily_image_from_gallery(_), do: {:error, :invalid_gallery}

  @doc """
  Calculate which image to show based on day of year.
  Rotates daily through the available images.

  ## Examples

      iex> get_daily_image_index(10)
      # Returns 0-9 based on current day of year
  """
  @spec get_daily_image_index(pos_integer()) :: non_neg_integer()
  def get_daily_image_index(image_count) when image_count > 0 do
    day_of_year = Date.utc_today() |> Date.day_of_year()
    rem(day_of_year, image_count)
  end
end
