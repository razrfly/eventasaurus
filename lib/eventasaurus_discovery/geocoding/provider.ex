defmodule EventasaurusDiscovery.Geocoding.Provider do
  @moduledoc """
  Behavior that all geocoding providers must implement.

  This defines the contract for pluggable geocoding services.
  Each provider (Mapbox, HERE, OpenStreetMap, etc.) implements this behavior.

  ## Example Provider Implementation

      defmodule EventasaurusDiscovery.Geocoding.Providers.Mapbox do
        @behaviour EventasaurusDiscovery.Geocoding.Provider

        @impl true
        def name, do: "mapbox"

        @impl true
        def geocode(address) do
          # Make API call to Mapbox
          # Parse response
          # Return standardized result
        end
      end
  """

  @type geocode_result :: %{
          latitude: float(),
          longitude: float(),
          city: String.t(),
          country: String.t()
        }

  @doc """
  Returns the name of the provider as a string.

  This name is used in metadata tracking and logging.

  ## Examples

      iex> MyProvider.name()
      "mapbox"
  """
  @callback name() :: String.t()

  @doc """
  Geocodes an address string to extract coordinates and location information.

  ## Parameters
  - `address` - Full address string to geocode (e.g., "123 Main St, London, UK")

  ## Returns
  - `{:ok, result}` - Success with standardized geocode result
  - `{:error, reason}` - Failure with error reason

  ## Error Reasons
  - `:rate_limited` - Provider rate limit exceeded
  - `:api_error` - Provider API returned error
  - `:timeout` - Request timed out
  - `:invalid_response` - Could not parse provider response
  - `:no_results` - Provider found no results for address
  """
  @callback geocode(address :: String.t()) ::
              {:ok, geocode_result()} | {:error, atom()}
end
