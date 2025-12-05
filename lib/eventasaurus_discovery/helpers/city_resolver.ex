defmodule EventasaurusDiscovery.Helpers.CityResolver do
  @moduledoc """
  Offline city name resolution using reverse geocoding.

  This module provides cost-free city name resolution from GPS coordinates using
  the `geocoding` library which contains 156,710+ cities from GeoNames database.

  ## Features
  - 100% offline, zero API costs
  - Fast k-d tree lookups (<1ms typical)
  - Built-in validation to prevent garbage city names
  - Comprehensive error handling with logging

  ## Usage

      iex> CityResolver.resolve_city(40.7128, -74.0060)
      {:ok, "New York"}

      iex> CityResolver.resolve_city(51.5074, -0.1278)
      {:ok, "London"}

      iex> CityResolver.validate_city_name("New York")
      {:ok, "New York"}

      iex> CityResolver.validate_city_name("SW18 2SS")
      {:error, :invalid_city_name}

  ## Validation Rules
  Rejects city names that are:
  - UK/US postcodes (e.g., "SW18 2SS", "90210") or contain embedded postcodes (e.g., "England E5 8NN")
  - Street addresses (containing numbers + street keywords)
  - Pure numeric values
  - Empty or whitespace-only strings
  """

  require Logger

  @doc """
  Resolves both city name and ISO country code from GPS coordinates.

  This function returns the country code that the geocoding library provides,
  allowing callers to use the Countries library to get the full country name.

  ## Parameters
  - `latitude` - Float, GPS latitude coordinate
  - `longitude` - Float, GPS longitude coordinate

  ## Returns
  - `{:ok, {city_name, country_code}}` - Successfully resolved city and ISO 2-letter country code
  - `{:error, :missing_coordinates}` - Missing or invalid coordinates
  - `{:error, :not_found}` - No city found near coordinates
  - `{:error, :invalid_city_name}` - Found city failed validation

  ## Examples

      iex> CityResolver.resolve_city_and_country(51.8985, -8.4756)
      {:ok, {"Cork", "IE"}}

      iex> CityResolver.resolve_city_and_country(51.5074, -0.1278)
      {:ok, {"London", "GB"}}

      iex> CityResolver.resolve_city_and_country(40.7128, -74.0060)
      {:ok, {"New York", "US"}}
  """
  @spec resolve_city_and_country(float() | nil, float() | nil) ::
          {:ok, {String.t(), String.t()}} | {:error, atom()}
  def resolve_city_and_country(latitude, longitude)
      when is_float(latitude) and is_float(longitude) do
    try do
      case :geocoding.reverse(latitude, longitude) do
        {:ok, {_continent, country_code, city_binary, _distance}} ->
          city_name = to_string(city_binary)
          # Uppercase country code to match ISO 3166-1 alpha-2 standard
          country = country_code |> to_string() |> String.upcase()

          case validate_city_name(city_name) do
            {:ok, validated_name} ->
              {:ok, {validated_name, country}}

            {:error, reason} ->
              Logger.warning(
                "City name failed validation: #{inspect(city_name)} (#{latitude}, #{longitude}) - #{reason}"
              )

              {:error, :invalid_city_name}
          end

        {:error, _reason} ->
          Logger.debug("No city found for coordinates: #{latitude}, #{longitude}")
          {:error, :not_found}

        other ->
          Logger.warning(
            "Unexpected geocoding response: #{inspect(other)} for coordinates: #{latitude}, #{longitude}"
          )

          {:error, :not_found}
      end
    rescue
      error ->
        Logger.error("Geocoding library error for (#{latitude}, #{longitude}): #{inspect(error)}")

        {:error, :geocoding_error}
    end
  end

  def resolve_city_and_country(nil, _longitude), do: {:error, :missing_coordinates}
  def resolve_city_and_country(_latitude, nil), do: {:error, :missing_coordinates}

  def resolve_city_and_country(latitude, longitude) do
    Logger.warning("Invalid coordinate types: #{inspect(latitude)}, #{inspect(longitude)}")

    {:error, :invalid_coordinates}
  end

  @doc """
  Resolves a city name from GPS coordinates using offline reverse geocoding.

  ## Parameters
  - `latitude` - Float or nil, GPS latitude coordinate
  - `longitude` - Float or nil, GPS longitude coordinate

  ## Returns
  - `{:ok, city_name}` - Successfully resolved and validated city name
  - `{:error, :missing_coordinates}` - Missing or invalid coordinates
  - `{:error, :not_found}` - No city found near coordinates
  - `{:error, :invalid_city_name}` - Found city failed validation (likely garbage)

  ## Examples

      iex> CityResolver.resolve_city(40.7128, -74.0060)
      {:ok, "New York"}

      iex> CityResolver.resolve_city(nil, nil)
      {:error, :missing_coordinates}

      iex> CityResolver.resolve_city(0.0, 0.0)
      {:error, :not_found}
  """
  @spec resolve_city(float() | nil, float() | nil) ::
          {:ok, String.t()} | {:error, atom()}
  def resolve_city(latitude, longitude)
      when is_float(latitude) and is_float(longitude) do
    try do
      case :geocoding.reverse(latitude, longitude) do
        # Library returns {:ok, {continent, country_code, city_name, distance}}
        {:ok, {_continent, _country_code, city_binary, _distance}} ->
          city_name = to_string(city_binary)

          case validate_city_name(city_name) do
            {:ok, validated_name} ->
              {:ok, validated_name}

            {:error, reason} ->
              Logger.warning(
                "City name failed validation: #{inspect(city_name)} (#{latitude}, #{longitude}) - #{reason}"
              )

              {:error, :invalid_city_name}
          end

        # No city found at coordinates
        {:error, _reason} ->
          Logger.debug("No city found for coordinates: #{latitude}, #{longitude}")
          {:error, :not_found}

        # Unexpected response format
        other ->
          Logger.warning(
            "Unexpected geocoding response: #{inspect(other)} for coordinates: #{latitude}, #{longitude}"
          )

          {:error, :not_found}
      end
    rescue
      error ->
        Logger.error("Geocoding library error for (#{latitude}, #{longitude}): #{inspect(error)}")

        {:error, :geocoding_error}
    end
  end

  def resolve_city(nil, _longitude), do: {:error, :missing_coordinates}
  def resolve_city(_latitude, nil), do: {:error, :missing_coordinates}

  def resolve_city(latitude, longitude) do
    Logger.warning("Invalid coordinate types: #{inspect(latitude)}, #{inspect(longitude)}")

    {:error, :invalid_coordinates}
  end

  @doc """
  Validates a city name to prevent garbage data.

  Rejects names that match patterns for:
  - UK/US postcodes (e.g., "SW18 2SS", "90210", "12345-6789") or contain embedded postcodes (e.g., "England E5 8NN", "London W1F 8PU")
  - Street addresses (e.g., "123 Main Street", "76 Narrow Street")
  - Pure numeric values
  - Empty/whitespace strings
  - Single character names (likely abbreviations)

  ## Parameters
  - `name` - String to validate as a city name

  ## Returns
  - `{:ok, name}` - Valid city name
  - `{:error, :empty_name}` - Empty or whitespace-only
  - `{:error, :too_short}` - Single character (likely abbreviation)
  - `{:error, :contains_postcode}` - Contains UK postcode pattern anywhere in string
  - `{:error, :street_address_pattern}` - Matches street address pattern
  - `{:error, :numeric_only}` - Pure numeric value

  ## Examples

      iex> CityResolver.validate_city_name("New York")
      {:ok, "New York"}

      iex> CityResolver.validate_city_name("SW18 2SS")
      {:error, :contains_postcode}

      iex> CityResolver.validate_city_name("England E5 8NN")
      {:error, :contains_postcode}

      iex> CityResolver.validate_city_name("123 Main Street")
      {:error, :street_address_pattern}

      iex> CityResolver.validate_city_name("90210")
      {:error, :contains_postcode}
  """
  @spec validate_city_name(String.t() | nil) :: {:ok, String.t()} | {:error, atom()}
  def validate_city_name(name) when is_binary(name) do
    trimmed = String.trim(name)

    cond do
      # Empty or whitespace-only
      trimmed == "" ->
        {:error, :empty_name}

      # Single character (likely abbreviation or error)
      String.length(trimmed) == 1 ->
        {:error, :too_short}

      # UK postcode pattern - detects postcodes ANYWHERE in string (e.g., "SW18 2SS", "England E5 8NN")
      Regex.match?(~r/[A-Z]{1,2}\d{1,2}[A-Z]?\s*\d[A-Z]{2}/i, trimmed) ->
        {:error, :contains_postcode}

      # Street address pattern (starts with number + contains street keywords)
      Regex.match?(
        ~r/^\d+\s+.*(street|road|avenue|lane|drive|way|court|place|boulevard|st|rd|ave|ln|dr|blvd)/i,
        trimmed
      ) ->
        {:error, :street_address_pattern}

      # Pure numeric (likely postcode or address number)
      Regex.match?(~r/^\d+$/, trimmed) ->
        {:error, :contains_postcode}

      # Likely venue name pattern (contains "at", "bar", "pub", etc.)
      Regex.match?(~r/\b(at|bar|pub|restaurant|cafe|hotel|inn)\b/i, trimmed) ->
        {:error, :venue_name_pattern}

      # Valid city name
      true ->
        {:ok, trimmed}
    end
  end

  def validate_city_name(nil), do: {:error, :empty_name}

  def validate_city_name(name) do
    Logger.warning("Invalid city name type: #{inspect(name)}")
    {:error, :invalid_type}
  end
end
