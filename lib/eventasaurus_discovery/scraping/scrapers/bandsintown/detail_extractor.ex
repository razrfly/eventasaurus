defmodule EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.DetailExtractor do
  @moduledoc """
  Extracts detailed event information from Bandsintown event pages.

  Parses:
  - Event metadata (title, date, description)
  - Venue information (name, address, coordinates)
  - Artist information (name, genre, links)
  - Ticket information (prices, availability, purchase links)
  - Social engagement (RSVP count, interested count)
  """

  require Logger

  @doc """
  Extracts comprehensive event details from an event page HTML.
  """
  def extract_event_details(html, url) do
    # First try to extract JSON-LD structured data
    case extract_json_ld_event(html) do
      {:ok, json_data} ->
        # Enhance with additional HTML parsing if needed
        enhanced_data = enhance_with_html_data(json_data, html)
        {:ok, enhanced_data}

      {:error, _} ->
        # Fallback to pure HTML parsing
        extract_from_html(html, url)
    end
  end

  # Extract JSON-LD structured data (most reliable)
  defp extract_json_ld_event(html) do
    # Look for all JSON-LD scripts - there may be multiple
    json_ld_scripts = Regex.scan(~r/<script[^>]*type="application\/ld\+json"[^>]*>(.*?)<\/script>/s, html)

    # Try to find the MusicEvent schema
    result = json_ld_scripts
    |> Enum.find_value(fn [_, json_str] ->
      case parse_json_ld(json_str) do
        {:ok, data} -> {:ok, data}
        _ -> nil
      end
    end)

    result || {:error, :no_json_ld}
  end

  defp parse_json_ld(json_str) do
    case Jason.decode(json_str) do
      {:ok, data} when is_list(data) ->
        # Find the Event object
        event = Enum.find(data, fn item ->
          is_map(item) && Map.get(item, "@type") in ["Event", "MusicEvent"]
        end)

        if event do
          {:ok, transform_json_ld_event(event)}
        else
          {:error, :no_event_schema}
        end

      {:ok, data} when is_map(data) ->
        if Map.get(data, "@type") in ["Event", "MusicEvent"] do
          {:ok, transform_json_ld_event(data)}
        else
          {:error, :not_event_schema}
        end

      _ ->
        {:error, :invalid_json_ld}
    end
  end

  defp transform_json_ld_event(event) do
    location = event["location"] || %{}
    offers = List.wrap(event["offers"])
    performer = extract_performer(event["performer"])

    %{
      "title" => event["name"],
      "description" => event["description"],
      "date" => event["startDate"],
      "end_date" => event["endDate"],
      "image_url" => extract_image_url(event["image"]),

      # Venue information
      "venue_name" => location["name"],
      "venue_address" => get_in(location, ["address", "streetAddress"]),
      "venue_city" => get_in(location, ["address", "addressLocality"]),
      "venue_region" => get_in(location, ["address", "addressRegion"]),
      "venue_country" => get_in(location, ["address", "addressCountry"]),
      "venue_postal_code" => get_in(location, ["address", "postalCode"]),
      "venue_latitude" => get_in(location, ["geo", "latitude"]),
      "venue_longitude" => get_in(location, ["geo", "longitude"]),

      # Artist information
      "artist_name" => performer["name"],
      "artist_url" => performer["url"],
      "artist_same_as" => performer["sameAs"], # Social media links

      # Ticket information
      "ticket_url" => extract_ticket_url(offers),
      "min_price" => extract_min_price(offers),
      "max_price" => extract_max_price(offers),
      "currency" => extract_currency(offers),
      "availability" => extract_availability(offers)
    }
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

  defp extract_ticket_url([]), do: nil
  defp extract_ticket_url([offer | _]), do: offer["url"]

  defp extract_min_price([]), do: nil
  defp extract_min_price(offers) do
    offers
    |> Enum.map(fn o -> parse_price(o["price"] || o["lowPrice"]) end)
    |> Enum.filter(& &1)
    |> Enum.min(fn -> nil end)
  end

  defp extract_max_price([]), do: nil
  defp extract_max_price(offers) do
    offers
    |> Enum.map(fn o -> parse_price(o["price"] || o["highPrice"]) end)
    |> Enum.filter(& &1)
    |> Enum.max(fn -> nil end)
  end

  defp extract_currency([]), do: nil
  defp extract_currency([offer | _]), do: offer["priceCurrency"]

  defp extract_availability([]), do: nil
  defp extract_availability([offer | _]) do
    case offer["availability"] do
      "http://schema.org/InStock" -> "in_stock"
      "http://schema.org/SoldOut" -> "sold_out"
      "http://schema.org/PreOrder" -> "pre_order"
      other -> other
    end
  end

  defp parse_price(nil), do: nil
  defp parse_price(price) when is_number(price), do: price
  defp parse_price(price) when is_binary(price) do
    price
    |> String.replace(~r/[^\d.]/, "")
    |> Float.parse()
    |> case do
      {value, _} -> value
      :error -> nil
    end
  end

  # Enhance JSON-LD data with additional HTML parsing
  defp enhance_with_html_data(json_data, html) do
    # Parse HTML with Floki
    {:ok, document} = Floki.parse_document(html)

    enhancements = %{
      # RSVP/Interested counts (usually in buttons or counters)
      "rsvp_count" => extract_rsvp_count(document),
      "interested_count" => extract_interested_count(document),

      # Genre/tags (might be in meta tags or page sections)
      "genre" => extract_genre(document),
      "tags" => extract_tags(document),

      # Supporting acts
      "supporting_acts" => extract_supporting_acts(document),

      # Social media specific to this event
      "facebook_event" => extract_facebook_event_url(document),
      "event_status" => extract_event_status(document)
    }

    Map.merge(json_data, enhancements)
  end

  # Fallback: Pure HTML extraction when no JSON-LD available
  defp extract_from_html(html, url) do
    {:ok, document} = Floki.parse_document(html)

    event_data = %{
      "url" => url,
      "title" => extract_title(document),
      "artist_name" => extract_artist_name(document),
      "date" => extract_date(document),
      "venue_name" => extract_venue_name(document),
      "venue_address" => extract_venue_address(document),
      "description" => extract_description(document),
      "image_url" => extract_image(document),
      "ticket_url" => extract_ticket_link(document),
      "rsvp_count" => extract_rsvp_count(document),
      "interested_count" => extract_interested_count(document),
      "genre" => extract_genre(document),
      "tags" => extract_tags(document)
    }

    {:ok, event_data}
  end

  # HTML extraction helpers
  defp extract_title(document) do
    Floki.find(document, "h1")
    |> Floki.text()
    |> String.trim()
  end

  defp extract_artist_name(document) do
    # Try multiple selectors
    Floki.find(document, ".artist-name, .event-artist, [data-artist-name]")
    |> Floki.text()
    |> String.trim()
  end

  defp extract_date(document) do
    # Look for time tag or specific date elements
    Floki.find(document, "time[datetime]")
    |> Floki.attribute("datetime")
    |> List.first()
  end

  defp extract_venue_name(document) do
    Floki.find(document, ".venue-name, .event-venue, [data-venue-name]")
    |> Floki.text()
    |> String.trim()
  end

  defp extract_venue_address(document) do
    Floki.find(document, ".venue-address, .event-location, [data-venue-address]")
    |> Floki.text()
    |> String.trim()
  end

  defp extract_description(document) do
    Floki.find(document, ".event-description, .artist-bio, [data-event-description]")
    |> Floki.text()
    |> String.trim()
  end

  defp extract_image(document) do
    # Try og:image meta tag first
    og_image = Floki.find(document, "meta[property='og:image']")
    |> Floki.attribute("content")
    |> List.first()

    og_image || extract_main_image(document)
  end

  defp extract_main_image(document) do
    Floki.find(document, ".event-image img, .artist-image img, picture img")
    |> Floki.attribute("src")
    |> List.first()
  end

  defp extract_ticket_link(document) do
    Floki.find(document, "a[href*='ticket'], .ticket-button, .buy-tickets")
    |> Floki.attribute("href")
    |> List.first()
  end

  defp extract_rsvp_count(document) do
    # Look for RSVP count in various formats
    rsvp_text = Floki.find(document, "[data-rsvp-count], .rsvp-count, .attending-count")
    |> Floki.text()

    extract_number_from_text(rsvp_text)
  end

  defp extract_interested_count(document) do
    interested_text = Floki.find(document, "[data-interested-count], .interested-count")
    |> Floki.text()

    extract_number_from_text(interested_text)
  end

  defp extract_genre(document) do
    Floki.find(document, ".genre, .music-genre, [data-genre]")
    |> Floki.text()
    |> String.trim()
    |> case do
      "" -> nil
      genre -> genre
    end
  end

  defp extract_tags(document) do
    Floki.find(document, ".tag, .event-tag, [data-tag]")
    |> Enum.map(&Floki.text/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp extract_supporting_acts(document) do
    Floki.find(document, ".supporting-acts, .lineup, [data-supporting-acts]")
    |> Enum.map(&Floki.text/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp extract_facebook_event_url(document) do
    Floki.find(document, "a[href*='facebook.com/events']")
    |> Floki.attribute("href")
    |> List.first()
  end

  defp extract_event_status(document) do
    status_text = Floki.find(document, ".event-status, [data-event-status]")
    |> Floki.text()
    |> String.downcase()

    cond do
      String.contains?(status_text, "cancelled") -> "cancelled"
      String.contains?(status_text, "postponed") -> "postponed"
      String.contains?(status_text, "sold out") -> "sold_out"
      true -> "scheduled"
    end
  end

  defp extract_number_from_text(text) do
    case Regex.run(~r/(\d+(?:,\d+)*(?:\.\d+)?)[kKmM]?/, text) do
      [_, number_str] ->
        number_str
        |> String.replace(",", "")
        |> parse_abbreviated_number()
      _ ->
        nil
    end
  end

  defp parse_abbreviated_number(str) do
    cond do
      String.ends_with?(str, "k") || String.ends_with?(str, "K") ->
        {num, _} = Float.parse(String.slice(str, 0..-2//1))
        round(num * 1000)

      String.ends_with?(str, "m") || String.ends_with?(str, "M") ->
        {num, _} = Float.parse(String.slice(str, 0..-2//1))
        round(num * 1_000_000)

      true ->
        case Integer.parse(str) do
          {num, _} -> num
          _ -> nil
        end
    end
  end
end