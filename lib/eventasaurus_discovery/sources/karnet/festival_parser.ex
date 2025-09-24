defmodule EventasaurusDiscovery.Sources.Karnet.FestivalParser do
  @moduledoc """
  Simplified parser for festival events from Karnet Kraków.

  Since Karnet is localized to Kraków only and lower priority than
  Ticketmaster/BandsInTown, this provides basic festival support
  without complex sub-event extraction.
  """

  require Logger
  alias EventasaurusDiscovery.Sources.Karnet.DateParser

  @doc """
  Detect if an event is a festival based on various indicators.
  """
  def is_festival?(event_data) do
    # Check multiple indicators
    title_check =
      event_data[:title] &&
        (String.contains?(String.downcase(event_data[:title]), "fest") ||
           String.contains?(String.downcase(event_data[:title]), "festiwal"))

    category_check =
      event_data[:category] &&
        String.contains?(String.downcase(event_data[:category]), "festiwal")

    # Multi-day events are often festivals
    date_range_check =
      event_data[:date_text] &&
        String.contains?(event_data[:date_text], " - ")

    # Check if explicitly marked as festival
    is_festival_flag = event_data[:is_festival] == true

    title_check || category_check || (date_range_check && is_festival_flag)
  end

  @doc """
  Parse festival data into a simplified structure.

  For Kraków-only events, we don't need complex sub-event parsing
  since there's likely overlap with Ticketmaster/BandsInTown data.
  """
  def parse_festival(html, event_data) do
    # Extract basic festival info
    festival_info = %{
      is_festival: true,
      festival_name: event_data[:title],
      date_range: extract_date_range(event_data),
      venues: extract_festival_venues(html),
      main_performers: extract_main_performers(html),
      estimated_sub_events: count_sub_events(html)
    }

    # Merge with original event data
    Map.merge(event_data, festival_info)
  end

  defp extract_date_range(event_data) do
    case DateParser.parse_date_string(event_data[:date_text]) do
      {:ok, {start_dt, end_dt}} ->
        %{
          start_date: start_dt,
          end_date: end_dt,
          duration_days: calculate_duration(start_dt, end_dt)
        }

      _ ->
        %{
          text: event_data[:date_text],
          parsed: false
        }
    end
  end

  defp calculate_duration(start_dt, end_dt) do
    DateTime.diff(end_dt, start_dt, :day) + 1
  end

  defp extract_festival_venues(html) do
    # Since most Kraków festivals use known venues that are likely
    # already in our system from other sources, just extract venue names
    case Floki.parse_document(html) do
      {:ok, document} ->
        venue_selectors = [
          ".venue",
          ".location",
          ".miejsce",
          "[class*='venue']",
          "h3:fl-contains('Miejsce') ~ *"
        ]

        venues =
          venue_selectors
          |> Enum.flat_map(fn selector ->
            Floki.find(document, selector)
          end)
          |> Enum.map(&Floki.text/1)
          |> Enum.map(&String.trim/1)
          |> Enum.filter(fn text ->
            String.length(text) > 3 && String.length(text) < 200
          end)
          |> Enum.uniq()

        # Return simplified venue list
        Enum.map(venues, fn venue_text ->
          %{
            name: venue_text,
            city: "Kraków",
            country: "Poland"
          }
        end)

      {:error, _reason} ->
        Logger.warning("Failed to parse document for venue extraction")
        []
    end
  end

  defp extract_main_performers(html) do
    # Extract headliners/main performers only
    # Sub-events would be handled by more comprehensive scrapers
    case Floki.parse_document(html) do
      {:ok, document} ->
        # Look for performer patterns
        performer_selectors = [
          ".performer",
          ".artist",
          ".wykonawca",
          # Often performers are in bold
          "strong",
          # Sometimes in subheadings
          "h4"
        ]

        performers =
          performer_selectors
          |> Enum.flat_map(fn selector ->
            Floki.find(document, selector)
          end)
          |> Enum.map(&Floki.text/1)
          |> Enum.map(&String.trim/1)
          |> Enum.filter(fn text ->
            # Basic filtering for likely performer names
            String.length(text) > 2 &&
              String.length(text) < 100 &&
              not String.contains?(text, ["ul.", "al.", "Kraków", "bilety"])
          end)
          # Limit to top 10 to avoid noise
          |> Enum.take(10)
          |> Enum.uniq()

        performers

      {:error, _reason} ->
        Logger.warning("Failed to parse document for performer extraction")
        []
    end
  end

  defp count_sub_events(html) do
    # Estimate sub-events by counting date/time patterns
    date_patterns = [
      # Polish date format
      ~r/\d{1,2}\.\d{1,2}\.\d{4}/,
      # Time format
      ~r/\d{1,2}:\d{2}/,
      # Polish "hour" abbreviation
      ~r/godz\./
    ]

    matches =
      date_patterns
      |> Enum.map(fn pattern ->
        Regex.scan(pattern, html) |> length()
      end)
      |> Enum.max()

    # Rough estimate - each date/time likely represents an event
    # Cap at 50 to avoid outliers
    min(matches, 50)
  end

  @doc """
  Create a simplified festival event for processing.

  Since Karnet is Kraków-only and lower priority, we store the
  festival as a single event with metadata rather than creating
  multiple sub-events.
  """
  def create_festival_event(festival_data) do
    %{
      # Standard event fields
      title: festival_data[:festival_name] || festival_data[:title],
      source_url: festival_data[:url],
      starts_at: get_in(festival_data, [:date_range, :start_date]),
      ends_at: get_in(festival_data, [:date_range, :end_date]),

      # Festival-specific metadata
      is_festival: true,
      festival_metadata: %{
        "duration_days" => get_in(festival_data, [:date_range, :duration_days]),
        "estimated_sub_events" => festival_data[:estimated_sub_events],
        "main_performers" => festival_data[:main_performers] || [],
        "venues" => festival_data[:venues] || []
      },

      # Use first venue if multiple
      venue_data: List.first(festival_data[:venues]),

      # Simplified performer list
      performer_names: festival_data[:main_performers] || [],

      # Standard fields
      description: festival_data[:description],
      category: "festival",
      external_id: "karnet_fest_#{extract_id(festival_data[:url])}"
    }
  end

  defp extract_id(url) do
    case Regex.run(~r/\/(\d+)-/, url) do
      [_, id] -> id
      _ -> :crypto.strong_rand_bytes(4) |> Base.encode16()
    end
  end
end
