defmodule EventasaurusDiscovery.Sources.Karnet.DetailExtractor do
  @moduledoc """
  Extracts detailed event information from Karnet Kraków event pages.

  Handles extraction of:
  - Event title and description
  - Date/time (including date ranges)
  - Venue information
  - Performer/artist information
  - Ticket URLs
  - Categories and metadata
  """

  require Logger
  alias EventasaurusDiscovery.Sources.Karnet.Config

  @doc """
  Extract event details from an event page HTML.
  Returns a map with all extracted information.
  """
  def extract_event_details(html, url) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        event_data = %{
          url: url,
          source_url: url,
          title: extract_title(document),
          description: extract_description(document),
          date_text: extract_date_text(document),
          venue_data: extract_venue(document),
          performers: extract_performers(document),
          ticket_url: extract_ticket_url(document),
          category: extract_category(document),
          image_url: extract_image_url(document),
          is_free: check_if_free(document),
          is_festival: check_if_festival(document),
          extracted_at: DateTime.utc_now()
        }

        {:ok, event_data}

      {:error, reason} ->
        Logger.error("Failed to parse event HTML: #{inspect(reason)}")
        {:error, :parse_failed}
    end
  end

  defp extract_title(document) do
    # Title is usually in h1
    case Floki.find(document, "h1") do
      [] ->
        # Fallback to other title selectors
        Floki.find(document, ".event-title, .title, title")
        |> List.first()
        |> case do
          nil -> "Untitled Event"
          elem ->
            Floki.text(elem)
            |> String.trim()
            |> String.replace(~r/\s+/, " ")
        end

      [h1 | _] ->
        Floki.text(h1)
        |> String.trim()
        |> String.replace(~r/\s+/, " ")
    end
  end

  defp extract_description(document) do
    # Look for main description content
    selectors = [
      ".event-description",
      ".description",
      ".content article",
      ".event-content",
      ".opis",
      "article p"
    ]

    description = Enum.find_value(selectors, fn selector ->
      case Floki.find(document, selector) do
        [] -> nil
        elements ->
          text = elements
          |> Enum.map(&Floki.text/1)
          |> Enum.join("\n")
          |> String.trim()

          if String.length(text) > 50 do
            text
          else
            nil
          end
      end
    end)

    # Clean up and limit length
    if description do
      description
      |> String.replace(~r/\s+/, " ")
      |> String.trim()
      |> String.slice(0, 2000)  # Limit to 2000 chars
    else
      nil
    end
  end

  defp extract_date_text(document) do
    # Look for date information
    date_selectors = [
      ".date",
      ".event-date",
      ".kiedy",
      ".when",
      "time",
      "[class*='date']"
    ]

    Enum.find_value(date_selectors, fn selector ->
      case Floki.find(document, selector) do
        [] -> nil
        elements ->
          # Get the first non-empty date text
          elements
          |> Enum.map(&Floki.text/1)
          |> Enum.map(&String.trim/1)
          |> Enum.find(fn text -> String.length(text) > 0 end)
      end
    end)
  end

  defp extract_venue(document) do
    # Look for venue section
    venue_section = Floki.find(document, ".event-venue, .event-location, .event-place")

    venue_data = if length(venue_section) > 0 do
      section = List.first(venue_section)

      %{
        name: extract_venue_name(section, document),
        address: extract_venue_address(section, document),
        city: "Kraków",  # Default to Kraków
        country: "Poland"
      }
    else
      # Try to find venue info in other places
      %{
        name: extract_venue_name_fallback(document),
        address: extract_venue_address_fallback(document),
        city: "Kraków",
        country: "Poland"
      }
    end

    # Check if we have a valid venue name (not generic placeholder)
    valid_name = venue_data.name &&
                 String.length(venue_data.name) > 0 &&
                 !String.contains?(String.downcase(venue_data.name), "miejsce wydarzenia")

    if valid_name do
      venue_data
    else
      # Return a default venue for Kraków events without specific venue
      %{
        name: "Kraków City Center",  # Generic but valid venue
        city: "Kraków",
        country: "Poland",
        address: venue_data.address
      }
    end
  end

  defp extract_venue_name(section, _document) do
    # Look for venue name in the section
    case Floki.find(section, "h3, h4, .venue-name, .location-name") do
      [] ->
        # Get text from the section itself
        Floki.text(section)
        |> String.split("\n")
        |> List.first()
        |> String.trim()

      [elem | _] ->
        Floki.text(elem)
        |> String.trim()
    end
  end

  defp extract_venue_name_fallback(document) do
    # Look for "Miejsce wydarzenia" (Event location) section
    case Floki.find(document, "h3:fl-contains('Miejsce wydarzenia')") do
      [] ->
        # Try other patterns
        Floki.find(document, ".location, .venue, .miejsce")
        |> List.first()
        |> case do
          nil -> nil
          elem ->
            Floki.text(elem)
            |> String.split(",")
            |> List.first()
            |> String.trim()
        end

      [_header | _] ->
        # Get the next sibling content
        case Floki.find(document, "h3:fl-contains('Miejsce wydarzenia') ~ *") do
          [] -> nil
          [next | _] ->
            case Floki.find(next, "h3, h4, a") do
              [] -> Floki.text(next) |> String.trim()
              [venue_elem | _] -> Floki.text(venue_elem) |> String.trim()
            end
        end
    end
  end

  defp extract_venue_address(section, _document) do
    # Look for address in the section
    case Floki.find(section, ".address, .adres, address, p") do
      [] -> nil
      elements ->
        elements
        |> Enum.map(&Floki.text/1)
        |> Enum.map(&String.trim/1)
        |> Enum.find(fn text ->
          String.contains?(text, "ul.") ||
          String.contains?(text, "al.") ||
          String.contains?(text, "plac") ||
          String.contains?(text, "Rynek")
        end)
    end
  end

  defp extract_venue_address_fallback(document) do
    # Look for address patterns in the whole document
    Floki.find(document, "p, div")
    |> Enum.map(&Floki.text/1)
    |> Enum.map(&String.trim/1)
    |> Enum.find(fn text ->
      (String.contains?(text, "ul.") ||
       String.contains?(text, "al.") ||
       String.contains?(text, "plac") ||
       String.contains?(text, "Rynek")) &&
      String.length(text) < 200  # Avoid long paragraphs
    end)
  end

  defp extract_performers(document) do
    # For simple events, performers might be in the title or description
    # This is a placeholder - will be enhanced for festivals in Phase 3
    performers = []

    # Look for artist/performer sections
    artist_sections = Floki.find(document, ".artist, .performer, .wykonawca, .artysta")

    if length(artist_sections) > 0 do
      Enum.map(artist_sections, fn section ->
        %{
          name: Floki.text(section) |> String.trim()
        }
      end)
      |> Enum.filter(fn p -> String.length(p.name) > 0 end)
    else
      performers
    end
  end

  defp extract_ticket_url(document) do
    # Look for ticket links
    ticket_selectors = [
      "a[href*='bilety']",
      "a[href*='ticket']",
      "a[href*='ebilet']",
      "a[href*='ewejsciowki']",
      ".tickets a",
      ".bilety a"
    ]

    Enum.find_value(ticket_selectors, fn selector ->
      case Floki.find(document, selector) do
        [] -> nil
        links ->
          # Get the first external ticket link
          links
          |> Enum.map(fn link -> Floki.attribute(link, "href") |> List.first() end)
          |> Enum.find(fn href ->
            href && (String.starts_with?(href, "http") || String.starts_with?(href, "//"))
          end)
      end
    end)
  end

  defp extract_category(document) do
    # Look for category/type information
    category_selectors = [
      ".category",
      ".kategoria",
      ".event-type",
      ".typ-wydarzenia",
      "[class*='category']"
    ]

    category = Enum.find_value(category_selectors, fn selector ->
      case Floki.find(document, selector) do
        [] -> nil
        elements ->
          Floki.text(List.first(elements))
          |> String.trim()
          |> String.downcase()
          |> case do
            "" -> nil
            text -> text
          end
      end
    end)

    # Normalize common categories to English
    normalize_category(category)
  end

  defp normalize_category(nil), do: nil
  defp normalize_category(category) do
    cond do
      String.contains?(category, "festiwal") -> "festival"
      String.contains?(category, "koncert") -> "concert"
      String.contains?(category, "spektakl") -> "performance"
      String.contains?(category, "wystaw") -> "exhibition"
      String.contains?(category, "film") -> "film"
      String.contains?(category, "teatr") -> "theater"
      String.contains?(category, "opera") -> "opera"
      String.contains?(category, "taniec") || String.contains?(category, "balet") -> "dance"
      true -> category
    end
  end

  defp extract_image_url(document) do
    # Look for main event image
    image_selectors = [
      ".event-image img",
      ".main-image img",
      ".featured-image img",
      "article img",
      "[class*='image'] img"
    ]

    img_url = Enum.find_value(image_selectors, fn selector ->
      case Floki.find(document, selector) do
        [] -> nil
        images ->
          img = List.first(images)

          # Try src first, then data-src for lazy loading
          src = Floki.attribute(img, "src") |> List.first()
          data_src = Floki.attribute(img, "data-src") |> List.first()

          url = src || data_src

          if url do
            # Make sure it's a full URL
            if String.starts_with?(url, "http") do
              url
            else
              Config.build_event_url(url)
            end
          else
            nil
          end
      end
    end)

    img_url
  end

  defp check_if_free(document) do
    # Look for free event indicators
    text = Floki.text(document) |> String.downcase()

    String.contains?(text, "wstęp wolny") ||
    String.contains?(text, "wstęp bezpłatny") ||
    String.contains?(text, "bezpłatne") ||
    String.contains?(text, "darmowe") ||
    String.contains?(text, "free entry") ||
    String.contains?(text, "free admission")
  end

  defp check_if_festival(document) do
    # Check if this is a festival (multi-day event with sub-events)
    text = Floki.text(document) |> String.downcase()

    String.contains?(text, "festiwal") ||
    String.contains?(text, "fest ") ||
    String.contains?(text, "festival")
  end
end