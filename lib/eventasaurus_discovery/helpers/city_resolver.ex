defmodule EventasaurusDiscovery.Helpers.CityResolver do
  @moduledoc """
  Offline city name resolution using reverse geocoding and GeoNames validation.

  This module provides cost-free city name resolution from GPS coordinates using
  the `geocoding` library which contains 165,602+ cities from GeoNames database.

  ## Features
  - 100% offline, zero API costs
  - Fast k-d tree lookups (<1ms typical)
  - Positive validation using authoritative GeoNames database
  - Prevents garbage city names (street addresses, postcodes, etc.)
  - Comprehensive error handling with logging

  ## Usage

      iex> CityResolver.resolve_city(40.7128, -74.0060)
      {:ok, "New York"}

      iex> CityResolver.resolve_city(51.5074, -0.1278)
      {:ok, "London"}

      iex> CityResolver.validate_city_name("London", "GB")
      {:ok, "London"}

      iex> CityResolver.validate_city_name("10-16 Botchergate", "GB")
      {:error, :not_a_valid_city}

  ## Validation Approach
  Uses POSITIVE VALIDATION instead of regex patterns:
  - Checks if name exists in GeoNames database of 165,602+ real cities
  - Works for all countries equally (GB, AU, US, etc.)
  - Rejects street addresses, postcodes, and invalid names automatically
  - Zero maintenance needed (authoritative database)
  """

  require Logger

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
        {:ok, {_continent, country_code, city_binary, _distance}} ->
          city_name = to_string(city_binary)
          country_code_str = to_string(country_code)

          case validate_city_name(city_name, country_code_str) do
            {:ok, validated_name} ->
              {:ok, validated_name}

            {:error, reason} ->
              Logger.warning(
                "City name failed validation: #{inspect(city_name)} (#{latitude}, #{longitude}) in #{country_code_str} - #{reason}"
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
  Validates city name by checking GeoNames database.

  Uses POSITIVE VALIDATION instead of negative regex patterns.
  Checks if the name is a real city in the authoritative GeoNames database
  of 165,602+ cities worldwide.

  ## Parameters
  - `name` - City name to validate
  - `country_code` - ISO 3166-1 alpha-2 country code (e.g., "GB", "US", "AU")

  ## Returns
  - `{:ok, validated_name}` - City exists in GeoNames database
  - `{:error, :empty_name}` - Empty or whitespace-only
  - `{:error, :too_short}` - Single character
  - `{:error, :not_a_valid_city}` - Not found in GeoNames database

  ## Examples

      iex> CityResolver.validate_city_name("London", "GB")
      {:ok, "London"}

      iex> CityResolver.validate_city_name("10-16 Botchergate", "GB")
      {:error, :not_a_valid_city}

      iex> CityResolver.validate_city_name("425 Burwood Hwy", "AU")
      {:error, :not_a_valid_city}
  """
  @spec validate_city_name(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, atom()}
  def validate_city_name(name, country_code) when is_binary(name) and is_binary(country_code) do
    trimmed = String.trim(name)

    cond do
      # Empty or whitespace-only
      trimmed == "" ->
        {:error, :empty_name}

      # Single character (likely abbreviation or error)
      String.length(trimmed) == 1 ->
        {:error, :too_short}

      # Check if it's a REAL CITY in GeoNames database (positive validation)
      true ->
        case lookup_in_geonames(trimmed, country_code) do
          {:ok, _geonames_data} ->
            # City exists in authoritative database
            {:ok, trimmed}

          {:error, :not_found} ->
            # Not a real city (catches ALL invalid inputs: addresses, postcodes, garbage)
            Logger.debug(
              "City name validation failed: '#{trimmed}' not found in GeoNames for country #{country_code}"
            )

            {:error, :not_a_valid_city}
        end
    end
  end

  def validate_city_name(nil), do: {:error, :empty_name}

  # Backward compatibility - if country not provided, return error
  # All callers should be updated to provide country_code
  def validate_city_name(name) when is_binary(name) do
    # Check for empty/whitespace before returning country_required
    trimmed = String.trim(name)

    cond do
      trimmed == "" ->
        {:error, :empty_name}

      String.length(trimmed) == 1 ->
        {:error, :too_short}

      true ->
        Logger.warning(
          "validate_city_name/1 called without country_code - update caller to use validate_city_name/2"
        )

        {:error, :country_required}
    end
  end

  def validate_city_name(name) do
    Logger.warning("Invalid city name type: #{inspect(name)}")
    {:error, :invalid_type}
  end

  # Use the existing :geocoding library's lookup function
  # This library is already in mix.exs:148 and contains 165,602 cities
  defp lookup_in_geonames(city_name, country_code) do
    # :geocoding.lookup requires:
    # - Country code as uppercase atom (e.g., :GB, :US, :AU)
    # - City name as lowercase binary
    country_atom = country_code |> String.upcase() |> String.to_atom()
    city_binary = city_name |> String.downcase()

    try do
      case :geocoding.lookup(country_atom, city_binary) do
        # Success: {:ok, {geoname_id, {lat, lng}, continent, country_code, city_name}}
        {:ok, {_geoname_id, {_lat, _lng}, _continent, _country, _city}} ->
          {:ok, :found}

        # Not found in database (library returns :none atom, not {:error, ...})
        :none ->
          {:error, :not_found}

        # Unexpected response
        other ->
          Logger.warning(
            "Unexpected GeoNames lookup response for '#{city_name}', #{country_code}: #{inspect(other)}"
          )

          {:error, :not_found}
      end
    rescue
      error ->
        Logger.error(
          "GeoNames lookup error for '#{city_name}', #{country_code}: #{inspect(error)}"
        )

        {:error, :not_found}
    end
  end
end
