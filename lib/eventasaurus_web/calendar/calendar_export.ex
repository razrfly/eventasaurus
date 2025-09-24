defmodule EventasaurusWeb.CalendarExport do
  @moduledoc """
  Handles calendar export functionality for events.
  Generates ICS files and calendar-specific URLs for various platforms.
  """

  @doc """
  Generates an ICS file content for an event
  """
  def generate_ics(event, venue \\ nil, event_url)
  def generate_ics(%{start_at: nil}, _venue, _event_url), do: {:error, :missing_start_at}

  def generate_ics(event = %{start_at: %DateTime{}}, venue, event_url) do
    lines = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//Eventasaurus//Event Calendar//EN",
      "CALSCALE:GREGORIAN",
      "METHOD:PUBLISH",
      "BEGIN:VEVENT",
      "UID:#{event.id}@eventasaurus.app",
      "DTSTAMP:#{format_datetime_utc(DateTime.utc_now())}",
      "DTSTART:#{format_datetime_for_ics(event.start_at, event.timezone)}",
      "DTEND:#{format_datetime_for_ics(event.ends_at || add_default_duration(event.start_at), event.timezone)}",
      "SUMMARY:#{escape_ics_text(event.title)}",
      "DESCRIPTION:#{escape_ics_text(format_description(event, event_url))}",
      "LOCATION:#{escape_ics_text(format_location(event, venue))}",
      "URL:#{event_url}",
      "STATUS:CONFIRMED",
      "TRANSP:OPAQUE",
      "END:VEVENT",
      "END:VCALENDAR"
    ]

    Enum.join(lines, "\r\n")
  end

  @doc """
  Generates a Google Calendar URL for an event
  """
  def google_calendar_url(event, venue \\ nil, event_url)
  def google_calendar_url(%{start_at: nil}, _venue, _event_url), do: {:error, :missing_start_at}

  def google_calendar_url(event = %{start_at: %DateTime{}}, venue, event_url) do
    base_url = "https://calendar.google.com/calendar/render"

    # Format dates for Google Calendar (YYYYMMDDTHHmmssZ format)
    start_date = format_google_datetime(event.start_at, event.timezone)

    end_date =
      format_google_datetime(
        event.ends_at || add_default_duration(event.start_at),
        event.timezone
      )

    params = %{
      "action" => "TEMPLATE",
      "text" => event.title,
      "dates" => "#{start_date}/#{end_date}",
      "details" => format_description(event, event_url),
      "location" => format_location(event, venue),
      "sprop" => "website:#{event_url}"
    }

    "#{base_url}?#{URI.encode_query(params)}"
  end

  @doc """
  Generates an Outlook.com Calendar URL for an event
  """
  def outlook_calendar_url(event, venue \\ nil, event_url)
  def outlook_calendar_url(%{start_at: nil}, _venue, _event_url), do: {:error, :missing_start_at}

  def outlook_calendar_url(event = %{start_at: %DateTime{}}, venue, event_url) do
    base_url = "https://outlook.live.com/calendar/0/deeplink/compose"

    # Format dates for Outlook (ISO 8601 format)
    start_date = format_outlook_datetime(event.start_at, event.timezone)

    end_date =
      format_outlook_datetime(
        event.ends_at || add_default_duration(event.start_at),
        event.timezone
      )

    params = %{
      "subject" => event.title,
      "startdt" => start_date,
      "enddt" => end_date,
      "body" => format_description(event, event_url),
      "location" => format_location(event, venue),
      "path" => "/calendar/action/compose",
      "rru" => "addevent"
    }

    "#{base_url}?#{URI.encode_query(params)}"
  end

  # Private helper functions

  # Convert to UTC (using the provided timezone) and format for ICS
  defp format_datetime_for_ics(%DateTime{} = datetime, _timezone) do
    # Shift into UTC if needed
    dt =
      case DateTime.shift_zone(datetime, "Etc/UTC", Tzdata.TimeZoneDatabase) do
        {:ok, utc_dt} -> utc_dt
        # Fallback to original if shift fails
        _ -> datetime
      end

    Calendar.strftime(dt, "%Y%m%dT%H%M%SZ")
  end

  # Gracefully handle nil dates
  defp format_datetime_for_ics(nil, _timezone), do: nil

  defp format_datetime_utc(datetime) do
    Calendar.strftime(datetime, "%Y%m%dT%H%M%SZ")
  end

  defp format_google_datetime(datetime, _timezone) do
    # Google Calendar expects UTC times in YYYYMMDDTHHmmssZ format
    Calendar.strftime(datetime, "%Y%m%dT%H%M%SZ")
  end

  defp format_outlook_datetime(datetime, _timezone) do
    # Outlook expects ISO 8601 format
    DateTime.to_iso8601(datetime)
  end

  defp add_default_duration(start_datetime) do
    # Add 2 hours as default duration if no end time is specified
    DateTime.add(start_datetime, 2 * 60 * 60, :second)
  end

  defp format_description(event, event_url) do
    description = event.description || ""
    tagline = if event.tagline, do: "#{event.tagline}\n\n", else: ""

    """
    #{tagline}#{description}

    Event Details: #{event_url}
    """
    |> String.trim()
  end

  defp format_location(event, venue) do
    cond do
      event.is_virtual && event.virtual_venue_url ->
        "Online Event: #{event.virtual_venue_url}"

      venue && venue.name ->
        address_parts =
          [
            venue.name,
            venue.address,
            EventasaurusApp.Venues.Venue.city_name(venue),
            EventasaurusApp.Venues.Venue.country_name(venue)
          ]
          |> Enum.filter(&(&1 && &1 != ""))
          |> Enum.join(", ")

        address_parts

      true ->
        "Location TBD"
    end
  end

  defp escape_ics_text(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace(",", "\\,")
    |> String.replace(";", "\\;")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "")
  end
end
