defmodule EventasaurusWeb.Services.RichDataProviderBehaviour do
  @moduledoc """
  Behaviour for rich data provider implementations.

  Defines the contract for external API providers that can supply
  comprehensive metadata for events. Each provider must implement
  these callbacks to integrate with the Rich Data Manager.

  ## Provider Requirements

  - Must provide search functionality
  - Must provide detailed data fetching
  - Must implement caching and rate limiting
  - Must handle errors gracefully
  - Must return structured data in a consistent format

  ## Data Format

  All providers should return data in a consistent structure:

      %{
        id: provider_specific_id,
        type: :movie | :tv | :music | :book | :event,
        title: "Content Title",
        description: "Content description/overview",
        metadata: %{
          # Provider-specific metadata
        },
        images: [%{url: "...", type: :poster | :backdrop, size: "..."}],
        external_urls: %{provider_name: "url", ...}
      }
  """

  @type search_result :: %{
    id: any(),
    type: atom(),
    title: String.t(),
    description: String.t(),
    images: list(),
    metadata: map()
  }

  @type detailed_result :: %{
    id: any(),
    type: atom(),
    title: String.t(),
    description: String.t(),
    metadata: map(),
    images: list(),
    external_urls: map(),
    cast: list(),
    crew: list(),
    media: map(),
    additional_data: map()
  }

  @type provider_config :: %{
    api_key: String.t(),
    base_url: String.t(),
    rate_limit: integer(),
    cache_ttl: integer(),
    options: map()
  }

  @doc """
  Get the provider's unique identifier.

  This should be a unique atom that identifies the provider
  (e.g., :tmdb, :spotify, :goodreads, :eventbrite).
  """
  @callback provider_id() :: atom()

  @doc """
  Get the provider's display name.

  This is the human-readable name shown in the UI.
  """
  @callback provider_name() :: String.t()

  @doc """
  Get the types of content this provider supports.

  Returns a list of content types this provider can handle.
  """
  @callback supported_types() :: [atom()]

  @doc """
  Search for content using the provider's API.

  ## Parameters

  - `query`: Search term
  - `options`: Provider-specific search options (page, filters, etc.)

  ## Returns

  - `{:ok, [search_result()]}`: List of search results
  - `{:error, reason}`: Error with reason
  """
  @callback search(query :: String.t(), options :: map()) ::
    {:ok, [search_result()]} | {:error, any()}

  @doc """
  Get detailed information for a specific content item.

  ## Parameters

  - `id`: Provider-specific content ID
  - `type`: Content type (:movie, :tv, etc.)
  - `options`: Provider-specific options

  ## Returns

  - `{:ok, detailed_result()}`: Detailed content information
  - `{:error, reason}`: Error with reason
  """
  @callback get_details(id :: any(), type :: atom(), options :: map()) ::
    {:ok, detailed_result()} | {:error, any()}

  @doc """
  Get cached details if available, otherwise fetch fresh data.

  This is the recommended method for getting details as it
  handles caching automatically.
  """
  @callback get_cached_details(id :: any(), type :: atom(), options :: map()) ::
    {:ok, detailed_result()} | {:error, any()}

  @doc """
  Validate provider configuration.

  Checks if the provider is properly configured with
  necessary API keys and settings.
  """
  @callback validate_config() :: :ok | {:error, String.t()}

  @doc """
  Get provider-specific configuration schema.

  Returns the expected configuration structure for this provider.
  """
  @callback config_schema() :: map()

  @doc """
  Transform provider-specific data into the standard format.

  This callback allows providers to convert their native
  API responses into the consistent format expected by
  the Rich Data Manager.
  """
  @callback normalize_data(raw_data :: map(), type :: atom()) ::
    {:ok, detailed_result()} | {:error, any()}

  @optional_callbacks [
    config_schema: 0,
    normalize_data: 2
  ]
end
