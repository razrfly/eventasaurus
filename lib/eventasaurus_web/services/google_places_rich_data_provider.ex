# Enhanced GooglePlacesRichDataProvider with caching and rate limiting
defmodule EventasaurusWeb.Services.GooglePlacesRichDataProvider do
  @moduledoc """
  Rich data provider for Google Places API integration.
  Fetches detailed venue, restaurant, and activity information with caching optimization.
  """

  @behaviour EventasaurusWeb.Services.RichDataProviderBehaviour



  require Logger

  # Cache keys and TTL
  @cache_name :google_places_cache
  @photo_cache_ttl 86_400_000  # 24 hours in ms
  @details_cache_ttl 3_600_000  # 1 hour in ms
  @rate_limit_key "google_places_rate_limit"
  @rate_limit_window 1000  # 1 second in ms
  @rate_limit_max_requests 10  # Max requests per second

  @impl true
  def provider_id, do: :google_places

  @impl true
  def provider_name, do: "Google Places"

  @impl true
  def supported_types, do: [:venue, :restaurant, :activity]

  @impl true
  def search(query, options \\ %{}) do
    with :ok <- check_rate_limit() do
      # Route to the appropriate API based on location scope
      location_scope = Map.get(options, :location_scope, "place")
      
      result = case location_scope do
        "city" -> search_cities_via_autocomplete(query, options)
        "region" -> search_via_geocoding(query, "administrative_area_level_1", options)
        "country" -> search_via_geocoding(query, "country", options)
        "custom" -> search_places_via_text_search(query, options)
        _ -> search_places_via_text_search(query, options)
      end
      
      case result do
        {:ok, results} -> {:ok, results}
        {:error, reason} ->
          Logger.warning("Google Places search failed: #{inspect(reason)}")
          {:error, :api_error}
      end
    else
      {:error, :rate_limited} = error -> error
    end
  end

  @impl true
  def get_details(_provider_id, content_id, _content_type, options \\ %{}) do
    # Use existing fetch_rich_data functionality
    external_data = %{"place_id" => content_id}
    case fetch_rich_data(external_data, Enum.into(options, [])) do
      {:ok, rich_data} -> {:ok, rich_data}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_cached_details(_provider_id, content_id, _content_type, _options \\ %{}) do
    cache_key = "place_details_#{content_id}"
    case Cachex.get(@cache_name, cache_key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, cached_data} -> {:ok, cached_data}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def validate_config do
    case get_api_key() do
      nil -> {:error, "Google Places API key not configured"}
      _key -> :ok
    end
  end

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

  # Search for actual places/venues using Text Search API
  defp search_places_via_text_search(query, options) do
    api_key = get_api_key()

    if api_key do
      # Build query parameters - no modification needed
      query_params = %{
        query: query,  # Pass query as-is, let Google handle it
        key: api_key
      }
      
      # Add location bias if provided
      query_params = add_location_bias(query_params, options)
      
      url = "https://maps.googleapis.com/maps/api/place/textsearch/json?" <>
        URI.encode_query(query_params)

      case HTTPoison.get(url, [], timeout: 10_000, recv_timeout: 10_000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"results" => results, "status" => "OK"}} ->
              normalized_results = Enum.map(results, &normalize_search_result/1)
              {:ok, normalized_results}
            {:ok, %{"results" => _results, "status" => "ZERO_RESULTS"}} ->
              {:ok, []}
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

  # Search for cities using Place Autocomplete API
  defp search_cities_via_autocomplete(query, options) do
    api_key = get_api_key()
    
    if api_key do
      # Use Place Autocomplete with (cities) type collection
      query_params = %{
        input: query,
        types: "(cities)",  # Returns locality or administrative_area_level_3
        key: api_key
      }
      
      # Add location bias if provided
      query_params = add_autocomplete_location_bias(query_params, options)
      
      url = "https://maps.googleapis.com/maps/api/place/autocomplete/json?" <>
        URI.encode_query(query_params)
      
      case HTTPoison.get(url, [], timeout: 10_000, recv_timeout: 10_000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"predictions" => predictions, "status" => "OK"}} ->
              # Convert autocomplete predictions to our normalized format
              normalized_results = Enum.map(predictions, &normalize_autocomplete_result/1)
              {:ok, normalized_results}
            {:ok, %{"predictions" => _, "status" => "ZERO_RESULTS"}} ->
              {:ok, []}
            {:ok, %{"status" => status}} ->
              {:error, "Autocomplete API returned status: #{status}"}
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
  
  # Search for regions/countries using Geocoding API
  defp search_via_geocoding(query, component_type, _options) do
    api_key = get_api_key()
    
    if api_key do
      query_params = %{
        address: query,
        key: api_key
      }
      
      url = "https://maps.googleapis.com/maps/api/geocode/json?" <>
        URI.encode_query(query_params)
      
      case HTTPoison.get(url, [], timeout: 10_000, recv_timeout: 10_000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"results" => results, "status" => "OK"}} ->
              # Filter results by component type
              filtered_results = filter_geocoding_results(results, component_type)
              normalized_results = Enum.map(filtered_results, &normalize_geocoding_result/1)
              {:ok, normalized_results}
            {:ok, %{"results" => _, "status" => "ZERO_RESULTS"}} ->
              {:ok, []}
            {:ok, %{"status" => status}} ->
              {:error, "Geocoding API returned status: #{status}"}
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
  
  # Add location bias to prefer results near a specific location
  defp add_location_bias(query_params, options) do
    case Map.get(options, :location_data) do
      %{"geometry" => %{"location" => %{"lat" => lat, "lng" => lng}}} ->
        # Add location bias using lat/lng
        Map.put(query_params, :location, "#{lat},#{lng}")
      _ ->
        query_params
    end
  end
  
  # Add location bias for autocomplete
  defp add_autocomplete_location_bias(query_params, options) do
    case Map.get(options, :location_data) do
      %{"geometry" => %{"location" => %{"lat" => lat, "lng" => lng}}} ->
        # Add location and radius for biasing
        query_params
        |> Map.put(:location, "#{lat},#{lng}")
        |> Map.put(:radius, 50000)  # 50km radius for city searches
      _ ->
        query_params
    end
  end
  
  # Filter geocoding results by type
  defp filter_geocoding_results(results, component_type) do
    Enum.filter(results, fn result ->
      types = Map.get(result, "types", [])
      component_type in types
    end)
  end

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
    System.get_env("GOOGLE_MAPS_API_KEY")
  end

  # Normalize Google Places Text Search results to match expected format
  defp normalize_search_result(place_data) do
    place_id = Map.get(place_data, "place_id")
    name = Map.get(place_data, "name", "Unknown Place")
    description = build_description(place_data)
    content_type = determine_content_type(place_data)
    # Get the first image URL, matching the polling system pattern
    image_url = extract_first_image_url(place_data)
    
    %{
      id: place_id,
      type: content_type,
      title: name,
      description: description,
      image_url: image_url,
      metadata: %{
        place_id: place_id,
        address: Map.get(place_data, "formatted_address"),
        rating: Map.get(place_data, "rating"),
        user_ratings_total: Map.get(place_data, "user_ratings_total"),
        price_level: Map.get(place_data, "price_level"),
        types: Map.get(place_data, "types", []),
        vicinity: Map.get(place_data, "vicinity"),
        geometry: Map.get(place_data, "geometry")
      }
    }
  end
  
  # Normalize Place Autocomplete results
  defp normalize_autocomplete_result(prediction) do
    place_id = Map.get(prediction, "place_id")
    description = Map.get(prediction, "description", "")
    
    # Extract city name and additional info from structured formatting
    main_text = Map.get(prediction, "structured_formatting", %{})
                |> Map.get("main_text", description)
    
    secondary_text = Map.get(prediction, "structured_formatting", %{})
                     |> Map.get("secondary_text", "")
    
    %{
      id: place_id,
      type: :city,  # Autocomplete with (cities) returns cities
      title: main_text,
      description: secondary_text,
      image_url: nil,  # Autocomplete doesn't provide images
      metadata: %{
        place_id: place_id,
        full_description: description,
        types: Map.get(prediction, "types", []),
        terms: Map.get(prediction, "terms", [])
      }
    }
  end
  
  # Normalize Geocoding API results
  defp normalize_geocoding_result(geocoding_data) do
    place_id = Map.get(geocoding_data, "place_id")
    formatted_address = Map.get(geocoding_data, "formatted_address", "")
    types = Map.get(geocoding_data, "types", [])
    
    # Determine the content type based on types
    content_type = cond do
      "country" in types -> :country
      "administrative_area_level_1" in types -> :region
      "administrative_area_level_2" in types -> :region
      "locality" in types -> :city
      true -> :place
    end
    
    # Extract the main name from address components
    address_components = Map.get(geocoding_data, "address_components", [])
    name = extract_name_from_components(address_components, types)
    
    %{
      id: place_id,
      type: content_type,
      title: name || formatted_address,
      description: formatted_address,
      image_url: nil,  # Geocoding doesn't provide images
      metadata: %{
        place_id: place_id,
        formatted_address: formatted_address,
        types: types,
        geometry: Map.get(geocoding_data, "geometry"),
        address_components: address_components
      }
    }
  end
  
  # Extract name from address components based on type
  defp extract_name_from_components(components, types) do
    target_type = cond do
      "country" in types -> "country"
      "administrative_area_level_1" in types -> "administrative_area_level_1"
      "administrative_area_level_2" in types -> "administrative_area_level_2"
      "locality" in types -> "locality"
      true -> nil
    end
    
    if target_type do
      component = Enum.find(components, fn comp ->
        target_type in Map.get(comp, "types", [])
      end)
      
      if component do
        Map.get(component, "long_name")
      end
    end
  end

  # Extract first image URL to match polling system pattern
  defp extract_first_image_url(place_data) do
    photos = Map.get(place_data, "photos", [])
    api_key = get_api_key()
    
    case {photos, api_key} do
      {[], _} -> nil
      {_, nil} -> nil
      {[first_photo | _], api_key} ->
        build_photo_url_from_reference(first_photo, api_key)
    end
  end

  # Note: extract_search_result_images removed as it was unused
  # Image extraction is handled by extract_first_image_url

  # Build photo URL from photo reference (similar to polling implementation)
  defp build_photo_url_from_reference(photo, api_key) when is_map(photo) do
    photo_reference = Map.get(photo, "photo_reference")
    max_width = min(Map.get(photo, "width", 400), 400)  # Smaller size for search results
    
    if photo_reference do
      "https://maps.googleapis.com/maps/api/place/photo" <>
        "?maxwidth=#{max_width}" <>
        "&photoreference=#{photo_reference}" <>
        "&key=#{api_key}"
    end
  end
  defp build_photo_url_from_reference(_, _), do: nil

  # ============================================================================
  # Polling-Specific Methods (PlacesDataService Compatibility)
  # ============================================================================

  @doc """
  Prepares place option data in a consistent format for polling system.
  Maintains compatibility with PlacesDataService while using the provider pattern.
  """
  def prepare_poll_option_data(place_data) do
    # Extract the place_id (Google's unique identifier)
    place_id = Map.get(place_data, "place_id") || Map.get(place_data, :place_id)

    # Extract the first photo URL for image_url field
    # First check if image_url is already provided (from search results)
    image_url = Map.get(place_data, "image_url") || 
                Map.get(place_data, :image_url) || 
                extract_poll_place_image_url(place_data)

    # Build rich description with rating, categories, and location
    description = build_poll_place_description(place_data)

    # Get the place name
    title = Map.get(place_data, "name") || Map.get(place_data, :name) || 
            Map.get(place_data, "title") || Map.get(place_data, :title) || "Unknown Place"

    # Prepare the data following the external API pattern
    %{
      "title" => title,
      "description" => description,
      "external_id" => "places:#{place_id}",  # Follow the "service:id" pattern
      "external_data" => place_data,          # Store complete Google Places response
      "image_url" => image_url                # Store first photo URL
    }
  end

  # Extract image URL from Google Places data, handling both string and map formats
  defp extract_poll_place_image_url(place_data) do
    photos = Map.get(place_data, "photos") || Map.get(place_data, :photos) || []

    case photos do
      [] -> nil
      [first_photo | _] when is_binary(first_photo) ->
        # Photos are already URL strings (from frontend processing)
        first_photo
      [first_photo | _] when is_map(first_photo) ->
        # Photos are map objects - build URL from reference
        api_key = get_api_key()
        if api_key, do: build_photo_url_from_reference(first_photo, api_key), else: nil
      _ -> nil
    end
  end

  @doc """
  Build a rich description for the place including rating, categories, and location.
  Used specifically for poll option display.
  """
  def build_poll_place_description(place_data) do
    parts = []

    # Add rating if available
    parts = if place_data["rating"] || place_data[:rating] do
      rating = place_data["rating"] || place_data[:rating]
      rating_text = "Rating: #{format_poll_rating(rating)}★"
      [rating_text | parts]
    else
      parts
    end

    # Add categories (place types)
    parts = if get_poll_place_categories(place_data) != [] do
      categories_text = get_poll_place_categories(place_data) |> Enum.join(", ")
      [categories_text | parts]
    else
      parts
    end

    # Add location (address or vicinity)
    parts = if get_poll_place_location(place_data) do
      location = get_poll_place_location(place_data)
      [location | parts]
    else
      parts
    end

    case parts do
      [] -> ""
      parts -> Enum.reverse(parts) |> Enum.join(" • ")
    end
  end

  @doc """
  Get place categories from types, filtering out generic ones.
  Used for poll display formatting.
  """
  def get_poll_place_categories(place_data) do
    types = place_data["types"] || place_data[:types] || []

    types
    |> Enum.reject(&(&1 in ["establishment", "point_of_interest"]))  # Filter generic types
    |> Enum.map(&humanize_poll_place_type/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.take(3)  # Limit to 3 categories for readability
  end

  @doc """
  Get place location text from various location fields.
  Used for poll option descriptions.
  """
  def get_poll_place_location(place_data) do
    place_data["vicinity"] || place_data[:vicinity] ||
    place_data["formatted_address"] || place_data[:formatted_address] ||
    place_data["address"] || place_data[:address]
  end

  # Private helper functions for polling

  defp format_poll_rating(rating) when is_number(rating) do
    Float.round(rating, 1)
  end
  defp format_poll_rating(rating) when is_binary(rating) do
    case Float.parse(rating) do
      {float_val, _} -> Float.round(float_val, 1)
      _ -> rating
    end
  end
  defp format_poll_rating(rating), do: rating

  defp humanize_poll_place_type(type) do
    case type do
      "restaurant" -> "Restaurant"
      "food" -> "Food"
      "meal_takeaway" -> "Takeaway"
      "meal_delivery" -> "Delivery"
      "cafe" -> "Cafe"
      "bar" -> "Bar"
      "night_club" -> "Nightclub"
      "tourist_attraction" -> "Tourist attraction"
      "amusement_park" -> "Amusement park"
      "zoo" -> "Zoo"
      "museum" -> "Museum"
      "park" -> "Park"
      "shopping_mall" -> "Shopping mall"
      "store" -> "Store"
      "lodging" -> "Lodging"
      "gym" -> "Gym"
      "spa" -> "Spa"
      "movie_theater" -> "Movie theater"
      "bowling_alley" -> "Bowling alley"
      "casino" -> "Casino"
      _ -> nil  # Filter out unrecognized types
    end
  end
end
