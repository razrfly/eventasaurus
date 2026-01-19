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
  - **Synthetic expiration**: Unknown-date events get 6-month expiration (Phase 4)

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

  ## Synthetic Expiration for Unknown Dates (Phase 4)

  Events with unparseable dates receive synthetic `ends_at` timestamps to prevent
  database accumulation:

  - **Synthetic ends_at**: `first_seen + 6 months`
  - **Purpose**: Allow discovery and manual curation before expiration
  - **Tracking**: Stored in metadata (`synthetic_ends_at`, `synthetic_expiration_months`)
  - **Expiration**: Works with Phase 1 date-based filtering
  - **Benefits**: Prevents unknown-date events from living forever

  This works in conjunction with:
  - Phase 1: Date-based expiration filtering (EventDetailJob)
  - Phase 2: EventFreshnessChecker (SyncJob efficiency)

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
  alias EventasaurusDiscovery.Sources.Shared.Parsers.MultilingualDateParser
  alias EventasaurusDiscovery.Sources.Shared.RecurringEventParser
  alias EventasaurusDiscovery.Sources.Shared.JsonSanitizer

  @doc """
  Transform raw event data into unified format.

  Returns a list of events (multiple for multi-date events).

  Supports **unknown occurrence fallback** for unparseable dates:
  - When date parsing fails, creates event with occurrence_type = "unknown"
  - Uses first_seen timestamp as starts_at
  - **Phase 4**: Sets synthetic ends_at = first_seen + 6 months (expiration)
  - Stores occurrence_type and synthetic_ends_at in metadata JSONB field
  - Prevents ~15-20% data loss from unparseable dates
  - Allows natural expiration after 6 months if not manually updated

  ## Parameters

  - `raw_event` - Map with extracted event data
  - `options` - Optional transformation options

  ## Returns

  - `{:ok, [event, ...]}` - List of transformed events
  - `{:error, reason}` - Transformation failed (only for critical errors)
  """
  def transform_event(raw_event, options \\ %{}) do
    Logger.debug("🔄 Transforming raw event data")

    with {:ok, article_id} <- extract_article_id(raw_event),
         {:ok, title} <- extract_title(raw_event),
         {:ok, venue_data} <- extract_venue(raw_event) do
      # Try to parse dates - if it fails, use unknown occurrence fallback
      case extract_and_parse_dates(raw_event, options) do
        {:ok, dates} ->
          # SUCCESS: Create events with parsed dates
          event_type = Map.get(raw_event, "event_type", :one_time)

          events =
            case event_type do
              :exhibition ->
                [
                  create_exhibition_event(
                    article_id,
                    title,
                    dates,
                    venue_data,
                    raw_event,
                    options
                  )
                ]

              :recurring ->
                [
                  create_recurring_event(
                    article_id,
                    title,
                    List.first(dates),
                    venue_data,
                    raw_event,
                    options
                  )
                ]

              :one_time ->
                Enum.map(dates, fn date ->
                  create_event(article_id, title, date, venue_data, raw_event, options)
                end)
            end

          Logger.info(
            "✅ Transformed into #{length(events)} #{event_type} event instance(s): #{title}"
          )

          {:ok, events}

        {:error, :unsupported_date_format} ->
          # FALLBACK: Create unknown occurrence event with synthetic expiration
          Logger.info("""
          📅 Date parsing failed for Sortiraparis event - using unknown occurrence fallback
          Title: #{title}
          Date string: #{inspect(Map.get(raw_event, "date_string") || Map.get(raw_event, "original_date_string"))}
          Creating event with occurrence_type = "unknown" (stored in metadata JSONB)
          Phase 4: Synthetic ends_at = now + 6 months (expiration mechanism)
          """)

          event =
            create_unknown_occurrence_event(article_id, title, venue_data, raw_event, options)

          Logger.info("✅ Created unknown occurrence event with 6-month expiration: #{title}")
          {:ok, [event]}

        {:error, other_reason} ->
          # Other errors (missing dates entirely, etc.) still fail
          Logger.warning("⚠️ Failed to transform event: #{inspect(other_reason)}")
          {:error, other_reason}
      end
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

  defp extract_and_parse_dates(%{"dates" => dates} = raw_event, options)
       when is_list(dates) and length(dates) > 0 do
    # Extract time_string if available
    time_string = Map.get(raw_event, "time_string")
    timezone = Map.get(options, :timezone, "Europe/Paris")

    # Coerce entries to UTC DateTime; accept %DateTime{} or ISO8601 strings
    coerced =
      dates
      |> Enum.flat_map(fn
        %DateTime{} = dt ->
          # Apply time to already-parsed datetime if time_string available
          [apply_time_to_datetime(dt, time_string, timezone)]

        bin when is_binary(bin) ->
          case parse_with_multilingual_parser(bin, time_string, options) do
            {:ok, [dt | _]} -> [dt]
            _ -> []
          end

        _ ->
          []
      end)

    if coerced == [], do: {:error, :no_dates_extracted}, else: {:ok, coerced}
  end

  defp extract_and_parse_dates(%{"date_string" => date_string} = raw_event, options)
       when is_binary(date_string) do
    # Extract time_string if available
    time_string = Map.get(raw_event, "time_string")

    # Parse date string using MultilingualDateParser with optional time
    parse_with_multilingual_parser(date_string, time_string, options)
  end

  defp extract_and_parse_dates(%{"date" => date} = raw_event, options) when is_binary(date) do
    # Fallback to generic "date" field - preserve time_string
    extract_and_parse_dates(Map.put(raw_event, "date_string", date), options)
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
      # Article ID for consolidation (similar to movie_id)
      article_id: article_id,
      title: title,
      # Assumes date is already DateTime in UTC
      starts_at: date,
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
      description_translations: get_description_translations(raw_event),
      source_url: Config.build_url(raw_event["url"]),
      image_url: Map.get(raw_event, "image_url"),

      # Pricing - DO NOT set defaults, nil = no data available
      is_ticketed: Map.get(raw_event, "is_ticketed"),
      is_free: Map.get(raw_event, "is_free"),
      min_price: Map.get(raw_event, "min_price"),
      max_price: Map.get(raw_event, "max_price"),
      currency: Map.get(raw_event, "currency"),

      # Performers (if available)
      performers: Map.get(raw_event, "performers", []),

      # Metadata (include occurrence_type for consistency)
      metadata: %{
        "_raw_upstream" => JsonSanitizer.sanitize(raw_event),
        article_id: article_id,
        # Store in metadata JSONB (validated type)
        occurrence_type: "explicit",
        original_date_string: Map.get(raw_event, "original_date_string"),
        category_url: Map.get(raw_event, "category"),
        language: "en"
      },

      # Raw event data for CategoryExtractor (includes URL for category extraction)
      raw_event_data: raw_event
    }
  end

  defp create_unknown_occurrence_event(article_id, title, venue_data, raw_event, _options) do
    # Use "first seen" timestamp as starts_at (required field)
    first_seen = DateTime.utc_now()

    # Generate external_id WITHOUT date suffix (unknown occurrence, single instance)
    external_id = Config.generate_external_id(article_id)

    # Phase 4: Synthetic ends_at for expiration
    # Set ends_at to 6 months after creation to allow natural expiration
    # Events can be manually curated/updated before expiration
    # Prevents unknown-date events from living forever in database
    synthetic_ends_at = DateTime.add(first_seen, 6 * 30 * 86400, :second)

    %{
      # Required fields
      external_id: external_id,
      article_id: article_id,
      title: title,
      # Use first_seen as starts_at
      starts_at: first_seen,
      # Keep as one_time for compatibility
      event_type: :one_time,

      # Venue data (REQUIRED - VenueProcessor handles geocoding)
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

      # Optional but recommended
      # Phase 4: Synthetic ends_at = first_seen + 6 months (expiration mechanism)
      ends_at: synthetic_ends_at,
      description_translations: get_description_translations(raw_event),
      source_url: Config.build_url(raw_event["url"]),
      image_url: Map.get(raw_event, "image_url"),

      # Pricing - DO NOT set defaults, nil = no data available
      is_ticketed: Map.get(raw_event, "is_ticketed"),
      is_free: Map.get(raw_event, "is_free"),
      min_price: Map.get(raw_event, "min_price"),
      max_price: Map.get(raw_event, "max_price"),
      currency: Map.get(raw_event, "currency"),

      # Performers (if available)
      performers: Map.get(raw_event, "performers", []),

      # Metadata - CRITICAL: Store occurrence_type = "exhibition" in JSONB
      # Events with unparseable dates are treated as exhibitions (open-ended)
      metadata: %{
        "_raw_upstream" => JsonSanitizer.sanitize(raw_event),
        article_id: article_id,
        # JSONB storage for occurrence type (validated)
        occurrence_type: "exhibition",
        # Flag indicating fallback was used
        occurrence_fallback: true,
        first_seen_at: DateTime.to_iso8601(first_seen),
        # Phase 4: Track synthetic expiration for manual curation
        synthetic_ends_at: DateTime.to_iso8601(synthetic_ends_at),
        synthetic_expiration_months: 6,
        original_date_string:
          Map.get(raw_event, "date_string") || Map.get(raw_event, "original_date_string"),
        category_url: Map.get(raw_event, "category"),
        language: get_source_language(raw_event)
      },

      # Raw event data for CategoryExtractor
      raw_event_data: raw_event
    }
  end

  defp create_exhibition_event(article_id, title, dates, venue_data, raw_event, _options) do
    # For exhibitions, use start date for starts_at, end date for ends_at
    # Sort dates to ensure correct chronological order (defensive programming)
    sorted_dates = Enum.sort(dates, &(DateTime.compare(&1, &2) != :gt))

    # Guard against empty dates list
    [start_date | rest] =
      case sorted_dates do
        [] -> raise ArgumentError, "Exhibition requires at least one date"
        dates -> dates
      end

    end_date = List.last(rest) || start_date

    # Generate external_id WITHOUT date suffix (exhibitions don't have multiple instances)
    external_id = Config.generate_external_id(article_id)

    %{
      # Required fields
      external_id: external_id,
      article_id: article_id,
      title: title,
      starts_at: start_date,
      # Exhibition closing date
      ends_at: end_date,
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
      description_translations: get_description_translations(raw_event),
      source_url: Config.build_url(raw_event["url"]),
      image_url: Map.get(raw_event, "image_url"),

      # Pricing - DO NOT set defaults, nil = no data available
      is_ticketed: Map.get(raw_event, "is_ticketed"),
      is_free: Map.get(raw_event, "is_free"),
      min_price: Map.get(raw_event, "min_price"),
      max_price: Map.get(raw_event, "max_price"),
      currency: Map.get(raw_event, "currency"),
      performers: Map.get(raw_event, "performers", []),

      # Metadata (include occurrence_type for consistency)
      metadata: %{
        "_raw_upstream" => JsonSanitizer.sanitize(raw_event),
        article_id: article_id,
        # Store in metadata JSONB
        occurrence_type: "exhibition",
        original_date_string: Map.get(raw_event, "original_date_string"),
        category_url: Map.get(raw_event, "category"),
        language: get_source_language(raw_event),
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
      description_translations: get_description_translations(raw_event),
      source_url: Config.build_url(raw_event["url"]),
      image_url: Map.get(raw_event, "image_url"),

      # Pricing - DO NOT set defaults, nil = no data available
      is_ticketed: Map.get(raw_event, "is_ticketed"),
      is_free: Map.get(raw_event, "is_free"),
      min_price: Map.get(raw_event, "min_price"),
      max_price: Map.get(raw_event, "max_price"),
      currency: Map.get(raw_event, "currency"),
      performers: Map.get(raw_event, "performers", []),

      # Metadata - include recurrence pattern and occurrence_type
      metadata: %{
        "_raw_upstream" => JsonSanitizer.sanitize(raw_event),
        article_id: article_id,
        # Store in metadata JSONB
        occurrence_type: "recurring",
        original_date_string: Map.get(raw_event, "original_date_string"),
        category_url: Map.get(raw_event, "category"),
        language: get_source_language(raw_event),
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

  defp get_description_translations(raw_event) do
    # Check if bilingual translations were merged (from EventDetailJob)
    case Map.get(raw_event, "description_translations") do
      nil ->
        # No translations map, check for single language description
        case Map.get(raw_event, "description") do
          nil ->
            nil

          "" ->
            nil

          desc ->
            # Single language description - use source_language if available
            lang = Map.get(raw_event, "source_language", "en")
            %{lang => desc}
        end

      translations when is_map(translations) ->
        # Bilingual translations already merged
        translations
    end
  end

  defp get_source_language(raw_event) do
    # Get source language from metadata (set by EventDetailJob during bilingual fetching)
    Map.get(raw_event, "source_language", "en")
  end

  # Wrapper to adapt MultilingualDateParser API to Transformer's expected format
  # Now also handles optional time parsing using RecurringEventParser
  defp parse_with_multilingual_parser(date_string, time_string, options) do
    # Get timezone from options (defaults to Europe/Paris for Sortiraparis)
    timezone = Map.get(options, :timezone, "Europe/Paris")

    # Call MultilingualDateParser with French and English fallback
    # Try French first since Sortiraparis is primarily French content
    case MultilingualDateParser.extract_and_parse(date_string,
           languages: [:french, :english],
           timezone: timezone
         ) do
      {:ok, %{starts_at: starts_at, ends_at: ends_at_from_range}} ->
        # Parse time if available and combine with date(s)
        starts_at_with_time = apply_time_to_datetime(starts_at, time_string, timezone)

        ends_at_with_time =
          if ends_at_from_range do
            # For date ranges, don't apply time to end date (use end of day)
            ends_at_from_range
          else
            nil
          end

        if ends_at_with_time do
          {:ok, [starts_at_with_time, ends_at_with_time]}
        else
          {:ok, [starts_at_with_time]}
        end

      {:error, :unsupported_date_format} = error ->
        # Pass through unsupported_date_format for unknown occurrence fallback
        error

      {:error, reason} ->
        # Other errors
        Logger.debug("MultilingualDateParser error: #{inspect(reason)}")
        {:error, :unsupported_date_format}
    end
  end

  # Apply parsed time to a DateTime, replacing the time component
  # Falls back to original datetime if time parsing fails
  defp apply_time_to_datetime(datetime, nil, _timezone), do: datetime

  defp apply_time_to_datetime(datetime, time_string, timezone) when is_binary(time_string) do
    case RecurringEventParser.parse_time(time_string) do
      {:ok, time} ->
        # Replace the time component of the datetime
        date = DateTime.to_date(datetime)

        case DateTime.new(date, time, timezone) do
          {:ok, new_datetime} ->
            # Convert to UTC
            DateTime.shift_zone!(new_datetime, "Etc/UTC")

          # Handle ambiguous time during DST fall-back (clocks set back)
          # Choose the first occurrence (before clocks are set back)
          {:ambiguous, first_occurrence, _second_occurrence} ->
            Logger.warning(
              "⚠️ Ambiguous local time '#{time_string}' in #{timezone} during DST transition. Using first occurrence (before clocks set back)."
            )

            DateTime.shift_zone!(first_occurrence, "Etc/UTC")

          # Handle gap during DST spring-forward (clocks jump ahead)
          # Choose the time after the gap (the valid time after clocks jump forward)
          {:gap, _before_gap, after_gap} ->
            Logger.warning(
              "⚠️ Gap in local time '#{time_string}' in #{timezone} during DST transition. Using time after gap (after clocks jump forward)."
            )

            DateTime.shift_zone!(after_gap, "Etc/UTC")

          {:error, reason} ->
            Logger.warning(
              "⚠️ Failed to create DateTime with parsed time: #{inspect(reason)}. Using original datetime."
            )

            datetime
        end

      {:error, reason} ->
        Logger.debug(
          "⚠️ Failed to parse time '#{time_string}': #{inspect(reason)}. Using midnight default."
        )

        datetime
    end
  end
end
