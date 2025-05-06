defmodule EventasaurusWeb.EventHTML do
  use EventasaurusWeb, :html

  embed_templates "event_html/*"

  # Helper function to format datetime
  def format_datetime(datetime) when is_struct(datetime) do
    Calendar.strftime(datetime, "%B %d, %Y at %I:%M %p")
  end
  def format_datetime(_), do: "Date not set"
end
