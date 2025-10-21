defmodule EventasaurusDiscovery.Geocoding.MultiProvider do
  @moduledoc """
  Behavior for providers that support multiple operations (geocoding, images, reviews, hours).

  This is the evolution of the single-operation Provider behavior, allowing providers
  to support multiple capabilities through a unified interface.

  ## Supported Operations

  - **Geocoding**: Convert address to coordinates and location data
  - **Images**: Retrieve venue images with URLs and metadata
  - **Reviews**: Get venue reviews and ratings
  - **Hours**: Fetch operating hours and special schedules

  ## Provider Capabilities

  Each provider declares which operations it supports via the `capabilities/0` callback.
  Only declare capabilities that are actually implemented.

  ## Example Provider Implementation

      defmodule EventasaurusDiscovery.Geocoding.Providers.Foursquare do
        @behaviour EventasaurusDiscovery.Geocoding.MultiProvider

        @impl true
        def name, do: "foursquare"

        @impl true
        def capabilities do
          %{
            "geocoding" => true,
            "images" => true,
            "reviews" => false,
            "hours" => false
          }
        end

        @impl true
        def geocode(address) do
          # Implementation
        end

        @impl true
        def get_images(place_id) do
          # Implementation
        end

        # reviews and hours not implemented (not in capabilities)
      end

  ## Return Value Standardization

  All callbacks must return standardized data structures to ensure consistency
  across providers. See individual callback documentation for exact formats.
  """

  # Type definitions for standardized results

  @type geocode_result :: %{
          latitude: float(),
          longitude: float(),
          city: String.t(),
          country: String.t(),
          # Optional: provider-specific place identifier
          provider_id: String.t() | nil
        }

  @type image_result :: %{
          url: String.t(),
          width: integer() | nil,
          height: integer() | nil,
          # Optional metadata
          attribution: String.t() | nil,
          source_url: String.t() | nil
        }

  @type review_result :: %{
          text: String.t(),
          rating: float() | nil,
          author: String.t() | nil,
          date: String.t() | nil
        }

  @type hours_result :: %{
          day_of_week: integer(),
          # 0 = Sunday, 6 = Saturday
          open_time: String.t(),
          # "09:00"
          close_time: String.t(),
          # "17:00"
          is_overnight: boolean()
        }

  @type capabilities :: %{
          optional(String.t()) => boolean()
        }

  # Callback definitions

  @doc """
  Returns the name of the provider as a string.

  This name must match the `name` field in the geocoding_providers database table.

  ## Examples

      iex> Foursquare.name()
      "foursquare"
  """
  @callback name() :: String.t()

  @doc """
  Returns a map indicating which operations this provider supports.

  Only include capabilities that are actually implemented. Missing capabilities
  are treated as false.

  ## Valid Capability Keys

  - `"geocoding"` - Address to coordinates conversion
  - `"images"` - Venue image retrieval
  - `"reviews"` - Venue review retrieval
  - `"hours"` - Operating hours retrieval

  ## Examples

      iex> Foursquare.capabilities()
      %{
        "geocoding" => true,
        "images" => true,
        "reviews" => false,
        "hours" => false
      }
  """
  @callback capabilities() :: capabilities()

  @doc """
  Geocodes an address string to extract coordinates and location information.

  **Required if** `capabilities()["geocoding"] == true`

  ## Parameters

  - `address` - Full address string to geocode (e.g., "123 Main St, London, UK")

  ## Returns

  - `{:ok, geocode_result()}` - Success with standardized result
  - `{:error, reason}` - Failure with error reason

  ## Error Reasons

  - `:rate_limited` - Provider rate limit exceeded
  - `:api_error` - Provider API returned error
  - `:timeout` - Request timed out
  - `:invalid_response` - Could not parse provider response
  - `:no_results` - Provider found no results for address
  - `:api_key_missing` - Required API key not configured
  """
  @callback geocode(address :: String.t()) ::
              {:ok, geocode_result()} | {:error, atom()}

  @doc """
  Retrieves images for a venue identified by provider-specific place ID.

  **Required if** `capabilities()["images"] == true`

  ## Parameters

  - `place_id` - Provider-specific place identifier

  ## Returns

  - `{:ok, [image_result()]}` - Success with list of images
  - `{:error, reason}` - Failure with error reason

  ## Error Reasons

  Same as `geocode/1` plus:
  - `:no_images` - Venue has no images
  """
  @callback get_images(place_id :: String.t()) ::
              {:ok, [image_result()]} | {:error, atom()}

  @doc """
  Retrieves reviews for a venue identified by provider-specific place ID.

  **Required if** `capabilities()["reviews"] == true`

  ## Parameters

  - `place_id` - Provider-specific place identifier

  ## Returns

  - `{:ok, [review_result()]}` - Success with list of reviews
  - `{:error, reason}` - Failure with error reason
  """
  @callback get_reviews(place_id :: String.t()) ::
              {:ok, [review_result()]} | {:error, atom()}

  @doc """
  Retrieves operating hours for a venue identified by provider-specific place ID.

  **Required if** `capabilities()["hours"] == true`

  ## Parameters

  - `place_id` - Provider-specific place identifier

  ## Returns

  - `{:ok, [hours_result()]}` - Success with list of hours (one per day of week)
  - `{:error, reason}` - Failure with error reason
  """
  @callback get_hours(place_id :: String.t()) ::
              {:ok, [hours_result()]} | {:error, atom()}

  # Optional callbacks - only required if capability is declared
  @optional_callbacks geocode: 1, get_images: 1, get_reviews: 1, get_hours: 1
end
