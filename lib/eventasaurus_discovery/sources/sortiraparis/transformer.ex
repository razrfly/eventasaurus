defmodule EventasaurusDiscovery.Sources.Sortiraparis.Transformer do
  @moduledoc """
  Transforms Sortiraparis event data into unified format for processing.

  ## Transformation Flow

  Raw HTML → Extractors → Transformer → Unified Event Format → VenueProcessor

  ## Key Features

  - **Multi-date support**: Creates separate event instances for multi-date events
  - **Date parsing**: Handles 5+ date format variations (see DateParser)
  - **Venue geocoding**: Provides full addresses for multi-provider geocoding system
  - **Category mapping**: Provides raw event data to CategoryExtractor for YAML-based category mapping

  ## Date Formats Handled

  1. Multi-date list: "February 25, 27, 28, 2026"
  2. Date range: "October 15, 2025 to January 19, 2026"
  3. Single date with day: "Friday, October 31, 2025"
  4. Date with time: "Saturday October 11 at 12 noon"
  5. Ticket sale dates: "on Saturday October 11 at 12 noon"

  See: `helpers/date_parser.ex` (TODO: Phase 4)

  ## Geocoding Strategy

  **IMPORTANT**: Do NOT geocode manually. Provide full venue address and let
  VenueProcessor handle geocoding via multi-provider system.

  See: [Geocoding System Documentation](../../../docs/geocoding/GEOCODING_SYSTEM.md)

  ## External ID Format

  - Base: `sortiraparis_{article_id}`
  - Multi-date: `sortiraparis_{article_id}_{date}` (e.g., "sortiraparis_319282_2026-02-25")

  ## Examples

      iex> transform_event(%{
      ...>   "url" => "/articles/319282-indochine-concert",
      ...>   "title" => "Indochine at Accor Arena",
      ...>   "dates" => ["2026-02-25", "2026-02-27"],
      ...>   "venue" => %{"name" => "Accor Arena", "address" => "8 Boulevard de Bercy, 75012 Paris 12"}
      ...> })
      {:ok, [
        %{external_id: "sortiraparis_319282_2026-02-25", ...},
        %{external_id: "sortiraparis_319282_2026-02-27", ...}
      ]}
  """

  require Logger
  alias EventasaurusDiscovery.Sources.Sortiraparis.Config
  alias EventasaurusDiscovery.Sources.Sortiraparis.Helpers.DateParser

  @doc """
  Transform raw event data into unified format.

  Returns a list of events (multiple for multi-date events).

  ## Parameters

  - `raw_event` - Map with extracted event data
  - `options` - Optional transformation options

  ## Returns

  - `{:ok, [event, ...]}` - List of transformed events
  - `{:error, reason}` - Transformation failed
  """
  def transform_event(raw_event, options \\ %{}) do
    Logger.debug("🔄 Transforming raw event data")

    with {:ok, article_id} <- extract_article_id(raw_event),
         {:ok, title} <- extract_title(raw_event),
         {:ok, dates} <- extract_and_parse_dates(raw_event, options),
         {:ok, venue_data} <- extract_venue(raw_event) do

      event_type = Map.get(raw_event, "event_type", :one_time)

      # Handle different event types
      events = case event_type do
        :exhibition ->
          # For exhibitions, create ONE event with start/end dates
          [create_exhibition_event(article_id, title, dates, venue_data, raw_event, options)]

        :recurring ->
          # For recurring, create ONE event (EventProcessor will handle recurrence)
          # Use first date as anchor date
          [create_recurring_event(article_id, title, List.first(dates), venue_data, raw_event, options)]

        :one_time ->
          # For one-time events, create separate event for each date
          Enum.map(dates, fn date ->
            create_event(article_id, title, date, venue_data, raw_event, options)
          end)
      end

      Logger.info("✅ Transformed into #{length(events)} #{event_type} event instance(s): #{title}")
      {:ok, events}
    else
      {:error, reason} = error ->
        Logger.warning("⚠️ Failed to transform event: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Validate that event has required fields.

  ## Required Fields

  - `title` - Event title
  - `starts_at` - DateTime in UTC
  - `external_id` - Stable identifier
  - `venue_data.name` - Venue name
  - `venue_data.city` - City name

  ## Returns

  - `:ok` - Event valid
  - `{:error, reason}` - Missing required field
  """
  def validate_event(event) do
    required_fields = [:title, :starts_at, :external_id, :venue_data]

    missing =
      Enum.filter(required_fields, fn field ->
        !Map.has_key?(event, field) || is_nil(Map.get(event, field))
      end)

    if Enum.empty?(missing) do
      # Validate types
      if match?(%DateTime{}, event.starts_at) do
        validate_venue_data(event.venue_data)
      else
        {:error, :invalid_starts_at_type}
      end
    else
      {:error, {:missing_fields, missing}}
    end
  end

  @doc """
  Validate venue data has required fields.

  ## Required Fields

  - `name` - Venue name
  - `city` - City name (can infer country from city)

  ## Optional but Recommended

  - `address` - Full address for geocoding
  - `latitude`, `longitude` - GPS coordinates (bypasses geocoding)
  - `external_id` - Stable venue identifier
  """
  def validate_venue_data(venue_data) when is_map(venue_data) do
    required = [:name, :city]

    missing =
      Enum.filter(required, fn field ->
        !Map.has_key?(venue_data, field) || is_nil(Map.get(venue_data, field))
      end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_venue_fields, missing}}
    end
  end

  def validate_venue_data(_), do: {:error, :invalid_venue_data}

  # Private transformation functions

  defp extract_article_id(%{"url" => url}) when is_binary(url) do
    case Config.extract_article_id(url) do
      nil -> {:error, :missing_article_id}
      id -> {:ok, id}
    end
  end

  defp extract_article_id(_), do: {:error, :missing_url}

  defp extract_title(%{"title" => title}) when is_binary(title) and title != "" do
    {:ok, String.trim(title)}
  end

  defp extract_title(_), do: {:error, :missing_title}

  defp extract_and_parse_dates(%{"dates" => dates}, options)
       when is_list(dates) and length(dates) > 0 do
    # Coerce entries to UTC DateTime; accept %DateTime{} or ISO8601 strings
    coerced =
      dates
      |> Enum.flat_map(fn
        %DateTime{} = dt -> [dt]
        bin when is_binary(bin) ->
          case DateParser.parse_dates(bin, options) do
            {:ok, [dt | _]} -> [dt]
            _ -> []
          end
        _ -> []
      end)

    if coerced == [], do: {:error, :no_dates_extracted}, else: {:ok, coerced}
  end

  defp extract_and_parse_dates(%{"date_string" => date_string}, options)
       when is_binary(date_string) do
    # Parse date string using DateParser
    case DateParser.parse_dates(date_string, options) do
      {:ok, [_ | _] = dates} -> {:ok, dates}
      {:ok, []} -> {:error, :no_dates_extracted}
      {:error, _} = error -> error
    end
  end

  defp extract_and_parse_dates(%{"date" => date}, options) when is_binary(date) do
    # Fallback to generic "date" field
    extract_and_parse_dates(%{"date_string" => date}, options)
  end

  defp extract_and_parse_dates(_, _), do: {:error, :missing_dates}

  defp extract_venue(%{"venue" => venue}) when is_map(venue) do
    # Ensure venue has at least name and city
    case {Map.get(venue, "name"), Map.get(venue, "city")} do
      {nil, _} -> {:error, :missing_venue_name}
      {_, nil} -> {:error, :missing_venue_city}
      {name, city} when is_binary(name) and is_binary(city) -> {:ok, venue}
      _ -> {:error, :invalid_venue_data}
    end
  end

  defp extract_venue(_), do: {:error, :missing_venue}

  defp create_event(article_id, title, date, venue_data, raw_event, _options) do
    # Generate external_id with date suffix for multi-date events
    external_id = "#{Config.generate_external_id(article_id)}_#{format_date_for_id(date)}"

    %{
      # Required fields
      external_id: external_id,
      article_id: article_id,  # Article ID for consolidation (similar to movie_id)
      title: title,
      starts_at: date,  # Assumes date is already DateTime in UTC
      event_type: :one_time,

      # Venue data (REQUIRED - VenueProcessor handles geocoding)
      venue_data: %{
        name: venue_data["name"],
        address: Map.get(venue_data, "address"),
        city: venue_data["city"],
        country: Map.get(venue_data, "country", "France"),
        # GPS coordinates (nil if not available - VenueProcessor will geocode)
        latitude: Map.get(venue_data, "latitude"),
        longitude: Map.get(venue_data, "longitude"),
        external_id: Map.get(venue_data, "external_id"),
        metadata: Map.get(venue_data, "metadata", %{})
      },

      # Optional but recommended
      ends_at: Map.get(raw_event, "ends_at"),
      description_translations:
        case Map.get(raw_event, "description") do
          nil -> nil
          "" -> nil
          desc -> %{"en" => desc}
        end,
      source_url: Config.build_url(raw_event["url"]),
      image_url: Map.get(raw_event, "image_url"),

      # Pricing
      is_ticketed: Map.get(raw_event, "is_ticketed", false),
      is_free: Map.get(raw_event, "is_free", false),
      min_price: Map.get(raw_event, "min_price"),
      max_price: Map.get(raw_event, "max_price"),
      currency: Map.get(raw_event, "currency", "EUR"),

      # Performers (if available)
      performers: Map.get(raw_event, "performers", []),

      # Metadata
      metadata: %{
        article_id: article_id,
        original_date_string: Map.get(raw_event, "original_date_string"),
        category_url: Map.get(raw_event, "category"),
        language: "en"
      },

      # Raw event data for CategoryExtractor (includes URL for category extraction)
      raw_event_data: raw_event
    }
  end

  defp create_exhibition_event(article_id, title, dates, venue_data, raw_event, _options) do
    # For exhibitions, use start date for starts_at, end date for ends_at
    # Sort dates to ensure correct chronological order (defensive programming)
    sorted_dates = Enum.sort(dates, DateTime)
    [start_date | rest] = sorted_dates
    end_date = List.last(rest) || start_date

    # Generate external_id WITHOUT date suffix (exhibitions don't have multiple instances)
    external_id = Config.generate_external_id(article_id)

    %{
      # Required fields
      external_id: external_id,
      article_id: article_id,
      title: title,
      starts_at: start_date,
      ends_at: end_date,  # Exhibition closing date
      event_type: :exhibition,

      # Venue data
      venue_data: %{
        name: venue_data["name"],
        address: Map.get(venue_data, "address"),
        city: venue_data["city"],
        country: Map.get(venue_data, "country", "France"),
        latitude: Map.get(venue_data, "latitude"),
        longitude: Map.get(venue_data, "longitude"),
        external_id: Map.get(venue_data, "external_id"),
        metadata: Map.get(venue_data, "metadata", %{})
      },

      description_translations:
        case Map.get(raw_event, "description") do
          nil -> nil
          "" -> nil
          desc -> %{"en" => desc}
        end,
      source_url: Config.build_url(raw_event["url"]),
      image_url: Map.get(raw_event, "image_url"),

      # Pricing
      is_ticketed: Map.get(raw_event, "is_ticketed", false),
      is_free: Map.get(raw_event, "is_free", false),
      min_price: Map.get(raw_event, "min_price"),
      max_price: Map.get(raw_event, "max_price"),
      currency: Map.get(raw_event, "currency", "EUR"),

      performers: Map.get(raw_event, "performers", []),

      # Metadata
      metadata: %{
        article_id: article_id,
        original_date_string: Map.get(raw_event, "original_date_string"),
        category_url: Map.get(raw_event, "category"),
        language: "en",
        exhibition_range: %{
          start_date: format_date_for_id(start_date),
          end_date: format_date_for_id(end_date)
        }
      },

      raw_event_data: raw_event
    }
  end

  defp create_recurring_event(article_id, title, anchor_date, venue_data, raw_event, _options) do
    # For recurring events, use anchor date and store recurrence pattern in metadata
    external_id = Config.generate_external_id(article_id)

    # Extract recurrence pattern from title/description
    recurrence_pattern = extract_recurrence_pattern(raw_event)

    %{
      # Required fields
      external_id: external_id,
      article_id: article_id,
      title: title,
      starts_at: anchor_date,
      event_type: :recurring,

      # Venue data
      venue_data: %{
        name: venue_data["name"],
        address: Map.get(venue_data, "address"),
        city: venue_data["city"],
        country: Map.get(venue_data, "country", "France"),
        latitude: Map.get(venue_data, "latitude"),
        longitude: Map.get(venue_data, "longitude"),
        external_id: Map.get(venue_data, "external_id"),
        metadata: Map.get(venue_data, "metadata", %{})
      },

      description_translations:
        case Map.get(raw_event, "description") do
          nil -> nil
          "" -> nil
          desc -> %{"en" => desc}
        end,
      source_url: Config.build_url(raw_event["url"]),
      image_url: Map.get(raw_event, "image_url"),

      # Pricing
      is_ticketed: Map.get(raw_event, "is_ticketed", false),
      is_free: Map.get(raw_event, "is_free", false),
      min_price: Map.get(raw_event, "min_price"),
      max_price: Map.get(raw_event, "max_price"),
      currency: Map.get(raw_event, "currency", "EUR"),

      performers: Map.get(raw_event, "performers", []),

      # Metadata - include recurrence pattern
      metadata: %{
        article_id: article_id,
        original_date_string: Map.get(raw_event, "original_date_string"),
        category_url: Map.get(raw_event, "category"),
        language: "en",
        recurrence_pattern: recurrence_pattern
      },

      raw_event_data: raw_event
    }
  end

  defp extract_recurrence_pattern(raw_event) do
    text = "#{Map.get(raw_event, "title", "")} #{Map.get(raw_event, "description", "")}"
    text_lower = String.downcase(text)

    cond do
      text_lower =~ ~r/every (monday|tuesday|wednesday|thursday|friday|saturday|sunday)/i ->
        %{type: "weekly", description: text}

      text_lower =~ ~r/every \w+ (evening|night)/i ->
        %{type: "weekly", description: text}

      text_lower =~ ~r/\d+ times? (per|a) (week|month)/i ->
        %{type: "custom", description: text}

      true ->
        %{type: "unknown", description: text}
    end
  end

  defp format_date_for_id(%DateTime{} = date) do
    Calendar.strftime(date, "%Y-%m-%d")
  end

  defp format_date_for_id(date_string) when is_binary(date_string) do
    # Assume YYYY-MM-DD format
    date_string
  end
end
