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
      # => "Wednesday, October 08, 2025 at 19:00"  (UK time)

      # Short format
      format_local_datetime(~U[2025-10-08 18:00:00Z], venue, :short)
      # => "Oct 08, 2025 • 19:00"

      # Time only
      format_local_datetime(~U[2025-10-08 18:00:00Z], venue, :time_only)
      # => "19:00"
  """
  def format_local_datetime(datetime, venue, format \\ :full)

  def format_local_datetime(%DateTime{} = datetime, venue, format) when not is_nil(venue) do
    timezone = TimezoneMapper.get_timezone_for_venue(venue)
    local_dt = TimezoneHelpers.convert_to_timezone(datetime, timezone)

    case format do
      :full ->
        Calendar.strftime(local_dt, "%A, %B %d, %Y at %H:%M")
        |> String.replace(" 0", " ")

      :short ->
        Calendar.strftime(local_dt, "%b %d, %Y • %H:%M")
        |> String.replace(" 0", " ")

      :time_only ->
        Calendar.strftime(local_dt, "%H:%M")

      :date_only ->
        Calendar.strftime(local_dt, "%A, %B %d, %Y")
        |> String.replace(" 0", " ")

      _ ->
        Calendar.strftime(local_dt, "%A, %B %d, %Y at %H:%M")
        |> String.replace(" 0", " ")
    end
  end

  # Fallback when venue is nil - format UTC time with indicator
  def format_local_datetime(%DateTime{} = datetime, nil, format) do
    formatted =
      case format do
        :full -> Calendar.strftime(datetime, "%A, %B %d, %Y at %H:%M UTC")
        :short -> Calendar.strftime(datetime, "%b %d, %Y • %H:%M UTC")
        :time_only -> Calendar.strftime(datetime, "%H:%M UTC")
        :date_only -> Calendar.strftime(datetime, "%A, %B %d, %Y")
        _ -> Calendar.strftime(datetime, "%A, %B %d, %Y at %H:%M UTC")
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
  Format exhibition datetime display.

  For exhibition-type events, returns a generic message as scraped dates are often unreliable.
  """
  def format_exhibition_datetime(%{occurrences: %{"type" => "exhibition"}}) do
    "Open dates vary"
  end

  def format_exhibition_datetime(_), do: nil
end
