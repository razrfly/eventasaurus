defmodule EventasaurusDiscovery.Sources.QuestionOne.Extractors.VenueExtractor do
  @moduledoc """
  Extracts venue and event data from Question One HTML pages.

  Question One uses a unique icon-based extraction pattern where
  fields are identified by SVG icon references (use[href] attributes).

  ## Icon Mappings
  - `pin` - Address/location
  - `calendar` - Schedule/time information
  - `tag` - Fee/pricing information
  - `phone` - Phone number

  ## Example HTML Structure
  ```html
  <div class="text-with-icon">
    <svg><use href="#pin"></use></svg>
    <span class="text-with-icon__text">123 High St, London</span>
  </div>
  ```
  """

  require Logger
  alias HtmlEntities

  @doc """
  Extract venue data from a parsed HTML document.

  ## Parameters
  - `document` - Floki-parsed HTML document
  - `url` - Source URL of the venue page
  - `raw_title` - Raw title from RSS feed

  ## Returns
  - `{:ok, venue_data}` - Successfully extracted data
  - `{:error, reason}` - Extraction failed

  ## Required Fields
  - title (cleaned)
  - address
  - time_text

  ## Optional Fields
  - fee_text, phone, website, description, hero_image_url
  """
  def extract_venue_data(document, url, raw_title) do
    # Clean title (remove "PUB QUIZ" prefix and extra formatting)
    title = clean_title(raw_title)

    # Extract required fields with icon-based extraction
    with {:ok, address} <- find_text_with_icon(document, "pin"),
         {:ok, time_text} <- find_text_with_icon(document, "calendar") do
      # Optional fields - don't fail if missing
      fee_text =
        case find_text_with_icon(document, "tag") do
          {:ok, value} -> value
          {:error, _} -> nil
        end

      phone =
        case find_text_with_icon(document, "phone") do
          {:ok, value} -> value
          {:error, _} -> nil
        end

      website = extract_website(document)
      description = extract_description(document)
      hero_image_url = extract_hero_image(document)

      venue_data = %{
        title: title,
        raw_title: raw_title,
        address: address,
        time_text: time_text,
        fee_text: fee_text,
        phone: phone,
        website: website,
        description: description,
        hero_image_url: hero_image_url,
        source_url: url
      }

      Logger.debug("✅ Extracted venue data: #{title}")
      {:ok, venue_data}
    else
      {:error, reason} ->
        Logger.error("❌ Failed to extract venue data from #{url}: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Clean the raw title by removing common prefixes and formatting.

  IMPORTANT: Decodes HTML entities FIRST, before any regex operations,
  so that cleaning regexes can properly match decoded characters.

  ## Examples
      iex> clean_title("PUB QUIZ &#8211; The Red Lion")
      "The Red Lion"

      iex> clean_title("PUB QUIZ: The Crown &#8211; Every Wednesday")
      "The Crown"
  """
  def clean_title(raw_title) do
    raw_title
    # CRITICAL: Decode HTML entities FIRST before any regex operations
    # This ensures regexes can match actual characters (–) not entity strings (&#8211;)
    |> HtmlEntities.decode()
    # Remove "PUB QUIZ" prefix with various punctuation
    |> String.replace(~r/^PUB QUIZ[[:punct:]]*/i, "")
    # Remove leading dashes and whitespace (now matches actual – character)
    |> String.replace(~r/^[–\s]+/, "")
    # Remove trailing dashes and anything after
    |> String.replace(~r/\s+[–].*$/i, "")
    |> String.trim()
  end

  # Find text associated with a specific icon in Question One's HTML structure.
  # Returns {:ok, text} or {:error, reason}
  defp find_text_with_icon(document, icon_name) do
    case document
         |> Floki.find(".text-with-icon")
         |> Enum.find(fn el ->
           # Find the SVG use tag and check its href attributes
           Floki.find(el, "use")
           |> Enum.any?(fn use_tag ->
             href = Floki.attribute(use_tag, "href") |> List.first()
             xlink = Floki.attribute(use_tag, "xlink:href") |> List.first()
             # Match on either href or xlink:href ending with #icon_name
             (href && String.ends_with?(href, "##{icon_name}")) ||
               (xlink && String.ends_with?(xlink, "##{icon_name}"))
           end)
         end) do
      nil ->
        {:error, "Missing icon text for '#{icon_name}'"}

      element ->
        text =
          element
          |> Floki.find(".text-with-icon__text")
          |> Floki.text()
          |> String.trim()

        if text == "" do
          {:error, "Empty text for icon '#{icon_name}'"}
        else
          {:ok, text}
        end
    end
  end

  # Extract website URL from "Visit Website" link
  defp extract_website(document) do
    document
    |> Floki.find("a[href]:fl-contains('Visit Website')")
    |> Floki.attribute("href")
    |> List.first()
    |> case do
      nil -> nil
      url -> String.trim(url)
    end
  end

  # Extract description from post content area paragraphs
  defp extract_description(document) do
    document
    |> Floki.find(".post-content-area p")
    |> Enum.map(&Floki.text/1)
    |> Enum.join("\n\n")
    |> String.trim()
    |> case do
      "" -> nil
      desc -> desc
    end
  end

  # Extract hero image URL from WordPress uploads
  defp extract_hero_image(document) do
    document
    |> Floki.find("img[src*='wp-content/uploads']")
    |> Floki.attribute("src")
    |> List.first()
  end
end
