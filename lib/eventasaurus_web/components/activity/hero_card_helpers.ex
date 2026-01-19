defmodule EventasaurusWeb.Components.Activity.HeroCardHelpers do
  @moduledoc """
  Shared helper functions for activity hero cards.

  Provides common utilities used across GenericHeroCard, ConcertHeroCard,
  TriviaHeroCard, VenueHeroCard, VenueLocationCard, and other specialized
  hero card components.

  ## Categories

  - **Date/Time**: `format_datetime/2`
  - **Text**: `truncate_text/2`
  - **Location**: `get_city_name/1`, `get_country_name/1`, `has_coordinates?/1`,
    `google_maps_directions_url/1`, `format_venue_address/1`
  """

  @doc """
  Formats a datetime for display in hero cards.

  Returns nil if datetime is nil, otherwise formats using the provided format string.

  ## Examples

      iex> format_datetime(~U[2024-12-17 19:00:00Z], "%A, %B %d, %Y · %H:%M")
      "Tuesday, December 17, 2024 · 19:00"

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

  # ============================================================================
  # Location Helpers
  # ============================================================================

  @doc """
  Extracts the country name from a venue struct.

  Handles nested city_ref.country association and returns nil if not available.

  ## Examples

      iex> get_country_name(%{city_ref: %{country: %{name: "Poland"}}})
      "Poland"

      iex> get_country_name(%{city_ref: %{country: nil}})
      nil
  """
  @spec get_country_name(map()) :: String.t() | nil
  def get_country_name(%{city_ref: %{country: %{name: name}}}) when is_binary(name), do: name
  def get_country_name(_), do: nil

  @doc """
  Checks if a venue has valid coordinates.

  Returns true only if both latitude and longitude are numbers.

  ## Examples

      iex> has_coordinates?(%{latitude: 52.2297, longitude: 21.0122})
      true

      iex> has_coordinates?(%{latitude: nil, longitude: nil})
      false

      iex> has_coordinates?(%{})
      false
  """
  @spec has_coordinates?(map()) :: boolean()
  def has_coordinates?(%{latitude: lat, longitude: lon})
      when is_number(lat) and is_number(lon),
      do: true

  def has_coordinates?(_), do: false

  @doc """
  Generates a Google Maps directions URL for a venue.

  Uses coordinates if available, falls back to encoded address/name.
  Returns "#" if neither coordinates nor address are available.

  ## Examples

      iex> google_maps_directions_url(%{latitude: 52.2297, longitude: 21.0122})
      "https://www.google.com/maps/dir/?api=1&destination=52.2297,21.0122"

      iex> google_maps_directions_url(%{name: "Venue", address: "123 Street"})
      "https://www.google.com/maps/dir/?api=1&destination=Venue%2C%20123%20Street"

      iex> google_maps_directions_url(%{})
      "#"
  """
  @spec google_maps_directions_url(map()) :: String.t()
  def google_maps_directions_url(%{latitude: lat, longitude: lon})
      when is_number(lat) and is_number(lon) do
    "https://www.google.com/maps/dir/?api=1&destination=#{lat},#{lon}"
  end

  def google_maps_directions_url(%{address: address, name: name})
      when is_binary(address) and is_binary(name) do
    query = URI.encode("#{name}, #{address}")
    "https://www.google.com/maps/dir/?api=1&destination=#{query}"
  end

  def google_maps_directions_url(%{address: address}) when is_binary(address) do
    query = URI.encode(address)
    "https://www.google.com/maps/dir/?api=1&destination=#{query}"
  end

  def google_maps_directions_url(_), do: "#"

  @doc """
  Formats a venue's full address for display.

  Combines address, city name, and country name with commas.
  Returns nil if no address parts are available.

  ## Examples

      iex> format_venue_address(%{address: "123 Main St", city_ref: %{name: "Warsaw", country: %{name: "Poland"}}})
      "123 Main St, Warsaw, Poland"

      iex> format_venue_address(%{address: nil, city_ref: %{name: "Warsaw"}})
      "Warsaw"

      iex> format_venue_address(%{})
      nil
  """
  @spec format_venue_address(map()) :: String.t() | nil
  def format_venue_address(venue) do
    parts =
      [
        Map.get(venue, :address),
        get_city_name(venue),
        get_country_name(venue)
      ]
      |> Enum.filter(&(&1 && &1 != ""))
      |> Enum.join(", ")

    if parts == "", do: nil, else: parts
  end
end
