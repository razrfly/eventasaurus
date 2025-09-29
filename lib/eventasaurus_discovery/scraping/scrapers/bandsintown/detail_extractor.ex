defmodule EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.DetailExtractor do
  @moduledoc """
  Extracts detailed event information from Bandsintown event pages.

  Primary focus is on extracting JSON-LD structured data which contains:
  - GPS coordinates for venues
  - Complete venue addresses
  - Artist information
  - Ticket details
  """

  require Logger

  @doc """
  Extracts comprehensive event details from an event page HTML.
  Prioritizes JSON-LD data which contains GPS coordinates.
  """
  def extract_event_details(html, url) do
    # First try to extract JSON-LD structured data (contains GPS!)
    case extract_json_ld_event(html) do
      {:ok, json_data} ->
        Logger.debug("✅ Extracted JSON-LD data with venue coordinates")
        {:ok, json_data}

      {:error, reason} ->
        Logger.warning("⚠️ No JSON-LD found: #{reason}, falling back to HTML parsing")
        # Fallback to HTML parsing (won't have GPS)
        extract_from_html(html, url)
    end
  end

  # Extract JSON-LD structured data (contains GPS coordinates!)
  defp extract_json_ld_event(html) do
    # Look for ALL JSON-LD script tags - there can be multiple
    matches = Regex.scan(~r/<script[^>]*type=["']application\/ld\+json["'][^>]*>(.*?)<\/script>/s, html)

    if matches == [] do
      {:error, "No JSON-LD script tag found"}
    else
      # Try to find an Event type in any of the JSON-LD blocks
      event_data = Enum.reduce_while(matches, nil, fn [_, json_str], _acc ->
        json_str = String.trim(json_str)

        case Jason.decode(json_str) do
          {:ok, data} when is_map(data) ->
            # Check if this is an Event type
            if Map.get(data, "@type") in ["Event", "MusicEvent", "Concert"] do
              {:halt, data}
            else
              {:cont, nil}
            end

          {:ok, data} when is_list(data) ->
            # Sometimes there are multiple items in one JSON-LD block
            event = Enum.find(data, fn item ->
              is_map(item) && Map.get(item, "@type") in ["Event", "MusicEvent", "Concert"]
            end)

            if event do
              {:halt, event}
            else
              {:cont, nil}
            end

          {:error, _} ->
            # Skip malformed JSON blocks
            {:cont, nil}
        end
      end)

      if event_data do
        {:ok, transform_json_ld_to_event(event_data)}
      else
        Logger.warning("No Event type found in any JSON-LD blocks")
        {:error, "No Event type found in JSON-LD"}
      end
    end
  end

  # Transform JSON-LD Event data to our format
  defp transform_json_ld_to_event(event) do
    location = event["location"] || %{}
    address = location["address"] || %{}
    geo = location["geo"] || %{}
    offers = List.wrap(event["offers"])
    performer = extract_performer(event["performer"])

    %{
      "title" => event["name"],
      "description" => event["description"],
      "date" => event["startDate"],
      "end_date" => event["endDate"],
      "image_url" => extract_image_url(event["image"]),
      "url" => event["url"],

      # Venue information WITH GPS COORDINATES!
      "venue_name" => location["name"],
      "venue_address" => address["streetAddress"],
      "venue_city" => address["addressLocality"],
      "venue_state" => address["addressRegion"],
      "venue_country" => address["addressCountry"],
      "venue_postal_code" => address["postalCode"],

      # THE CRITICAL GPS COORDINATES!
      "venue_latitude" => extract_coordinate(geo["latitude"]),
      "venue_longitude" => extract_coordinate(geo["longitude"]),

      # Artist information
      "artist_name" => performer["name"],
      "artist_url" => performer["url"],
      "artist_image_url" => extract_image_url(performer["image"]),

      # Ticket information
      "ticket_url" => extract_ticket_url(offers, event),
      "min_price" => extract_min_price(offers),
      "max_price" => extract_max_price(offers),
      "currency" => extract_currency(offers),

      # Additional metadata
      "metadata" => %{
        "source" => "json-ld",
        "has_coordinates" => geo["latitude"] != nil && geo["longitude"] != nil
      }
    }
  end

  # Extract coordinate as float
  defp extract_coordinate(nil), do: nil
  defp extract_coordinate(coord) when is_number(coord), do: coord
  defp extract_coordinate(coord) when is_binary(coord) do
    case Float.parse(coord) do
      {float, _} -> float
      _ -> nil
    end
  end

  defp extract_performer(nil), do: %{}
  defp extract_performer(performer) when is_list(performer), do: List.first(performer) || %{}
  defp extract_performer(performer) when is_map(performer), do: performer

  defp extract_image_url(nil), do: nil
  defp extract_image_url(image) when is_binary(image), do: image
  defp extract_image_url(image) when is_map(image), do: image["url"]
  defp extract_image_url(images) when is_list(images) do
    case List.first(images) do
      nil -> nil
      img when is_binary(img) -> img
      img when is_map(img) -> img["url"]
    end
  end

  defp extract_ticket_url([], event), do: event["url"]
  defp extract_ticket_url([offer | _], _event), do: offer["url"]

  defp extract_min_price([]), do: nil
  defp extract_min_price([offer | _]) do
    case offer["price"] do
      nil -> nil
      price when is_number(price) -> price
      price when is_binary(price) ->
        case Float.parse(price) do
          {num, _} -> num
          _ -> nil
        end
    end
  end

  defp extract_max_price(offers) do
    extract_min_price(offers)  # Often same for Bandsintown
  end

  defp extract_currency([]), do: "USD"
  defp extract_currency([offer | _]), do: offer["priceCurrency"] || "USD"

  # Fallback HTML parsing (won't have GPS coordinates)
  defp extract_from_html(html, url) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        event_data = %{
          "url" => url,
          "title" => extract_text(document, "h1"),
          "artist_name" => extract_text(document, ".artist-name, .event-artist"),
          "venue_name" => extract_text(document, ".venue-name, .event-venue"),
          "venue_address" => extract_text(document, ".venue-address, .event-location"),
          "description" => extract_text(document, ".event-description, .artist-bio"),
          "image_url" => extract_meta_image(document),
          "metadata" => %{
            "source" => "html",
            "has_coordinates" => false
          }
        }
        {:ok, event_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_text(document, selector) do
    document
    |> Floki.find(selector)
    |> Floki.text()
    |> String.trim()
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp extract_meta_image(document) do
    document
    |> Floki.find("meta[property='og:image']")
    |> Floki.attribute("content")
    |> List.first()
  end
end