defmodule EventasaurusWeb.Live.Components.Adapters.GooglePlacesDataAdapter do
  @moduledoc """
  Data adapter for Google Places content.

  Normalizes Google Places venue, restaurant, and activity data into the standardized format
  for use with generic rich content display components.
  """

  @behaviour EventasaurusWeb.Live.Components.RichDataAdapterBehaviour

  @impl true
  def adapt(raw_data) when is_map(raw_data) do
    %{
      id: get_place_id(raw_data),
      type: get_content_type(raw_data),
      title: get_title(raw_data),
      description: get_description(raw_data),
      primary_image: get_primary_image(raw_data),
      secondary_image: get_secondary_image(raw_data),
      rating: get_rating_info(raw_data),
      year: nil,  # Places don't have years
      status: get_status(raw_data),
      categories: get_categories(raw_data),
      tags: get_tags(raw_data),
      external_urls: get_external_urls(raw_data),
      sections: build_sections(raw_data)
    }
  end

  @impl true
  def content_type, do: :venue

  @impl true
  def supported_sections, do: [:hero, :details, :reviews, :photos]

  @impl true
  def handles?(raw_data) when is_map(raw_data) do
    # Check if this looks like Google Places data
    has_place_id = Map.has_key?(raw_data, "place_id") || Map.has_key?(raw_data, "id")
    has_places_fields = Map.has_key?(raw_data, "rating") || Map.has_key?(raw_data, "vicinity")
    has_location_data = Map.has_key?(raw_data, "geometry") || Map.has_key?(raw_data, "formatted_address")

        has_place_id && has_places_fields && has_location_data
  end

  @impl true
  def display_config do
    %{
      default_sections: [:hero, :details, :reviews, :photos],
      compact_sections: [:hero, :details],
      required_fields: [:id, :title, :type],
      optional_fields: [:description, :rating, :categories, :primary_image]
    }
  end

  # Private implementation functions

  defp get_place_id(raw_data) do
    case raw_data["place_id"] || raw_data["id"] do
      id when is_binary(id) -> "places_#{id}"
      _ -> "places_unknown"
    end
  end

  defp get_content_type(raw_data) do
    types = raw_data["types"] || []

    cond do
      "restaurant" in types || "food" in types || "meal_takeaway" in types -> :restaurant
      "lodging" in types || "tourist_attraction" in types || "amusement_park" in types -> :activity
      true -> :venue
    end
  end

  defp get_title(raw_data) do
    raw_data["name"] || raw_data["title"] || "Unknown Place"
  end

  defp get_description(raw_data) do
    parts = []

    # Add rating if available
    parts = if raw_data["rating"] do
      rating_text = "Rating: #{format_rating(raw_data["rating"])}★"
      [rating_text | parts]
    else
      parts
    end

    # Add categories
    parts = if get_categories(raw_data) != [] do
      categories_text = get_categories(raw_data) |> Enum.join(", ")
      [categories_text | parts]
    else
      parts
    end

    # Add location
    parts = if raw_data["vicinity"] || raw_data["formatted_address"] do
      location = raw_data["vicinity"] || raw_data["formatted_address"]
      [location | parts]
    else
      parts
    end

    case parts do
      [] -> nil
      parts -> Enum.reverse(parts) |> Enum.join(" • ")
    end
  end

  defp get_primary_image(raw_data) do
    photos = raw_data["photos"] || []

    case photos do
      [first_photo | _] when is_map(first_photo) ->
        %{
          url: build_photo_url(first_photo),
          alt: get_title(raw_data),
          type: :photo
        }
      _ -> nil
    end
  end

  defp get_secondary_image(raw_data) do
    photos = raw_data["photos"] || []

    case photos do
      [_, second_photo | _] when is_map(second_photo) ->
        %{
          url: build_photo_url(second_photo),
          alt: "#{get_title(raw_data)} photo",
          type: :photo
        }
      _ -> nil
    end
  end

  defp get_rating_info(raw_data) do
    rating = raw_data["rating"]
    user_ratings_total = raw_data["user_ratings_total"]

    case {rating, user_ratings_total} do
      {rating, count} when is_number(rating) and is_integer(count) ->
        %{
          value: rating,
          scale: 5,
          count: count,
          display: "#{format_rating(rating)}/5"
        }
      {rating, _} when is_number(rating) ->
        %{
          value: rating,
          scale: 5,
          count: 0,
          display: "#{format_rating(rating)}/5"
        }
      _ -> nil
    end
  end

  defp get_status(raw_data) do
    case raw_data["business_status"] do
      "OPERATIONAL" -> "open"
      "CLOSED_TEMPORARILY" -> "temporarily_closed"
      "CLOSED_PERMANENTLY" -> "permanently_closed"
      status when is_binary(status) -> String.downcase(status)
      _ ->
        # Fallback to opening hours
        if raw_data["opening_hours"] do
          case raw_data["opening_hours"]["open_now"] do
            true -> "open"
            false -> "closed"
            _ -> nil
          end
        end
    end
  end

  defp get_categories(raw_data) do
    types = raw_data["types"] || []

    types
    |> Enum.reject(&(&1 in ["establishment", "point_of_interest"]))  # Filter generic types
    |> Enum.map(&humanize_type/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp get_tags(raw_data) do
    tags = []

    # Add tags based on various criteria
    tags = if (raw_data["rating"] || 0) >= 4.5, do: ["Highly Rated" | tags], else: tags
    tags = if (raw_data["user_ratings_total"] || 0) >= 1000, do: ["Popular" | tags], else: tags
    tags = if raw_data["price_level"] && raw_data["price_level"] == 4, do: ["Premium" | tags], else: tags

    # Check if permanently closed
    tags = if raw_data["business_status"] == "CLOSED_PERMANENTLY", do: ["Closed" | tags], else: tags

    tags
  end

  defp get_external_urls(raw_data) do
    %{
      source: build_google_maps_url(raw_data),
      official: raw_data["website"],
      maps: build_google_maps_url(raw_data)
    }
    |> filter_empty_urls()
  end

  defp build_sections(raw_data) do
    %{
      hero: build_hero_section(raw_data),
      details: build_details_section(raw_data),
      reviews: build_reviews_section(raw_data),
      photos: build_photos_section(raw_data)
    }
    |> Enum.filter(fn {_key, value} -> value != nil end)
    |> Enum.into(%{})
  end

  defp build_hero_section(raw_data) do
    %{
      title: get_title(raw_data),
      subtitle: raw_data["vicinity"] || raw_data["formatted_address"],
      photo_url: get_primary_image(raw_data)[:url],
      rating: get_rating_info(raw_data),
      price_level: raw_data["price_level"],
      categories: get_categories(raw_data),
      status: get_status(raw_data),
      opening_hours: raw_data["opening_hours"]
    }
  end

  defp build_details_section(raw_data) do
    %{
      formatted_address: raw_data["formatted_address"],
      phone: raw_data["formatted_phone_number"] || raw_data["international_phone_number"],
      website: raw_data["website"],
      opening_hours: raw_data["opening_hours"],
      price_level: raw_data["price_level"],
      wheelchair_accessible: raw_data["wheelchair_accessible_entrance"],
      geometry: raw_data["geometry"],
      place_id: raw_data["place_id"]
    }
  end

  defp build_reviews_section(raw_data) do
    reviews = raw_data["reviews"] || []
    overall_rating = raw_data["rating"]
    total_ratings = raw_data["user_ratings_total"]

    if length(reviews) > 0 || overall_rating do
      %{
        overall_rating: overall_rating,
        total_ratings: total_ratings,
        reviews: reviews
      }
    end
  end

  defp build_photos_section(raw_data) do
    photos = raw_data["photos"] || []

    if length(photos) > 0 do
      %{
        photos: photos
      }
    end
  end

  # Helper functions

  defp format_rating(rating) when is_number(rating) do
    :erlang.float_to_binary(rating, [{:decimals, 1}])
  end
  defp format_rating(_), do: "N/A"

  defp humanize_type(type) when is_binary(type) do
    case type do
      "amusement_park" -> "Amusement Park"
      "art_gallery" -> "Art Gallery"
      "bakery" -> "Bakery"
      "bank" -> "Bank"
      "bar" -> "Bar"
      "beauty_salon" -> "Beauty Salon"
      "book_store" -> "Book Store"
      "bowling_alley" -> "Bowling Alley"
      "bus_station" -> "Bus Station"
      "cafe" -> "Cafe"
      "campground" -> "Campground"
      "car_dealer" -> "Car Dealer"
      "car_rental" -> "Car Rental"
      "car_repair" -> "Car Repair"
      "car_wash" -> "Car Wash"
      "casino" -> "Casino"
      "cemetery" -> "Cemetery"
      "church" -> "Church"
      "city_hall" -> "City Hall"
      "clothing_store" -> "Clothing Store"
      "convenience_store" -> "Convenience Store"
      "courthouse" -> "Courthouse"
      "dentist" -> "Dentist"
      "department_store" -> "Department Store"
      "doctor" -> "Doctor"
      "drugstore" -> "Drugstore"
      "electrician" -> "Electrician"
      "electronics_store" -> "Electronics Store"
      "embassy" -> "Embassy"
      "fire_station" -> "Fire Station"
      "florist" -> "Florist"
      "funeral_home" -> "Funeral Home"
      "furniture_store" -> "Furniture Store"
      "gas_station" -> "Gas Station"
      "gym" -> "Gym"
      "hair_care" -> "Hair Care"
      "hardware_store" -> "Hardware Store"
      "hindu_temple" -> "Hindu Temple"
      "home_goods_store" -> "Home Goods Store"
      "hospital" -> "Hospital"
      "insurance_agency" -> "Insurance Agency"
      "jewelry_store" -> "Jewelry Store"
      "laundry" -> "Laundry"
      "lawyer" -> "Lawyer"
      "library" -> "Library"
      "light_rail_station" -> "Light Rail Station"
      "liquor_store" -> "Liquor Store"
      "local_government_office" -> "Government Office"
      "locksmith" -> "Locksmith"
      "lodging" -> "Lodging"
      "meal_delivery" -> "Meal Delivery"
      "meal_takeaway" -> "Takeaway"
      "mosque" -> "Mosque"
      "movie_rental" -> "Movie Rental"
      "movie_theater" -> "Movie Theater"
      "moving_company" -> "Moving Company"
      "museum" -> "Museum"
      "night_club" -> "Night Club"
      "painter" -> "Painter"
      "park" -> "Park"
      "parking" -> "Parking"
      "pet_store" -> "Pet Store"
      "pharmacy" -> "Pharmacy"
      "physiotherapist" -> "Physiotherapist"
      "plumber" -> "Plumber"
      "police" -> "Police"
      "post_office" -> "Post Office"
      "primary_school" -> "Primary School"
      "real_estate_agency" -> "Real Estate Agency"
      "restaurant" -> "Restaurant"
      "roofing_contractor" -> "Roofing Contractor"
      "rv_park" -> "RV Park"
      "school" -> "School"
      "secondary_school" -> "Secondary School"
      "shoe_store" -> "Shoe Store"
      "shopping_mall" -> "Shopping Mall"
      "spa" -> "Spa"
      "stadium" -> "Stadium"
      "storage" -> "Storage"
      "store" -> "Store"
      "subway_station" -> "Subway Station"
      "supermarket" -> "Supermarket"
      "synagogue" -> "Synagogue"
      "taxi_stand" -> "Taxi Stand"
      "tourist_attraction" -> "Tourist Attraction"
      "train_station" -> "Train Station"
      "transit_station" -> "Transit Station"
      "travel_agency" -> "Travel Agency"
      "university" -> "University"
      "veterinary_care" -> "Veterinary Care"
      "zoo" -> "Zoo"
      _ ->
        type
        |> String.replace("_", " ")
        |> String.split(" ")
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")
    end
  end
  defp humanize_type(_), do: nil

  defp build_photo_url(photo) when is_map(photo) do
    photo_reference = photo["photo_reference"]
    max_width = photo["width"] || 400

    if photo_reference do
      "https://maps.googleapis.com/maps/api/place/photo" <>
        "?maxwidth=#{max_width}" <>
        "&photoreference=#{photo_reference}" <>
        "&key=#{System.get_env("GOOGLE_MAPS_API_KEY")}"
    end
  end
  defp build_photo_url(_), do: nil

  defp build_google_maps_url(raw_data) do
    place_id = raw_data["place_id"]

    if place_id do
      "https://www.google.com/maps/place/?q=place_id:#{place_id}"
    else
      # Fallback to name and address search
      name = raw_data["name"]
      address = raw_data["vicinity"] || raw_data["formatted_address"]

      if name && address do
        query = URI.encode("#{name}, #{address}")
        "https://www.google.com/maps/search/#{query}"
      end
    end
  end

  defp filter_empty_urls(url_map) when is_map(url_map) do
    url_map
    |> Enum.filter(fn
      {_key, value} when is_binary(value) -> value != ""
      {_key, value} when is_map(value) -> map_size(filter_empty_urls(value)) > 0
      _ -> false
    end)
    |> Enum.into(%{})
  end
end
