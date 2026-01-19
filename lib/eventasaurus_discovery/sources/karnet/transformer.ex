defmodule EventasaurusDiscovery.Sources.Karnet.Transformer do
  @moduledoc """
  Transforms Karnet event data into the unified format expected by the Processor.

  IMPORTANT: All events MUST have a venue with complete location data.
  Events without proper venue information will be rejected.
  """

  require Logger
  alias EventasaurusDiscovery.Sources.Shared.Parsers.MultilingualDateParser
  alias EventasaurusDiscovery.Sources.Shared.JsonSanitizer

  @doc """
  Transform a raw Karnet event into our unified format.

  Required fields for the unified format:
  - title
  - external_id
  - starts_at (DateTime)
  - venue (with name, latitude, longitude, address)

  Optional fields:
  - description
  - ends_at
  - ticket_url
  - performers
  - category
  - is_free

  Returns {:ok, transformed_event} or {:error, reason}
  """
  def transform_event(raw_event) do
    # Extract and validate venue first since it's critical
    venue_data = extract_venue(raw_event)

    # Validate venue has required fields
    case validate_venue(venue_data) do
      :ok ->
        transformed = %{
          # Required fields
          title: extract_title(raw_event),
          external_id: extract_external_id(raw_event),
          starts_at: extract_starts_at(raw_event),
          ends_at: extract_ends_at(raw_event),

          # Venue data - REQUIRED and validated
          venue_data: venue_data,

          # Optional fields
          description: extract_description(raw_event),
          ticket_url: raw_event[:ticket_url] || raw_event[:url],

          # Pricing
          is_free: raw_event[:is_free] || false,
          # Karnet doesn't provide specific pricing
          min_price: nil,
          max_price: nil,
          currency: "PLN",

          # Performer data
          performer: extract_performer(raw_event),

          # Categories and tags
          tags: extract_tags(raw_event),
          category: raw_event[:category],

          # Translations
          title_translations: raw_event[:title_translations],
          description_translations: raw_event[:description_translations],

          # Original URL for reference
          source_url: raw_event[:url],

          # Image
          image_url: raw_event[:image_url],

          # Metadata with raw upstream data for debugging
          metadata: %{
            "_raw_upstream" => JsonSanitizer.sanitize(raw_event)
          }
        }

        {:ok, transformed}

      {:error, reason} ->
        Logger.error("""
        ❌ Karnet event rejected due to invalid venue:
        Event: #{raw_event[:title]}
        URL: #{raw_event[:url]}
        Reason: #{reason}
        Venue data: #{inspect(venue_data)}
        """)

        {:error, reason}
    end
  end

  @doc """
  Validates that venue data contains all required fields.
  Returns :ok if valid, {:error, reason} if not.

  Note: Coordinates are optional - VenueProcessor will geocode if missing.
  """
  def validate_venue(venue_data) do
    cond do
      is_nil(venue_data) ->
        {:error, "Venue data is required"}

      is_nil(venue_data[:name]) || venue_data[:name] == "" ->
        {:error, "Venue name is required"}

      true ->
        :ok
    end
  end

  # Private functions

  defp extract_title(event) do
    event[:title] || "Unknown Event"
  end

  defp extract_external_id(event) do
    # Extract ID from URL pattern or generate from URL
    case event[:url] do
      nil ->
        # Generate a unique ID from available data
        generate_external_id(event)

      url ->
        # Try to extract ID from URL
        case Regex.run(~r/\/(\d+)(?:\/|$)/, url) do
          [_, id] ->
            "karnet_#{id}"

          _ ->
            # Use URL hash as fallback
            "karnet_#{:crypto.hash(:md5, url) |> Base.encode16(case: :lower)}"
        end
    end
  end

  defp generate_external_id(event) do
    # Generate ID from title + venue + date
    components = [
      event[:title] || "",
      get_in(event, [:venue_data, :name]) || "",
      event[:date_text] || ""
    ]

    hash = :crypto.hash(:md5, Enum.join(components, "|")) |> Base.encode16(case: :lower)
    "karnet_generated_#{hash}"
  end

  defp extract_starts_at(event) do
    # Use already parsed dates or parse date_text
    cond do
      event[:starts_at] ->
        event[:starts_at]

      event[:date_text] ->
        case MultilingualDateParser.extract_and_parse(event[:date_text],
               languages: [:polish],
               timezone: "Europe/Warsaw"
             ) do
          {:ok, %{starts_at: start_dt}} ->
            start_dt

          {:error, _reason} ->
            Logger.warning("Could not parse date for Karnet event: #{event[:date_text]}")
            # Fallback to 30 days from now
            DateTime.add(DateTime.utc_now(), 30 * 86400, :second)
        end

      true ->
        Logger.warning("No date information for Karnet event")
        DateTime.add(DateTime.utc_now(), 30 * 86400, :second)
    end
  end

  defp extract_ends_at(event) do
    cond do
      event[:ends_at] ->
        event[:ends_at]

      event[:date_text] ->
        case MultilingualDateParser.extract_and_parse(event[:date_text],
               languages: [:polish],
               timezone: "Europe/Warsaw"
             ) do
          {:ok, %{ends_at: end_dt}} when not is_nil(end_dt) -> end_dt
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp extract_venue(event) do
    # Karnet doesn't provide GPS coordinates - VenueProcessor will geocode via Orchestrator
    # We provide venue name, address, city, country and let the modular geocoding system handle coordinates

    venue_data = event[:venue_data] || event[:venue]

    cond do
      venue_data && venue_data[:name] ->
        # Check if coordinates were explicitly provided (rare for Karnet)
        has_coordinates = venue_data[:latitude] && venue_data[:longitude]

        %{
          name: venue_data[:name],
          # Set nil coordinates so VenueProcessor geocodes via Orchestrator
          # Only use provided coordinates if they exist (rare)
          latitude: if(has_coordinates, do: venue_data[:latitude], else: nil),
          longitude: if(has_coordinates, do: venue_data[:longitude], else: nil),
          address: build_address(venue_data),
          city: venue_data[:city] || "Kraków",
          state: venue_data[:state],
          country: venue_data[:country] || "Poland",
          postal_code: venue_data[:postal_code]
        }

      # Try to extract venue name from event data
      event[:venue_name] ->
        Logger.info("🔄 Building venue from venue_name field - VenueProcessor will geocode")

        %{
          name: event[:venue_name],
          latitude: nil,
          longitude: nil,
          address: nil,
          city: "Kraków",
          state: nil,
          country: "Poland",
          postal_code: nil
        }

      # Last resort - create placeholder venue
      true ->
        Logger.warning("""
        ⚠️ Creating placeholder venue for Karnet event:
        Title: #{inspect(event[:title])}
        URL: #{inspect(event[:url])}
        VenueProcessor will attempt geocoding.
        """)

        %{
          name: "Venue TBD - Kraków",
          latitude: nil,
          longitude: nil,
          address: nil,
          city: "Kraków",
          state: nil,
          country: "Poland",
          postal_code: nil,
          metadata: %{placeholder: true}
        }
    end
  end

  defp build_address(venue_data) do
    parts =
      [
        venue_data[:address],
        venue_data[:city] || "Kraków",
        venue_data[:country] || "Poland"
      ]
      |> Enum.filter(&(&1 && &1 != ""))

    if Enum.any?(parts), do: Enum.join(parts, ", "), else: nil
  end

  defp extract_description(event) do
    # Combine Polish and English descriptions if available
    descriptions = []

    descriptions =
      if event[:description_translations] do
        desc = descriptions

        desc =
          if event[:description_translations]["pl"] do
            ["PL: " <> event[:description_translations]["pl"] | desc]
          else
            desc
          end

        if event[:description_translations]["en"] do
          ["EN: " <> event[:description_translations]["en"] | desc]
        else
          desc
        end
      else
        descriptions
      end

    if Enum.any?(descriptions) do
      Enum.join(descriptions, "\n\n")
    else
      nil
    end
  end

  defp extract_performer(event) do
    case event[:performers] do
      performers when is_list(performers) and length(performers) > 0 ->
        # Take first performer as main
        first = List.first(performers)

        %{
          name: extract_performer_name(first),
          # Karnet doesn't provide genre info
          genres: [],
          image_url: nil
        }

      _ ->
        nil
    end
  end

  defp extract_performer_name(performer) when is_map(performer) do
    performer[:name] || performer["name"]
  end

  defp extract_performer_name(name) when is_binary(name), do: name
  defp extract_performer_name(_), do: nil

  defp extract_tags(event) do
    tags = []

    # Add category as tag
    tags = if event[:category], do: [event[:category] | tags], else: tags

    # Add event type tags
    tags = if event[:is_free], do: ["free" | tags], else: tags
    tags = if event[:is_festival], do: ["festival" | tags], else: tags

    # Add language tag
    tags = ["polish" | tags]

    Enum.uniq(tags)
  end
end
