defmodule EventasaurusDiscovery.Sources.Kupbilecik.Extractors.EventExtractor do
  @moduledoc """
  Extracts event data from Kupbilecik HTML pages.

  ## Extraction Strategy

  Kupbilecik uses Server-Side Rendering (SSR) for SEO purposes.
  All event data is available in the initial HTML response - no
  JavaScript rendering is required.

  Key selectors (based on analysis):
  - Title: h1 tag or meta og:title
  - Date: Elements containing Polish date format ("7 grudnia 2025 o godz. 20:00")
  - Venue: Links to /obiekty/ paths with venue info
  - Description: og:description meta tag (most reliable)
  - Image: og:image meta tag
  - Performers: Extracted from "Obsada:" section in description paragraphs
  - Category: Breadcrumb links to event categories

  ## Date Handling

  Date strings are extracted raw in Polish format and passed to Transformer
  for parsing. Common format: "7 grudnia 2025 o godz. 20:00"

  ## HTML Structure (SSR)

  The site serves fully-rendered HTML for SEO. Plain HTTP requests
  return all necessary data for extraction.
  """

  require Logger

  @doc """
  Extract event data from HTML page.

  ## Parameters

  - `html` - HTML content as string (plain HTTP response)
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
      venue = extract_venue(html, url)
      price = extract_price(html)
      category = extract_category(html, url)
      performers = extract_performers(html)

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
        "category" => category,
        "performers" => performers
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

  Kupbilecik provides description in og:description meta tag which is the most
  reliable source. Falls back to description elements or first paragraph.

  Returns nil if not found (optional field).
  """
  def extract_description(html) do
    cond do
      # Strategy 1: og:description meta tag (most reliable for kupbilecik)
      desc = extract_meta_description(html) ->
        clean_text(desc)

      # Strategy 2: Look for description container
      desc = extract_description_element(html) ->
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
  def extract_venue(html, url \\ nil) do
    name = extract_venue_name(html)
    address = extract_venue_address(html)
    city = extract_city(html, address, url)

    %{
      name: name,
      address: address,
      city: city
    }
  end

  @doc """
  Extract price information from HTML.

  Kupbilecik embeds prices in various ways:
  1. Open Graph product:price meta tags (most reliable)
  2. In description bullet points: "* Dorośli - 55 zł", "* Studenci - 40 zł"
  3. In "Bilety:" sections with price lists
  4. Standard price patterns: "od 99 zł", "99 zł"
  5. Price ranges: "od 50 do 150 zł"

  Returns formatted price string (e.g., "od 55 zł" or "55-150 zł") or nil.
  """
  def extract_price(html) do
    # Strategy 1: Try OG product:price meta tags first (most reliable)
    case extract_og_product_price(html) do
      price when is_integer(price) and price > 0 ->
        format_price(price)

      _ ->
        # Strategy 2: Fall back to extracting prices from HTML content
        prices = extract_all_prices(html)

        case prices do
          [] ->
            nil

          [single_price] ->
            format_price(single_price)

          multiple_prices ->
            # Return range if we have multiple prices
            min_price = Enum.min(multiple_prices)
            max_price = Enum.max(multiple_prices)

            if min_price == max_price do
              format_price(min_price)
            else
              "#{min_price}-#{max_price} zł"
            end
        end
    end
  end

  # Extract price from Open Graph product:price meta tags
  # Format: <meta property="product:price:amount" content="105" />
  defp extract_og_product_price(html) do
    patterns = [
      ~r{<meta\s+[^>]*property="product:price:amount"[^>]*content="(\d+(?:\.\d+)?)"[^>]*>}i,
      ~r{<meta\s+[^>]*content="(\d+(?:\.\d+)?)"[^>]*property="product:price:amount"[^>]*>}i,
      ~r{<meta\s+[^>]*property="product:original_price:amount"[^>]*content="(\d+(?:\.\d+)?)"[^>]*>}i,
      ~r{<meta\s+[^>]*content="(\d+(?:\.\d+)?)"[^>]*property="product:original_price:amount"[^>]*>}i
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [_, price_str] ->
          case Float.parse(price_str) do
            {value, _} -> round(value)
            :error -> nil
          end

        _ ->
          nil
      end
    end)
  end

  defp extract_all_prices(html) do
    # Multiple patterns to catch different price formats
    patterns = [
      # Pattern: "- 55 zł" (bullet point price) - most common on kupbilecik
      ~r/[-–—]\s*(\d+(?:[,\.]\d+)?)\s*zł/iu,
      # Pattern: "od 99 zł" or "99 zł"
      ~r/(?:od\s+)?(\d+(?:[,\.]\d+)?)\s*zł/iu,
      # Pattern: "PLN 99" or "99 PLN"
      ~r/(\d+(?:[,\.]\d+)?)\s*PLN/iu,
      ~r/PLN\s*(\d+(?:[,\.]\d+)?)/iu
    ]

    patterns
    |> Enum.flat_map(fn pattern ->
      Regex.scan(pattern, html)
      |> Enum.map(fn
        [_, price_str] -> parse_price_value(price_str)
        _ -> nil
      end)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == 0))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp parse_price_value(price_str) do
    # Handle Polish decimal format (comma) and period
    normalized =
      price_str
      |> String.replace(",", ".")
      |> String.trim()

    case Float.parse(normalized) do
      {value, _} -> round(value)
      :error -> nil
    end
  end

  defp format_price(price) when is_integer(price) and price > 0 do
    "od #{price} zł"
  end

  defp format_price(_), do: nil

  @doc """
  Extract category from HTML or URL.

  Returns Polish category name for mapping in Transformer.

  Strategy (in order of preference):
  1. Breadcrumb/navigation links with category hrefs
  2. Event title keywords (most reliable for kupbilecik)
  3. Keywords meta tag
  4. URL path
  """
  def extract_category(html, url) do
    cond do
      # Strategy 1: Try breadcrumb/navigation links with category hrefs
      cat = extract_category_element(html) ->
        cat

      # Strategy 2: Extract from event title keywords (most reliable for kupbilecik)
      cat = extract_category_from_title_keywords(html) ->
        cat

      # Strategy 3: Extract from keywords meta tag
      cat = extract_category_from_keywords_meta(html) ->
        cat

      # Strategy 4: Extract from URL path if present
      cat = extract_category_from_url(url) ->
        cat

      true ->
        nil
    end
  end

  # Extract category based on keywords in the event title
  # Kupbilecik titles often contain Polish event type words like:
  # "Koncert Przy Świecach", "Stand-up Comedy", "Kabaret Neo-Nówka"
  defp extract_category_from_title_keywords(html) do
    case extract_title(html) do
      {:ok, title} ->
        title_lower = String.downcase(title)

        cond do
          # Music/Concert patterns
          String.contains?(title_lower, ["koncert", "recital", "festiwal muzyki", "muzyczny"]) ->
            "koncerty"

          # Stand-up comedy (specific pattern before general comedy)
          String.contains?(title_lower, ["stand-up", "stand up", "standup"]) ->
            "stand-up"

          # Cabaret/Comedy patterns
          String.contains?(title_lower, ["kabaret", "kabareton"]) ->
            "kabarety"

          # Theater patterns
          String.contains?(title_lower, ["spektakl", "sztuka", "przedstawienie", "dramat"]) ->
            "teatr"

          # Opera/Musical patterns
          String.contains?(title_lower, ["opera", "operetka"]) ->
            "opera"

          String.contains?(title_lower, ["musical"]) ->
            "musical"

          # Ballet patterns
          String.contains?(title_lower, ["balet"]) ->
            "balet"

          # Festival patterns
          String.contains?(title_lower, ["festiwal", "festival"]) ->
            "festiwale"

          # Shows/performances
          String.contains?(title_lower, ["widowisko", "show", "rewia"]) ->
            "widowiska"

          # Sports
          String.contains?(title_lower, ["mecz", "zawody", "sport"]) ->
            "sport"

          # Kids/Family
          String.contains?(title_lower, ["dla dzieci", "bajka", "familijny"]) ->
            "dla-dzieci"

          true ->
            nil
        end

      _ ->
        nil
    end
  end

  # Extract category from keywords meta tag
  # Format: <meta name="keywords" content="...,koncerty,teatr,...">
  defp extract_category_from_keywords_meta(html) do
    case Regex.run(~r{<meta\s+name="keywords"\s+content="([^"]+)"}i, html) do
      [_, keywords] ->
        keywords_lower = String.downcase(keywords)

        # Priority order matters - check specific categories first
        cond do
          String.contains?(keywords_lower, "koncerty") -> "koncerty"
          String.contains?(keywords_lower, "kabarety") -> "kabarety"
          String.contains?(keywords_lower, "spektakle") -> "teatr"
          String.contains?(keywords_lower, "teatr") -> "teatr"
          String.contains?(keywords_lower, "festiwale") -> "festiwale"
          String.contains?(keywords_lower, "opera") -> "opera"
          String.contains?(keywords_lower, "musical") -> "musical"
          String.contains?(keywords_lower, "balet") -> "balet"
          String.contains?(keywords_lower, "sport") -> "sport"
          true -> nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Extract performer names from HTML.

  Kupbilecik embeds performer info in several ways:
  1. **PRIMARY**: Links to /baza/{id}/{name}/ - artist database entries (most reliable)
  2. **SECONDARY**: "Obsada:" section with names in bold tags or after dashes
  3. **SECONDARY**: "Występują:" or similar labels

  Note: We intentionally do NOT extract from all <strong>/<b> tags globally,
  as these often contain user comments, form labels, prices, etc.
  Only /baza/ links and labeled sections are reliable sources for performer names.

  Returns list of performer names or empty list.
  """
  def extract_performers(html) do
    performers =
      []
      # PRIMARY: Extract from /baza/ links (artist database - most reliable)
      |> extract_baza_performers(html)
      # SECONDARY: Extract from labeled sections
      |> extract_obsada_section(html)
      |> extract_wystepuja_section(html)
      |> Enum.uniq()
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(String.length(&1) < 3))
      # Performer names should be reasonable length (DB column is varchar(255))
      |> Enum.reject(&(String.length(&1) > 100))
      # Filter to only names that look like real performer names
      |> Enum.filter(&looks_like_performer_name?/1)

    if Enum.empty?(performers), do: [], else: performers
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
          {:ok, %{"startDate" => start_date}} ->
            start_date

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
      # Pattern 1: h3 with venue link (with <b> wrapper) followed by ", Address" text
      # HTML: <h3><a href="/obiekty/..."><b>VenueName</b></a>, Address Street 123</h3>
      ~r{<h3[^>]*>\s*<a[^>]*href="/obiekty/[^"]*"[^>]*><b>[^<]+</b></a>\s*,\s*([^<]+)</h3>}is,
      # Pattern 2: h3 with venue link (without <b> wrapper) followed by ", Address" text
      # HTML: <h3><a href="/obiekty/...">VenueName</a>, Address Street 123</h3>
      ~r{<h3[^>]*>\s*<a[^>]*href="/obiekty/[^"]*"[^>]*>[^<]+</a>\s*,\s*([^<]+)</h3>}is,
      # Pattern 3: Standard CSS class patterns
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

  defp extract_city(html, address, url) do
    # Try to find city from various sources
    cond do
      # Look for city element (most reliable - /miasta/ links)
      city = extract_city_element(html) ->
        city

      # Try to extract from URL path (very reliable - URLs contain city)
      # Pattern: /imprezy/{event_id}/{city}/{slug}/
      city = extract_city_from_url(url) ->
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

  defp extract_city_from_url(nil), do: nil

  defp extract_city_from_url(url) when is_binary(url) do
    # Kupbilecik URL pattern: /imprezy/{event_id}/{city}/{slug}/
    # Example: https://www.kupbilecik.pl/imprezy/175576/Katowice/Grinch/
    case Regex.run(~r{/imprezy/\d+/([^/]+)/}i, url) do
      [_, city] ->
        # URL-decode and clean the city name
        city
        |> URI.decode()
        |> String.replace("+", " ")
        |> String.trim()

      _ ->
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
      # Primary: City link with /miasta/ path (most reliable)
      # HTML: <h2><a href="/miasta/61/Katowice/"><b>Katowice</b></a></h2>
      ~r{<a[^>]*href="/miasta/[^"]*"[^>]*><b>([^<]+)</b></a>}i,
      # Secondary: City link without <b> wrapper
      ~r{<a[^>]*href="/miasta/[^"]*"[^>]*>([^<]+)</a>}i,
      # Fallback: CSS class patterns
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
    # Kupbilecik has breadcrumb links with category-specific hrefs:
    # Examples found: /kabarety/, /inne/, /koncerty/, /teatr/, /sport/, etc.
    # These hrefs map to canonical categories via Config.category_mapping/0
    #
    # Strategy:
    # 1. Extract category from href path (most reliable)
    # 2. Fall back to link text for categories

    # First try: Extract category slug from href in breadcrumb/navigation links
    # Pattern matches links like: <a href="/kabarety/">Występy kabaretowe</a>
    category_href_pattern =
      ~r{<a[^>]*href="/([a-z\-]+)/"[^>]*>[^<]*</a>}iu

    case Regex.scan(category_href_pattern, html) do
      matches when is_list(matches) and length(matches) > 0 ->
        # Find category slugs (skip generic paths like "imprezy", "bilety", etc.)
        category_slugs = [
          "teatr",
          "koncerty",
          "kabarety",
          "festiwale",
          "opera",
          "musical",
          "stand-up",
          "widowiska",
          "balet",
          "sport",
          "dla-dzieci",
          "inne",
          "muzyka"
        ]

        match =
          Enum.find_value(matches, fn
            [_, slug] ->
              normalized_slug = String.downcase(slug)

              if normalized_slug in category_slugs do
                normalized_slug
              else
                nil
              end

            _ ->
              nil
          end)

        match || extract_category_from_link_text(html)

      _ ->
        extract_category_from_link_text(html)
    end
  end

  defp extract_category_from_link_text(html) do
    # Fallback: Try to extract from link text or class patterns
    patterns = [
      # Category page links by text content (Polish names)
      ~r{<a[^>]*href="/[^"]*"[^>]*>(Teatr|Koncerty|Kabaret[yi]?|Festiwal[ey]?|Opera|Musical|Stand-up|Widowisk[ao]|Balet|Sport|Dla dzieci|Inne|Muzyka|Występy kabaretowe)</a>}iu,
      # Category class elements
      ~r{<[^>]*class="[^"]*category[^"]*"[^>]*>(.*?)</[^>]+>}is
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, html) do
        [_, cat] ->
          cleaned = clean_text(cat)
          # Filter out generic/non-category text
          if cleaned != "" and
               not String.match?(cleaned, ~r/^(strona główna|home|kupbilecik|bilety)/iu) do
            map_polish_category_text(cleaned)
          else
            nil
          end

        _ ->
          nil
      end
    end)
  end

  # Map Polish category display names to category slugs
  defp map_polish_category_text(text) do
    text_lower = String.downcase(text)

    cond do
      String.contains?(text_lower, "kabaret") -> "kabarety"
      String.contains?(text_lower, "koncert") -> "koncerty"
      String.contains?(text_lower, "teatr") -> "teatr"
      String.contains?(text_lower, "festiwal") -> "festiwale"
      String.contains?(text_lower, "opera") -> "opera"
      String.contains?(text_lower, "musical") -> "musical"
      String.contains?(text_lower, "stand-up") -> "stand-up"
      String.contains?(text_lower, "widowisk") -> "widowiska"
      String.contains?(text_lower, "balet") -> "balet"
      String.contains?(text_lower, "sport") -> "sport"
      String.contains?(text_lower, "dzieci") -> "dla-dzieci"
      String.contains?(text_lower, "muzyk") -> "muzyka"
      String.contains?(text_lower, "inne") -> "inne"
      true -> text
    end
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

  # Performer extraction helpers

  # Extract performer names from /baza/ links (artist database - PRIMARY source)
  # Kupbilecik links performers to their database entries:
  # <a href="/baza/1846/Cezary+Jurkiewicz/">Cezary Jurkiewicz</a>
  # The URL-encoded name in the path is the most reliable source
  defp extract_baza_performers(acc, html) do
    # Pattern: /baza/{id}/{url-encoded-name}/
    # Extract the name from the URL path (more reliable than link text)
    case Regex.scan(~r{<a[^>]*href="/baza/\d+/([^/]+)/"[^>]*>}i, html) do
      matches when is_list(matches) and length(matches) > 0 ->
        names =
          matches
          |> Enum.map(fn [_, url_encoded_name] ->
            # Decode URL encoding: "Cezary+Jurkiewicz" -> "Cezary Jurkiewicz"
            url_encoded_name
            |> String.replace("+", " ")
            |> URI.decode()
            |> String.trim()
          end)
          |> Enum.reject(&(String.length(&1) < 3))
          |> Enum.uniq()

        acc ++ names

      _ ->
        acc
    end
  end

  # Validate that a name looks like an actual performer name
  # Filters out random text extracted from HTML that isn't a real name
  defp looks_like_performer_name?(name) when is_binary(name) do
    # Must have at least one space (first + last name) OR be a known single-name performer format
    # Single names are acceptable if they look like stage names (capitalized, reasonable length)
    word_count = name |> String.split(~r/\s+/) |> length()

    cond do
      # Must have at least one space for most names (First Last)
      word_count >= 2 ->
        # Multi-word name - validate format
        validate_multi_word_name(name)

      # Single word names are only valid if they look like stage names
      word_count == 1 ->
        validate_single_name(name)

      true ->
        false
    end
  end

  defp looks_like_performer_name?(_), do: false

  # Validate multi-word names (First Last, etc.)
  defp validate_multi_word_name(name) do
    words = String.split(name, ~r/\s+/)

    # Each word should start with uppercase (proper names)
    # Allow for particles like "von", "de", "van" which may be lowercase
    all_valid_words =
      Enum.all?(words, fn word ->
        # Allow lowercase particles (2-3 chars)
        # Or starts with uppercase
        String.length(word) <= 3 or
          String.match?(word, ~r/^[\p{Lu}]/u)
      end)

    # At least one word must be properly capitalized (the main name part)
    has_capitalized_word =
      Enum.any?(words, fn word ->
        String.length(word) > 1 and String.match?(word, ~r/^[\p{Lu}]/u)
      end)

    # Not too many words (4 is reasonable max for names)
    reasonable_word_count = length(words) <= 4

    # No garbage patterns (all caps, random strings)
    not_all_caps = not String.match?(name, ~r/^[\p{Lu}\s]+$/u) or String.length(name) <= 10

    all_valid_words and has_capitalized_word and reasonable_word_count and not_all_caps
  end

  # Validate single-word names (stage names like "Cher", "Madonna", etc.)
  defp validate_single_name(name) do
    # Single names must:
    # 1. Start with uppercase
    # 2. Be reasonable length (4-20 chars)
    # 3. Not be all uppercase (unless short)
    # 4. Look like a proper name (not random text)

    len = String.length(name)

    starts_uppercase = String.match?(name, ~r/^[\p{Lu}]/u)
    reasonable_length = len >= 4 and len <= 20
    not_all_caps = not String.match?(name, ~r/^[\p{Lu}]+$/u) or len <= 6

    # Reject obvious non-names
    not_garbage = not String.match?(name, ~r/^(menu|english|deutsch|polski|home|bilety)$/i)

    starts_uppercase and reasonable_length and not_all_caps and not_garbage
  end

  defp extract_obsada_section(acc, html) do
    # Look for "Obsada:" section followed by names
    # Pattern: "Obsada: Name1, Name2" or "Obsada:<br>Name1<br>Name2"
    case Regex.run(~r/Obsada:?\s*(.*?)(?:<\/p>|<br|$)/isu, html) do
      [_, content] ->
        names = extract_names_from_text(content)
        acc ++ names

      _ ->
        acc
    end
  end

  defp extract_wystepuja_section(acc, html) do
    # Look for "Występują:" or similar labels
    patterns = [
      ~r/Wyst[eę]puj[aą]:?\s*(.*?)(?:<\/p>|<br|$)/isu,
      ~r/W\s+rolach:?\s*(.*?)(?:<\/p>|<br|$)/isu,
      ~r/Arty[sś]ci:?\s*(.*?)(?:<\/p>|<br|$)/isu
    ]

    Enum.reduce(patterns, acc, fn pattern, current_acc ->
      case Regex.run(pattern, html) do
        [_, content] ->
          names = extract_names_from_text(content)
          current_acc ++ names

        _ ->
          current_acc
      end
    end)
  end

  defp extract_names_from_text(text) do
    # Clean HTML and extract names separated by commas, slashes, or newlines
    clean = clean_text(text)

    clean
    |> String.split(~r/[,\/\n]+/)
    |> Enum.map(&clean_performer_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(String.length(&1) < 3))
  end

  defp clean_performer_name(nil), do: nil

  defp clean_performer_name(name) do
    cleaned =
      name
      |> String.trim()
      |> String.replace(~r/<[^>]+>/, "")
      |> String.replace(~r/^\s*[-–—]\s*/, "")
      |> String.replace(~r/\s*[-–—]\s*$/, "")
      |> String.trim()

    len = String.length(cleaned)

    # Skip if it's not a valid name format
    # Must be 3-100 chars, only letters/spaces/punctuation, not start with digit
    if len >= 3 and len <= 100 and
         String.match?(cleaned, ~r/^[\p{L}\s\.\-']+$/u) and
         not String.match?(cleaned, ~r/^\d/) do
      cleaned
    else
      nil
    end
  end
end
