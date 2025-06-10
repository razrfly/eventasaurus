defmodule EventasaurusWeb.EventHTML do
  use EventasaurusWeb, :html

  embed_templates "event_html/*"

  # No need for explicit render functions as Phoenix 1.7+ handles this automatically
  # when using embed_templates

  # Helper function to format datetime with timezone conversion
  def format_datetime(%DateTime{} = dt, timezone \\ nil) do
    converted_dt = if timezone do
      EventasaurusWeb.TimezoneHelpers.convert_to_timezone(dt, timezone)
    else
      dt
    end

    Calendar.strftime(converted_dt, "%A, %B %d · %I:%M %p")
    |> String.replace(" 0", " ")
  end
  def format_datetime(_, _), do: "Date not set"

  # Helper function to format time only
  def format_time(%DateTime{} = dt, timezone \\ nil) do
    converted_dt = if timezone do
      EventasaurusWeb.TimezoneHelpers.convert_to_timezone(dt, timezone)
    else
      dt
    end

    Calendar.strftime(converted_dt, "%I:%M %p")
    |> String.replace(" 0", " ")
  end
  def format_time(_, _), do: ""

  # Helper function to format date only
  def format_date(%DateTime{} = dt, timezone \\ nil) do
    converted_dt = if timezone do
      EventasaurusWeb.TimezoneHelpers.convert_to_timezone(dt, timezone)
    else
      dt
    end

    Calendar.strftime(converted_dt, "%A, %B %d")
  end
  def format_date(_, _), do: ""
end
