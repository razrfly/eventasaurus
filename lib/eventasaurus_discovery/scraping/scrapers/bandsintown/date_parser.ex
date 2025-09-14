defmodule EventasaurusDiscovery.Scraping.Scrapers.Bandsintown.DateParser do
  @moduledoc """
  Date parsing utilities for Bandsintown events.

  Handles various date formats that appear in Bandsintown data:
  - Full ISO 8601 datetime (e.g., "2025-09-14T16:00:00")
  - Date only (e.g., "2025-09-14")
  - Other formats via comprehensive parser fallback
  """

  @doc """
  Parses a start date string into a UTC DateTime.

  For date-only strings, sets time to midnight (00:00:00) UTC.
  For datetime strings, preserves the time and converts to UTC.

  ## Examples

      iex> parse_start_date("2025-09-14")
      ~U[2025-09-14 00:00:00Z]

      iex> parse_start_date("2025-09-14T16:00:00")
      ~U[2025-09-14 16:00:00Z]
  """
  def parse_start_date(date_string) when is_binary(date_string) do
    parse_date_with_default_time(date_string, ~T[00:00:00])
  end
  def parse_start_date(_), do: nil

  @doc """
  Parses an end date string into a UTC DateTime.

  For date-only strings, sets time to end of day (23:59:59) UTC.
  For datetime strings, preserves the time and converts to UTC.

  ## Examples

      iex> parse_end_date("2025-09-14")
      ~U[2025-09-14 23:59:59Z]

      iex> parse_end_date("2025-09-14T16:00:00")
      ~U[2025-09-14 16:00:00Z]
  """
  def parse_end_date(date_string) when is_binary(date_string) do
    parse_date_with_default_time(date_string, ~T[23:59:59])
  end
  def parse_end_date(_), do: nil

  # Private helper function that handles the actual parsing logic
  defp parse_date_with_default_time(date_string, default_time) do
    cond do
      # Full ISO 8601 datetime (e.g., "2025-09-14T16:00:00")
      String.contains?(date_string, "T") ->
        parse_iso8601_datetime(date_string)

      # Date only (e.g., "2025-09-14")
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, date_string) ->
        parse_date_only(date_string, default_time)

      # Other formats - try comprehensive parsing
      true ->
        # Fall back to general date parser if available
        if function_exported?(EventasaurusDiscovery.Scraping.Helpers.DateParser, :parse_datetime, 1) do
          EventasaurusDiscovery.Scraping.Helpers.DateParser.parse_datetime(date_string)
        else
          nil
        end
    end
  end

  defp parse_iso8601_datetime(datetime_string) do
    # Try with timezone first
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _} ->
        datetime
      _ ->
        # If no timezone, assume UTC and add Z
        case DateTime.from_iso8601(datetime_string <> "Z") do
          {:ok, datetime, _} ->
            datetime
          _ ->
            # Last resort: parse as NaiveDateTime and convert to UTC
            case NaiveDateTime.from_iso8601(datetime_string) do
              {:ok, naive_dt} ->
                DateTime.from_naive!(naive_dt, "Etc/UTC")
              _ ->
                nil
            end
        end
    end
  end

  defp parse_date_only(date_string, default_time) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        DateTime.new!(date, default_time, "Etc/UTC")
      _ ->
        nil
    end
  end
end