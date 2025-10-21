defmodule EventasaurusWeb.Helpers.PublicEventDisplayHelpers do
  @moduledoc """
  Unified datetime display helpers for PublicEvents.

  Handles timezone conversion from UTC storage to local event timezone
  based on venue location.
  """

  alias EventasaurusDiscovery.Helpers.TimezoneMapper
  alias EventasaurusWeb.TimezoneHelpers

  @doc """
  Format a PublicEvent datetime in the event's local timezone.

  Converts UTC datetime to the venue's local timezone and formats for display.

  ## Parameters
  - `datetime` - UTC datetime from database
  - `venue` - Venue struct with preloaded city_ref and country
  - `format` - Display format (:full, :short, :time_only, :date_only)

  ## Examples

      # Full format
      format_local_datetime(~U[2025-10-08 18:00:00Z], venue, :full)
      # => "Wednesday, October 08, 2025 at 07:00 PM"  (UK time)

      # Short format
      format_local_datetime(~U[2025-10-08 18:00:00Z], venue, :short)
      # => "Oct 08, 2025 • 07:00 PM"

      # Time only
      format_local_datetime(~U[2025-10-08 18:00:00Z], venue, :time_only)
      # => "07:00 PM"
  """
  def format_local_datetime(datetime, venue, format \\ :full)

  def format_local_datetime(%DateTime{} = datetime, venue, format) when not is_nil(venue) do
    timezone = TimezoneMapper.get_timezone_for_venue(venue)
    local_dt = TimezoneHelpers.convert_to_timezone(datetime, timezone)

    case format do
      :full ->
        Calendar.strftime(local_dt, "%A, %B %d, %Y at %I:%M %p")
        |> String.replace(" 0", " ")

      :short ->
        Calendar.strftime(local_dt, "%b %d, %Y • %I:%M %p")
        |> String.replace(" 0", " ")

      :time_only ->
        Calendar.strftime(local_dt, "%I:%M %p")
        |> String.replace(" 0", " ")

      :date_only ->
        Calendar.strftime(local_dt, "%A, %B %d, %Y")
        |> String.replace(" 0", " ")

      _ ->
        Calendar.strftime(local_dt, "%A, %B %d, %Y at %I:%M %p")
        |> String.replace(" 0", " ")
    end
  end

  # Fallback when venue is nil - format UTC time with indicator
  def format_local_datetime(%DateTime{} = datetime, nil, format) do
    formatted =
      case format do
        :full -> Calendar.strftime(datetime, "%A, %B %d, %Y at %I:%M %p UTC")
        :short -> Calendar.strftime(datetime, "%b %d, %Y • %I:%M %p UTC")
        :time_only -> Calendar.strftime(datetime, "%I:%M %p UTC")
        :date_only -> Calendar.strftime(datetime, "%A, %B %d, %Y")
        _ -> Calendar.strftime(datetime, "%A, %B %d, %Y at %I:%M %p UTC")
      end

    formatted |> String.replace(" 0", " ")
  end

  def format_local_datetime(nil, _, _), do: ""
  def format_local_datetime(_, _, _), do: ""

  @doc """
  Check if an event is an exhibition type based on its occurrences field.

  ## Examples

      iex> is_exhibition?(%{occurrences: %{"type" => "exhibition"}})
      true

      iex> is_exhibition?(%{occurrences: %{"type" => "explicit"}})
      false
  """
  def is_exhibition?(%{occurrences: %{"type" => "exhibition"}}), do: true
  def is_exhibition?(_), do: false

  @doc """
  Format exhibition date range for display.

  Shows "Month Day - Month Day, Year" or "Month Day, Year - Month Day, Year" format.

  ## Examples

      iex> format_exhibition_range(~D[2025-05-01], ~D[2025-06-30])
      "May 1 - June 30, 2025"

      iex> format_exhibition_range(~D[2024-12-15], ~D[2025-01-15])
      "December 15, 2024 - January 15, 2025"
  """
  def format_exhibition_range(%Date{} = start_date, %Date{} = end_date) do
    cond do
      # Same year - show range within year
      start_date.year == end_date.year ->
        start_str = Calendar.strftime(start_date, "%B %-d")
        end_str = Calendar.strftime(end_date, "%B %-d, %Y")
        "#{start_str} - #{end_str}"

      # Different years - show full dates
      true ->
        start_str = Calendar.strftime(start_date, "%B %-d, %Y")
        end_str = Calendar.strftime(end_date, "%B %-d, %Y")
        "#{start_str} - #{end_str}"
    end
  end

  def format_exhibition_range(%Date{} = start_date, nil) do
    # No end date - show "Starting Month Day, Year"
    Calendar.strftime(start_date, "Starting %B %-d, %Y")
  end

  def format_exhibition_range(nil, _), do: "Dates TBD"

  @doc """
  Format exhibition datetime from event occurrences.

  First tries to use the original date string from the source (as scraped),
  which is more accurate for exhibitions with unparseable dates.
  Falls back to parsed dates if original string is not available.
  """
  def format_exhibition_datetime(
        %{occurrences: %{"type" => "exhibition"}, sources: sources} = event
      )
      when is_list(sources) and length(sources) > 0 do
    # Try to get original_date_string from first source's metadata
    original_date =
      sources
      |> List.first()
      |> case do
        %{metadata: %{"original_date_string" => original}} when is_binary(original) ->
          String.slice(original, 0, 50)

        _ ->
          nil
      end

    if original_date do
      original_date
    else
      # Fallback to parsed dates from occurrences
      format_exhibition_datetime_from_occurrences(event)
    end
  end

  def format_exhibition_datetime(%{occurrences: %{"type" => "exhibition"}} = event) do
    # No sources preloaded - try to format from occurrences
    format_exhibition_datetime_from_occurrences(event)
  end

  def format_exhibition_datetime(_), do: nil

  # Private helper to format from parsed occurrence dates
  defp format_exhibition_datetime_from_occurrences(%{
         occurrences: %{"type" => "exhibition", "dates" => dates}
       })
       when is_list(dates) and length(dates) > 0 do
    first_date = List.first(dates)

    with {:ok, start_date} <- parse_date(first_date["date"]),
         end_date <- parse_optional_end_date(first_date["end_date"]) do
      format_exhibition_range(start_date, end_date)
    else
      _ -> "Exhibition dates available"
    end
  end

  defp format_exhibition_datetime_from_occurrences(_), do: "Exhibition dates available"

  # Private helpers

  defp parse_date(date_string) when is_binary(date_string) do
    Date.from_iso8601(date_string)
  end

  defp parse_date(_), do: {:error, :invalid_date}

  defp parse_optional_end_date(nil), do: nil
  defp parse_optional_end_date(""), do: nil

  defp parse_optional_end_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_optional_end_date(_), do: nil
end
