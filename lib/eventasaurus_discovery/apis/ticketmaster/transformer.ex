defmodule EventasaurusDiscovery.Apis.Ticketmaster.Transformer do
  @moduledoc """
  Transforms Ticketmaster API responses to our standardized schema.
  Handles the mapping of complex nested structures to our database format.
  """

  require Logger

  @doc """
  Transforms a Ticketmaster event to our standardized event data structure.
  """
  def transform_event(tm_event) when is_map(tm_event) do
    %{
      external_id: "tm_#{tm_event["id"]}",
      title: tm_event["name"],
      description: extract_description(tm_event),
      start_at: parse_event_datetime(tm_event),
      ends_at: parse_event_end_datetime(tm_event),
      status: map_event_status(tm_event),
      is_ticketed: true,  # All Ticketmaster events are ticketed
      venue_data: extract_venue(tm_event),
      performers: extract_performers(tm_event),
      metadata: extract_event_metadata(tm_event),
      # Add raw event data for category extraction
      raw_event_data: tm_event
    }
  end

  @doc """
  Transforms a Ticketmaster venue to our standardized venue data structure.
  """
  def transform_venue(tm_venue) when is_map(tm_venue) do
    %{
      external_id: "tm_venue_#{tm_venue["id"]}",
      name: tm_venue["name"],
      address: get_in(tm_venue, ["address", "line1"]),
      city: get_in(tm_venue, ["city", "name"]),
      state: get_in(tm_venue, ["state", "name"]) || get_in(tm_venue, ["state", "stateCode"]),
      country: get_in(tm_venue, ["country", "name"]) || get_in(tm_venue, ["country", "countryCode"]),
      postal_code: tm_venue["postalCode"],
      latitude: get_in(tm_venue, ["location", "latitude"]) |> to_float(),
      longitude: get_in(tm_venue, ["location", "longitude"]) |> to_float(),
      timezone: tm_venue["timezone"],
      metadata: extract_venue_metadata(tm_venue)
    }
  end

  @doc """
  Transforms a Ticketmaster attraction/performer to our standardized performer data structure.
  """
  def transform_performer(tm_attraction) when is_map(tm_attraction) do
    %{
      external_id: "tm_performer_#{tm_attraction["id"]}",
      name: tm_attraction["name"],
      type: extract_performer_type(tm_attraction),
      metadata: extract_performer_metadata(tm_attraction)
    }
  end

  # Private helper functions

  defp extract_description(event) do
    cond do
      event["info"] -> event["info"]
      event["pleaseNote"] -> event["pleaseNote"]
      event["description"] -> event["description"]
      true -> generate_description(event)
    end
  end

  defp generate_description(event) do
    parts = []

    # Add genre/classification info
    parts = if classifications = event["classifications"] do
      classification = List.first(classifications) || %{}
      genre = get_in(classification, ["genre", "name"])
      segment = get_in(classification, ["segment", "name"])

      if genre && segment do
        ["#{segment} - #{genre}" | parts]
      else
        parts
      end
    else
      parts
    end

    # Add price range info
    parts = if price_ranges = event["priceRanges"] do
      price = List.first(price_ranges) || %{}
      if min = price["min"] do
        ["Starting from #{min} #{price["currency"]}" | parts]
      else
        parts
      end
    else
      parts
    end

    # Add sale dates
    parts = if sales = get_in(event, ["sales", "public"]) do
      if start_date = sales["startDateTime"] do
        ["Tickets on sale: #{format_date(start_date)}" | parts]
      else
        parts
      end
    else
      parts
    end

    Enum.join(parts, ". ")
  end

  defp parse_event_datetime(event) do
    dates = event["dates"] || %{}
    start = dates["start"] || %{}

    datetime_string = start["dateTime"] || start["localDate"]

    case datetime_string do
      nil ->
        Logger.warning("No start date found for event #{event["id"]}")
        nil
      date_string ->
        parse_datetime_string(date_string, dates["timezone"])
    end
  end

  defp parse_event_end_datetime(event) do
    dates = event["dates"] || %{}

    # Ticketmaster rarely provides end times
    if end_date = dates["end"] do
      datetime_string = end_date["dateTime"] || end_date["localDate"]
      parse_datetime_string(datetime_string, dates["timezone"])
    else
      nil
    end
  end

  defp parse_datetime_string(datetime_string, timezone) do
    cond do
      # Check if it's already a valid datetime with timezone
      String.contains?(datetime_string, "T") ->
        case DateTime.from_iso8601(datetime_string) do
          {:ok, datetime, _offset} ->
            datetime
          {:error, :missing_offset} ->
            # Try with Z suffix for UTC
            case DateTime.from_iso8601(datetime_string <> "Z") do
              {:ok, datetime, _offset} ->
                datetime
              _ ->
                Logger.warning("Could not parse datetime: #{datetime_string}")
                nil
            end
          _ ->
            Logger.warning("Could not parse datetime: #{datetime_string}")
            nil
        end

      # It's just a date, parse and add default time
      true ->
        case Date.from_iso8601(datetime_string) do
          {:ok, date} ->
            # Default to 8 PM in the venue's timezone or UTC
            time = ~T[20:00:00]
            _tz = timezone || "UTC"

            # Create a NaiveDateTime first
            naive_datetime = NaiveDateTime.new!(date, time)

            # Convert to UTC datetime (we'll store everything as UTC)
            # For now, just assume the timezone offset
            DateTime.from_naive!(naive_datetime, "Etc/UTC")
          _ ->
            Logger.warning("Could not parse date: #{datetime_string}")
            nil
        end
    end
  end

  defp map_event_status(event) do
    status_code = get_in(event, ["dates", "status", "code"])

    case status_code do
      "onsale" -> "active"
      "offsale" -> "completed"
      "cancelled" -> "cancelled"
      "postponed" -> "postponed"
      "rescheduled" -> "rescheduled"
      _ -> "active"
    end
  end

  defp extract_venue(event) do
    venues = get_in(event, ["_embedded", "venues"]) || []

    case List.first(venues) do
      nil -> nil
      venue -> transform_venue(venue)
    end
  end

  defp extract_performers(event) do
    attractions = get_in(event, ["_embedded", "attractions"]) || []
    Enum.map(attractions, &transform_performer/1)
  end

  defp extract_performer_type(attraction) do
    classifications = attraction["classifications"] || []

    case List.first(classifications) do
      nil -> "artist"
      classification ->
        segment = get_in(classification, ["segment", "name"])
        case String.downcase(segment || "") do
          "music" -> "band"
          "sports" -> "team"
          "arts" -> "artist"
          "theatre" -> "theater"
          _ -> "artist"
        end
    end
  end

  defp extract_event_metadata(event) do
    %{
      ticketmaster_data: %{
        id: event["id"],
        url: event["url"],
        locale: event["locale"],
        images: extract_images(event["images"]),
        price_ranges: event["priceRanges"],
        sales: event["sales"],
        classifications: event["classifications"],
        promoters: event["promoters"],
        seatmap: get_in(event, ["seatmap", "staticUrl"]),
        accessibility: event["accessibility"],
        ticket_limit: get_in(event, ["ticketLimit", "info"]),
        age_restrictions: event["ageRestrictions"],
        products: extract_products(event)
      }
    }
  end

  defp extract_venue_metadata(venue) do
    %{
      ticketmaster_data: %{
        id: venue["id"],
        url: venue["url"],
        locale: venue["locale"],
        images: extract_images(venue["images"]),
        parking_detail: venue["parkingDetail"],
        accessible_seating: venue["accessibleSeatingDetail"],
        general_info: venue["generalInfo"],
        box_office_info: venue["boxOfficeInfo"],
        social_media: venue["social"],
        ada: venue["ada"],
        upcoming_events: get_in(venue, ["upcomingEvents", "_total"])
      }
    }
  end

  defp extract_performer_metadata(attraction) do
    %{
      ticketmaster_data: %{
        id: attraction["id"],
        url: attraction["url"],
        locale: attraction["locale"],
        images: extract_images(attraction["images"]),
        classifications: attraction["classifications"],
        upcoming_events: get_in(attraction, ["upcomingEvents", "_total"]),
        external_links: extract_external_links(attraction["externalLinks"])
      }
    }
  end

  defp extract_images(nil), do: []
  defp extract_images(images) when is_list(images) do
    images
    |> Enum.map(fn img ->
      %{
        url: img["url"],
        ratio: img["ratio"],
        width: img["width"],
        height: img["height"],
        fallback: img["fallback"]
      }
    end)
    |> Enum.reject(fn img -> is_nil(img.url) end)
  end

  defp extract_products(event) do
    products = get_in(event, ["products"]) || []
    Enum.map(products, fn product ->
      %{
        id: product["id"],
        name: product["name"],
        type: product["type"],
        url: product["url"]
      }
    end)
  end

  defp extract_external_links(nil), do: %{}
  defp extract_external_links(links) do
    Enum.reduce(links, %{}, fn {platform, platform_links}, acc ->
      if is_list(platform_links) && length(platform_links) > 0 do
        link = List.first(platform_links)
        Map.put(acc, platform, link["url"])
      else
        acc
      end
    end)
  end

  defp format_date(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} ->
        Calendar.strftime(datetime, "%B %d, %Y")
      _ ->
        date_string
    end
  end

  defp to_float(nil), do: nil
  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value * 1.0
  defp to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> nil
    end
  end
end