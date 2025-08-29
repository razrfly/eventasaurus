defmodule EventasaurusWeb.Services.GooglePlaces.Photos do
  @moduledoc """
  Handles Google Places photo URL generation and caching.
  Processes photo references into usable URLs with various sizes.
  """

  alias EventasaurusWeb.Services.GooglePlaces.Client
  require Logger

  @base_url "https://maps.googleapis.com/maps/api/place/photo"
  @photo_cache_ttl 86_400_000  # 24 hours in ms
  @max_width_default 800
  @thumbnail_width 200

  @doc """
  Builds a photo URL from a photo reference.
  """
  def build_url(photo_reference, options \\ %{}) when is_binary(photo_reference) do
    api_key = Client.get_api_key()
    
    if api_key do
      max_width = Map.get(options, :max_width, @max_width_default)
      
      url = "#{@base_url}?" <> URI.encode_query(%{
        maxwidth: max_width,
        photoreference: photo_reference,
        key: api_key
      })
      
      {:ok, url}
    else
      {:error, "No API key configured"}
    end
  end

  @doc """
  Processes a photo object from the API response with caching.
  Returns URLs for both full size and thumbnail.
  """
  def process_photo(photo) when is_map(photo) do
    photo_reference = Map.get(photo, "photo_reference")
    
    if photo_reference do
      cache_key = "photo_url_#{photo_reference}"
      
      Client.get_cached_or_fetch(cache_key, @photo_cache_ttl, fn ->
        generate_photo_urls(photo)
      end)
    else
      {:error, "No photo reference"}
    end
  end

  def process_photo(_), do: {:error, "Invalid photo data"}

  @doc """
  Processes multiple photos with caching.
  """
  def process_photos(photos, opts \\ []) when is_list(photos) do
    max_photos = Keyword.get(opts, :max_photos, 12)
    
    photos
    |> Enum.take(max_photos)
    |> Enum.map(&process_photo/1)
    |> Enum.map(fn
      {:ok, photo_data} -> photo_data
      {:error, _} -> nil
    end)
    |> Enum.filter(& &1)
  end

  @doc """
  Extracts the first image URL from place data.
  Used for search results and list displays.
  """
  def extract_first_image_url(place_data) do
    photos = Map.get(place_data, "photos", [])
    
    case photos do
      [] -> nil
      [first_photo | _] ->
        case build_url_from_photo(first_photo, max_width: 400) do
          {:ok, url} -> url
          {:error, _} -> nil
        end
    end
  end

  @doc """
  Gets all photo URLs from place data with caching.
  """
  def get_photos_with_caching(place_data, opts \\ []) do
    photos = Map.get(place_data, "photos", [])
    max_photos = Keyword.get(opts, :max_photos, 12)
    
    photos
    |> Enum.take(max_photos)
    |> Enum.map(&process_photo/1)
    |> Enum.map(fn
      {:ok, photo_data} -> photo_data
      {:error, _} -> nil
    end)
    |> Enum.filter(& &1)
  end

  # Private functions

  defp generate_photo_urls(photo) do
    api_key = Client.get_api_key()
    photo_reference = Map.get(photo, "photo_reference")
    
    if api_key && photo_reference do
      width = Map.get(photo, "width", @max_width_default)
      height = Map.get(photo, "height")
      max_width = min(width, @max_width_default)
      
      # Generate main URL
      main_url = "#{@base_url}?" <> URI.encode_query(%{
        maxwidth: max_width,
        photoreference: photo_reference,
        key: api_key
      })
      
      # Generate thumbnail URL
      thumbnail_url = "#{@base_url}?" <> URI.encode_query(%{
        maxwidth: @thumbnail_width,
        photoreference: photo_reference,
        key: api_key
      })
      
      {:ok, %{
        "url" => main_url,
        "thumbnail_url" => thumbnail_url,
        "width" => width,
        "height" => height
      }}
    else
      {:error, "Missing API key or photo reference"}
    end
  end

  defp build_url_from_photo(photo, options) when is_map(photo) do
    photo_reference = Map.get(photo, "photo_reference")
    
    if photo_reference do
      build_url(photo_reference, Enum.into(options, %{}))
    else
      {:error, "No photo reference"}
    end
  end
end