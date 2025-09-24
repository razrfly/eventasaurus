defmodule EventasaurusWeb.Services.GooglePlaces.Normalizer do
  @moduledoc """
  Normalizes Google Places API responses into consistent format for the application.
  Handles different response types and transforms them into unified structure.
  """

  alias EventasaurusWeb.Services.GooglePlaces.Photos
  require Logger

  @doc """
  Normalizes search results from Text Search API.
  """
  def normalize_search_result(place_data) do
    place_id = Map.get(place_data, "place_id")
    name = Map.get(place_data, "name", "Unknown Place")
    description = build_description(place_data)
    content_type = determine_content_type(place_data)
    image_url = Photos.extract_first_image_url(place_data)

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

  @doc """
  Normalizes autocomplete predictions for city searches.
  """
  def normalize_autocomplete_prediction(prediction) do
    place_id = Map.get(prediction, "place_id")
    description = Map.get(prediction, "description", "")

    # Extract main text (usually city name) and secondary text (region/country)
    structured = Map.get(prediction, "structured_formatting", %{})
    main_text = Map.get(structured, "main_text", description)
    secondary_text = Map.get(structured, "secondary_text", "")

    %{
      id: place_id,
      type: :city,
      title: main_text,
      description: secondary_text,
      # Autocomplete doesn't provide images
      image_url: nil,
      metadata: %{
        place_id: place_id,
        full_description: description,
        types: Map.get(prediction, "types", [])
      }
    }
  end

  @doc """
  Normalizes geocoding results for regions/countries.
  """
  def normalize_geocoding_result(result) do
    place_id = Map.get(result, "place_id")
    formatted_address = Map.get(result, "formatted_address", "")
    types = Map.get(result, "types", [])

    # Determine the administrative level
    content_type =
      cond do
        "country" in types -> :country
        "administrative_area_level_1" in types -> :region
        "administrative_area_level_2" in types -> :region
        true -> :location
      end

    # Extract components for better display
    components = Map.get(result, "address_components", [])
    name = extract_name_from_components(components, types)

    %{
      id: place_id,
      type: content_type,
      title: name || formatted_address,
      description: formatted_address,
      # Geocoding doesn't provide images
      image_url: nil,
      metadata: %{
        place_id: place_id,
        formatted_address: formatted_address,
        types: types,
        geometry: Map.get(result, "geometry"),
        address_components: components
      }
    }
  end

  @doc """
  Processes detailed place data into rich data format.
  """
  def process_place_data(place_data, opts \\ []) do
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

  @doc """
  Creates fallback data when API fails.
  """
  def create_fallback_data(external_data) do
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

  # Private helper functions

  defp determine_content_type(place_data) do
    types = Map.get(place_data, "types", [])

    cond do
      Enum.any?(
        types,
        &(&1 in ["restaurant", "food", "meal_takeaway", "meal_delivery", "cafe", "bar"])
      ) ->
        :restaurant

      Enum.any?(
        types,
        &(&1 in ["tourist_attraction", "amusement_park", "zoo", "museum", "park", "stadium"])
      ) ->
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
      # Assume open if status unknown
      {"OPERATIONAL", nil} -> "open"
      {"CLOSED_TEMPORARILY", _} -> "closed"
      {"CLOSED_PERMANENTLY", _} -> "closed"
      _ -> "unknown"
    end
  end

  defp extract_categories(place_data) do
    Map.get(place_data, "types", [])
    |> Enum.reject(&(&1 in ["establishment", "point_of_interest"]))
    |> Enum.map(&humanize_type/1)
    |> Enum.take(6)
  end

  defp humanize_type(type) do
    type
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp build_external_urls(place_data) do
    urls = %{}

    urls =
      if website = Map.get(place_data, "website") do
        Map.put(urls, :official, website)
      else
        urls
      end

    urls =
      if place_id = Map.get(place_data, "place_id") do
        google_maps_url = "https://www.google.com/maps/place/?q=place_id:#{place_id}"
        Map.put(urls, :maps, google_maps_url)
      else
        urls
      end

    urls
  end

  defp get_primary_image(place_data, opts) do
    case Photos.get_photos_with_caching(place_data, opts) do
      [first_photo | _] -> %{url: first_photo["url"], alt: "Primary image"}
      [] -> nil
    end
  end

  defp get_secondary_image(place_data, opts) do
    case Photos.get_photos_with_caching(place_data, opts) do
      [_, second_photo | _] -> %{url: second_photo["url"], alt: "Secondary image"}
      _ -> nil
    end
  end

  defp process_all_images(place_data, opts) do
    Photos.get_photos_with_caching(place_data, opts)
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
      price_level: format_price_level(Map.get(place_data, "price_level")),
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
      opening_hours: format_opening_hours(opening_hours),
      is_open_now: Map.get(opening_hours, "open_now")
    }
  end

  defp build_reviews_section(place_data, opts) do
    include_reviews = Keyword.get(opts, :include_reviews, true)

    if include_reviews do
      reviews = Map.get(place_data, "reviews", [])

      %{
        reviews: format_reviews(reviews |> Enum.take(5)),
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

  defp format_price_level(nil), do: nil

  defp format_price_level(level) do
    String.duplicate("$", level)
  end

  defp format_opening_hours(%{"weekday_text" => weekday_text}) when is_list(weekday_text) do
    %{
      weekday_text: weekday_text,
      formatted: Enum.join(weekday_text, "\n")
    }
  end

  defp format_opening_hours(_), do: nil

  defp format_reviews(reviews) when is_list(reviews) do
    Enum.map(reviews, fn review ->
      %{
        author_name: Map.get(review, "author_name"),
        rating: Map.get(review, "rating"),
        text: Map.get(review, "text"),
        time: Map.get(review, "time"),
        relative_time_description: Map.get(review, "relative_time_description")
      }
    end)
  end

  defp format_reviews(_), do: []

  defp extract_name_from_components(components, types) do
    cond do
      "country" in types ->
        find_component_name(components, "country")

      "administrative_area_level_1" in types ->
        find_component_name(components, "administrative_area_level_1")

      "administrative_area_level_2" in types ->
        find_component_name(components, "administrative_area_level_2")

      "locality" in types ->
        find_component_name(components, "locality")

      true ->
        nil
    end
  end

  defp find_component_name(components, type) do
    component =
      Enum.find(components, fn c ->
        type in Map.get(c, "types", [])
      end)

    if component do
      Map.get(component, "long_name")
    end
  end
end
