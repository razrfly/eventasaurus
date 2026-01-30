defmodule EventasaurusDiscovery.Sources.Waw4free.DetailExtractor do
  @moduledoc """
  Extracts event details from waw4free.pl event detail pages.

  Parses HTML to extract:
  - Title
  - Date and time (Polish date formats)
  - Venue (address and district)
  - Description
  - Categories (Polish category links)
  - Image URL
  - Voluntary donation indicator
  """

  require Logger
  alias EventasaurusDiscovery.Sources.Waw4free.Config
  alias EventasaurusDiscovery.Sources.Shared.Parsers.MultilingualDateParser

  @doc """
  Extract event details from event page HTML.
  Returns event data map or error tuple.
  """
  def extract_event_from_html(html, url) when is_binary(html) and is_binary(url) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        # Check for error page or missing content
        if is_error_page?(document) do
          Logger.warning("⚠️ Error page detected for URL: #{url}")
          {:error, :not_found}
        else
          extract_event_details(document, url)
        end

      {:error, reason} ->
        Logger.error("Failed to parse HTML for #{url}: #{inspect(reason)}")
        {:error, :parse_failed}
    end
  end

  defp is_error_page?(document) do
    # Check for common error indicators
    title = Floki.find(document, "h1") |> Floki.text() |> String.downcase()

    String.contains?(title, "błąd") ||
      String.contains?(title, "nie znaleziono") ||
      String.contains?(title, "error") ||
      String.contains?(title, "404")
  end

  defp extract_event_details(document, url) do
    try do
      # Extract basic fields
      title = extract_title(document)
      description = extract_description(document)
      image_url = extract_image(document)

      Logger.debug("🖼️ Extracted image_url: #{inspect(image_url)}")
      Logger.debug("📝 Extracted description length: #{String.length(description || "")}")

      # Extract date/time with Polish parser
      date_text = extract_date_text(document)
      time_text = extract_time_text(document)
      combined_date_text = combine_date_time_text(date_text, time_text)

      # Parse dates using Polish date parser
      date_result = parse_polish_date(combined_date_text)

      # Extract venue information
      venue = extract_venue(document)
      district = extract_district(document)

      # Extract categories (Polish)
      categories = extract_categories(document)

      # Check for voluntary donation
      is_free = check_voluntary_donation(document, description)

      # Build event data
      event_data = %{
        title: title,
        description: description,
        image_url: image_url,
        venue: venue,
        district: district,
        categories: categories,
        is_free: is_free,
        source_url: url,
        external_id: Config.extract_external_id(url),
        raw_date_text: combined_date_text
      }

      # Merge date parsing results
      event_data =
        case date_result do
          {:ok, %{starts_at: starts_at} = dates} ->
            event_data
            |> Map.put(:starts_at, starts_at)
            |> Map.put(:ends_at, Map.get(dates, :ends_at))

          {:error, reason} ->
            Logger.warning("Failed to parse date '#{combined_date_text}': #{inspect(reason)}")
            event_data
        end

      # Validate required fields
      if valid_event?(event_data) do
        {:ok, event_data}
      else
        Logger.warning("Invalid event data for #{url}: missing required fields")
        {:error, :invalid_data}
      end
    rescue
      e ->
        Logger.error("Failed to extract event details from #{url}: #{inspect(e)}")
        {:error, :extraction_failed}
    end
  end

  # Extract title from h1 element.
  defp extract_title(document) do
    document
    |> Floki.find("h1")
    |> Floki.text()
    |> String.trim()
    |> clean_text()
  end

  # Extract description from paragraphs.
  defp extract_description(document) do
    # Try waw4free-specific selector: ONLY .article_text WITH itemprop="description"
    description =
      document
      |> Floki.find("div[itemprop='description'].article_text")
      |> Floki.text()
      |> String.trim()

    # Fallback to generic content selectors
    if !description || String.length(description) < 20 do
      description =
        document
        |> Floki.find(".content, .opis, .description, article p")
        |> Enum.map(&Floki.text/1)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n\n")

      # Final fallback to all paragraphs if still no content found
      if String.length(description) < 20 do
        document
        |> Floki.find("p")
        |> Enum.map(&Floki.text/1)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        # Limit to first 5 paragraphs
        |> Enum.take(5)
        |> Enum.join("\n\n")
        |> clean_text()
      else
        clean_text(description)
      end
    else
      clean_text(description)
    end
  end

  # Extract date text from document.
  # Looks for patterns like "📅 Data: wtorek, 28 października 2025"
  defp extract_date_text(document) do
    # Try specific date selectors
    selectors = [
      # Common Polish selector
      ".kiedy",
      ".data",
      ".date",
      "[class*='date']",
      "[class*='data']"
    ]

    date_text =
      Enum.find_value(selectors, fn selector ->
        text = document |> Floki.find(selector) |> Floki.text() |> String.trim()
        if String.length(text) > 0, do: text, else: nil
      end)

    # Fallback: search for text containing "Data:"
    date_text || find_text_containing(document, ["Data:", "📅"])
  end

  # Extract time text from document.
  # Looks for patterns like "⌚ Godzina rozpoczęcia: 18:00"
  defp extract_time_text(document) do
    # Try specific time selectors
    selectors = [
      ".godzina",
      ".time",
      "[class*='time']",
      "[class*='godzina']"
    ]

    time_text =
      Enum.find_value(selectors, fn selector ->
        text = document |> Floki.find(selector) |> Floki.text() |> String.trim()
        if String.length(text) > 0, do: text, else: nil
      end)

    # Fallback: search for text containing "Godzina:"
    time_text || find_text_containing(document, ["Godzina:", "⌚"])
  end

  # Combine date and time text for parsing.
  defp combine_date_time_text(date_text, time_text) do
    cond do
      date_text && time_text -> "#{date_text} #{time_text}"
      date_text -> date_text
      time_text -> time_text
      true -> ""
    end
  end

  # Parse Polish date using MultilingualDateParser.
  defp parse_polish_date(text) when is_binary(text) and byte_size(text) > 0 do
    MultilingualDateParser.extract_and_parse(text,
      languages: [:polish],
      timezone: "Europe/Warsaw"
    )
  end

  defp parse_polish_date(_), do: {:error, :no_date_text}

  # Extract venue information.
  # Looks for patterns like "📌 Miejsce: Warszawa - Śródmieście, ul. Złota 11"
  defp extract_venue(document) do
    # Try specific venue selectors
    selectors = [
      # Common Polish selector
      ".gdzie",
      ".miejsce",
      ".venue",
      ".location",
      "[class*='venue']",
      "[class*='miejsce']"
    ]

    venue_text =
      Enum.find_value(selectors, fn selector ->
        text = document |> Floki.find(selector) |> Floki.text() |> String.trim()
        if String.length(text) > 0, do: text, else: nil
      end)

    # Fallback: search for text containing "Miejsce:"
    venue_text = venue_text || find_text_containing(document, ["Miejsce:", "📌"])

    # Clean up venue text
    if venue_text do
      venue_text
      |> String.replace(~r/^.*Miejsce:\s*/i, "")
      |> String.replace("📌", "")
      |> String.trim()
      |> clean_text()
    else
      nil
    end
  end

  # Extract district from venue text or district links.
  defp extract_district(document) do
    # Try district links
    district_links = Floki.find(document, "a[href*='dzielnica'], a[href*='district']")

    if Enum.any?(district_links) do
      district_links
      |> List.first()
      |> Floki.text()
      |> String.trim()
    else
      # Try to extract from venue text
      venue = extract_venue(document)

      if venue && String.contains?(venue, " - ") do
        venue
        |> String.split(" - ")
        |> Enum.at(1)
        |> case do
          nil -> nil
          text -> text |> String.split(",") |> List.first() |> String.trim()
        end
      else
        nil
      end
    end
  end

  # Extract categories from category links.
  # Returns list of Polish category slugs.
  defp extract_categories(document) do
    # waw4free uses .box-category div with nested category links
    document
    |> Floki.find(".box-category a")
    |> Enum.map(&Floki.text/1)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  # Extract image URL from document.
  defp extract_image(document) do
    # Try og:image meta tag first (most reliable) - returns full URL
    og_image_elements = Floki.find(document, "meta[property='og:image']")
    Logger.debug("🔍 Found #{length(og_image_elements)} og:image elements")

    og_image =
      og_image_elements
      |> Floki.attribute("content")
      |> List.first()

    Logger.debug("🖼️ og:image value: #{inspect(og_image)}")

    cond do
      og_image && String.length(og_image) > 0 ->
        Logger.debug("✅ Using og:image: #{og_image}")
        og_image

      true ->
        # Try img[itemprop="image"] selector (waw4free uses this)
        img_elements = Floki.find(document, "img[itemprop='image']")
        Logger.debug("🔍 Found #{length(img_elements)} img[itemprop='image'] elements")

        img_src =
          img_elements
          |> Floki.attribute("src")
          |> List.first()

        Logger.debug("🖼️ img[itemprop='image'] src: #{inspect(img_src)}")

        if img_src && !String.starts_with?(img_src, "data:") do
          url = build_full_url(img_src)
          Logger.debug("✅ Using img[itemprop]: #{url}")
          url
        else
          # Fallback: try .article_image container
          fallback_elements = Floki.find(document, ".article_image img")
          Logger.debug("🔍 Found #{length(fallback_elements)} .article_image img elements")

          fallback_src =
            fallback_elements
            |> Floki.attribute("src")
            |> List.first()

          Logger.debug("🖼️ .article_image img src: #{inspect(fallback_src)}")

          if fallback_src && !String.starts_with?(fallback_src, "data:") do
            url = build_full_url(fallback_src)
            Logger.debug("✅ Using .article_image: #{url}")
            url
          else
            Logger.warning("❌ No image found in document")
            nil
          end
        end
    end
  end

  # Check if event has voluntary donation indicator.
  defp check_voluntary_donation(document, description) do
    text = Floki.text(document) |> String.downcase()
    desc = String.downcase(description || "")

    String.contains?(text, "dobrowolna zrzutka") ||
      String.contains?(desc, "dobrowolna zrzutka") ||
      String.contains?(text, "wstęp wolny") ||
      String.contains?(desc, "wstęp wolny")
  end

  # Helper functions

  defp find_text_containing(document, search_terms) do
    document
    |> Floki.text()
    |> String.split("\n")
    |> Enum.find(fn line ->
      Enum.any?(search_terms, &String.contains?(line, &1))
    end)
    |> case do
      nil -> nil
      line -> String.trim(line)
    end
  end

  defp clean_text(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp clean_text(nil), do: nil

  defp build_full_url(url) when is_binary(url) do
    cond do
      String.starts_with?(url, "http://") or String.starts_with?(url, "https://") ->
        url

      String.starts_with?(url, "//") ->
        "https:" <> url

      String.starts_with?(url, "/") ->
        Config.base_url() <> url

      true ->
        Config.base_url() <> "/" <> url
    end
  end

  defp valid_event?(event_data) do
    # Required fields
    has_title = event_data[:title] && String.length(event_data.title) > 3
    has_url = event_data[:source_url] != nil
    has_external_id = event_data[:external_id] != nil

    has_title && has_url && has_external_id
  end
end
