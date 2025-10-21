defmodule EventasaurusWeb.Dev.UnsplashTestHTML do
  @moduledoc """
  HTML module for Unsplash testing page.
  """
  use EventasaurusWeb, :html

  embed_templates "unsplash_test_html/*"

  @doc """
  Format ISO8601 datetime string to human-readable format.
  """
  def format_date(nil), do: "Unknown"

  def format_date(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, datetime, _offset} ->
        Calendar.strftime(datetime, "%b %d, %Y %H:%M UTC")

      _ ->
        iso_string
    end
  end

  def format_date(_), do: "Invalid date"
end
