defmodule EventasaurusDiscovery.Sources.WeekPl.Transformer do
  @moduledoc """
  Transform week.pl restaurant data into event structures.

  ## Transformation Logic
  - Each restaurant has 44 time slots per day (10 AM - 10 PM)
  - Each slot becomes an occurrence (explicit type)
  - Daily consolidation groups all slots into one event per restaurant per day
  - Consolidation key: metadata.restaurant_date_id

  ## Event Model
  - External ID: week_pl_{restaurant_id}_{date}_{slot}
  - Occurrence Type: explicit
  - Consolidation: Daily by restaurant_date_id
  """

  require Logger
  alias EventasaurusDiscovery.Sources.WeekPl.Helpers.TimeConverter

  @doc """
  Transform a restaurant time slot into an event occurrence.

  ## Parameters
  - restaurant: Restaurant data from week.pl API
  - slot: Time slot in minutes from midnight (e.g., 1140 = 7:00 PM)
  - date: Date string (ISO format, e.g., "2025-11-20")
  - festival: Festival data with name, code, and price
  - city: City name (from job args, e.g., "Kraków")

  ## Returns
  Map with event fields ready for EventProcessor
  """
  def transform_restaurant_slot(restaurant, slot, date, festival, city) do
    restaurant_id = get_restaurant_id(restaurant)
    date_struct = Date.from_iso8601!(date)
    timezone = TimeConverter.get_timezone(city)

    # Convert slot time to UTC DateTime
    {:ok, start_datetime} = TimeConverter.convert_minutes_to_time(slot, date_struct, timezone)

    # End time is 2 hours later (typical restaurant reservation duration)
    end_datetime = DateTime.add(start_datetime, 2 * 60 * 60, :second)

    # Consolidation key: Groups all 44 slots for same restaurant+date
    restaurant_date_id = "#{restaurant_id}_#{date}"

    # Slot-specific external ID for uniqueness
    external_id = "week_pl_#{restaurant_id}_#{date}_#{slot}"

    %{
      title: restaurant["name"],
      description: build_description(restaurant, festival, city),
      url: build_url(restaurant["slug"]),
      image_url: extract_primary_image(restaurant),
      external_id: external_id,
      occurrence_type: :explicit,
      starts_at: start_datetime,
      ends_at: end_datetime,
      # Food & Drink category (id 14)
      category_id: 14,
      venue_attributes: %{
        name: restaurant["name"],
        latitude: get_coordinate(restaurant, "lat"),
        longitude: get_coordinate(restaurant, "lng"),
        address: restaurant["address"],
        city: city,
        country: "Poland"
      },
      metadata: %{
        # Consolidation key for daily grouping
        restaurant_date_id: restaurant_date_id,
        # Additional context
        restaurant_id: restaurant_id,
        date: date,
        slot: slot,
        slot_time: TimeConverter.format_time(slot),
        festival_code: festival.code,
        festival_name: festival.name,
        menu_price: festival.price,
        cuisine: restaurant["cuisine"],
        available_spots: get_availability(restaurant, slot),
        # Social proof & quality
        rating: restaurant["rating"],
        rating_count: restaurant["ratingCount"],
        # Restaurant details
        chef: restaurant["chef"],
        restaurator: restaurant["restaurator"],
        establishment_year: restaurant["establishmentYear"],
        # External links
        website_url: restaurant["webUrl"],
        facebook_url: restaurant["facebookUrl"],
        instagram_url: restaurant["instagramUrl"],
        menu_file_url: restaurant["menuFileUrl"],
        # Raw upstream data for debugging
        _raw_upstream: restaurant
      }
    }
  end

  @doc """
  Transform listing of restaurants into multiple event occurrences.

  ## Parameters
  - restaurants: List of restaurant data from API
  - date: Date string (ISO format)
  - festival: Festival data
  - city: City name (e.g., "Kraków")

  ## Returns
  List of event maps, one per restaurant per slot
  """
  def transform_restaurants_listing(restaurants, date, festival, city) do
    Enum.flat_map(restaurants, fn restaurant ->
      # Get available slots for this restaurant
      slots = get_available_slots(restaurant)

      # Create event occurrence for each available slot
      Enum.map(slots, fn slot ->
        transform_restaurant_slot(restaurant, slot, date, festival, city)
      end)
    end)
  end

  # Private Helper Functions

  defp get_restaurant_id(%{"id" => id}) when is_binary(id), do: id
  defp get_restaurant_id(%{"id" => id}) when is_integer(id), do: Integer.to_string(id)
  defp get_restaurant_id(_), do: nil

  defp get_coordinate(%{"location" => %{"lat" => lat}}, "lat"), do: lat
  defp get_coordinate(%{"location" => %{"lng" => lng}}, "lng"), do: lng
  defp get_coordinate(%{"location" => %{"latitude" => lat}}, "lat"), do: lat
  defp get_coordinate(%{"location" => %{"longitude" => lng}}, "lng"), do: lng
  defp get_coordinate(%{"lat" => lat}, "lat"), do: lat
  defp get_coordinate(%{"lng" => lng}, "lng"), do: lng
  defp get_coordinate(%{"latitude" => lat}, "lat"), do: lat
  defp get_coordinate(%{"longitude" => lng}, "lng"), do: lng
  defp get_coordinate(_, _), do: nil

  defp get_availability(%{"slots" => slots}, slot) when is_list(slots) do
    case Enum.find(slots, fn s -> s["time"] == slot end) do
      %{"available" => available} -> available
      _ -> 0
    end
  end

  defp get_availability(_, _), do: 0

  defp get_available_slots(%{"slots" => slots}) when is_list(slots) do
    slots
    |> Enum.filter(fn slot -> slot["available"] > 0 end)
    |> Enum.map(fn slot -> slot["time"] end)
  end

  defp get_available_slots(_), do: []

  defp build_description(restaurant, festival, city) do
    """
    #{restaurant["name"]} - #{festival.name}

    Experience a specially curated #{festival.name} menu at #{restaurant["name"]}.
    Fixed price menu for #{festival.price} PLN per person.

    #{if restaurant["description"], do: restaurant["description"], else: ""}

    Cuisine: #{restaurant["cuisine"] || "Not specified"}
    Location: #{restaurant["address"]}, #{city}

    Book your table for this limited-time restaurant festival event.
    """
    |> String.trim()
  end

  defp build_url(slug) do
    "https://week.pl/#{slug}"
  end

  @doc """
  Extract all images from restaurant data for multi-image caching.

  Returns a list of image specs compatible with EventImageCaching.cache_event_images/4.
  First image is marked as "hero", subsequent images as "gallery".

  ## Parameters
  - restaurant: Restaurant data from Week.pl API containing "imageFiles" array
  - max_count: Maximum number of images to extract (default 5)

  ## Returns
  List of image specs: [%{url: String.t(), image_type: String.t(), position: integer()}]
  """
  def extract_all_images(restaurant, max_count \\ 5)

  def extract_all_images(%{"imageFiles" => image_files}, max_count)
      when is_list(image_files) and length(image_files) > 0 do
    image_files
    |> Enum.take(max_count)
    |> Enum.with_index()
    |> Enum.map(fn {image, index} ->
      # Priority order: profile (900px) > preview (500px) > original (1600px) > thumbnail (300px)
      url =
        image["profile"] || image["preview"] || image["original"] || image["thumbnail"]

      %{
        url: url,
        image_type: if(index == 0, do: "hero", else: "gallery"),
        position: index
      }
    end)
    |> Enum.filter(fn spec -> spec.url != nil end)
  end

  def extract_all_images(_, _max_count), do: []

  # Extract primary image URL from restaurant imageFiles array.
  # Uses 'profile' size (900px) for optimal quality/size balance.
  # Returns image URL string or nil if no images available.
  defp extract_primary_image(%{"imageFiles" => [first_image | _]} = restaurant)
       when is_map(first_image) do
    require Logger

    Logger.debug(
      "[WeekPl.Transformer] ✅ Found imageFiles for #{restaurant["name"]}, count: #{length(restaurant["imageFiles"])}"
    )

    # Priority order: profile (900px) > preview (500px) > original (1600px) > thumbnail (300px)
    image_url =
      first_image["profile"] || first_image["preview"] || first_image["original"] ||
        first_image["thumbnail"]

    Logger.debug(
      "[WeekPl.Transformer] 📸 Extracted image URL: #{String.slice(image_url || "nil", 0..60)}"
    )

    image_url
  end

  defp extract_primary_image(restaurant) do
    require Logger

    Logger.warning(
      "[WeekPl.Transformer] ❌ No imageFiles found for restaurant: #{restaurant["name"] || "unknown"}"
    )

    Logger.debug("[WeekPl.Transformer] Restaurant keys: #{inspect(Map.keys(restaurant))}")
    nil
  end
end
