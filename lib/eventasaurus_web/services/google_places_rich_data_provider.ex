# Enhanced GooglePlacesRichDataProvider with caching and rate limiting
defmodule EventasaurusWeb.Services.GooglePlacesRichDataProvider do
  @moduledoc """
  Rich data provider for Google Places API integration.
  Fetches detailed venue, restaurant, and activity information with caching optimization.
  """



  require Logger

  # Cache keys and TTL
  @cache_name :google_places_cache
  @photo_cache_ttl 86_400_000  # 24 hours in ms
  @details_cache_ttl 3_600_000  # 1 hour in ms
  @rate_limit_key "google_places_rate_limit"
  @rate_limit_window 1000  # 1 second in ms
  @rate_limit_max_requests 10  # Max requests per second

  def supported_types, do: [:venue, :restaurant, :activity]

  def can_handle?(external_data) when is_map(external_data) do
    # Check for Google Places specific fields
    has_place_id = Map.has_key?(external_data, "place_id")
    has_google_fields = Map.has_key?(external_data, "formatted_address") or
                       Map.has_key?(external_data, "geometry") or
                       Map.has_key?(external_data, "rating")

    has_place_id and has_google_fields
  end

  def can_handle?(_), do: false

  def fetch_rich_data(external_data, opts \\ []) do
    with :ok <- check_rate_limit(),
         {:ok, enhanced_data} <- fetch_enhanced_place_details(external_data, opts),
         {:ok, processed_data} <- process_place_data(enhanced_data, opts) do
      {:ok, processed_data}
    else
      {:error, :rate_limited} ->
                  Logger.warning("Google Places API rate limited")
        {:ok, create_fallback_data(external_data)}

      {:error, reason} ->
        Logger.error("Failed to fetch Google Places data: #{inspect(reason)}")
        {:ok, create_fallback_data(external_data)}
    end
  end

  # Private functions

  defp check_rate_limit do
    current_time = System.monotonic_time(:millisecond)

    case Cachex.get(@cache_name, @rate_limit_key) do
      {:ok, nil} ->
        # First request in window
        Cachex.put(@cache_name, @rate_limit_key, %{count: 1, window_start: current_time}, ttl: @rate_limit_window)
        :ok

      {:ok, %{count: count, window_start: window_start}} ->
        if current_time - window_start > @rate_limit_window do
          # New window, reset counter
          Cachex.put(@cache_name, @rate_limit_key, %{count: 1, window_start: current_time}, ttl: @rate_limit_window)
          :ok
        else
          if count >= @rate_limit_max_requests do
            {:error, :rate_limited}
          else
            # Increment counter
            Cachex.put(@cache_name, @rate_limit_key, %{count: count + 1, window_start: window_start}, ttl: @rate_limit_window)
            :ok
          end
        end

      {:error, _} ->
        # Cache error, allow request but log warning
        Logger.warning("Rate limit cache error, allowing request")
        :ok
    end
  end

  defp fetch_enhanced_place_details(external_data, opts) do
    place_id = Map.get(external_data, "place_id")
    cache_key = "place_details_#{place_id}"

    case get_cached_or_fetch(cache_key, @details_cache_ttl, fn ->
      fetch_place_details_from_api(place_id, opts)
    end) do
      {:ok, enhanced_data} ->
        # Merge original data with enhanced data
        merged_data = Map.merge(external_data, enhanced_data)
        {:ok, merged_data}

      {:error, reason} ->
        Logger.warning("Failed to fetch enhanced place details: #{inspect(reason)}")
        {:ok, external_data}  # Fallback to original data
    end
  end

  defp fetch_place_details_from_api(place_id, opts) do
    api_key = get_api_key()

    if api_key do
      url = build_details_url(place_id, api_key, opts)

      case HTTPoison.get(url, [], timeout: 10_000, recv_timeout: 10_000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"result" => result, "status" => "OK"}} ->
              {:ok, result}
            {:ok, %{"status" => status}} ->
              {:error, "API returned status: #{status}"}
            {:error, reason} ->
              {:error, "JSON decode error: #{inspect(reason)}"}
          end

        {:ok, %HTTPoison.Response{status_code: status_code}} ->
          {:error, "HTTP #{status_code}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, "HTTP error: #{inspect(reason)}"}
      end
    else
      {:error, "No API key configured"}
    end
  end

  defp build_details_url(place_id, api_key, opts) do
    fields = get_fields_for_request(opts)

    "https://maps.googleapis.com/maps/api/place/details/json?" <>
    URI.encode_query(%{
      place_id: place_id,
      fields: fields,
      key: api_key
    })
  end

  defp get_fields_for_request(opts) do
    base_fields = ["name", "formatted_address", "rating", "user_ratings_total",
                   "price_level", "types", "business_status", "opening_hours",
                   "formatted_phone_number", "website", "geometry"]

    additional_fields = case Keyword.get(opts, :include_photos, true) do
      true -> ["photos"]
      false -> []
    end

    review_fields = case Keyword.get(opts, :include_reviews, true) do
      true -> ["reviews"]
      false -> []
    end

    (base_fields ++ additional_fields ++ review_fields)
    |> Enum.join(",")
  end

  defp process_place_data(place_data, opts) do
    try do
      processed = %{
        title: Map.get(place_data, "name", "Unknown Place"),
        type: determine_content_type(place_data),
        description: build_description(place_data),
        rating: build_rating_data(place_data),
        status: determine_status(place_data),
        categories: extract_categories(place_data),
        external_urls: build_external_urls(place_data),
        primary_image: get_primary_image(place_data, opts),
        secondary_image: get_secondary_image(place_data, opts),
        images: process_all_images(place_data, opts),
        sections: build_sections(place_data, opts)
      }

      {:ok, processed}
    rescue
      e ->
        Logger.error("Error processing place data: #{inspect(e)}")
        {:error, "Data processing failed"}
    end
  end

  defp get_primary_image(place_data, opts) do
    case get_photos_with_caching(place_data, opts) do
      [first_photo | _] -> %{url: first_photo["url"], alt: "Primary image"}
      [] -> nil
    end
  end

  defp get_secondary_image(place_data, opts) do
    case get_photos_with_caching(place_data, opts) do
      [_, second_photo | _] -> %{url: second_photo["url"], alt: "Secondary image"}
      _ -> nil
    end
  end

  defp process_all_images(place_data, opts) do
    case get_photos_with_caching(place_data, opts) do
      photos when is_list(photos) ->
        photos
        |> Enum.take(12)  # Limit to 12 photos for performance
        |> Enum.with_index()
        |> Enum.map(fn {photo, index} ->
          %{
            url: photo["url"],
            alt: "Photo #{index + 1}",
            thumbnail_url: photo["thumbnail_url"],
            width: photo["width"],
            height: photo["height"]
          }
        end)
      _ -> []
    end
  end

  defp get_photos_with_caching(place_data, opts) do
    photos = Map.get(place_data, "photos", [])
    max_photos = Keyword.get(opts, :max_photos, 12)

    photos
    |> Enum.take(max_photos)
    |> Enum.map(&process_photo_with_cache/1)
    |> Enum.filter(& &1)  # Remove failed photo fetches
  end

  defp process_photo_with_cache(photo) when is_map(photo) do
    photo_reference = Map.get(photo, "photo_reference")
    cache_key = "photo_url_#{photo_reference}"

    case get_cached_or_fetch(cache_key, @photo_cache_ttl, fn ->
      fetch_photo_url(photo)
    end) do
      {:ok, photo_data} -> photo_data
      {:error, _} -> nil
    end
  end

  defp fetch_photo_url(photo) do
    api_key = get_api_key()
    photo_reference = Map.get(photo, "photo_reference")

    if api_key and photo_reference do
      # Build photo URL with caching-friendly parameters
      base_url = "https://maps.googleapis.com/maps/api/place/photo"
      max_width = min(Map.get(photo, "width", 800), 800)  # Limit size for performance

      photo_url = "#{base_url}?" <> URI.encode_query(%{
        maxwidth: max_width,
        photo_reference: photo_reference,
        key: api_key
      })

      # Also generate a thumbnail URL
      thumbnail_url = "#{base_url}?" <> URI.encode_query(%{
        maxwidth: 200,
        photo_reference: photo_reference,
        key: api_key
      })

      photo_data = %{
        "url" => photo_url,
        "thumbnail_url" => thumbnail_url,
        "width" => Map.get(photo, "width"),
        "height" => Map.get(photo, "height")
      }

      {:ok, photo_data}
    else
      {:error, "Missing API key or photo reference"}
    end
  end

  defp get_cached_or_fetch(cache_key, ttl, fetch_fn) do
    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} ->
        # Not in cache, fetch and cache
        case fetch_fn.() do
          {:ok, data} ->
            Cachex.put(@cache_name, cache_key, data, ttl: ttl)
            {:ok, data}
          error ->
            error
        end

      {:ok, cached_data} ->
        # Found in cache
        {:ok, cached_data}

      {:error, _cache_error} ->
        # Cache error, fetch directly
        fetch_fn.()
    end
  end

  defp create_fallback_data(external_data) do
    # Create minimal data structure when API fails
    %{
      title: Map.get(external_data, "name", "Unknown Place"),
      type: :venue,
      description: Map.get(external_data, "vicinity", ""),
      rating: %{
        value: Map.get(external_data, "rating"),
        count: Map.get(external_data, "user_ratings_total")
      },
      status: "unknown",
      categories: Map.get(external_data, "types", []),
      external_urls: %{},
      primary_image: nil,
      secondary_image: nil,
      images: [],
      sections: %{
        hero: build_hero_section(external_data),
        details: build_details_section(external_data)
      }
    }
  end

  defp determine_content_type(place_data) do
    types = Map.get(place_data, "types", [])

    cond do
      Enum.any?(types, &(&1 in ["restaurant", "food", "meal_takeaway", "meal_delivery"])) ->
        :restaurant
      Enum.any?(types, &(&1 in ["tourist_attraction", "amusement_park", "zoo", "museum", "park"])) ->
        :activity
      true ->
        :venue
    end
  end

  defp build_description(place_data) do
    vicinity = Map.get(place_data, "vicinity")
    formatted_address = Map.get(place_data, "formatted_address")

    vicinity || formatted_address || ""
  end

  defp build_rating_data(place_data) do
    %{
      value: Map.get(place_data, "rating"),
      count: Map.get(place_data, "user_ratings_total")
    }
  end

  defp determine_status(place_data) do
    business_status = Map.get(place_data, "business_status")
    opening_hours = Map.get(place_data, "opening_hours", %{})
    is_open = Map.get(opening_hours, "open_now")

    case {business_status, is_open} do
      {"OPERATIONAL", true} -> "open"
      {"OPERATIONAL", false} -> "closed"
      {"OPERATIONAL", nil} -> "open"  # Assume open if status unknown
      {"CLOSED_TEMPORARILY", _} -> "closed"
      {"CLOSED_PERMANENTLY", _} -> "closed"
      _ -> "unknown"
    end
  end

  defp extract_categories(place_data) do
    Map.get(place_data, "types", [])
    |> Enum.reject(&(&1 in ["establishment", "point_of_interest"]))
    |> Enum.take(6)  # Limit categories for performance
  end

  defp build_external_urls(place_data) do
    urls = %{}

    urls = if website = Map.get(place_data, "website") do
      Map.put(urls, :official, website)
    else
      urls
    end

    urls = if place_id = Map.get(place_data, "place_id") do
      google_maps_url = "https://www.google.com/maps/place/?q=place_id:#{place_id}"
      Map.put(urls, :maps, google_maps_url)
    else
      urls
    end

    urls
  end

  defp build_sections(place_data, opts) do
    %{
      hero: build_hero_section(place_data),
      details: build_details_section(place_data),
      reviews: build_reviews_section(place_data, opts),
      photos: build_photos_section(place_data, opts)
    }
  end

  defp build_hero_section(place_data) do
    %{
      subtitle: Map.get(place_data, "formatted_address") || Map.get(place_data, "vicinity"),
      price_level: Map.get(place_data, "price_level"),
      status: Map.get(place_data, "business_status"),
      categories: extract_categories(place_data)
    }
  end

  defp build_details_section(place_data) do
    opening_hours = Map.get(place_data, "opening_hours", %{})

    %{
      formatted_address: Map.get(place_data, "formatted_address"),
      phone: Map.get(place_data, "formatted_phone_number"),
      website: Map.get(place_data, "website"),
      opening_hours: opening_hours
    }
  end

  defp build_reviews_section(place_data, opts) do
    include_reviews = Keyword.get(opts, :include_reviews, true)

    if include_reviews do
      reviews = Map.get(place_data, "reviews", [])
      %{
        reviews: reviews |> Enum.take(5),  # Limit reviews for performance
        overall_rating: Map.get(place_data, "rating"),
        total_ratings: Map.get(place_data, "user_ratings_total")
      }
    else
      %{reviews: [], overall_rating: nil, total_ratings: nil}
    end
  end

  defp build_photos_section(place_data, opts) do
    %{
      photos: process_all_images(place_data, opts)
    }
  end

  defp get_api_key do
    Application.get_env(:eventasaurus, :google_places_api_key) ||
    System.get_env("GOOGLE_PLACES_API_KEY")
  end
end
