defmodule EventasaurusDiscovery.Sources.Sortiraparis.Extractors.EventExtractor do
  @moduledoc """
  Extracts event data from Sortiraparis HTML pages.

  ## Extraction Strategy

  Uses CSS selectors and regex patterns to extract:
  - Event title from h1 or meta tags
  - Date information from multiple possible locations
  - Description from article body
  - Image URL from og:image or first article image
  - Pricing information from text content
  - Performer information (for concerts)

  ## HTML Structure

  Sortiraparis uses semantic HTML with:
  - `<article>` wrapper for event content
  - `<h1>` for title
  - Date info in various formats and locations
  - `<figure>` for images
  - Pricing info embedded in text content

  ## Date Handling

  Date strings are extracted raw and passed to DateParser.
  Common patterns:
  - "February 25, 27, 28, 2026" (multi-date)
  - "October 15, 2025 to January 19, 2026" (range)
  - "Friday, October 31, 2025" (single with day)
  """

  require Logger
  alias EventasaurusDiscovery.Scraping.Helpers.Normalizer

  @doc """
  Extract event data from HTML page.

  ## Parameters

  - `html` - HTML content as string
  - `url` - Page URL for context

  ## Returns

  - `{:ok, event_data}` - Map with extracted fields
  - `{:error, reason}` - Extraction failed
  """
  def extract(html, url) when is_binary(html) and is_binary(url) do
    Logger.debug("🔍 Extracting event data from HTML (#{byte_size(html)} bytes)")

    with {:ok, title} <- extract_title(html),
         {:ok, date_string} <- extract_date_string(html),
         {:ok, description} <- extract_description(html),
         {:ok, image_url} <- extract_image_url(html) do
      # Extract optional fields (don't fail if missing)
      pricing = extract_pricing(html)
      performers = extract_performers(html)

      # Classify event type based on date pattern, title, and description
      event_type = classify_event_type(date_string, title, description)

      event_data = %{
        "url" => url,
        "title" => title,
        "date_string" => date_string,
        "description" => description,
        "image_url" => image_url,
        "is_ticketed" => pricing[:is_ticketed],
        "is_free" => pricing[:is_free],
        "min_price" => pricing[:min_price],
        "max_price" => pricing[:max_price],
        "currency" => pricing[:currency] || "EUR",
        "performers" => performers,
        "original_date_string" => date_string,
        "event_type" => event_type
      }

      Logger.debug("✅ Successfully extracted event data: #{title} (type: #{event_type})")
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
  1. <h1> tag in article
  2. og:title meta tag
  3. <title> tag (fallback)
  """
  def extract_title(html) do
    cond do
      # Strategy 1: <h1> tag
      title = extract_h1_title(html) ->
        {:ok, title}

      # Strategy 2: og:title
      title = extract_meta_title(html) ->
        {:ok, title}

      # Strategy 3: <title> tag (fallback)
      title = extract_page_title(html) ->
        {:ok, title}

      true ->
        {:error, :title_not_found}
    end
  end

  @doc """
  Extract date string from HTML.

  Dates can appear in multiple locations:
  1. Dedicated date section with class "date" or "datetime"
  2. Within article metadata
  3. In structured data (JSON-LD)
  """
  def extract_date_string(html) do
    cond do
      # Strategy 1: Look for date-specific elements
      date = extract_date_element(html) ->
        {:ok, date}

      # Strategy 2: Search article text for date patterns
      date = extract_date_from_text(html) ->
        {:ok, date}

      # Strategy 3: Check structured data
      date = extract_date_from_json_ld(html) ->
        {:ok, date}

      true ->
        {:error, :date_not_found}
    end
  end

  @doc """
  Extract event description from article body.

  Extracts first paragraph or two for summary.
  Cleans HTML tags and normalizes whitespace.
  """
  def extract_description(html) do
    # Look for article content paragraphs
    case Regex.run(~r{<article[^>]*>(.*?)</article>}s, html) do
      [_, article_content] ->
        # Extract first 2-3 paragraphs
        paragraphs =
          Regex.scan(~r{<p[^>]*>(.*?)</p>}s, article_content, capture: :all_but_first)
          |> Enum.take(2)
          |> Enum.map(fn [p] -> Normalizer.clean_html(p) end)
          |> Enum.reject(&(&1 == ""))

        if length(paragraphs) > 0 do
          {:ok, Enum.join(paragraphs, "\n\n")}
        else
          {:error, :description_not_found}
        end

      _ ->
        # Fallback: try meta description
        case extract_meta_description(html) do
          nil -> {:error, :description_not_found}
          desc -> {:ok, desc}
        end
    end
  end

  @doc """
  Extract image URL from page.

  Priority:
  1. og:image meta tag
  2. First <figure> image in article
  3. First <img> in article
  """
  def extract_image_url(html) do
    cond do
      # Strategy 1: og:image
      url = extract_og_image(html) ->
        {:ok, url}

      # Strategy 2: First figure image
      url = extract_figure_image(html) ->
        {:ok, url}

      # Strategy 3: First article image
      url = extract_first_image(html) ->
        {:ok, url}

      true ->
        {:ok, nil}  # Image is optional
    end
  end

  @doc """
  Extract pricing information from text content.

  Returns map with:
  - `:is_ticketed` - Boolean
  - `:is_free` - Boolean
  - `:min_price` - Decimal (if found)
  - `:max_price` - Decimal (if found)
  - `:currency` - String (EUR, USD, etc.)
  """
  def extract_pricing(html) do
    text = Normalizer.clean_html(html)
    down = String.downcase(text)

    is_free =
      String.contains?(down, "free") or
        String.contains?(down, "free admission") or
        String.contains?(down, "no charge") or
        String.contains?(down, "gratuit") or
        String.contains?(down, "entrée libre")

    # Look for price patterns: "€15", "$20", "15€", "20 euros"
    # Handle EU formats with comma decimals and thousand separators
    prices =
      Regex.scan(
        ~r/(?:(?:€|EUR|euros?)\s*([\d\s.,]+)|([\d\s.,]+)\s*(?:€|EUR|euros?))/i,
        text
      )
      |> Enum.flat_map(fn
        [_, p1, ""] when p1 != "" -> [parse_price(p1)]
        [_, "", p2] when p2 != "" -> [parse_price(p2)]
        [_, p1, p2] -> [p1, p2] |> Enum.reject(&is_nil_or_empty/1) |> Enum.map(&parse_price/1)
        _ -> []
      end)
      |> Enum.reject(&is_nil/1)

    # Database constraint: if is_free = true, then min_price and max_price must be NULL
    # So when event is free, ignore any extracted prices
    {min_price, max_price} =
      if is_free do
        {nil, nil}
      else
        {
          if(length(prices) > 0, do: Enum.min(prices), else: nil),
          if(length(prices) > 1, do: Enum.max(prices), else: nil)
        }
      end

    %{
      is_free: is_free,
      is_ticketed: not is_free and length(prices) > 0,
      min_price: min_price,
      max_price: max_price,
      currency: "EUR"
    }
  end

  @doc """
  Extract performer information (mainly for concerts).

  Returns list of performer names.
  """
  def extract_performers(_html) do
    # Look for common performer patterns
    # This is basic - can be enhanced based on actual HTML structure
    []  # TODO: Implement if needed based on real HTML structure
  end

  # Private helper functions

  defp extract_h1_title(html) do
    case Regex.run(~r{<h1[^>]*>(.*?)</h1>}s, html) do
      [_, title] -> Normalizer.clean_html(title)
      _ -> nil
    end
  end

  defp extract_meta_title(html) do
    case Regex.run(~r{<meta\s+property="og:title"\s+content="([^"]+)"}i, html) do
      [_, title] -> String.trim(title)
      _ -> nil
    end
  end

  defp extract_page_title(html) do
    case Regex.run(~r{<title[^>]*>(.*?)</title>}s, html) do
      [_, title] ->
        title
        |> String.trim()
        |> String.replace(~r{\s*\|\s*Sortiraparis\.com.*$}, "")

      _ ->
        nil
    end
  end

  defp extract_date_element(html) do
    # Look for common date element patterns
    patterns = [
      ~r{<time[^>]*>(.*?)</time>}s,
      ~r{<div[^>]*class="[^"]*date[^"]*"[^>]*>(.*?)</div>}s,
      ~r{<span[^>]*class="[^"]*datetime[^"]*"[^>]*>(.*?)</span>}s
    ]

    patterns
    |> Enum.find_value(fn pattern ->
      case Regex.run(pattern, html) do
        [_, date] -> Normalizer.clean_html(date)
        _ -> nil
      end
    end)
  end

  defp extract_date_from_text(html) do
    # Clean HTML and look for date patterns
    # NOTE: This function only EXTRACTS date text from HTML.
    # Actual date PARSING happens in the Transformer using MultilingualDateParser.
    text = Normalizer.clean_html(html)

    # Month names (English|French)
    months =
      "(?:January|February|March|April|May|June|July|August|September|October|November|December|janvier|février|mars|avril|mai|juin|juillet|août|septembre|octobre|novembre|décembre)"

    # Day names (English|French)
    days =
      "(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)"

    # Date range connectors (English: "to" | French: "au")
    connector = "(?:to|au)"

    # Broad patterns to extract date text
    patterns = [
      # Range with "Du...au": "Du 1er janvier au 15 février 2026"
      ~r/(?:Du|From)\s+\d+(?:er|st|nd|rd|th)?\s+#{months}\s+#{connector}\s+\d+(?:er|st|nd|rd|th)?\s+#{months}\s+\d{4}/i,
      # Range: "October 15, 2025 to January 19, 2026" or "15 octobre 2025 au 19 janvier 2026"
      ~r/(#{months}\s+\d+,?\s*\d{4}\s+#{connector}\s+#{months}\s+\d+,?\s*\d{4})/i,
      # Range with shared year: "15 octobre au 20 novembre 2025"
      ~r/(#{months}\s+\d+\s+#{connector}\s+#{months}\s+\d+,?\s*\d{4})/i,
      ~r/(\d+\s+#{months}\s+#{connector}\s+\d+\s+#{months}\s+\d{4})/i,
      # Short-range with shared month: "from July 4 to 6, 2025" or "du 4 au 6 juillet 2025"
      ~r/(?:from|du)\s+#{months}\s+\d+\s+#{connector}\s+\d+,?\s*\d{4}/i,
      ~r/(?:from|du)\s+\d+\s+#{connector}\s+\d+\s+#{months}\s+\d{4}/i,
      # Multi-date: "February 25, 27, 28, 2026"
      ~r/(#{months}\s+\d+(?:,\s*\d+)+,\s*\d{4})/i,
      # Single with day: "Friday, October 31, 2025" or "vendredi 31 octobre 2025"
      ~r/(#{days},?\s*\d+\s+#{months}\s+\d{4})/i,
      ~r/(#{days},?\s*#{months}\s+\d+,?\s*\d{4})/i,
      # French date with article: "Le 19 avril 2025"
      ~r/(?:Le|The)\s+(\d+(?:er|st|nd|rd|th)?\s+#{months}\s+\d{4})/i,
      # Simple French date: "15 décembre 2025"
      ~r/(\d+(?:er|e)?\s+#{months}\s+\d{4})/i,
      # Simple English date: "December 15, 2025"
      ~r/(#{months}\s+\d+(?:er|st|nd|rd|th)?,?\s+\d{4})/i
    ]

    # Find and return date text (no parsing here - that happens in Transformer)
    patterns
    |> Enum.find_value(fn pattern ->
      case Regex.run(pattern, text) do
        [_, date] -> String.trim(date)
        [date] -> String.trim(date)
        _ -> nil
      end
    end)
  end

  defp extract_date_from_json_ld(html) do
    case Regex.run(~r{<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>}s, html) do
      [_, json] ->
        # Try to parse JSON and extract startDate
        case Jason.decode(json) do
          {:ok, %{"startDate" => start_date}} -> start_date
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp extract_meta_description(html) do
    case Regex.run(~r{<meta\s+(?:name|property)="description"\s+content="([^"]+)"}i, html) do
      [_, desc] -> desc |> String.trim() |> HtmlEntities.decode()
      _ -> nil
    end
  end

  defp extract_og_image(html) do
    case Regex.run(~r{<meta\s+property="og:image"\s+content="([^"]+)"}i, html) do
      [_, url] -> String.trim(url)
      _ -> nil
    end
  end

  defp extract_figure_image(html) do
    case Regex.run(~r{<figure[^>]*>.*?<img[^>]*src="([^"]+)".*?</figure>}s, html) do
      [_, url] -> String.trim(url)
      _ -> nil
    end
  end

  defp extract_first_image(html) do
    case Regex.run(~r{<article[^>]*>.*?<img[^>]*src="([^"]+)"}s, html) do
      [_, url] -> String.trim(url)
      _ -> nil
    end
  end

  defp parse_price(price_string) when is_binary(price_string) do
    # Normalize EU number formats (e.g., "1.500,50" → "1500.50")
    normalized =
      price_string
      |> String.replace(~r/\s+/, "")          # Remove spaces
      |> String.replace(~r/\.(?=\d{3}\b)/, "") # Remove thousand dots
      |> String.replace(",", ".")             # Convert comma to dot

    case Decimal.parse(normalized) do
      {decimal, _} -> decimal
      :error -> nil
    end
  end

  defp parse_price(_), do: nil

  defp is_nil_or_empty(nil), do: true
  defp is_nil_or_empty(""), do: true
  defp is_nil_or_empty(_), do: false

  # Classify event type based on date pattern, title, and description.
  # Returns one of:
  # - `:one_time` - Single specific date event (concerts, performances)
  # - `:exhibition` - Continuous access during a period (museums, galleries)
  # - `:recurring` - Pattern-based events (weekly/monthly)
  defp classify_event_type(date_string, title, description) do
    date_pattern = classify_by_date_pattern(date_string)
    text = "#{title} #{description}" |> String.downcase()

    cond do
      # Recurring indicators
      recurring_pattern?(text) ->
        :recurring

      # Exhibition indicators - check date pattern AND keywords
      date_pattern == :potential_exhibition && exhibition_keywords?(text) ->
        :exhibition

      # One-time events - single date detected
      date_pattern == :one_time ->
        :one_time

      # Ambiguous - default to exhibition (safer than creating duplicates)
      true ->
        :exhibition
    end
  end

  defp classify_by_date_pattern(date_string) when is_binary(date_string) do
    text = String.downcase(date_string)

    cond do
      # Range pattern: "October 15, 2025 to January 19, 2026"
      text =~ ~r/\d{4}\s+to\s+\w+\s+\d+,\s*\d{4}/ ->
        :potential_exhibition

      # Multi-date pattern: "February 25, 27, 28, 2026"
      text =~ ~r/\w+\s+\d+(?:,\s*\d+)+,\s*\d{4}/ ->
        :one_time

      # Single date with day: "Friday, October 31, 2025"
      text =~ ~r/(monday|tuesday|wednesday|thursday|friday|saturday|sunday),\s*\w+\s+\d+,\s*\d{4}/i ->
        :one_time

      # Default to potential exhibition for safety
      true ->
        :potential_exhibition
    end
  end

  defp classify_by_date_pattern(_), do: :potential_exhibition

  defp recurring_pattern?(text) when is_binary(text) do
    text =~ ~r/every (monday|tuesday|wednesday|thursday|friday|saturday|sunday)/i ||
      text =~ ~r/every \w+ evening/i ||
      text =~ ~r/every \w+ night/i ||
      text =~ ~r/\d+ times? (per|a) (week|month)/i ||
      text =~ ~r/tous les (lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)/i ||
      text =~ ~r/chaque (lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)/i
  end

  defp recurring_pattern?(_), do: false

  defp exhibition_keywords?(text) when is_binary(text) do
    text =~ ~r/exhibition/i ||
      text =~ ~r/musée|museum/i ||
      text =~ ~r/gallery|galerie/i ||
      text =~ ~r/exposition/i ||
      text =~ ~r/installat/i ||
      text =~ ~r/retrospective/i
  end

  defp exhibition_keywords?(_), do: false
end
