defmodule EventasaurusDiscovery.Sources.Bandsintown.DateParser do
  @moduledoc """
  Date parsing utilities for Bandsintown events.

  IMPORTANT: Uses venue timezone to convert local event times to UTC for storage.
  This ensures international events are stored with correct UTC times.

  Handles various date formats that appear in Bandsintown data:
  - Full ISO 8601 datetime (e.g., "2025-09-14T16:00:00")
  - Date only (e.g., "2025-09-14")
  - Other formats via comprehensive parser fallback
  """

  alias EventasaurusDiscovery.Scraping.Helpers.TimezoneConverter

  @doc """
  Parses a start date string into a UTC DateTime using the venue's timezone.

  For date-only strings, sets time to midnight in the venue's timezone, then converts to UTC.
  For datetime strings, treats the time as local to the venue timezone, then converts to UTC.

  ## Examples

      # Event in New York at midnight EST
      iex> parse_start_date("2025-09-14", "America/New_York")
      ~U[2025-09-14 04:00:00Z]  # Midnight EST = 4:00 AM UTC

      # Event in Warsaw at 4:00 PM
      iex> parse_start_date("2025-09-14T16:00:00", "Europe/Warsaw")
      ~U[2025-09-14 14:00:00Z]  # 4:00 PM CEST = 2:00 PM UTC

      # No timezone provided - defaults to UTC
      iex> parse_start_date("2025-09-14")
      ~U[2025-09-14 00:00:00Z]
  """
  def parse_start_date(date_string, venue_timezone \\ "Etc/UTC")

  def parse_start_date(date_string, venue_timezone) when is_binary(date_string) do
    parse_date_with_default_time(date_string, ~T[00:00:00], venue_timezone)
  end

  def parse_start_date(_, _), do: nil

  @doc """
  Parses an end date string into a UTC DateTime using the venue's timezone.

  For date-only strings, sets time to end of day (23:59:59) in the venue's timezone, then converts to UTC.
  For datetime strings, treats the time as local to the venue timezone, then converts to UTC.

  ## Examples

      # Event ends at 11:59 PM in New York
      iex> parse_end_date("2025-09-14", "America/New_York")
      ~U[2025-09-15 03:59:59Z]  # Next day, 3:59 AM UTC

      # Event ends at 4:00 PM in Warsaw
      iex> parse_end_date("2025-09-14T16:00:00", "Europe/Warsaw")
      ~U[2025-09-14 14:00:00Z]  # 4:00 PM CEST = 2:00 PM UTC
  """
  def parse_end_date(date_string, venue_timezone \\ "Etc/UTC")

  def parse_end_date(date_string, venue_timezone) when is_binary(date_string) do
    parse_date_with_default_time(date_string, ~T[23:59:59], venue_timezone)
  end

  def parse_end_date(_, _), do: nil

  # Private helper function that handles the actual parsing logic
  defp parse_date_with_default_time(date_string, default_time, venue_timezone) do
    cond do
      # Full ISO 8601 datetime (e.g., "2025-09-14T16:00:00")
      String.contains?(date_string, "T") ->
        # Use shared TimezoneConverter for consistent handling
        TimezoneConverter.parse_datetime_with_timezone(date_string, venue_timezone)

      # Date only (e.g., "2025-09-14")
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, date_string) ->
        parse_date_only(date_string, default_time, venue_timezone)

      # Other formats - try comprehensive parsing
      true ->
        # Fall back to general date parser if available
        if function_exported?(
             EventasaurusDiscovery.Scraping.Helpers.DateParser,
             :parse_datetime,
             1
           ) do
          # The general parser may not have timezone context, so parse first then convert
          case EventasaurusDiscovery.Scraping.Helpers.DateParser.parse_datetime(date_string) do
            %DateTime{} = dt ->
              # If we got a datetime, it's already in UTC from the general parser
              dt

            _ ->
              nil
          end
        else
          nil
        end
    end
  end

  defp parse_date_only(date_string, default_time, venue_timezone) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        # Create naive datetime and convert from venue timezone to UTC
        naive_dt = NaiveDateTime.new!(date, default_time)
        TimezoneConverter.convert_local_to_utc(naive_dt, venue_timezone)

      _ ->
        nil
    end
  end
end
