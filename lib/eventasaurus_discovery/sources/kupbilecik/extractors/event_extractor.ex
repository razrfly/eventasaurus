defmodule EventasaurusDiscovery.Sources.Kupbilecik.Extractors.EventExtractor do
  @moduledoc """
  Extracts event data from Kupbilecik HTML pages.

  ## Extraction Strategy

  Kupbilecik uses React SPA architecture. After Zyte rendering,
  the HTML contains semantic elements with Polish content.

  Key selectors (based on Playwright analysis):
  - Title: h1.event-title or meta og:title
  - Date: Elements containing Polish date format ("7 grudnia 2025 o godz. 20:00")
  - Venue: .venue-name, .venue-address classes
  - Description: .event-description or meta description
  - Image: og:image meta tag or first image in content

  ## Date Handling

  Date strings are extracted raw in Polish format and passed to Transformer
  for parsing. Common format: "7 grudnia 2025 o godz. 20:00"

  ## HTML Structure (React-rendered)

  The React app renders to standard HTML after JavaScript execution.
  Zyte's browserHtml mode handles the JS rendering.
  """

  require Logger

  @doc """
  Extract event data from HTML page.

  ## Parameters

  - `html` - HTML content as string (Zyte-rendered)
  - `url` - Page URL for context

  ## Returns

  - `{:ok, event_data}` - Map with extracted fields
  - `{:error, reason}` - Extraction failed
  """
  def extract(html, url) when is_binary(html) and is_binary(url) do
    Logger.debug("🔍 Extracting Kupbilecik event data (#{byte_size(html)} bytes)")

    with {:ok, title} <- extract_title(html),
         {:ok, date_string} <- extract_date_string(html) do
      # Extract optional fields (don't fail if missing)
      description = extract_description(html)
      image_url = extract_image_url(html)
      venue = extract_venue(html)
      price = extract_price(html)
      category = extract_category(html, url)

      event_data = %{
        "url" => url,
        "title" => title,
        "date_string" => date_string,
        "description" => description,
        "image_url" => image_url,
        "venue_name" => venue[:name],
        "address" => venue[:address],
        "city" => venue[:city],
        "price" => price,
        "category" => category
      }

      Logger.debug("✅ Extracted event: #{title}")
      {:ok, event_data}
    else
      {:error, reason} = error ->
        Logger.warning("⚠️ Failed to extract event data: #{inspect(reason)}")
        error
    end
  end

  def extract(_, _), do: {:error, :invalid_input}

  @doc """
  Extract event title from HTML.

  Tries multiple strategies:
  1. <h1> tag with event-related class
  2. og:title meta tag
  3. Generic <h1> tag
  4. <title> tag (fallback)
  """
  def extract_title(html) do
    cond do
      title = extract_h1_title(html) ->
        {:ok, clean_text(title)}

      title = extract_meta_title(html, "og:title") ->
        {:ok, clean_title(title)}

      title = extract_page_title(html) ->
        {:ok, clean_title(title)}

      true ->
        {:error, :title_not_found}
    end
  end

  @doc """
  Extract date string from HTML.

  Polish date patterns:
  - "7 grudnia 2025 o godz. 20:00"
  - "7 grudnia 2025, 20:00"
  - "7 grudnia 2025"
  """
  def extract_date_string(html) do
    cond do
      # Strategy 1: Look for date-specific elements
      date = extract_date_element(html) ->
        {:ok, date}

      # Strategy 2: Search text for Polish date patterns
      date = extract_polish_date_from_text(html) ->
        {:ok, date}

      # Strategy 3: Check JSON-LD structured data
      date = extract_date_from_json_ld(html) ->
        {:ok, date}

      true ->
        {:error, :date_not_found}
    end
  end

  @doc """
  Extract description from HTML.

  Returns nil if not found (optional field).
  """
  def extract_description(html) do
    cond do
      # Strategy 1: Look for description container
      desc = extract_description_element(html) ->
        clean_text(desc)

      # Strategy 2: Meta description
      desc = extract_meta_description(html) ->
        clean_text(desc)

      # Strategy 3: First paragraph in content
      desc = extract_first_paragraph(html) ->
        clean_text(desc)

      true ->
        nil
    end
  end

  @doc """
  Extract image URL from HTML.

  Returns nil if not found (optional field).
  """
  def extract_image_url(html) do
    cond do
      url = extract_meta_content(html, "og:image") ->
        url

      url = extract_first_content_image(html) ->
        url

      true ->
        nil
    end
  end

  @doc """
  Extract venue information from HTML.

  Returns map with :name, :address, :city keys.
  """
  def extract_venue(html) do
    name = extract_venue_name(html)
    address = extract_venue_address(html)
    city = extract_city(html, address)

    %{
      name: name,
      address: address,
      city: city
    }
  end

  @doc """
  Extract price information from HTML.

  Returns formatted price string or nil.
  """
  def extract_price(html) do
    # Look for price patterns
    patterns = [
      # Polish format: "od 99 zł" or "99 zł"
      ~r/(?:od\s+)?(\d+(?:[,\.]\d+)?)\s*zł/i,
      # Alternative: "PLN 99" or "99 PLN"
      ~r/(\d+(?:[,\.]\d+)?)\s*PLN/i,
      ~r/PLN\s*(\d+(?:[,\.]\d+)?)/i
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [match, _price] -> clean_text(match)
        _ -> nil
      end
    end)
  end

  @doc """
  Extract category from HTML or URL.

  Returns Polish category name for mapping in Transformer.
  """
  def extract_category(html, url) do
    # Try to extract from breadcrumb or category element
    cond do
      cat = extract_category_element(html) ->
        cat

      # Extract from URL path if present
      cat = extract_category_from_url(url) ->
        cat

      true ->
        nil
    end
  end

  # Private helper functions

  defp extract_h1_title(html) do
    # Try specific event title classes first
    patterns = [
      ~r{<h1[^>]*class="[^"]*event[^"]*"[^>]*>(.*?)</h1>}is,
      ~r{<h1[^>]*class="[^"]*title[^"]*"[^>]*>(.*?)</h1>}is,
      ~r{<h1[^>]*>(.*?)</h1>}is
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [_, title] -> title
        _ -> nil
      end
    end)
  end

  defp extract_meta_title(html, property) do
    # Try multiple patterns since attributes can be in any order
    # Pattern 1: property="og:title" followed by content
    # Pattern 2: content followed by property="og:title"
    # Pattern 3: Handle name="og:title" with content
    patterns = [
      ~r{<meta\s+[^>]*property="#{property}"[^>]*content="([^"]+)"}i,
      ~r{<meta\s+[^>]*content="([^"]+)"[^>]*property="#{property}"}i,
      ~r{<meta\s+[^>]*name="#{property}"[^>]*content="([^"]+)"}i,
      ~r{<meta\s+[^>]*content="([^"]+)"[^>]*name="#{property}"}i
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [_, title] -> title
        _ -> nil
      end
    end)
  end

  defp extract_page_title(html) do
    case Regex.run(~r{<title[^>]*>(.*?)</title>}is, html) do
      [_, title] -> title
      _ -> nil
    end
  end

  defp clean_title(title) do
    title
    |> clean_text()
    |> String.replace(~r{\s*[\-\|]\s*kupbilecik.*$}i, "")
    |> String.trim()
  end

  defp extract_date_element(html) do
    # Look for date-specific elements
    patterns = [
      ~r{<time[^>]*>(.*?)</time>}is,
      ~r{<[^>]*class="[^"]*date[^"]*"[^>]*>(.*?)</[^>]+>}is,
      ~r{<[^>]*data-date[^>]*>(.*?)</[^>]+>}is
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [_, date] ->
          cleaned = clean_text(date)
          if contains_polish_date?(cleaned), do: cleaned, else: nil

        _ ->
          nil
      end
    end)
  end

  defp extract_polish_date_from_text(html) do
    text = clean_text(html)

    # Polish month names pattern
    months =
      "(?:stycznia|lutego|marca|kwietnia|maja|czerwca|lipca|sierpnia|września|października|listopada|grudnia)"

    # Date with time: "7 grudnia 2025 o godz. 20:00"
    patterns = [
      ~r/(\d{1,2}\s+#{months}\s+\d{4}\s+o\s+godz\.\s*\d{1,2}:\d{2})/i,
      ~r/(\d{1,2}\s+#{months}\s+\d{4},?\s*\d{1,2}:\d{2})/i,
      ~r/(\d{1,2}\s+#{months}\s+\d{4})/i
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, text) do
        [_, date] -> String.trim(date)
        [date] -> String.trim(date)
        _ -> nil
      end
    end)
  end

  defp extract_date_from_json_ld(html) do
    case Regex.run(~r{<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>}is, html) do
      [_, json] ->
        case Jason.decode(json) do
          {:ok, %{"startDate" => start_date}} -> start_date
          {:ok, data} when is_list(data) ->
            Enum.find_value(data, fn item ->
              item["startDate"]
            end)

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp contains_polish_date?(text) do
    months =
      "(?:stycznia|lutego|marca|kwietnia|maja|czerwca|lipca|sierpnia|września|października|listopada|grudnia)"

    Regex.match?(~r/\d{1,2}\s+#{months}\s+\d{4}/i, text)
  end

  defp extract_description_element(html) do
    patterns = [
      ~r{<[^>]*class="[^"]*description[^"]*"[^>]*>(.*?)</[^>]+>}is,
      ~r{<[^>]*class="[^"]*event-desc[^"]*"[^>]*>(.*?)</[^>]+>}is,
      ~r{<[^>]*class="[^"]*content[^"]*"[^>]*>(.*?)</[^>]+>}is
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [_, desc] ->
          cleaned = clean_text(desc)
          if String.length(cleaned) > 20, do: cleaned, else: nil

        _ ->
          nil
      end
    end)
  end

  defp extract_meta_description(html) do
    # Try both standard description and og:description (kupbilecik uses og:description)
    patterns = [
      ~r{<meta\s+(?:name|property)="description"\s+content="([^"]+)"}i,
      ~r{<meta\s+[^>]*property="og:description"[^>]*content="([^"]+)"}i,
      ~r{<meta\s+[^>]*content="([^"]+)"[^>]*property="og:description"}i
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [_, desc] -> desc
        _ -> nil
      end
    end)
  end

  defp extract_first_paragraph(html) do
    case Regex.run(~r{<p[^>]*>(.*?)</p>}is, html) do
      [_, p] ->
        cleaned = clean_text(p)
        if String.length(cleaned) > 30, do: cleaned, else: nil

      _ ->
        nil
    end
  end

  defp extract_meta_content(html, property) do
    # Try multiple patterns since attributes can be in any order
    patterns = [
      ~r{<meta\s+[^>]*property="#{property}"[^>]*content="([^"]+)"}i,
      ~r{<meta\s+[^>]*content="([^"]+)"[^>]*property="#{property}"}i,
      ~r{<meta\s+[^>]*name="#{property}"[^>]*content="([^"]+)"}i,
      ~r{<meta\s+[^>]*content="([^"]+)"[^>]*name="#{property}"}i
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [_, content] -> String.trim(content)
        _ -> nil
      end
    end)
  end

  defp extract_first_content_image(html) do
    # Look for main content image
    patterns = [
      ~r{<img[^>]*class="[^"]*event[^"]*"[^>]*src="([^"]+)"}i,
      ~r{<img[^>]*class="[^"]*main[^"]*"[^>]*src="([^"]+)"}i,
      ~r{<figure[^>]*>.*?<img[^>]*src="([^"]+)".*?</figure>}is
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [_, url] -> url
        _ -> nil
      end
    end)
  end

  defp extract_venue_name(html) do
    # Kupbilecik-specific patterns based on actual HTML structure
    # The main venue link in the h3 header wraps the name in <b> tags:
    # <h3><a href="/obiekty/277/..."><b>Venue Name</b></a>, Address</h3>
    # Secondary venue links don't have <b> tags:
    # <a href="/obiekty/277/...">Venue Name</a>
    patterns = [
      # Primary: Link with <b> wrapper (main header venue)
      ~r{<a[^>]*href="/obiekty/[^"]*"[^>]*><b>([^<]+)</b></a>}i,
      # Secondary: Link without <b> wrapper
      ~r{<a[^>]*href="/obiekty/[^"]*"[^>]*>([^<]+)</a>}i,
      # Fallback: CSS class patterns (for future changes)
      ~r{<[^>]*class="[^"]*venue[^"]*name[^"]*"[^>]*>(.*?)</[^>]+>}is,
      ~r{<[^>]*class="[^"]*location[^"]*"[^>]*>(.*?)</[^>]+>}is,
      ~r{<[^>]*data-venue[^>]*>(.*?)</[^>]+>}is
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [_, name] ->
          cleaned = clean_text(name)
          # Only return non-empty venue names
          if cleaned != "" and String.length(cleaned) > 1, do: cleaned, else: nil

        _ ->
          nil
      end
    end)
  end

  defp extract_venue_address(html) do
    # Kupbilecik-specific patterns based on actual HTML structure
    patterns = [
      # Pattern 1: h3 with venue link followed by ", Address" text
      # HTML: <h3><a href="/obiekty/...">VenueName</a>, Address Street 123</h3>
      ~r{<h3[^>]*>\s*<a[^>]*href="/obiekty/[^"]*"[^>]*>[^<]+</a>\s*,\s*([^<]+)</h3>}is,
      # Pattern 2: Standard CSS class patterns
      ~r{<[^>]*class="[^"]*address[^"]*"[^>]*>(.*?)</[^>]+>}is,
      ~r{<address[^>]*>(.*?)</address>}is
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [_, addr] ->
          cleaned = clean_text(addr)
          if cleaned != "" and String.length(cleaned) > 3, do: cleaned, else: nil

        _ ->
          nil
      end
    end)
  end

  defp extract_city(html, address) do
    # Try to find city from various sources
    cond do
      # Look for city element
      city = extract_city_element(html) ->
        city

      # Try to extract from meta description (e.g., "Event Name (Bolesławiec) w dn...")
      city = extract_city_from_meta_description(html) ->
        city

      # Try to extract from page title (e.g., "Event / Bolesławiec / 2026-03-12")
      city = extract_city_from_title(html) ->
        city

      # Try to extract from address (only if address is not nil)
      address != nil ->
        extract_city_from_address(address)

      true ->
        nil
    end
  end

  defp extract_city_from_meta_description(html) do
    # Pattern: "Event Name (CityName) w dn. ..."
    case extract_meta_description(html) do
      nil ->
        nil

      desc ->
        case Regex.run(~r/\(([^)]+)\)\s+w\s+dn\./u, desc) do
          [_, city] -> String.trim(city)
          _ -> nil
        end
    end
  end

  defp extract_city_from_title(html) do
    # Pattern: "Event Name / CityName / 2026-03-12"
    case extract_page_title(html) do
      nil ->
        nil

      title ->
        case Regex.run(~r|/\s*([^/]+)\s*/\s*\d{4}-\d{2}-\d{2}|, title) do
          [_, city] -> String.trim(city)
          _ -> nil
        end
    end
  end

  defp extract_city_element(html) do
    patterns = [
      ~r{<[^>]*class="[^"]*city[^"]*"[^>]*>(.*?)</[^>]+>}is,
      ~r{<[^>]*data-city="([^"]+)"}i
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [_, city] ->
          cleaned = clean_text(city)
          # Only return if non-empty (skip icon-city type elements)
          if cleaned != "" and String.length(cleaned) > 0, do: cleaned, else: nil

        _ ->
          nil
      end
    end)
  end

  defp extract_city_from_address(address) do
    # Polish cities commonly found on kupbilecik
    cities = [
      "Warszawa",
      "Kraków",
      "Gdańsk",
      "Wrocław",
      "Poznań",
      "Łódź",
      "Katowice",
      "Szczecin",
      "Lublin",
      "Bydgoszcz"
    ]

    Enum.find(cities, fn city ->
      String.contains?(address, city)
    end)
  end

  defp extract_category_element(html) do
    patterns = [
      ~r{<[^>]*class="[^"]*category[^"]*"[^>]*>(.*?)</[^>]+>}is,
      ~r{<[^>]*class="[^"]*breadcrumb[^"]*"[^>]*>.*?<a[^>]*>(.*?)</a>.*?</[^>]+>}is
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [_, cat] -> clean_text(cat)
        _ -> nil
      end
    end)
  end

  defp extract_category_from_url(url) do
    # URL might contain category: /koncerty/..., /spektakle/...
    case Regex.run(~r{kupbilecik\.pl/([^/]+)/}, url) do
      [_, segment] when segment not in ["imprezy", "en", "pl"] ->
        segment

      _ ->
        nil
    end
  end

  defp clean_text(nil), do: nil

  defp clean_text(text) when is_binary(text) do
    text
    |> String.replace(~r{<[^>]+>}, " ")
    |> String.replace(~r{&nbsp;}, " ")
    |> String.replace(~r{&amp;}, "&")
    |> String.replace(~r{&lt;}, "<")
    |> String.replace(~r{&gt;}, ">")
    |> String.replace(~r{&quot;}, "\"")
    |> String.replace(~r{&#\d+;}, "")
    |> String.replace(~r{\s+}, " ")
    |> String.trim()
  end
end
