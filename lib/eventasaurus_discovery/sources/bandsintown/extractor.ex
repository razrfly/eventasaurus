defmodule EventasaurusDiscovery.Sources.Bandsintown.Extractor do
  @moduledoc """
  HTML extraction logic for Bandsintown pages.

  Handles:
  - Extracting event URLs from city pages
  - Parsing event details from event pages
  - Extracting venue and performer information
  """

  require Logger

  @doc """
  Extracts event URLs and basic info from a city page HTML.
  Returns a list of event data maps.
  """
  def extract_events_from_city_page(html) do
    # First try to extract JSON-LD data (preferred method)
    case extract_json_ld_events(html) do
      {:ok, events} when events != [] ->
        Logger.info("📋 Extracted #{length(events)} events from JSON-LD data")
        {:ok, events}

      _ ->
        # Fallback to HTML parsing
        case Floki.parse_document(html) do
          {:ok, document} ->
            events = extract_event_cards(document)
            Logger.info("📋 Extracted #{length(events)} events from HTML parsing")
            {:ok, events}

          {:error, reason} ->
            Logger.error("Failed to parse HTML: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp extract_json_ld_events(html) do
    # Look for the window.__data JavaScript object inside <script> tags
    with start_pos when start_pos != :nomatch <- :binary.match(html, "window.__data="),
         {start, _} = start_pos,
         start_idx = start + byte_size("window.__data="),
         # Find the end by looking for </script> tag
         end_pos when end_pos != :nomatch <-
           :binary.match(html, "</script>", [{:scope, {start_idx, byte_size(html) - start_idx}}]),
         {end_idx, _} = end_pos,
         json_str = binary_part(html, start_idx, end_idx - start_idx) do
      try do
        case Jason.decode(json_str) do
          {:ok, data} ->
            events = extract_events_from_json_data(data)
            {:ok, events}

          {:error, reason} ->
            Logger.error("JSON decode failed: #{inspect(reason)}")
            {:error, :json_decode_failed}
        end
      rescue
        e ->
          Logger.error("JSON parse error: #{inspect(e)}")
          {:error, :json_parse_error}
      end
    else
      _ ->
        Logger.debug("No window.__data found in HTML")
        {:error, :no_json_data}
    end
  end

  defp extract_events_from_json_data(data) do
    # Navigate the JSON structure to get events
    events =
      data
      |> get_in(["templateData", "jsonLdContainer", "eventsJsonLd"])
      |> case do
        events when is_list(events) -> events
        _ -> []
      end

    # Transform JSON-LD events to our format
    Enum.map(events, &transform_json_ld_event/1)
  end

  defp transform_json_ld_event(event) do
    %{
      url: Map.get(event, "url", ""),
      artist_name:
        get_in(event, ["performer", "name"]) || get_in(event, ["organizer", "name"]) || "",
      venue_name: get_in(event, ["location", "name"]) || "",
      date: Map.get(event, "startDate", ""),
      description: Map.get(event, "description", ""),
      image_url: Map.get(event, "image", ""),
      external_id: extract_event_id_from_url(Map.get(event, "url", ""))
    }
  end

  defp extract_event_cards(document) do
    # Try multiple selectors as Bandsintown might use different structures
    selectors = [
      "[data-testid='event-card']",
      ".event-card",
      "[class*='EventCard']",
      "a[href^='/e/']",
      "[data-event-id]"
    ]

    events =
      Enum.flat_map(selectors, fn selector ->
        document
        |> Floki.find(selector)
        |> Enum.map(&parse_event_card/1)
        |> Enum.reject(&is_nil/1)
      end)
      |> Enum.uniq_by(& &1[:url])

    events
  end

  defp parse_event_card(card) do
    # Extract the event URL
    url = extract_event_url(card)

    if url do
      %{
        url: url,
        artist_name: extract_text(card, "[class*='artist'], .artist-name, h3"),
        venue_name: extract_text(card, "[class*='venue'], .venue-name"),
        date: extract_text(card, "[class*='date'], .event-date, time"),
        # Extract event ID from URL if possible
        external_id: extract_event_id_from_url(url)
      }
    else
      nil
    end
  end

  defp extract_event_url(card) do
    # Try to find the event link
    case card do
      # If the card itself is a link
      {"a", attrs, _} ->
        get_href(attrs)

      # If it's another element, look for a link inside
      _ ->
        card
        |> Floki.find("a[href^='/e/']")
        |> List.first()
        |> case do
          {"a", attrs, _} -> get_href(attrs)
          _ -> nil
        end
    end
  end

  defp get_href(attrs) do
    Enum.find_value(attrs, fn
      {"href", href} -> href
      _ -> nil
    end)
  end

  defp extract_text(element, selector) do
    element
    |> Floki.find(selector)
    |> Floki.text()
    |> String.trim()
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp extract_event_id_from_url(url) do
    # URLs are typically /e/104563789-artist-name-at-venue
    case Regex.run(~r/\/e\/(\d+)/, url) do
      [_, id] -> id
      _ -> nil
    end
  end

  @doc """
  Extracts detailed event information from an event page.
  """
  def extract_event_details(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        {:ok, parse_event_page(document)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_event_page(document) do
    %{
      title: extract_text(document, "h1"),
      description: extract_description(document),
      start_at: extract_datetime(document),
      venue_data: extract_venue_info(document),
      performers: extract_performers(document),
      ticket_url: extract_ticket_url(document),
      image_url: extract_image_url(document),
      metadata: extract_metadata(document)
    }
  end

  defp extract_description(document) do
    selectors = [
      "[class*='description']",
      "[data-testid='event-description']",
      ".event-details p"
    ]

    Enum.find_value(selectors, fn selector ->
      text = extract_text(document, selector)
      if text && String.length(text) > 20, do: text, else: nil
    end)
  end

  defp extract_datetime(document) do
    # Look for datetime in various formats
    selectors = [
      "time[datetime]",
      "[class*='date-time']",
      "[data-testid='event-date']"
    ]

    Enum.find_value(selectors, fn selector ->
      document
      |> Floki.find(selector)
      |> List.first()
      |> case do
        {_, attrs, _} ->
          # Try to get datetime attribute
          Enum.find_value(attrs, fn
            {"datetime", dt} -> dt
            _ -> nil
          end)

        _ ->
          nil
      end
    end)
  end

  defp extract_venue_info(document) do
    %{
      name: extract_text(document, "[class*='venue-name'], .venue h2"),
      address: extract_text(document, "[class*='address'], .venue-address"),
      city: extract_text(document, "[class*='city'], .venue-city"),
      country: extract_text(document, "[class*='country'], .venue-country")
    }
  end

  defp extract_performers(document) do
    document
    |> Floki.find("[class*='artist'], [class*='performer'], .lineup-artist")
    |> Enum.map(&Floki.text/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp extract_ticket_url(document) do
    document
    |> Floki.find("a[href*='ticket'], a[class*='ticket'], [data-testid='ticket-button']")
    |> List.first()
    |> case do
      {"a", attrs, _} -> get_href(attrs)
      _ -> nil
    end
  end

  defp extract_image_url(document) do
    document
    |> Floki.find("img[class*='event'], img[class*='artist'], meta[property='og:image']")
    |> List.first()
    |> case do
      {"img", attrs, _} ->
        Enum.find_value(attrs, fn
          {"src", src} -> src
          _ -> nil
        end)

      {"meta", attrs, _} ->
        Enum.find_value(attrs, fn
          {"content", content} -> content
          _ -> nil
        end)

      _ ->
        nil
    end
  end

  defp extract_metadata(document) do
    %{
      page_title: extract_text(document, "title"),
      og_title: extract_meta_content(document, "og:title"),
      og_description: extract_meta_content(document, "og:description"),
      extracted_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp extract_meta_content(document, property) do
    document
    |> Floki.find("meta[property='#{property}']")
    |> List.first()
    |> case do
      {"meta", attrs, _} ->
        Enum.find_value(attrs, fn
          {"content", content} -> content
          _ -> nil
        end)

      _ ->
        nil
    end
  end

  @doc """
  Extracts events from an HTML fragment returned by the pagination API.
  This is used when the API returns HTML instead of JSON.
  """
  def extract_events_from_html_fragment(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        events = extract_event_cards(document)
        {:ok, events}

      {:error, reason} ->
        Logger.error("Failed to parse HTML fragment: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
