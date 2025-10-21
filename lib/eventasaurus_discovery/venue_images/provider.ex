defmodule EventasaurusDiscovery.VenueImages.Provider do
  @moduledoc """
  Behavior for venue image providers.

  Providers implement this behavior to fetch venue images from various sources
  (Google Places, Foursquare, HERE, Geoapify, Unsplash, etc.).

  Unlike geocoding which returns on first success, the image orchestrator aggregates
  results from ALL active providers and deduplicates by URL.
  """

  @type image_result :: %{
          url: String.t(),
          width: integer() | nil,
          height: integer() | nil,
          attribution: String.t() | nil,
          attribution_url: String.t() | nil
        }

  @type venue_input :: %{
          place_id: String.t() | nil,
          name: String.t(),
          latitude: float(),
          longitude: float(),
          provider_ids: map()
        }

  @doc """
  Returns the provider name (must match database name).
  """
  @callback name() :: String.t()

  @doc """
  Fetches images for a venue.

  Providers should:
  - Use provider_ids[provider_name] if available (avoids duplicate geocoding)
  - Fall back to geocoding if provider_id not available
  - Return structured image results with attribution
  - Handle rate limits and errors gracefully

  Returns {:ok, [image_result()]} or {:error, atom()}
  """
  @callback fetch_images(venue :: venue_input()) ::
              {:ok, [image_result()]} | {:error, atom()}

  @doc """
  Whether this provider supports direct place_id lookups.

  If true, provider can use provider_ids map directly without geocoding.
  If false, provider must geocode first to get its own place_id.
  """
  @callback supports_place_id?() :: boolean()
end
