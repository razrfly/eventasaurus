defmodule EventasaurusWeb.Utils.TimezoneUtils do
  @moduledoc """
  Centralized timezone utilities for Eventasaurus.

  This module provides a single source of truth for all timezone-related operations,
  ensuring consistent behavior across the application.

  ## Key Functions

  - `get_event_timezone/1` - Get timezone for an event based on venue's city or coordinates
  - `get_venue_timezone/1` - Get timezone for a venue based on city or coordinates
  - `get_city_timezone/1` - Get timezone for a city (precomputed or from coordinates)
  - `get_timezone_from_coordinates/2` - Get timezone from lat/lng coordinates
  - `default_timezone_for_context/1` - Get timezone based on current city/country context

  ## Timezone Resolution Strategy (Issue #3334)

  To eliminate runtime TzWorld GenServer bottlenecks, this module uses a tiered lookup:

  1. **City.timezone** (precomputed) - Fastest, no runtime lookup
  2. **TzWorld from coordinates** - Fallback for cities without precomputed timezone
  3. **Country fallback** - For cities without coordinates
  4. **Default timezone** - Final fallback

  ## Fallback Behavior

  When timezone cannot be determined (missing coordinates, TzWorld lookup fails),
  the module falls back to `"Europe/Warsaw"` as the default timezone since this
  is the primary market for the application.

  ## Usage

      # Get timezone for an event (uses venue's city.timezone if available)
      timezone = TimezoneUtils.get_event_timezone(event)

      # Get timezone for a venue directly
      timezone = TimezoneUtils.get_venue_timezone(venue)

      # Get timezone for a city (precomputed or calculated)
      timezone = TimezoneUtils.get_city_timezone(city)

      # Get timezone from coordinates (direct TzWorld call)
      timezone = TimezoneUtils.get_timezone_from_coordinates(52.2297, 21.0122)
  """

  require Logger
  alias EventasaurusDiscovery.Helpers.TimezoneMapper

  @default_timezone "Europe/Warsaw"

  @doc """
  Returns the default timezone used as fallback when timezone cannot be determined.

  Currently returns "Europe/Warsaw" as the primary market for the application.
  """
  @spec default_timezone() :: String.t()
  def default_timezone, do: @default_timezone

  @doc """
  Returns a context-aware default timezone based on the current city/country being viewed.

  When a city or country context is available, derives the timezone from the country code
  using TimezoneMapper. Falls back to the default timezone when no context is available.

  This is preferred over `default_timezone/0` when you have access to the current
  viewing context (e.g., city page, country page).

  ## Parameters

  - `context` - A map that may contain `:country` with `:code`, or `:city` with nested `:country`

  ## Returns

  IANA timezone string derived from context, or default timezone

  ## Examples

      iex> default_timezone_for_context(%{country: %{code: "GB"}})
      "Europe/London"

      iex> default_timezone_for_context(%{city: %{country: %{code: "US"}}})
      "America/New_York"

      iex> default_timezone_for_context(nil)
      "Europe/Warsaw"
  """
  @spec default_timezone_for_context(map() | nil) :: String.t()
  def default_timezone_for_context(%{country: %{code: code}}) when is_binary(code) do
    TimezoneMapper.get_timezone_for_country(code)
  end

  def default_timezone_for_context(%{city: %{country: %{code: code}}}) when is_binary(code) do
    TimezoneMapper.get_timezone_for_country(code)
  end

  # Handle city struct directly - use precomputed timezone if available
  def default_timezone_for_context(%EventasaurusDiscovery.Locations.City{timezone: tz} = _city)
      when is_binary(tz) and tz != "" do
    tz
  end

  def default_timezone_for_context(%EventasaurusDiscovery.Locations.City{} = city) do
    TimezoneMapper.get_timezone_for_city(city)
  end

  def default_timezone_for_context(_), do: @default_timezone

  @doc """
  Gets the timezone for a city, using precomputed value if available.

  This is the preferred method for getting city timezone as it avoids
  runtime TzWorld lookups when city.timezone is already populated.

  ## Resolution Order

  1. city.timezone (precomputed) - No runtime lookup needed
  2. TzWorld from city coordinates - If city has lat/lng
  3. Country fallback - Using TimezoneMapper
  4. Default timezone - Final fallback

  ## Parameters

  - `city` - A City struct or map with timezone, coordinates, or country

  ## Returns

  IANA timezone string

  ## Examples

      iex> get_city_timezone(%City{timezone: "Europe/Warsaw"})
      "Europe/Warsaw"

      iex> get_city_timezone(%City{timezone: nil, latitude: 50.0647, longitude: 19.9450})
      "Europe/Warsaw"
  """
  @spec get_city_timezone(map() | nil) :: String.t()
  def get_city_timezone(%{timezone: tz}) when is_binary(tz) and tz != "" do
    tz
  end

  def get_city_timezone(%{latitude: lat, longitude: lng} = city)
      when is_number(lat) and is_number(lng) do
    # Fall back to coordinates lookup if no precomputed timezone
    get_timezone_from_coordinates(lat, lng)
  rescue
    # If TzWorld fails, try country fallback
    _ -> get_city_timezone_from_country(city)
  end

  def get_city_timezone(%{latitude: lat, longitude: lng} = city)
      when not is_nil(lat) and not is_nil(lng) do
    # Handle Decimal coordinates
    lat_float = to_float(lat)
    lng_float = to_float(lng)
    get_timezone_from_coordinates(lat_float, lng_float)
  rescue
    _ -> get_city_timezone_from_country(city)
  end

  def get_city_timezone(city) when is_map(city) do
    # No coordinates - use country fallback
    get_city_timezone_from_country(city)
  end

  def get_city_timezone(_), do: @default_timezone

  # Get timezone from city's country association
  defp get_city_timezone_from_country(%{country: %{code: code}}) when is_binary(code) do
    TimezoneMapper.get_timezone_for_country(code)
  end

  defp get_city_timezone_from_country(_), do: @default_timezone

  # Convert Decimal to float for TzWorld
  defp to_float(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value * 1.0

  @doc """
  Gets the timezone for an event based on its venue's city or coordinates.

  ## Resolution Order (Issue #3334)

  1. event.venue.city.timezone (precomputed) - No runtime lookup needed
  2. event.venue coordinates via TzWorld - If venue has lat/lng
  3. Default timezone - Final fallback

  This approach eliminates runtime TzWorld GenServer bottlenecks by using
  the precomputed city.timezone when available.

  ## Parameters

  - `event` - An event struct or map with a nested venue (optionally with city preloaded)

  ## Returns

  IANA timezone string (e.g., "Europe/Warsaw", "America/New_York")

  ## Examples

      iex> get_event_timezone(%{venue: %{city: %{timezone: "Europe/Warsaw"}}})
      "Europe/Warsaw"

      iex> get_event_timezone(%{venue: %{latitude: 50.0647, longitude: 19.9450}})
      "Europe/Warsaw"

      iex> get_event_timezone(%{venue: nil})
      "Europe/Warsaw"

      iex> get_event_timezone(nil)
      "Europe/Warsaw"
  """
  @spec get_event_timezone(map() | nil) :: String.t()
  # First priority: Use venue's city precomputed timezone
  def get_event_timezone(%{venue: %{city: %{timezone: tz}}}) when is_binary(tz) and tz != "" do
    tz
  end

  # Second priority: Delegate to get_venue_timezone for full resolution
  def get_event_timezone(%{venue: venue}) when is_map(venue) do
    get_venue_timezone(venue)
  end

  def get_event_timezone(_), do: @default_timezone

  @doc """
  Gets the timezone for a venue, preferring city's precomputed timezone.

  ## Resolution Order (Issue #3334)

  1. venue.city.timezone (precomputed) - No runtime lookup needed
  2. venue coordinates via TzWorld - If venue has lat/lng
  3. Default timezone - Final fallback

  ## Parameters

  - `venue` - A venue struct or map, optionally with city preloaded

  ## Returns

  IANA timezone string

  ## Examples

      iex> get_venue_timezone(%{city: %{timezone: "Europe/Warsaw"}})
      "Europe/Warsaw"

      iex> get_venue_timezone(%{latitude: 50.0647, longitude: 19.9450})
      "Europe/Warsaw"

      iex> get_venue_timezone(%{latitude: nil, longitude: nil})
      "Europe/Warsaw"
  """
  @spec get_venue_timezone(map() | nil) :: String.t()
  # First priority: Use city's precomputed timezone if available
  def get_venue_timezone(%{city: %{timezone: tz}}) when is_binary(tz) and tz != "" do
    tz
  end

  # Second priority: Use city struct for timezone lookup
  def get_venue_timezone(%{city: city}) when is_map(city) do
    get_city_timezone(city)
  end

  # Third priority: Fall back to venue coordinates
  def get_venue_timezone(%{latitude: lat, longitude: lng})
      when is_number(lat) and is_number(lng) do
    get_timezone_from_coordinates(lat, lng)
  end

  def get_venue_timezone(_), do: @default_timezone

  @doc """
  Gets timezone from latitude/longitude coordinates using TzWorld.

  TzWorld expects coordinates in {longitude, latitude} order.

  ## Parameters

  - `latitude` - Latitude as a number
  - `longitude` - Longitude as a number

  ## Returns

  IANA timezone string, or default timezone if lookup fails

  ## Examples

      iex> get_timezone_from_coordinates(50.0647, 19.9450)
      "Europe/Warsaw"

      iex> get_timezone_from_coordinates(40.7128, -74.0060)
      "America/New_York"
  """
  @spec get_timezone_from_coordinates(number(), number()) :: String.t()
  def get_timezone_from_coordinates(latitude, longitude)
      when is_number(latitude) and is_number(longitude) do
    # TzWorld expects {longitude, latitude} tuple
    case TzWorld.timezone_at({longitude, latitude}) do
      {:ok, timezone} ->
        timezone

      {:error, :time_zone_not_found} ->
        Logger.debug(
          "[TimezoneUtils] TzWorld could not find timezone for coordinates (#{latitude}, #{longitude}), using default"
        )

        @default_timezone

      {:error, reason} ->
        Logger.warning(
          "[TimezoneUtils] TzWorld lookup failed for (#{latitude}, #{longitude}): #{inspect(reason)}, using default"
        )

        @default_timezone
    end
  end

  def get_timezone_from_coordinates(_, _), do: @default_timezone

  @doc """
  Converts a datetime to the event's local timezone.

  ## Parameters

  - `datetime` - A DateTime struct
  - `event` - An event with venue coordinates

  ## Returns

  DateTime shifted to the event's local timezone, or original datetime on failure

  ## Examples

      iex> shift_to_event_timezone(~U[2024-01-15 12:00:00Z], %{venue: %{latitude: 50.0647, longitude: 19.9450}})
      #DateTime<2024-01-15 13:00:00+01:00 CET Europe/Warsaw>
  """
  @spec shift_to_event_timezone(DateTime.t() | nil, map() | nil) :: DateTime.t() | nil
  def shift_to_event_timezone(nil, _event), do: nil

  def shift_to_event_timezone(%DateTime{} = datetime, event) do
    timezone = get_event_timezone(event)
    shift_to_timezone(datetime, timezone)
  end

  @doc """
  Converts a datetime to a specific timezone.

  ## Parameters

  - `datetime` - A DateTime struct
  - `timezone` - IANA timezone string

  ## Returns

  DateTime shifted to the specified timezone, or original datetime on failure
  """
  @spec shift_to_timezone(DateTime.t() | nil, String.t()) :: DateTime.t() | nil
  def shift_to_timezone(nil, _timezone), do: nil

  def shift_to_timezone(%DateTime{} = datetime, timezone) when is_binary(timezone) do
    case DateTime.shift_zone(datetime, timezone) do
      {:ok, shifted} -> shifted
      {:error, _} -> datetime
    end
  end

  def shift_to_timezone(datetime, _), do: datetime

  @doc """
  Creates a DateTime from date, time, and event context.

  Uses the event's venue coordinates to determine the correct timezone,
  then creates a DateTime in that timezone.

  ## Parameters

  - `date` - A Date struct
  - `time` - A Time struct
  - `event` - An event with venue coordinates for timezone lookup

  ## Returns

  - `{:ok, DateTime.t()}` on success
  - `{:error, reason}` on failure

  Note: Handles DST transitions by selecting the earlier time for ambiguous cases
  and the later time for gap cases.

  ## Examples

      iex> create_datetime_for_event(~D[2024-01-15], ~T[19:30:00], %{venue: %{latitude: 50.0647, longitude: 19.9450}})
      {:ok, #DateTime<2024-01-15 19:30:00+01:00 CET Europe/Warsaw>}
  """
  @spec create_datetime_for_event(Date.t(), Time.t(), map()) ::
          {:ok, DateTime.t()} | {:error, atom()}
  def create_datetime_for_event(%Date{} = date, %Time{} = time, event) do
    timezone = get_event_timezone(event)

    case DateTime.new(date, time, timezone) do
      {:ok, datetime} ->
        {:ok, datetime}

      # DST "fall back" - time occurs twice, pick the earlier one (before DST ends)
      {:ambiguous, dt1, _dt2} ->
        {:ok, dt1}

      # DST "spring forward" - time doesn't exist, pick the later valid time
      {:gap, _dt_before, dt_after} ->
        {:ok, dt_after}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a DateTime from date, time, and event context, raising on error.

  Same as `create_datetime_for_event/3` but raises on failure.
  Handles DST transitions by selecting appropriate times.
  """
  @spec create_datetime_for_event!(Date.t(), Time.t(), map()) :: DateTime.t()
  def create_datetime_for_event!(%Date{} = date, %Time{} = time, event) do
    case create_datetime_for_event(date, time, event) do
      {:ok, datetime} -> datetime
      {:error, reason} -> raise ArgumentError, "Failed to create datetime: #{inspect(reason)}"
    end
  end
end
