defmodule EventasaurusDiscovery.Sources.SpeedQuizzing.Extractors.VenueExtractor do
  @moduledoc """
  Extracts venue and event data from Speed Quizzing detail pages.

  Handles HTML parsing using Floki to extract:
  - Venue name and address (from p.mb-0 elements)
  - GPS coordinates (from embedded script with createMarker)
  - Event title, date, time (from meta tags and clock icons)
  - Description and fee information
  - Performer/host data (from host section or metadata)

  Based on trivia_advisor implementation but adapted for Eventasaurus.
  """

  require Logger

  alias EventasaurusDiscovery.Sources.SpeedQuizzing.Helpers.PerformerCleaner

  @base_url "https://www.speedquizzing.com"

  @doc """
  Extract venue and event data from HTML document.

  Takes the parsed Floki document and event_id.
  Returns a map with all extracted venue and event data.

  ## Examples
      iex> extract(document, "12345")
      %{
        event_id: "12345",
        venue_name: "The Red Lion",
        address: "123 High Street, London, SW1A 1AA",
        lat: "51.5074",
        lng: "-0.1278",
        ...
      }
  """
  def extract(document, event_id) do
    Logger.info("[SpeedQuizzing] Extracting venue data for event ID: #{event_id}")

    # Extract all data fields
    title = extract_title(document)
    venue_name = extract_venue_name(document)
    address = extract_address(document)
    postcode = extract_postcode(address)
    latitude = extract_latitude(document)
    longitude = extract_longitude(document)
    description = extract_description(document)
    fee = extract_fee(description)
    {time, day, date} = extract_date_time(document)

    # Extract performer info if available
    performer = extract_performer(document)

    # Return the extracted data as a map
    %{
      event_id: event_id,
      event_title: title,
      venue_name: venue_name,
      address: address,
      postcode: postcode,
      lat: latitude,
      lng: longitude,
      start_time: time,
      day_of_week: day,
      date: date,
      description: description,
      fee: fee,
      event_url: "#{@base_url}/events/#{event_id}/",
      performer: performer
    }
  end

  # Extract title from og:title meta tag or h1
  defp extract_title(document) do
    case Floki.find(document, "meta[property='og:title']") |> Floki.attribute("content") do
      [content | _] ->
        # Extract title from pattern: "SpeedQuizzing Smartphone Pub Quiz • Title • ..."
        case Regex.run(~r/SpeedQuizzing Smartphone Pub Quiz • (.*?) •/, content) do
          [_, title] -> title
          _ -> extract_title_from_h1(document)
        end

      _ ->
        extract_title_from_h1(document)
    end
  end

  defp extract_title_from_h1(document) do
    case Floki.find(document, "h1") |> Floki.text() do
      "" -> "Unknown"
      title -> title
    end
  end

  # Extract venue name from p.mb-0 b tag or meta description
  defp extract_venue_name(document) do
    case Floki.find(document, "p.mb-0 b") do
      [] ->
        extract_venue_name_from_meta(document)

      [venue_element | _] ->
        venue_name = Floki.text(venue_element)
        if venue_name == "", do: extract_venue_name_from_meta(document), else: venue_name
    end
  end

  defp extract_venue_name_from_meta(document) do
    case Floki.find(document, "meta[name='description']") |> Floki.attribute("content") do
      [content | _] ->
        case Regex.run(~r/Join the fun at (.*?),/, content) do
          [_, venue_name] -> venue_name
          _ -> "Unknown"
        end

      _ ->
        "Unknown"
    end
  end

  # Extract full address from p.mb-0 element with map marker icon
  defp extract_address(document) do
    case Floki.find(document, "p.mb-0") do
      elements when is_list(elements) and length(elements) > 0 ->
        Enum.find_value(elements, "Unknown", fn element ->
          html = Floki.raw_html(element)

          if String.contains?(html, "fa-map-marker") do
            address_text = Floki.text(element)

            # Remove venue name from beginning
            case Regex.run(~r/^(.*?), (.*)$/, address_text) do
              [_, _venue_name, address] -> String.trim(address)
              _ -> address_text
            end
          else
            nil
          end
        end)

      _ ->
        "Unknown"
    end
  end

  # Extract postcode from address (UK/US formats)
  defp extract_postcode(address) do
    # UK: AA9A 9AA, A9A 9AA, A9 9AA, A99 9AA, AA9 9AA, AA99 9AA
    # US: 12345 or 12345-6789
    case Regex.run(
           ~r/\b([A-Z]{1,2}[0-9][A-Z0-9]? ?[0-9][A-Z]{2}|[0-9]{5}(?:-[0-9]{4})?)\b/,
           address
         ) do
      [postcode | _] -> postcode
      _ -> ""
    end
  end

  # Extract latitude from embedded script with createMarker
  defp extract_latitude(document) do
    script_content = extract_script_content(document)

    case Regex.run(~r/lat:\s*(-?\d+\.\d+)/, script_content) do
      [_, lat] -> lat
      _ -> ""
    end
  end

  # Extract longitude from embedded script with createMarker
  defp extract_longitude(document) do
    script_content = extract_script_content(document)

    case Regex.run(~r/lng:\s*(-?\d+\.\d+)/, script_content) do
      [_, lng] -> lng
      _ -> ""
    end
  end

  # Find script tag containing createMarker with GPS coordinates
  defp extract_script_content(document) do
    document
    |> Floki.find("script")
    |> Enum.map(&Floki.raw_html/1)
    |> Enum.find("", &String.contains?(&1, "createMarker"))
  end

  # Extract description from p.sm1 element
  defp extract_description(document) do
    case Floki.find(document, "p.sm1") do
      [element | _] -> Floki.text(element)
      _ -> ""
    end
  end

  # Extract fee from description text - preserves currency symbol
  # Transformer will handle defaults, we just extract what's present
  defp extract_fee(description) when is_binary(description) do
    # Prefer explicit symbol + amount; fall back to worded amounts
    with [_, sym, amt] <- Regex.run(~r/(£|\$|€)\s*([1-9]\d*(?:\.\d{2})?)/, description) do
      "#{sym}#{amt}"
    else
      _ ->
        case Regex.run(~r/\b([1-9]\d*(?:\.\d{2})?)\s+(pounds|dollars|euros)\b/i, description) do
          [_, amt, unit] ->
            sym =
              case String.downcase(unit) do
                "pounds" -> "£"
                "dollars" -> "$"
                "euros" -> "€"
              end

            "#{sym}#{amt}"

          _ ->
            # Let Transformer handle default pricing
            nil
        end
    end
  end

  defp extract_fee(_), do: nil

  # Extract date and time from p.mb-0 element with clock icon
  defp extract_date_time(document) do
    # Find elements with clock icon
    clock_elements =
      Floki.find(document, "p.mb-0")
      |> Enum.filter(fn el ->
        html = Floki.raw_html(el)
        String.contains?(html, "fa-clock")
      end)

    date_time_text =
      case clock_elements do
        [first | _] ->
          Floki.text(first)

        [] ->
          extract_from_og_title(document)
      end

    parse_date_time_text(date_time_text)
  end

  # Parse date/time text (Phase 3 will use shared DateParser for proper conversion)
  # For now, return raw values
  defp parse_date_time_text(text) when is_binary(text) and text != "" do
    # Extract basic patterns - Phase 3 will use shared DateParser for proper parsing
    bullet = <<226, 128, 162>>

    # Extract time (12-hour format like "8pm", "7.30PM")
    time =
      case Regex.run(~r/(\d+(?:\.\d+)?(?:\s*[ap]m|\s*PM|\s*AM))/i, text) do
        [_, t] -> t
        _ -> "00:00"
      end

    # Extract day
    day =
      case Regex.run(~r/#{bullet}\s*([A-Za-z]+)/, text) do
        [_, d] -> d
        _ -> "Unknown"
      end

    # Extract date
    date =
      case Regex.run(~r/#{day}\s*(\d+\s*[A-Za-z]+(?:\s*\d{4})?)/, text) do
        [_, dt] -> dt
        _ -> "Unknown"
      end

    {time, day, date}
  end

  defp parse_date_time_text(_), do: {"00:00", "Unknown", "Unknown"}

  # Extract from og:title metadata
  defp extract_from_og_title(document) do
    case Floki.find(document, "meta[property='og:title']") |> Floki.attribute("content") do
      [content | _] ->
        # Pattern: "Next on Saturday 1 Mar"
        case Regex.run(~r/Next on ([A-Za-z]+) (\d+ [A-Za-z]+)/, content) do
          [_, day, date] -> "#{day} #{date}"
          _ -> ""
        end

      _ ->
        ""
    end
  end

  # Extract performer/host information
  defp extract_performer(document) do
    # Look for host section with multiple possible selectors
    host_section =
      document
      |> Floki.find("#menu4, .host-section, .host-info")
      |> List.first()

    case host_section do
      nil ->
        # Fallback: extract from title or meta tags
        extract_performer_from_meta(document)

      _ ->
        extract_performer_from_section(host_section)
    end
  end

  defp extract_performer_from_section(host_section) do
    # Extract host name
    name =
      host_section
      |> Floki.find("h3, .host-name, .quiz-master-name")
      |> Floki.text()
      |> String.replace(~r/This event is hosted by |Hosted by |Quiz Master: /, "")
      |> String.trim()
      |> PerformerCleaner.clean_name()

    if name != "" and name != nil do
      # Extract profile image
      profile_image =
        host_section
        |> Floki.find(".host-img, .quiz-master-img, img[alt*='host'], img[alt*='quiz master']")
        |> Floki.attribute("src")
        |> List.first()
        |> case do
          nil ->
            nil

          url ->
            if String.starts_with?(url, "http"), do: url, else: "#{@base_url}#{url}"
        end

      # Extract description
      description =
        host_section
        |> Floki.find(".sm1, .host-description, .quiz-master-description")
        |> Floki.text()
        |> String.trim()

      %{
        name: name,
        profile_image: profile_image,
        description: description
      }
    else
      nil
    end
  end

  defp extract_performer_from_meta(document) do
    # Check title tag
    title_host =
      document
      |> Floki.find("title")
      |> Floki.text()
      |> extract_host_from_text()

    # Check meta tags
    meta_host =
      document
      |> Floki.find("meta[property='og:title']")
      |> Floki.attribute("content")
      |> List.first()
      |> extract_host_from_text()

    host_name = title_host || meta_host

    if is_binary(host_name) and String.trim(host_name) != "" do
      %{
        name: host_name,
        profile_image: nil,
        description: ""
      }
    else
      nil
    end
  end

  defp extract_host_from_text(nil), do: nil

  defp extract_host_from_text(text) do
    case Regex.run(~r/Hosted by ([^•\n\r]+)/, text) do
      [_, host_name] ->
        cleaned = host_name |> String.trim() |> PerformerCleaner.clean_name()
        if cleaned != "" and cleaned != nil, do: cleaned, else: nil

      _ ->
        nil
    end
  end
end
