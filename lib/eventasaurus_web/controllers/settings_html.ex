defmodule EventasaurusWeb.SettingsHTML do
  @moduledoc """
  This module contains pages rendered by SettingsController.

  See the `settings_html` directory for all templates.
  """
  use EventasaurusWeb, :html

  embed_templates "settings_html/*"

  @doc """
  Format connection dates for display in a user-friendly format.
  """
  def format_connection_date(nil), do: "Unknown"
  def format_connection_date("Unknown"), do: "Unknown"
  def format_connection_date(date_string) when is_binary(date_string) do
    try do
      case Date.from_iso8601(date_string) do
        {:ok, date} ->
          # Format as "January 15, 2024"
          Calendar.strftime(date, "%B %d, %Y")
        {:error, _} ->
          # Try parsing as datetime
          case DateTime.from_iso8601(date_string) do
            {:ok, datetime, _} ->
              Calendar.strftime(datetime, "%B %d, %Y")
            {:error, _} ->
              "Invalid date"
          end
      end
    rescue
      _ -> "Invalid date"
    end
  end
  def format_connection_date(_), do: "Unknown"

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
