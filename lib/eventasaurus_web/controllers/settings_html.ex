defmodule EventasaurusWeb.SettingsHTML do
  use EventasaurusWeb, :html

  embed_templates "settings_html/*"

  @doc """
  Format a connection date for display in the settings page.
  """
  def format_connection_date(date_string) do
    try do
      # Try to parse ISO8601 date first
      case Date.from_iso8601(date_string) do
        {:ok, date} ->
          date
          |> Date.to_string()
          |> format_date_string()

        {:error, _} ->
          # Try to parse as DateTime
          case DateTime.from_iso8601(date_string) do
            {:ok, datetime, _} ->
              datetime
              |> DateTime.to_date()
              |> Date.to_string()
              |> format_date_string()

            {:error, _} ->
              "Unknown"
          end
      end
    rescue
      _ -> "Unknown"
    end
  end

  defp format_date_string(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        # Format as "January 15, 2024"
        month_names = [
          "January", "February", "March", "April", "May", "June",
          "July", "August", "September", "October", "November", "December"
        ]

        month_name = Enum.at(month_names, date.month - 1, "Unknown")
        "#{month_name} #{date.day}, #{date.year}"

      {:error, _} ->
        "Unknown"
    end
  end
end
