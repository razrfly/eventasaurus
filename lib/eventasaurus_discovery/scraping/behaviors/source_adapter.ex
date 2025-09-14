defmodule EventasaurusDiscovery.Scraping.Behaviors.SourceAdapter do
  @moduledoc """
  Behavior for implementing source-specific scrapers.

  Each source (Bandsintown, Ticketmaster, etc.) must implement this behavior
  to ensure consistent interfaces across all scrapers.
  """

  @type venue_data :: %{
    name: String.t(),
    address: String.t() | nil,
    city: String.t() | nil,
    state: String.t() | nil,
    country: String.t() | nil,
    latitude: float() | nil,
    longitude: float() | nil,
    place_id: String.t() | nil,
    metadata: map()
  }

  @type event_data :: %{
    external_id: String.t(),
    title: String.t(),
    description: String.t() | nil,
    start_at: DateTime.t(),
    ends_at: DateTime.t() | nil,
    venue_data: venue_data() | nil,
    performer_names: [String.t()],
    metadata: map()
  }

  @type source_config :: %{
    name: String.t(),
    slug: String.t(),
    priority: integer(),
    base_url: String.t(),
    api_key: String.t() | nil,
    rate_limit: integer()
  }

  @doc """
  Returns the source configuration for this adapter.
  """
  @callback source_config() :: source_config()

  @doc """
  Fetches index data (list of events/venues to process).
  Returns a list of items that need detailed processing.
  """
  @callback fetch_index(params :: map()) :: {:ok, list(map())} | {:error, term()}

  @doc """
  Fetches detailed data for a specific item.
  Returns structured event data ready for processing.
  """
  @callback fetch_detail(item :: map(), source_id :: integer()) :: {:ok, event_data()} | {:error, term()}

  @doc """
  Parses raw response data into structured format.
  """
  @callback parse_response(body :: String.t()) :: {:ok, list(map())} | {:error, term()}

  @doc """
  Validates that required configuration is present.
  """
  @callback validate_config() :: :ok | {:error, String.t()}

  @doc """
  Returns headers needed for API requests.
  """
  @callback request_headers() :: [{String.t(), String.t()}]

  @doc """
  Builds the URL for a specific API endpoint.
  """
  @callback build_url(endpoint :: String.t(), params :: map()) :: String.t()

  @optional_callbacks request_headers: 0, build_url: 2
end