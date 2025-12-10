defmodule EventasaurusDiscovery.Geocoding.Pricing do
  @moduledoc """
  Centralized pricing configuration for geocoding services.

  ## Pricing Sources
  - Google Maps Platform: https://developers.google.com/maps/billing-and-pricing/pricing
  - OpenStreetMap/Nominatim: Free (no API key required)

  ## Important Notes

  ### Google API Free Tier
  Google provides 0-10,000 requests/month FREE for most APIs.
  After 10,000 requests, the following rates apply:

  ### Pricing Tiers (10,001-100,000 requests)
  - Geocoding API: $5.00 per 1,000 requests
  - Places Text Search: $32.00 per 1,000 requests
  - Places Details: $5.00 per 1,000 requests

  ### Cost Calculation Strategy
  We use the **10,001-100,000 tier pricing** for all cost tracking because:
  1. First 10,000 requests/month are free (we exceed this easily)
  2. Our volume typically falls in the 10K-100K range
  3. Provides consistent month-to-month cost tracking
  4. Slightly overestimates costs (conservative budgeting)

  ## Pricing Verification
  Last verified: 2025-01-11

  **IMPORTANT**: Verify pricing periodically as Google may change rates.
  Check: https://developers.google.com/maps/billing-and-pricing/pricing
  """

  # Google Maps Geocoding API
  # Used by: QuestionOne (as fallback when OSM fails)
  # Pricing tier: 10,001-100,000 requests
  @google_maps_geocoding 0.005

  # Google Places API - Text Search
  # Used by: Repertuary, Resident Advisor (via VenueProcessor)
  # Pricing tier: 10,001-100,000 requests
  @google_places_text_search 0.032

  # Google Places API - Place Details
  # Used by: Repertuary, Resident Advisor (via VenueProcessor)
  # Pricing tier: 10,001-100,000 requests
  @google_places_details 0.005

  # Combined Google Places cost (Text Search + Details)
  # Most scrapers use both APIs in sequence
  @google_places_combined @google_places_text_search + @google_places_details

  # OpenStreetMap/Nominatim - Free
  # Used by: QuestionOne (primary), all scrapers (via AddressGeocoder fallback)
  @openstreetmap 0.0

  # CityResolver - Free (offline reverse geocoding)
  # Used by: Cinema City
  @city_resolver_offline 0.0

  # Pricing verification metadata
  @pricing_verified_at ~D[2025-01-11]
  @pricing_source "https://developers.google.com/maps/billing-and-pricing/pricing"

  @doc """
  Returns the cost per request for Google Maps Geocoding API.

  ## Examples

      iex> Pricing.google_maps_cost()
      0.005
  """
  def google_maps_cost, do: @google_maps_geocoding

  @doc """
  Returns the cost per request for Google Places Text Search.

  ## Examples

      iex> Pricing.google_places_text_search_cost()
      0.032
  """
  def google_places_text_search_cost, do: @google_places_text_search

  @doc """
  Returns the cost per request for Google Places Place Details.

  ## Examples

      iex> Pricing.google_places_details_cost()
      0.005
  """
  def google_places_details_cost, do: @google_places_details

  @doc """
  Returns the combined cost for Google Places (Text Search + Details).

  This is the most commonly used cost as most geocoding operations
  require both Text Search and Details API calls.

  ## Examples

      iex> Pricing.google_places_cost()
      0.037
  """
  def google_places_cost, do: @google_places_combined

  @doc """
  Returns the cost for OpenStreetMap/Nominatim geocoding.
  Always returns 0.0 as OSM is free.

  ## Examples

      iex> Pricing.openstreetmap_cost()
      0.0
  """
  def openstreetmap_cost, do: @openstreetmap

  @doc """
  Returns the cost for CityResolver offline geocoding.
  Always returns 0.0 as it uses local data.

  ## Examples

      iex> Pricing.city_resolver_cost()
      0.0
  """
  def city_resolver_cost, do: @city_resolver_offline

  @doc """
  Returns the date when pricing was last verified against Google's official docs.

  ## Examples

      iex> Pricing.pricing_verified_at()
      ~D[2025-01-11]
  """
  def pricing_verified_at, do: @pricing_verified_at

  @doc """
  Returns the URL of the pricing source for verification.

  ## Examples

      iex> Pricing.pricing_source()
      "https://developers.google.com/maps/billing-and-pricing/pricing"
  """
  def pricing_source, do: @pricing_source

  @doc """
  Returns all pricing information as a map for reporting.

  ## Examples

      iex> Pricing.all()
      %{
        google_maps_geocoding: 0.005,
        google_places_text_search: 0.032,
        google_places_details: 0.005,
        google_places_combined: 0.037,
        openstreetmap: 0.0,
        city_resolver_offline: 0.0,
        verified_at: ~D[2025-01-11],
        source: "https://developers.google.com/maps/billing-and-pricing/pricing"
      }
  """
  def all do
    %{
      google_maps_geocoding: @google_maps_geocoding,
      google_places_text_search: @google_places_text_search,
      google_places_details: @google_places_details,
      google_places_combined: @google_places_combined,
      openstreetmap: @openstreetmap,
      city_resolver_offline: @city_resolver_offline,
      verified_at: @pricing_verified_at,
      source: @pricing_source
    }
  end

  @doc """
  Returns a formatted pricing report for display.

  ## Examples

      iex> Pricing.report()
      \"\"\"
      Geocoding Service Pricing (Verified: 2025-01-11)

      Google Maps Geocoding: $0.005 per request
      Google Places Text Search: $0.032 per request
      Google Places Details: $0.005 per request
      Google Places Combined: $0.037 per request
      OpenStreetMap: $0.00 per request (FREE)
      CityResolver (offline): $0.00 per request (FREE)

      Source: https://developers.google.com/maps/billing-and-pricing/pricing
      \"\"\"
  """
  def report do
    """
    Geocoding Service Pricing (Verified: #{@pricing_verified_at})

    Google Maps Geocoding: $#{@google_maps_geocoding} per request
    Google Places Text Search: $#{@google_places_text_search} per request
    Google Places Details: $#{@google_places_details} per request
    Google Places Combined: $#{@google_places_combined} per request
    OpenStreetMap: $#{@openstreetmap} per request (FREE)
    CityResolver (offline): $#{@city_resolver_offline} per request (FREE)

    Source: #{@pricing_source}
    """
  end
end
