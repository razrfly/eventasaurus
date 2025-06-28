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
end
