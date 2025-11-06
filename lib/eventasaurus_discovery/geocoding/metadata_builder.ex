defmodule EventasaurusDiscovery.Geocoding.MetadataBuilder do
  @moduledoc """
  Builds standardized geocoding metadata for all providers.

  This module provides a consistent interface for creating geocoding metadata
  across all geocoding methods (OSM, Google Maps, Google Places, etc).

  ## Metadata Structure

  All metadata includes:
  - `provider`: Which geocoding service was used
  - `cost_per_call`: Cost in USD for this geocoding operation
  - `geocoded_at`: Timestamp when geocoding occurred
  - `geocoding_failed`: Boolean indicating success/failure

  Provider-specific fields are added based on the geocoding method.

  ## Examples

      # OpenStreetMap metadata
      iex> MetadataBuilder.build_openstreetmap_metadata("London, UK")
      %{
        provider: "openstreetmap",
        cost_per_call: 0.0,
        geocoded_at: ~U[2025-01-11 10:30:00Z],
        original_address: "London, UK",
        fallback_used: false,
        geocoding_failed: false
      }

      # Google Places metadata
      iex> MetadataBuilder.build_google_places_metadata(%{"place_id" => "ChIJ..."})
      %{
        provider: "google_places",
        cost_per_call: 0.037,
        geocoded_at: ~U[2025-01-11 10:30:00Z],
        google_places_response: %{"place_id" => "ChIJ..."},
        geocoding_failed: false
      }
  """

  alias EventasaurusDiscovery.Geocoding.Pricing

  @doc """
  Builds metadata for OpenStreetMap/Nominatim geocoding.

  ## Parameters
  - `address` - The address that was geocoded

  ## Returns
  Map with OSM-specific metadata fields
  """
  def build_openstreetmap_metadata(address) do
    %{
      provider: "openstreetmap",
      geocoded_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      cost_per_call: Pricing.openstreetmap_cost(),
      original_address: address,
      fallback_used: false,
      geocoding_failed: false
    }
  end

  @doc """
  Builds metadata for Google Maps Geocoding API.

  This is typically used as a fallback when OSM fails.

  ## Parameters
  - `address` - The address that was geocoded
  - `attempts` - Number of retry attempts made (default: 1)

  ## Returns
  Map with Google Maps-specific metadata fields
  """
  def build_google_maps_metadata(address, attempts \\ 1) do
    %{
      provider: "google_maps",
      geocoded_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      cost_per_call: Pricing.google_maps_cost(),
      original_address: address,
      fallback_used: true,
      geocoding_attempts: attempts,
      geocoding_failed: false
    }
  end

  @doc """
  Builds metadata for Google Places API (Text Search + Details).

  Used by Kino Krakow and Resident Advisor when venues don't provide coordinates.

  ## Parameters
  - `google_response` - The full response from Google Places Details API

  ## Returns
  Map with Google Places-specific metadata fields
  """
  def build_google_places_metadata(google_response) do
    %{
      provider: "google_places",
      geocoded_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      cost_per_call: Pricing.google_places_cost(),
      google_places_response: google_response,
      geocoding_failed: false
    }
  end

  @doc """
  Builds metadata for venues with directly provided coordinates.

  No geocoding occurred - coordinates came from the source API/scraper.

  ## Returns
  Map indicating coordinates were provided (no geocoding cost)
  """
  def build_provided_coordinates_metadata do
    %{
      provider: "provided",
      cost_per_call: 0.0,
      geocoded_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      geocoding_failed: false
    }
  end

  @doc """
  Builds metadata for CityResolver offline geocoding.

  Used by Cinema City for reverse geocoding (coordinates → city name).

  ## Returns
  Map indicating offline geocoding was used (no cost)
  """
  def build_city_resolver_metadata do
    %{
      provider: "city_resolver_offline",
      cost_per_call: 0.0,
      geocoded_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      geocoding_failed: false
    }
  end

  @doc """
  Builds metadata for deferred geocoding (Karnet pattern).

  Venue was created with default coordinates and needs manual geocoding later.

  ## Returns
  Map indicating geocoding is pending
  """
  def build_deferred_geocoding_metadata do
    %{
      provider: "deferred",
      needs_manual_geocoding: true,
      cost_per_call: 0.0,
      geocoded_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      geocoding_failed: false
    }
  end

  @doc """
  Adds source scraper name to metadata.

  ## Parameters
  - `metadata` - Existing metadata map
  - `scraper` - Scraper name (e.g., "question_one", "kino_krakow")

  ## Examples

      iex> metadata = build_openstreetmap_metadata("London, UK")
      iex> add_scraper_source(metadata, "question_one")
      %{
        provider: "openstreetmap",
        source_scraper: "question_one",
        # ... other fields
      }
  """
  def add_scraper_source(metadata, scraper) when is_map(metadata) do
    Map.put(metadata, :source_scraper, scraper)
  end

  @doc """
  Marks metadata as failed and adds failure reason.

  ## Parameters
  - `metadata` - Existing metadata map
  - `reason` - Failure reason (atom or string)

  ## Examples

      iex> metadata = build_google_maps_metadata("Invalid Address", 3)
      iex> mark_failed(metadata, :geocoding_timeout)
      %{
        provider: "google_maps",
        geocoding_failed: true,
        failure_reason: "geocoding_timeout",
        # ... other fields
      }
  """
  def mark_failed(metadata, reason) when is_map(metadata) do
    metadata
    |> Map.put(:geocoding_failed, true)
    |> Map.put(:failure_reason, to_string(reason))
  end

  @doc """
  Updates deferred geocoding metadata after successful geocoding.

  Converts a deferred geocoding metadata to the actual provider used.

  ## Parameters
  - `deferred_metadata` - Original deferred metadata
  - `new_metadata` - Metadata from actual geocoding operation

  ## Examples

      iex> deferred = build_deferred_geocoding_metadata()
      iex> actual = build_google_places_metadata(%{"place_id" => "ChIJ..."})
      iex> resolve_deferred_geocoding(deferred, actual)
      %{
        provider: "google_places",
        cost_per_call: 0.037,
        needs_manual_geocoding: false,
        originally_deferred: true,
        deferred_at: ~U[2025-01-11 10:00:00Z],
        # ... other fields from actual geocoding
      }
  """
  def resolve_deferred_geocoding(deferred_metadata, new_metadata)
      when is_map(deferred_metadata) and is_map(new_metadata) do
    new_metadata
    |> Map.put(:needs_manual_geocoding, false)
    |> Map.put(:originally_deferred, true)
    |> Map.put(:deferred_at, deferred_metadata.geocoded_at)
  end

  @doc """
  Validates that metadata has all required fields.

  ## Parameters
  - `metadata` - Metadata map to validate

  ## Returns
  - `{:ok, metadata}` if valid
  - `{:error, reason}` if invalid
  """
  def validate(metadata) when is_map(metadata) do
    required_fields = [:provider, :cost_per_call, :geocoded_at, :geocoding_failed]

    missing_fields =
      required_fields
      |> Enum.reject(&Map.has_key?(metadata, &1))

    case missing_fields do
      [] ->
        {:ok, metadata}

      fields ->
        {:error, "Missing required fields: #{inspect(fields)}"}
    end
  end

  @doc """
  Returns a summary of metadata for logging/reporting.

  ## Parameters
  - `metadata` - Metadata map

  ## Returns
  String summary of key metadata fields

  ## Examples

      iex> metadata = build_google_places_metadata(%{"place_id" => "ChIJ123"})
      iex> summary(metadata)
      "provider=google_places cost=$0.037 failed=false"
  """
  def summary(metadata) when is_map(metadata) do
    provider = metadata[:provider] || "unknown"
    cost = metadata[:cost_per_call] || 0.0
    failed = metadata[:geocoding_failed] || false
    scraper = metadata[:source_scraper]

    base = "provider=#{provider} cost=$#{cost} failed=#{failed}"

    if scraper do
      "#{base} scraper=#{scraper}"
    else
      base
    end
  end
end
