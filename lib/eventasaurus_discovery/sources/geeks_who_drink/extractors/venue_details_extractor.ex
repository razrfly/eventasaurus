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
    # Construct the API endpoint URL
    params = %{
      "action" => "mb_display_venue_events",
      "pag" => "1",
      "venue" => venue_id,
      "team" => "*"
    }

    Logger.debug("🔍 Fetching performer data for venue: #{venue_id}")

    case Client.post_ajax(params) do
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

  defp extract_description(document) do
    document
    |> Floki.find(".venue__description")
    |> Floki.text()
    |> String.trim()
    |> case do
      "" -> nil
      desc -> desc
    end
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
    # First, try to extract the visible time directly from the time-moment span
    visible_time =
      document
      |> Floki.find(".venueHero__time .time-moment")
      |> Floki.text()
      |> String.trim()

    if visible_time && visible_time != "" do
      # Try to convert 12-hour time (7:00 pm) to 24-hour time (19:00)
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

          # Format as HH:MM
          :io_lib.format("~2..0B:~2..0B", [hour, minute]) |> to_string()

        _ ->
          # Default fallback if parsing fails
          "20:00"
      end
    else
      # Fallback to data-time attribute or default
      "20:00"
    end
  end
end
