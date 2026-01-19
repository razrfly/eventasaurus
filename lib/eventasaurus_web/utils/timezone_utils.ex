defmodule EventasaurusWeb.Utils.TimezoneUtils do
  @moduledoc """
  Centralized timezone utilities for Eventasaurus.

  This module provides a single source of truth for all timezone-related operations,
  ensuring consistent behavior across the application.

  ## Key Functions

  - `get_event_timezone/1` - Get timezone for an event based on venue coordinates
  - `get_venue_timezone/1` - Get timezone for a venue based on coordinates
  - `get_timezone_from_coordinates/2` - Get timezone from lat/lng coordinates

  ## Fallback Behavior

  When timezone cannot be determined (missing coordinates, TzWorld lookup fails),
  the module falls back to `"Europe/Warsaw"` as the default timezone since this
  is the primary market for the application.

  ## Usage

      # Get timezone for an event
      timezone = TimezoneUtils.get_event_timezone(event)

      # Get timezone for a venue directly
      timezone = TimezoneUtils.get_venue_timezone(venue)

      # Get timezone from coordinates
      timezone = TimezoneUtils.get_timezone_from_coordinates(52.2297, 21.0122)
  """

  require Logger

  @default_timezone "Europe/Warsaw"

  @doc """
  Returns the default timezone used as fallback when timezone cannot be determined.

  Currently returns "Europe/Warsaw" as the primary market for the application.
  """
  @spec default_timezone() :: String.t()
  def default_timezone, do: @default_timezone

  @doc """
  Gets the timezone for an event based on its venue's coordinates.

  Uses TzWorld to determine timezone from venue latitude/longitude.
  Falls back to default timezone if coordinates are missing or lookup fails.

  ## Parameters

  - `event` - An event struct or map with a nested venue containing coordinates

  ## Returns

  IANA timezone string (e.g., "Europe/Warsaw", "America/New_York")

  ## Examples

      iex> get_event_timezone(%{venue: %{latitude: 50.0647, longitude: 19.9450}})
      "Europe/Warsaw"

      iex> get_event_timezone(%{venue: nil})
      "Europe/Warsaw"

      iex> get_event_timezone(nil)
      "Europe/Warsaw"
  """
  @spec get_event_timezone(map() | nil) :: String.t()
  def get_event_timezone(%{venue: %{latitude: lat, longitude: lng}})
      when is_number(lat) and is_number(lng) do
    get_timezone_from_coordinates(lat, lng)
  end

  def get_event_timezone(%{venue: venue}) when is_map(venue) do
    get_venue_timezone(venue)
  end

  def get_event_timezone(_), do: @default_timezone

  @doc """
  Gets the timezone for a venue based on its coordinates.

  ## Parameters

  - `venue` - A venue struct or map with latitude and longitude fields

  ## Returns

  IANA timezone string

  ## Examples

      iex> get_venue_timezone(%{latitude: 50.0647, longitude: 19.9450})
      "Europe/Warsaw"

      iex> get_venue_timezone(%{latitude: nil, longitude: nil})
      "Europe/Warsaw"
  """
  @spec get_venue_timezone(map() | nil) :: String.t()
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

  ## Examples

      iex> create_datetime_for_event(~D[2024-01-15], ~T[19:30:00], %{venue: %{latitude: 50.0647, longitude: 19.9450}})
      {:ok, #DateTime<2024-01-15 19:30:00+01:00 CET Europe/Warsaw>}
  """
  @spec create_datetime_for_event(Date.t(), Time.t(), map()) ::
          {:ok, DateTime.t()} | {:error, atom()}
  def create_datetime_for_event(%Date{} = date, %Time{} = time, event) do
    timezone = get_event_timezone(event)
    DateTime.new(date, time, timezone)
  end

  @doc """
  Creates a DateTime from date, time, and event context, raising on error.

  Same as `create_datetime_for_event/3` but raises on failure.
  """
  @spec create_datetime_for_event!(Date.t(), Time.t(), map()) :: DateTime.t()
  def create_datetime_for_event!(%Date{} = date, %Time{} = time, event) do
    timezone = get_event_timezone(event)
    DateTime.new!(date, time, timezone)
  end
end
