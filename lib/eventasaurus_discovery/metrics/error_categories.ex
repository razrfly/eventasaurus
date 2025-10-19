defmodule EventasaurusDiscovery.Metrics.ErrorCategories do
  @moduledoc """
  Standardized error categorization for event processing failures.

  Provides consistent error categories across all scrapers to enable
  aggregation, trending, and analysis.

  ## Error Categories

  - `:validation_error` - Missing required fields, invalid data format
  - `:geocoding_error` - Address geocoding failures, coordinate issues
  - `:venue_error` - Venue processing or matching failures
  - `:performer_error` - Performer/artist processing failures
  - `:category_error` - Category classification or matching failures
  - `:duplicate_error` - Duplicate event detection, unique constraint violations
  - `:network_error` - HTTP errors, timeouts, rate limits, API failures
  - `:data_quality_error` - Parse errors, encoding issues, malformed data
  - `:unknown_error` - Errors that don't match known patterns

  ## Usage

      iex> ErrorCategories.categorize_error("Event title is required")
      :validation_error

      iex> ErrorCategories.categorize_error("Failed to geocode address")
      :geocoding_error

      iex> ErrorCategories.categories()
      [:validation_error, :geocoding_error, :venue_error, ...]
  """

  @categories ~w(
    validation_error
    geocoding_error
    venue_error
    performer_error
    category_error
    duplicate_error
    network_error
    data_quality_error
    unknown_error
  )a

  @doc """
  Returns all available error categories.

  ## Examples

      iex> ErrorCategories.categories()
      [:validation_error, :geocoding_error, :venue_error, :performer_error,
       :category_error, :duplicate_error, :network_error, :data_quality_error,
       :unknown_error]
  """
  def categories, do: @categories

  @doc """
  Categorizes an error reason into a standardized category.

  Analyzes the error message or exception and maps it to one of the
  predefined categories based on pattern matching.

  ## Examples

      iex> categorize_error("Event title is required")
      :validation_error

      iex> categorize_error("Failed to geocode address")
      :geocoding_error

      iex> categorize_error("HTTP 429 - Rate limit exceeded")
      :network_error

      iex> categorize_error("Invalid JSON format")
      :data_quality_error
  """
  def categorize_error(error_reason) when is_binary(error_reason) do
    error_lower = String.downcase(error_reason)

    cond do
      # Validation errors - missing required fields, invalid data
      validation_error?(error_lower) ->
        :validation_error

      # Geocoding errors - address and coordinate issues
      geocoding_error?(error_lower) ->
        :geocoding_error

      # Venue errors - venue processing failures
      venue_error?(error_lower) ->
        :venue_error

      # Performer errors - artist/performer issues
      performer_error?(error_lower) ->
        :performer_error

      # Category errors - classification issues
      category_error?(error_lower) ->
        :category_error

      # Duplicate errors - unique constraint violations
      duplicate_error?(error_lower) ->
        :duplicate_error

      # Network errors - HTTP, API, connection issues
      network_error?(error_lower) ->
        :network_error

      # Data quality errors - parsing, encoding, format issues
      data_quality_error?(error_lower) ->
        :data_quality_error

      # Unknown - doesn't match any pattern
      true ->
        :unknown_error
    end
  end

  def categorize_error(%{__exception__: true} = exception) do
    categorize_error(Exception.message(exception))
  end

  def categorize_error(other) do
    categorize_error(inspect(other))
  end

  # Pattern matching functions for each category

  defp validation_error?(error_lower) do
    Enum.any?(
      [
        "is required",
        "missing required",
        "required field",
        "cannot be blank",
        "must be present",
        "validation failed",
        "invalid format",
        "must be",
        "should be"
      ],
      &String.contains?(error_lower, &1)
    )
  end

  defp geocoding_error?(error_lower) do
    Enum.any?(
      [
        "geocode",
        "geocoding",
        "address not found",
        "coordinates",
        "latitude",
        "longitude",
        "location not found"
      ],
      &String.contains?(error_lower, &1)
    )
  end

  defp venue_error?(error_lower) do
    Enum.any?(
      [
        "venue",
        "venue processing",
        "venue not found",
        "venue matching"
      ],
      &String.contains?(error_lower, &1)
    )
  end

  defp performer_error?(error_lower) do
    Enum.any?(
      [
        "performer",
        "artist",
        "performer processing",
        "artist not found"
      ],
      &String.contains?(error_lower, &1)
    )
  end

  defp category_error?(error_lower) do
    Enum.any?(
      [
        "category",
        "classification",
        "category not found",
        "category matching"
      ],
      &String.contains?(error_lower, &1)
    )
  end

  defp duplicate_error?(error_lower) do
    Enum.any?(
      [
        "duplicate",
        "already exists",
        "unique constraint",
        "uniqueness",
        "constraint violation"
      ],
      &String.contains?(error_lower, &1)
    )
  end

  defp network_error?(error_lower) do
    Enum.any?(
      [
        "http",
        "timeout",
        "rate limit",
        "api",
        "connection",
        "network",
        "429",
        "500",
        "502",
        "503",
        "504"
      ],
      &String.contains?(error_lower, &1)
    )
  end

  defp data_quality_error?(error_lower) do
    Enum.any?(
      [
        "parse",
        "parsing",
        "invalid json",
        "invalid xml",
        "malformed",
        "encoding",
        "decode",
        "format error"
      ],
      &String.contains?(error_lower, &1)
    )
  end
end
