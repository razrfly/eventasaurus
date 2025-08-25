defmodule EventasaurusWeb.Services.PlacesDataService do
  @moduledoc """
  DEPRECATED: This module has been replaced by GooglePlacesRichDataProvider.
  Use GooglePlacesRichDataProvider.prepare_poll_option_data/1 instead.
  
  This module is kept for backward compatibility only and will be removed in a future release.
  
  Original purpose: Shared service for preparing Google Places data consistently across all interfaces.
  Ensures places data follows the same external_id/external_data pattern as movies.
  """
  
  @deprecated "Use GooglePlacesRichDataProvider.prepare_poll_option_data/1 instead"

  @doc """
  Prepares place option data in a consistent format following the external API pattern.
  Uses external_id and external_data fields like movies, not metadata.
  """
  def prepare_place_option_data(place_data) do
    # Extract the place_id (Google's unique identifier)
    place_id = Map.get(place_data, "place_id") || Map.get(place_data, :place_id)

    # Extract the first photo URL for image_url field
    image_url = extract_place_image_url(place_data)

    # Build rich description with rating, categories, and location
    description = build_place_description(place_data)

    # Get the place name
    title = Map.get(place_data, "name") || Map.get(place_data, :name) || "Unknown Place"

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
  defp extract_place_image_url(place_data) do
    photos = Map.get(place_data, "photos") || Map.get(place_data, :photos) || []

    case photos do
      [] -> nil
      [first_photo | _] when is_binary(first_photo) ->
        # Photos are already URL strings (from frontend processing)
        first_photo
      [first_photo | _] when is_map(first_photo) ->
        # Photos are map objects with "url" key (from raw API)
        Access.get(first_photo, "url") || Access.get(first_photo, :url)
      _ -> nil
    end
  end

  @doc """
  Build a rich description for the place including rating, categories, and location.
  """
  def build_place_description(place_data) do
    parts = []

    # Add rating if available
    parts = if place_data["rating"] || place_data[:rating] do
      rating = place_data["rating"] || place_data[:rating]
      rating_text = "Rating: #{format_rating(rating)}★"
      [rating_text | parts]
    else
      parts
    end

    # Add categories (place types)
    parts = if get_place_categories(place_data) != [] do
      categories_text = get_place_categories(place_data) |> Enum.join(", ")
      [categories_text | parts]
    else
      parts
    end

    # Add location (address or vicinity)
    parts = if get_place_location(place_data) do
      location = get_place_location(place_data)
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
  """
  def get_place_categories(place_data) do
    types = place_data["types"] || place_data[:types] || []

    types
    |> Enum.reject(&(&1 in ["establishment", "point_of_interest"]))  # Filter generic types
    |> Enum.map(&humanize_place_type/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.take(3)  # Limit to 3 categories for readability
  end

  @doc """
  Get place location text from various location fields.
  """
  def get_place_location(place_data) do
    place_data["vicinity"] || place_data[:vicinity] ||
    place_data["formatted_address"] || place_data[:formatted_address] ||
    place_data["address"] || place_data[:address]
  end

  # Private helper functions

  defp format_rating(rating) when is_number(rating) do
    Float.round(rating, 1)
  end
  defp format_rating(rating) when is_binary(rating) do
    case Float.parse(rating) do
      {float_val, _} -> Float.round(float_val, 1)
      _ -> rating
    end
  end
  defp format_rating(rating), do: rating

  defp humanize_place_type(type) do
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
