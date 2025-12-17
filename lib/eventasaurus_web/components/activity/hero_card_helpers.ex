defmodule EventasaurusWeb.Components.Activity.HeroCardHelpers do
  @moduledoc """
  Shared helper functions for activity hero cards.

  Provides common utilities used across GenericHeroCard, ConcertHeroCard,
  TriviaHeroCard, and other specialized hero card components.
  """

  @doc """
  Formats a datetime for display in hero cards.

  Returns nil if datetime is nil, otherwise formats using the provided format string.

  ## Examples

      iex> format_datetime(~U[2024-12-17 19:00:00Z], "%A, %B %d, %Y · %I:%M %p")
      "Tuesday, December 17, 2024 · 07:00 PM"

      iex> format_datetime(nil, "%A, %B %d")
      nil
  """
  @spec format_datetime(DateTime.t() | NaiveDateTime.t() | nil, String.t()) :: String.t() | nil
  def format_datetime(nil, _format), do: nil

  def format_datetime(datetime, format) do
    Calendar.strftime(datetime, format)
  end

  @doc """
  Extracts the city name from a venue struct.

  Handles nested city_ref association and returns nil if not available.

  ## Examples

      iex> get_city_name(%{city_ref: %{name: "Warsaw"}})
      "Warsaw"

      iex> get_city_name(%{city_ref: nil})
      nil
  """
  @spec get_city_name(map()) :: String.t() | nil
  def get_city_name(%{city_ref: %{name: name}}) when is_binary(name), do: name
  def get_city_name(_), do: nil

  @doc """
  Truncates text to a maximum length, adding ellipsis if truncated.

  Returns nil if text is nil. Preserves the full text if it's already
  shorter than the maximum length.

  ## Examples

      iex> truncate_text("Short text", 100)
      "Short text"

      iex> truncate_text("This is a very long text that exceeds the limit", 20)
      "This is a very long ..."

      iex> truncate_text(nil, 100)
      nil
  """
  @spec truncate_text(String.t() | nil, non_neg_integer()) :: String.t() | nil
  def truncate_text(nil, _max_length), do: nil

  def truncate_text(text, max_length) when is_binary(text) do
    if String.length(text) <= max_length do
      text
    else
      text
      |> String.slice(0, max_length)
      |> String.trim_trailing()
      |> Kernel.<>("...")
    end
  end

  def truncate_text(_, _), do: nil
end
