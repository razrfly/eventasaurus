defmodule EventasaurusDiscovery.Sources.Kupbilecik.Transformer do
  @moduledoc """
  Transforms raw Kupbilecik data into standardized event format.

  Handles:
  - Polish date parsing (e.g., "7 grudnia 2025 o godz. 20:00")
  - Category mapping (Polish → canonical)
  - Venue normalization
  - Multi-date event splitting (if applicable)
  """

  require Logger

  alias EventasaurusDiscovery.Sources.Kupbilecik.Config

  @doc """
  Transforms a list of raw events into standardized format.

  ## Parameters

    * `raw_events` - List of raw event data from extractors

  ## Returns

    * `{:ok, events}` - List of transformed events
    * `{:error, reason}` - Error tuple if transformation fails
  """
  def transform_events(raw_events) when is_list(raw_events) do
    events =
      raw_events
      |> Enum.flat_map(&transform_event/1)
      |> Enum.reject(&is_nil/1)

    {:ok, events}
  rescue
    error ->
      Logger.error("Failed to transform events: #{inspect(error)}")
      {:error, error}
  end

  @doc """
  Transforms a single raw event into standardized format.

  If the event has multiple dates, returns a list of event instances.
  Returns an empty list if the event cannot be transformed.
  """
  def transform_event(raw_event) do
    with {:ok, starts_at} <- parse_datetime(raw_event),
         {:ok, external_id} <- build_external_id(raw_event, starts_at) do
      event = %{
        external_id: external_id,
        title: extract_title(raw_event),
        description: extract_description(raw_event),
        starts_at: starts_at,
        ends_at: calculate_ends_at(starts_at, raw_event),
        source_url: raw_event["url"],
        image_url: raw_event["image_url"],
        venue_data: extract_venue(raw_event),
        performer_names: extract_performers(raw_event),
        categories: extract_categories(raw_event),
        price_info: raw_event["price"],
        ticket_url: raw_event["ticket_url"] || raw_event["url"],
        source_data: raw_event
      }

      [event]
    else
      {:error, reason} ->
        Logger.warning("Failed to transform event: #{inspect(reason)}")
        Logger.debug("Raw event: #{inspect(raw_event)}")
        []
    end
  rescue
    error ->
      Logger.warning("Exception transforming event: #{inspect(error)}")
      []
  end

  # Date/Time Parsing

  @doc """
  Parses Polish date string into DateTime.

  Supports formats:
  - "7 grudnia 2025 o godz. 20:00"
  - "7 grudnia 2025, 20:00"
  - "7 grudnia 2025"

  ## Examples

      iex> parse_polish_date("7 grudnia 2025 o godz. 20:00")
      {:ok, ~U[2025-12-07 20:00:00Z]}

      iex> parse_polish_date("15 maja 2025")
      {:ok, ~U[2025-05-15 00:00:00Z]}
  """
  def parse_polish_date(date_string) when is_binary(date_string) do
    # Normalize the string
    normalized =
      date_string
      |> String.trim()
      |> String.downcase()

    # Try different patterns
    cond do
      # Pattern: "7 grudnia 2025 o godz. 20:00"
      result = parse_with_godz_pattern(normalized) ->
        result

      # Pattern: "7 grudnia 2025, 20:00"
      result = parse_with_comma_time(normalized) ->
        result

      # Pattern: "7 grudnia 2025"
      result = parse_date_only(normalized) ->
        result

      true ->
        {:error, {:invalid_date_format, date_string}}
    end
  end

  def parse_polish_date(nil), do: {:error, :date_is_nil}
  def parse_polish_date(_), do: {:error, :invalid_date_type}

  defp parse_with_godz_pattern(text) do
    # Pattern: "7 grudnia 2025 o godz. 20:00"
    # Uses \p{L} for Unicode letter support (Polish characters like ś, ę, ń, etc.)
    regex = ~r/(\d{1,2})\s+([\p{L}]+)\s+(\d{4})\s+o\s+godz\.\s*(\d{1,2}):(\d{2})/u

    case Regex.run(regex, text, capture: :all_but_first) do
      [day, month_name, year, hour, minute] ->
        build_datetime(day, month_name, year, hour, minute)

      _ ->
        nil
    end
  end

  defp parse_with_comma_time(text) do
    # Pattern: "7 grudnia 2025, 20:00"
    # Uses \p{L} for Unicode letter support (Polish characters like ś, ę, ń, etc.)
    regex = ~r/(\d{1,2})\s+([\p{L}]+)\s+(\d{4}),?\s*(\d{1,2}):(\d{2})/u

    case Regex.run(regex, text, capture: :all_but_first) do
      [day, month_name, year, hour, minute] ->
        build_datetime(day, month_name, year, hour, minute)

      _ ->
        nil
    end
  end

  defp parse_date_only(text) do
    # Pattern: "7 grudnia 2025"
    # Uses \p{L} for Unicode letter support (Polish characters like ś, ę, ń, etc.)
    regex = ~r/(\d{1,2})\s+([\p{L}]+)\s+(\d{4})/u

    case Regex.run(regex, text, capture: :all_but_first) do
      [day, month_name, year] ->
        build_datetime(day, month_name, year, "0", "0")

      _ ->
        nil
    end
  end

  defp build_datetime(day_str, month_name, year_str, hour_str, minute_str) do
    months = Config.polish_months()

    with {day, _} <- Integer.parse(day_str),
         {year, _} <- Integer.parse(year_str),
         {hour, _} <- Integer.parse(hour_str),
         {minute, _} <- Integer.parse(minute_str),
         month when not is_nil(month) <- Map.get(months, month_name) do
      case DateTime.new(Date.new!(year, month, day), Time.new!(hour, minute, 0)) do
        {:ok, datetime} -> {:ok, datetime}
        {:error, reason} -> {:error, reason}
      end
    else
      nil -> {:error, {:unknown_month, month_name}}
      _ -> {:error, :parse_failed}
    end
  end

  # Private extraction functions

  defp parse_datetime(raw_event) do
    cond do
      # Already parsed DateTime
      is_struct(raw_event["starts_at"], DateTime) ->
        {:ok, raw_event["starts_at"]}

      # ISO8601 string
      is_binary(raw_event["starts_at"]) ->
        case DateTime.from_iso8601(raw_event["starts_at"]) do
          {:ok, dt, _} -> {:ok, dt}
          _ -> parse_polish_date(raw_event["date_string"])
        end

      # Polish date string
      is_binary(raw_event["date_string"]) ->
        parse_polish_date(raw_event["date_string"])

      # Date field
      is_binary(raw_event["date"]) ->
        parse_polish_date(raw_event["date"])

      true ->
        {:error, :no_date_found}
    end
  end

  defp build_external_id(raw_event, starts_at) do
    event_id = raw_event["event_id"] || raw_event["id"]

    if is_nil(event_id) do
      {:error, :no_event_id}
    else
      date_str = DateTime.to_date(starts_at) |> Date.to_iso8601()
      {:ok, Config.generate_external_id(event_id, date_str)}
    end
  end

  defp extract_title(raw_event) do
    raw_event["title"] || raw_event["name"] || "Untitled Event"
  end

  defp extract_description(raw_event) do
    raw_event["description"]
  end

  defp calculate_ends_at(starts_at, raw_event) do
    cond do
      # Explicit ends_at
      is_struct(raw_event["ends_at"], DateTime) ->
        raw_event["ends_at"]

      # Duration in minutes
      is_integer(raw_event["duration_minutes"]) ->
        DateTime.add(starts_at, raw_event["duration_minutes"] * 60, :second)

      # Default: 2 hours after start
      true ->
        DateTime.add(starts_at, 2 * 60 * 60, :second)
    end
  end

  defp extract_venue(raw_event) do
    venue_data = raw_event["venue"] || %{}

    %{
      name: venue_data["name"] || raw_event["venue_name"],
      address: venue_data["address"] || raw_event["address"],
      city: venue_data["city"] || raw_event["city"],
      country: venue_data["country"] || "Poland",
      latitude: venue_data["latitude"],
      longitude: venue_data["longitude"]
    }
  end

  defp extract_performers(raw_event) do
    cond do
      is_list(raw_event["performers"]) ->
        raw_event["performers"]

      is_binary(raw_event["performers"]) ->
        String.split(raw_event["performers"], ",")
        |> Enum.map(&String.trim/1)

      is_binary(raw_event["artist"]) ->
        [raw_event["artist"]]

      true ->
        []
    end
  end

  defp extract_categories(raw_event) do
    cond do
      is_list(raw_event["categories"]) ->
        Enum.map(raw_event["categories"], &Config.map_category/1)

      is_binary(raw_event["category"]) ->
        [Config.map_category(raw_event["category"])]

      true ->
        ["other"]
    end
  end
end
