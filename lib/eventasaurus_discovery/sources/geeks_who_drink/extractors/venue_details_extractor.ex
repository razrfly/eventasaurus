defmodule EventasaurusDiscovery.Sources.GeeksWhoDrink.Extractors.VenueDetailsExtractor do
  @moduledoc """
  Extracts additional venue details from individual venue pages
  and performer data from the AJAX API.

  ## Venue Detail Fields
  - website: Venue website URL
  - phone: Phone number
  - description: Venue description
  - fee_text: Entry fee information
  - facebook: Facebook URL
  - instagram: Instagram URL
  - start_time: Event start time (24-hour format)

  ## Performer Fields
  - name: Quizmaster name (cleaned from "Quizmaster: [Name]" format)
  - profile_image: Profile image URL
  """

  require Logger
  alias EventasaurusDiscovery.Sources.GeeksWhoDrink.Client

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
            # Extract venue ID for performer API call
            venue_id = extract_venue_id(url, document)

            # Parse basic details from main document
            details = parse_details(document)

            # Add performer details if possible
            details =
              case extract_performer(venue_id) do
                {:ok, performer} ->
                  Logger.debug("✅ Found performer: #{inspect(performer.name)}")
                  Map.put(details, :performer, performer)

                {:error, reason} ->
                  Logger.debug("ℹ️  No performer found: #{reason}")
                  details
              end

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

  # Extract venue ID from URL or document
  defp extract_venue_id(url, document) do
    # Try to extract from URL first
    case Regex.run(~r/\/venues\/(\d+)/, url) do
      [_, venue_id] ->
        Logger.debug("📌 Extracted venue ID from URL: #{venue_id}")
        venue_id

      nil ->
        # Try to find it in the document
        document
        |> Floki.find("body")
        |> Floki.attribute("data-venue-id")
        |> List.first()
    end
  end

  # Parse details from main document
  defp parse_details(document) do
    %{
      website: extract_website(document),
      phone: extract_phone(document),
      description: extract_description(document),
      fee_text: extract_fee(document),
      facebook: extract_social_link(document, "facebook"),
      instagram: extract_social_link(document, "instagram"),
      start_time: extract_start_time(document)
    }
  end

  # Extract performer from AJAX endpoint
  defp extract_performer(nil), do: {:error, "No venue ID available"}

  defp extract_performer(venue_id) do
    # Construct the API endpoint URL with query parameters
    params = %{
      "action" => "mb_display_venue_events",
      "pag" => "1",
      "venue" => venue_id,
      "team" => "*"
    }

    Logger.debug("🔍 Fetching performer data for venue: #{venue_id}")

    case Client.get_ajax(params) do
      {:ok, body} ->
        process_performer_response(body)

      {:error, reason} ->
        Logger.error("❌ Failed to fetch performer data: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_performer_response(body) do
    case Floki.parse_document(body) do
      {:ok, document} ->
        # Look for quizmaster info in the quizzes__meta div
        meta_div = Floki.find(document, ".quizzes__meta")

        if Enum.empty?(meta_div) do
          Logger.debug("ℹ️  No .quizzes__meta div found in performer response")
          {:error, "No quizmaster information found"}
        else
          # Extract name
          name =
            document
            |> Floki.find(".quiz__master p")
            |> Floki.text()
            |> String.trim()
            |> extract_name_from_text()
            |> truncate_name(200)

          # Extract profile image
          profile_image =
            document
            |> Floki.find(".quiz__avatar img")
            |> Floki.attribute("src")
            |> List.first()

          # If we have an image but no name, provide a default name
          cond do
            is_nil(name) and is_nil(profile_image) ->
              {:error, "No performer name or image found"}

            is_nil(name) and not is_nil(profile_image) ->
              {:ok, %{name: "Geeks Who Drink Quizmaster", profile_image: profile_image}}

            true ->
              {:ok, %{name: name, profile_image: profile_image}}
          end
        end

      {:error, reason} ->
        Logger.error("❌ Failed to parse performer HTML: #{inspect(reason)}")
        {:error, "Failed to parse performer HTML"}
    end
  end

  defp extract_name_from_text(text) do
    case text do
      nil ->
        nil

      "" ->
        nil

      text ->
        # Clean up the text by removing repeated "Quizmaster:" prefixes
        clean_text =
          text
          |> String.replace(~r/Quizmaster:\s*/i, "Quizmaster: ", global: true)
          |> String.replace(~r/(Quizmaster:\s+){2,}/i, "Quizmaster: ", global: true)

        # Extract the name, typically in "With Quizmaster: John Doe" format
        name =
          if String.contains?(clean_text, "Quizmaster") do
            clean_text
            |> String.replace(~r/.*Quizmaster:\s*/i, "")
            |> String.trim()
          else
            # If not in the expected format, just return the text
            clean_text |> String.trim()
          end

        # Ensure we don't return an empty string
        case name do
          "" -> "Unknown Quizmaster"
          name -> name
        end
    end
  end

  # Helper to truncate name to a maximum length
  defp truncate_name(nil, _), do: nil

  defp truncate_name(name, max_length) when is_binary(name) do
    if String.length(name) > max_length do
      Logger.warning(
        "⚠️  Truncating performer name from #{String.length(name)} to #{max_length} characters"
      )

      String.slice(name, 0, max_length)
    else
      name
    end
  end

  # Extract individual fields from venue page

  defp extract_website(document) do
    document
    |> Floki.find(".venueHero__address a[href]:not([href*='maps.google.com'])")
    |> Floki.attribute("href")
    |> List.first()
  end

  defp extract_phone(document) do
    document
    |> Floki.find(".venueHero__phone")
    |> Floki.text()
    |> String.trim()
    |> case do
      "" -> nil
      phone -> phone
    end
  end

  # Description extraction removed - .venue__description class no longer exists on GWD pages
  # Phase 2 Fix: HTML structure changed, this field is not available
  defp extract_description(_document) do
    nil
  end

  defp extract_fee(document) do
    document
    |> Floki.find(".venue__fee")
    |> Floki.text()
    |> String.trim()
    |> case do
      "" -> nil
      fee -> fee
    end
  end

  defp extract_social_link(document, platform) do
    document
    |> Floki.find(".venue__social a[href*='#{platform}']")
    |> Floki.attribute("href")
    |> List.first()
  end

  defp extract_start_time(document) do
    # Strategy 1: Try visible text extraction first (most reliable when available)
    case extract_start_time_from_text(document) do
      nil ->
        # Strategy 2: Fall back to data-time attribute from .time-moment
        # Note: .time-moment contains the regular recurring schedule time in UTC
        # (NOT .time-moment-date which is the next specific occurrence)
        data_time =
          document
          |> Floki.find(".venueHero__time .time-moment")
          |> Floki.attribute("data-time")
          |> List.first()

        case data_time do
          nil ->
            Logger.warning("⚠️ No time found in HTML structure")
            nil

          time_str when is_binary(time_str) ->
            # Parse ISO datetime from data-time attribute (in UTC)
            case DateTime.from_iso8601(time_str) do
              {:ok, dt, _offset} ->
                # Convert UTC time to local time
                # The data-time contains UTC time, we need to convert to local venue time
                # Since we don't have venue coordinates here, we'll do a best-effort conversion
                # based on common US timezones where Geeks Who Drink operates
                convert_utc_to_local_time(dt)

              _ ->
                Logger.warning("⚠️ Failed to parse data-time: #{time_str}")
                nil
            end
        end

      time ->
        time
    end
  end

  # Convert UTC datetime to likely local time for US venues
  # This is a best-effort conversion since we don't have venue coordinates at extraction time
  # The job will later use proper timezone detection via TzWorld
  defp convert_utc_to_local_time(utc_datetime) do
    utc_hour = utc_datetime.hour
    utc_minute = utc_datetime.minute

    # Geeks Who Drink venues are across US timezones (UTC-5 to UTC-8)
    # Most trivia happens 6-9 PM local time
    # Common UTC times: 00:00-04:00 UTC = 6-9 PM in various US zones

    # Heuristic: If UTC hour is 00:00-05:00, likely evening (6-10 PM) in US
    # Convert assuming UTC-6 (Central) to UTC-7 (Mountain) as most common
    local_hour = cond do
      # 00:00-05:00 UTC = likely evening trivia
      utc_hour >= 0 && utc_hour <= 5 ->
        # Try UTC-7 (Mountain Time) as Geeks Who Drink HQ is in Denver
        rem(utc_hour + 24 - 7, 24)

      # Other times - use UTC-6 (Central) as it's most common US timezone
      true ->
        rem(utc_hour + 24 - 6, 24)
    end

    formatted_time = :io_lib.format("~2..0B:~2..0B", [local_hour, utc_minute]) |> to_string()

    Logger.debug(
      "📅 Converted UTC #{utc_hour}:#{String.pad_leading(to_string(utc_minute), 2, "0")} to local #{formatted_time}"
    )

    formatted_time
  end

  # Extract time from visible text (legacy format: "7:00 pm")
  defp extract_start_time_from_text(document) do
    visible_time =
      document
      |> Floki.find(".venueHero__time .time-moment")
      |> Floki.text()
      |> String.trim()

    if visible_time && visible_time != "" do
      case Regex.run(~r/(\d+):(\d+)\s*(am|pm)/i, visible_time) do
        [_, hour_str, minute_str, period] ->
          hour = String.to_integer(hour_str)
          minute = String.to_integer(minute_str)

          hour =
            case String.downcase(period) do
              "pm" when hour < 12 -> hour + 12
              "am" when hour == 12 -> 0
              _ -> hour
            end

          :io_lib.format("~2..0B:~2..0B", [hour, minute]) |> to_string()

        _ ->
          Logger.warning("⚠️ Failed to parse time from text: #{visible_time}")
          nil
      end
    else
      Logger.warning("⚠️ No time found in HTML structure")
      nil
    end
  end
end
