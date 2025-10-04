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
    # First check if this is an error page
    if is_error_page?(html) do
      Logger.warning("⚠️ Detected error page for URL: #{url}")
      {:error, :error_page}
    else
      case Floki.parse_document(html) do
        {:ok, document} ->
          event_data = %{
            url: url,
            source_url: url,
            title: extract_title(document),
            title_translations: extract_title_translations(document),
            description_translations: extract_description_translations(document),
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
  end

  @doc """
  Detect if the HTML content is an error page (404, 500, etc.)
  """
  def is_error_page?(html) when is_binary(html) do
    # Check for common error page indicators
    # Check if the title contains Error followed by a number
    # Check for h1 with Error text
    String.contains?(html, "Error 404") ||
      String.contains?(html, "404 - ") ||
      String.contains?(html, "Page not found") ||
      String.contains?(html, "Nie znaleziono strony") ||
      String.contains?(html, "Strona nie została znaleziona") ||
      String.contains?(html, "No such page") ||
      String.contains?(html, "class=\"error-404\"") ||
      String.contains?(html, "id=\"error-404\"") ||
      Regex.match?(~r/<title>[^<]*Error\s+\d{3}/i, html) ||
      Regex.match?(~r/<h1[^>]*>Error\s+\d{3}/i, html)
  end

  defp extract_title(document) do
    # Title is usually in h1
    case Floki.find(document, "h1") do
      [] ->
        # Fallback to other title selectors
        Floki.find(document, ".event-title, .title, title")
        |> List.first()
        |> case do
          nil ->
            "Untitled Event"

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

  defp extract_title_translations(document) do
    # Extract the title in Polish (primary language)
    title = extract_title(document)

    # For now, we only have Polish titles from Karnet
    # Future enhancement could detect multiple languages or generate translations
    if title && title != "Untitled Event" do
      %{"pl" => title}
    else
      nil
    end
  end

  defp extract_description_translations(document) do
    # Extract the description in Polish (primary language)
    description = extract_description(document)

    # For now, we only have Polish descriptions from Karnet
    # Future enhancement could detect multiple languages or generate translations
    if description && String.length(description) > 0 do
      %{"pl" => description}
    else
      nil
    end
  end

  defp extract_description(document) do
    # Look for main description content with Polish-specific selectors
    selectors = [
      # Primary selector for Karnet pages
      ".article-content",
      ".event-description",
      ".description",
      ".content article",
      ".event-content",
      ".opis",
      ".tresc",
      ".artykul",
      ".tekst",
      "article p",
      ".main-content p",
      ".content p",
      "main p"
    ]

    description =
      Enum.find_value(selectors, fn selector ->
        case Floki.find(document, selector) do
          [] ->
            nil

          elements ->
            text =
              elements
              |> Enum.map(&Floki.text/1)
              |> Enum.join("\n")
              |> String.trim()

            # Reduced threshold from 50 to 20 characters for Polish content
            if String.length(text) > 20 do
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
      # Limit to 2000 chars
      |> String.slice(0, 2000)
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
        [] ->
          nil

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
    # Look for the "Miejsce wydarzenia" (Event Location) section
    # The venue is in a link with data-name attribute or in an h3 tag
    venue_links = Floki.find(document, "a.event-list-element[data-name]")

    venue_data =
      if length(venue_links) > 0 do
        # Extract venue from the data-name attribute
        venue_link = List.first(venue_links)
        venue_name = Floki.attribute(venue_link, "data-name") |> List.first()

        # Try to find address near the selected link, scoped to its container
        venue_address =
          case Floki.find(venue_link, ".data") do
            [addr | _] ->
              Floki.text(addr) |> String.trim()

            _ ->
              # Find the specific container that contains this venue link
              container =
                Floki.find(document, ".event-list-element")
                |> Enum.find(fn section ->
                  Floki.find(section, "a.event-list-element[data-name]")
                  |> Enum.any?(fn a ->
                    Floki.attribute(a, "data-name") |> List.first() == venue_name
                  end)
                end)

              case container && Floki.find(container, ".data") do
                [addr | _] -> Floki.text(addr) |> String.trim()
                _ -> extract_venue_address_fallback(document)
              end
          end

        %{
          name: venue_name,
          address: venue_address,
          city: "Kraków",
          country: "Poland"
        }
      else
        # Fallback: try to find venue in article content using pattern matching
        article_content = Floki.find(document, ".article-content")

        if length(article_content) > 0 do
          content_text = Floki.text(article_content)
          venue_name = extract_venue_from_text(content_text)

          %{
            name: venue_name,
            address: extract_venue_address_fallback(document),
            city: "Kraków",
            country: "Poland"
          }
        else
          %{
            name: extract_venue_name_fallback(document),
            address: extract_venue_address_fallback(document),
            city: "Kraków",
            country: "Poland"
          }
        end
      end

    # Check if we have a valid venue name (not generic placeholder)
    valid_name =
      venue_data.name &&
        String.length(venue_data.name) > 0 &&
        !String.contains?(String.downcase(venue_data.name), "miejsce wydarzenia")

    if valid_name do
      venue_data
    else
      # No fallback - events without valid venues will be rejected by processor
      nil
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
          nil ->
            nil

          elem ->
            Floki.text(elem)
            |> String.split(",")
            |> List.first()
            |> String.trim()
        end

      [_header | _] ->
        # Get the next sibling content
        case Floki.find(document, "h3:fl-contains('Miejsce wydarzenia') ~ *") do
          [] ->
            nil

          [next | _] ->
            case Floki.find(next, "h3, h4, a") do
              [] -> Floki.text(next) |> String.trim()
              [venue_elem | _] -> Floki.text(venue_elem) |> String.trim()
            end
        end
    end
  end

  defp extract_venue_address_fallback(document) do
    # Look for address patterns in the whole document
    Floki.find(document, "p, div")
    |> Enum.map(&Floki.text/1)
    |> Enum.map(&String.trim/1)
    |> Enum.find(fn text ->
      # Avoid long paragraphs
      (String.contains?(text, "ul.") ||
         String.contains?(text, "al.") ||
         String.contains?(text, "plac") ||
         String.contains?(text, "Rynek")) &&
        String.length(text) < 200
    end)
  end

  defp extract_venue_from_text(text) do
    # List of known Kraków venues
    venue_patterns = [
      # Museums and Galleries
      {"Pałac.*Sztuki", "Pałac Sztuki"},
      {"Muzeum Narodow", "Muzeum Narodowe"},
      {"MOCAK", "MOCAK"},
      {"Manggha", "Manggha"},
      {"Cricoteka", "Cricoteka"},
      {"Bunkier Sztuki", "Bunkier Sztuki"},
      {"Galeria Krakowska", "Galeria Krakowska"},
      {"Muzeum Historyczne", "Muzeum Historyczne Miasta Krakowa"},

      # Theaters and Concert Halls
      {"Teatr.*Słowackiego", "Teatr im. Juliusza Słowackiego"},
      {"Teatr.*Stary", "Teatr Stary"},
      {"Teatr.*Bagatela", "Teatr Bagatela"},
      {"Teatr.*Łaźnia.*Nowa", "Teatr Łaźnia Nowa"},
      {"Teatr.*KTO", "Teatr KTO"},
      {"Filharmoni", "Filharmonia Krakowska"},
      {"Opera Krakowska", "Opera Krakowska"},

      # Cultural Centers
      {"ICE Kraków", "ICE Kraków"},
      {"Centrum Kongresowe", "ICE Kraków Congress Centre"},
      {"Tauron Arena", "Tauron Arena"},
      {"Nowohuckie Centrum Kultury", "Nowohuckie Centrum Kultury"},
      {"NCK", "Nowohuckie Centrum Kultury"},

      # Cinemas
      {"Kino.*Pod Baranami", "Kino Pod Baranami"},
      {"Kino.*Paradox", "Kino Paradox"},
      {"Kino.*Mikro", "Kino Mikro"},
      {"Kino.*Agrafka", "Kino Agrafka"},

      # Other Venues
      {"Rynek Główny", "Rynek Główny"},
      {"Wawel", "Zamek Królewski na Wawelu"},
      {"Fabryka Schindlera", "Fabryka Schindlera"},
      {"Sukiennice", "Sukiennice"}
    ]

    # Try to find a venue match in the text
    venue_patterns
    |> Enum.find_value(fn {pattern, venue_name} ->
      if Regex.match?(~r/#{pattern}/iu, text) do
        venue_name
      end
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
        [] ->
          nil

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

    category =
      Enum.find_value(category_selectors, fn selector ->
        case Floki.find(document, selector) do
          [] ->
            nil

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

    # NEW: Extract from breadcrumbs if no category found
    category =
      if is_nil(category) do
        breadcrumbs = Floki.find(document, ".breadcrumb a, nav.breadcrumbs a, .breadcrumbs a")

        Enum.find_value(breadcrumbs, fn link ->
          href = Floki.attribute([link], "href") |> List.first()
          text = Floki.text(link) |> String.trim() |> String.downcase()

          # Check if this is a category breadcrumb
          if href && String.contains?(href, "/wydarzenia/") do
            # Extract from URL or use text
            extract_category_from_wydarzenia_url(href) || text
          end
        end)
      else
        category
      end

    # NEW: Extract from canonical URL as last resort
    category =
      if is_nil(category) do
        canonical =
          Floki.find(document, "link[rel='canonical']")
          |> Floki.attribute("href")
          |> List.first()

        if canonical do
          extract_category_from_wydarzenia_url(canonical)
        end
      else
        category
      end

    # Normalize common categories to English
    normalize_category(category)
  end

  defp extract_category_from_wydarzenia_url(nil), do: nil

  defp extract_category_from_wydarzenia_url(url) when is_binary(url) do
    case Regex.run(~r{/wydarzenia/([^/,]+)}, url) do
      [_, category] -> String.trim(category) |> String.downcase()
      _ -> nil
    end
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
    # First, try to get og:image meta tag (usually the best quality)
    og_image = extract_og_image(document)

    if og_image do
      full_og = normalize_image_url(og_image)

      if full_og && valid_event_image?(full_og) do
        full_og
      else
        nil
      end
    else
      # Fall back to finding images in the content
      # Updated selectors to match Karnet's actual HTML structure
      image_selectors = [
        # Existing selectors for compatibility
        ".event-image img",
        ".main-image img",
        ".featured-image img",
        "article img",
        "[class*='image'] img",

        # NEW: Find any img from media.krakow.travel (Karnet's image CDN)
        "img[src*='media.krakow.travel']",

        # NEW: Find any reasonably sized image as fallback
        "img"
      ]

      # Collect all valid images and sort by quality
      all_images =
        Enum.flat_map(image_selectors, fn selector ->
          Floki.find(document, selector)
          |> Enum.map(fn img ->
            src = Floki.attribute(img, "src") |> List.first()
            data_src = Floki.attribute(img, "data-src") |> List.first()
            url = src || data_src

            if url && valid_event_image?(url) do
              # Make sure it's a full URL
              full_url = normalize_image_url(url)

              if full_url do
                {full_url, image_quality_score(full_url)}
              else
                nil
              end
            else
              nil
            end
          end)
          |> Enum.reject(&is_nil/1)
        end)
        |> Enum.uniq_by(fn {url, _} -> url end)
        |> Enum.sort_by(fn {_, score} -> score end, :desc)

      case all_images do
        [{best_url, _} | _] -> best_url
        [] -> nil
      end
    end
  end

  # Extract og:image meta tag
  defp extract_og_image(document) do
    case Floki.find(document, "meta[property='og:image']") do
      [] ->
        nil

      [meta | _] ->
        Floki.attribute(meta, "content") |> List.first()
    end
  end

  # Score images by quality (higher is better)
  defp image_quality_score(url) when is_binary(url) do
    cond do
      # XXL images are best
      String.contains?(url, "/xxl") -> 100
      # XL images are great
      String.contains?(url, "/xl") -> 90
      # Large images are good
      String.contains?(url, "/l.jpg") -> 80
      # Medium images are okay
      String.contains?(url, "/m.jpg") -> 70
      # Small images are last resort
      String.contains?(url, "/s.jpg") -> 30
      # Thumbnails are worst
      String.contains?(url, "/thumb/") -> 20
      # Default score for unknown sizes
      String.contains?(url, "media.krakow.travel") -> 60
      true -> 40
    end
  end

  # Helper function to validate if an image is a real event image
  defp valid_event_image?(url) when is_binary(url) do
    # Accept media.krakow.travel images (these are real event images)
    # Accept other large images but reject category icons
    # Prefer larger image sizes
    # If no size indicator, accept if it's not obviously a thumbnail
    String.contains?(url, "media.krakow.travel") ||
      (not String.contains?(url, "/img/category/") &&
         not String.contains?(url, "category") &&
         (String.contains?(url, "/xxl") ||
            String.contains?(url, "/xl") ||
            String.contains?(url, "/l") ||
            (not String.contains?(url, "/s.jpg") &&
               not String.contains?(url, "/thumb/"))))
  end

  defp valid_event_image?(_), do: false

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

  # Helper to normalize image URLs
  defp normalize_image_url(nil), do: nil

  defp normalize_image_url(url) when is_binary(url) do
    cond do
      String.starts_with?(url, "http") -> url
      String.starts_with?(url, "//") -> "https:" <> url
      true -> Config.build_event_url(url)
    end
  end
end
