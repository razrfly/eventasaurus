defmodule EventasaurusWeb.Dev.VenueImagesTestHTML do
  @moduledoc """
  HTML module for venue images testing page.
  """
  use EventasaurusWeb, :html

  embed_templates "venue_images_test_html/*"

  @doc """
  Format ISO8601 datetime string to human-readable format.
  """
  def format_date(nil), do: "Never"

  def format_date(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, datetime, _offset} ->
        Calendar.strftime(datetime, "%b %d, %Y %H:%M UTC")

      _ ->
        iso_string
    end
  end

  def format_date(_), do: "Invalid date"

  @doc """
  Format cost as currency with 4 decimal places.
  """
  def format_cost(cost) when is_float(cost) do
    "$#{:erlang.float_to_binary(cost, decimals: 4)}"
  end

  def format_cost(cost) when is_integer(cost) do
    "$#{:erlang.float_to_binary(cost / 1.0, decimals: 4)}"
  end

  def format_cost(_), do: "$0.0000"

  @doc """
  Format percentage with 2 decimal places.
  """
  def format_percentage(ratio) when is_float(ratio) do
    "#{Float.round(ratio, 2)}%"
  end

  def format_percentage(ratio) when is_integer(ratio) do
    "#{ratio}%"
  end

  def format_percentage(_), do: "0%"

  @doc """
  Format large numbers with commas for readability.
  """
  def format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/.{3}(?=.)/, "\\0,")
    |> String.reverse()
  end

  def format_number(num) when is_float(num) do
    format_number(trunc(num))
  end

  def format_number(_), do: "0"

  @doc """
  Format duration in seconds to human-readable format.
  """
  def format_duration(seconds) when is_integer(seconds) and seconds < 60 do
    "#{seconds}s"
  end

  def format_duration(seconds) when is_integer(seconds) and seconds < 3600 do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}m #{secs}s"
  end

  def format_duration(seconds) when is_integer(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{minutes}m"
  end

  def format_duration(_), do: "0s"

  @doc """
  Get status badge class based on boolean value.
  """
  def status_badge_class(true), do: "bg-green-100 text-green-800"
  def status_badge_class(false), do: "bg-red-100 text-red-800"

  @doc """
  Get status text.
  """
  def status_text(true), do: "Active"
  def status_text(false), do: "Inactive"

  @doc """
  Get freshness badge class based on staleness.
  """
  def freshness_badge_class(true), do: "bg-red-100 text-red-800"
  def freshness_badge_class(false), do: "bg-green-100 text-green-800"

  @doc """
  Get freshness text.
  """
  def freshness_text(true), do: "Stale"
  def freshness_text(false), do: "Fresh"

  @doc """
  Get ID source badge class based on source type.
  """
  def id_source_badge_class(:stored), do: "bg-blue-100 text-blue-800"
  def id_source_badge_class(:dynamic), do: "bg-yellow-100 text-yellow-800"
  def id_source_badge_class(:unavailable), do: "bg-gray-100 text-gray-800"
  def id_source_badge_class(_), do: "bg-gray-100 text-gray-800"

  @doc """
  Get ID source text.
  """
  def id_source_text(:stored), do: "Stored"
  def id_source_text(:dynamic), do: "Dynamic"
  def id_source_text(:unavailable), do: "Unavailable"
  def id_source_text(_), do: "Unknown"
end
