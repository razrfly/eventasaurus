defmodule EventasaurusDiscovery.Sources.Quizmeisters.Extractors.VenueDetailsExtractor do
  @moduledoc """
  Extracts additional venue details from individual Quizmeisters venue pages.

  ## Venue Detail Fields
  - description: Venue description text
  - hero_image_url: Main venue image URL
  - website: Venue website URL
  - facebook: Facebook profile URL
  - instagram: Instagram profile URL
  - phone: Phone number (from venue-block)
  - on_break: Whether venue is temporarily not hosting events

  ## Performer Fields
  - name: Host/quizmaster name (from .host-name)
  - image_url: Profile image URL (from .host-image, stored as string)

  Note: Performer image URLs are stored as strings (no download/upload).
  """

  require Logger
  alias EventasaurusDiscovery.Sources.Quizmeisters.Client

  @doc """
  Extracts additional details from a venue detail page.

  ## Parameters
  - `url` - Full URL to the venue page (or nil)

  ## Returns
  - `{:ok, details_map}` - Successfully extracted details
  - `{:error, reason}` - Failed to fetch or parse
  """
  def extract_additional_details(nil), do: {:error, "No URL available"}

  def extract_additional_details(url) when is_binary(url) do
    Logger.debug("🔍 Fetching venue details from: #{url}")

    case Client.fetch_page(url) do
      {:ok, %{body: body}} ->
        case Floki.parse_document(body) do
          {:ok, document} ->
            details = parse_details(document)
            {:ok, details}

          {:error, reason} ->
            Logger.error("❌ Failed to parse venue details HTML: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("❌ Failed to fetch venue details: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Parse all details from document
  defp parse_details(document) do
    %{
      description: extract_description(document),
      hero_image_url: extract_hero_image(document),
      website: extract_website(document),
      facebook: extract_social_link(document, "facebook"),
      instagram: extract_social_link(document, "instagram"),
      phone: extract_phone(document),
      on_break: extract_on_break(document),
      performer: extract_performer(document)
    }
  end

  # Extract venue description
  defp extract_description(document) do
    # Try venue-specific description first
    description =
      document
      |> Floki.find(
        ".venue-description.w-richtext:not(.trivia-generic):not(.bingo-generic):not(.survey-generic) p"
      )
      |> Enum.map(&Floki.text/1)
      |> Enum.join("\n\n")
      |> String.trim()
      |> filter_lorem_ipsum()

    # Fall back to generic trivia description if needed
    if description == "" do
      document
      |> Floki.find(".venue-description.trivia-generic.w-richtext p")
      |> Enum.map(&Floki.text/1)
      |> Enum.join("\n\n")
      |> String.trim()
      |> filter_lorem_ipsum()
    else
      description
    end
  end

  # Extract hero/main image
  defp extract_hero_image(document) do
    document
    |> Floki.find(".venue-photo")
    |> Floki.attribute("src")
    |> List.first()
  end

  # Extract website from icon block
  defp extract_website(document) do
    document
    |> Floki.find(".icon-block a")
    |> Enum.find_value(fn el ->
      href = Floki.attribute(el, "href") |> List.first()

      if Floki.find(el, "img[alt*='website']") |> Enum.any?() do
        href
      end
    end)
  end

  # Extract social media link by platform
  defp extract_social_link(document, platform) do
    document
    |> Floki.find(".icon-block a")
    |> Enum.find_value(fn el ->
      href = Floki.attribute(el, "href") |> List.first()

      if Floki.find(el, "img[alt*='#{platform}']") |> Enum.any?() do
        href
      end
    end)
  end

  # Extract phone from venue-block
  defp extract_phone(document) do
    document
    |> Floki.find(".venue-block .paragraph")
    |> Enum.map(&Floki.text/1)
    |> Enum.find(fn text ->
      String.match?(text, ~r/^\+?[\d\s\-\(\)]{8,}$/)
    end)
    |> case do
      nil -> nil
      number -> String.trim(number)
    end
  end

  # Check if venue is on break
  defp extract_on_break(document) do
    document
    |> Floki.find(".on-break")
    |> Enum.any?()
  end

  # Extract performer/host information
  defp extract_performer(document) do
    host_info = Floki.find(document, ".host-info")

    case host_info do
      [] ->
        Logger.debug("❌ No host_info elements found for performer extraction")
        nil

      elements ->
        Logger.debug("🔍 Found host_info elements: #{Enum.count(elements)}")

        # Extract name
        name_elements = Floki.find(elements, ".host-name")
        Logger.debug("🔍 Found #{Enum.count(name_elements)} name elements")

        name =
          if Enum.empty?(name_elements) do
            Logger.debug("❌ No host-name elements found")
            ""
          else
            raw_name = Floki.text(name_elements) |> String.trim()
            Logger.debug("🔍 Extracted raw performer name: '#{raw_name}'")
            raw_name
          end

        # Find all host images
        all_images = Floki.find(elements, ".host-image")
        Logger.debug("🔍 Found #{Enum.count(all_images)} total host image elements")

        # Filter out placeholder images
        images =
          all_images
          |> Enum.filter(fn img ->
            class = Floki.attribute(img, "class") |> List.first() || ""
            src = Floki.attribute(img, "src") |> List.first() || ""

            valid =
              not String.contains?(class, "placeholder") and
                not String.contains?(class, "w-condition-invisible") and
                src != ""

            if not valid do
              Logger.debug("🔍 Filtering out image with class='#{class}', src='#{src}'")
            end

            valid
          end)

        Logger.debug("🔍 Found #{Enum.count(images)} valid host images after filtering")

        # Get the src attribute of the first real image (store as string)
        image_url =
          case images do
            [] ->
              Logger.debug("❌ No valid host images found")
              nil

            [img | _] ->
              image_src = Floki.attribute(img, "src") |> List.first()
              Logger.debug("✅ Found host image URL: #{image_src}")
              image_src
          end

        # Return performer data if we have EITHER a name OR an image
        cond do
          name != "" and image_url ->
            Logger.info(
              "✅ Found complete performer data: name='#{name}', image_url='#{String.slice(image_url, 0, 50)}...'"
            )

            %{name: name, image_url: image_url}

          name != "" ->
            Logger.info("✅ Found performer with name only: '#{name}'")
            %{name: name, image_url: nil}

          image_url ->
            # Generate a default name from image filename
            image_basename = Path.basename(image_url)

            extracted_name =
              image_basename
              |> String.split(["-", "_"], trim: true)
              |> Enum.filter(fn part ->
                String.length(part) > 2 and
                  not String.match?(part, ~r/^\d+/) and
                  not String.match?(part, ~r/^[0-9a-f]{32}$/i)
              end)
              |> Enum.join(" ")
              |> String.trim()
              |> case do
                "" -> "Quizmeisters Host"
                name -> String.capitalize(name)
              end

            Logger.info(
              "✅ Found performer with image only - extracted name: '#{extracted_name}' from image: #{image_basename}"
            )

            %{name: extracted_name, image_url: image_url}

          true ->
            Logger.debug("❌ No useful performer data found")
            nil
        end
    end
  end

  # Filter out Lorem ipsum placeholder text
  defp filter_lorem_ipsum(text) when is_binary(text) do
    if String.starts_with?(
         text,
         "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore e"
       ),
       do: "",
       else: text
  end

  defp filter_lorem_ipsum(_), do: ""
end
