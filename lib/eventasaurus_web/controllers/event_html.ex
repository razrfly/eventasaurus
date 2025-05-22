defmodule EventasaurusWeb.EventHTML do
  use EventasaurusWeb, :html

  embed_templates "event_html/*"

  # No need for explicit render functions as Phoenix 1.7+ handles this automatically
  # when using embed_templates

  # Helper function to format datetime
  def format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%A, %B %d · %I:%M %p")
    |> String.replace(" 0", " ")
  end
  def format_datetime(_), do: "Date not set"
end
