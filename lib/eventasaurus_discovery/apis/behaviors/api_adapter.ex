defmodule EventasaurusDiscovery.Apis.Behaviors.ApiAdapter do
  @moduledoc """
  Behavior for implementing API integrations.

  Each API source (Ticketmaster, etc.) must implement this behavior
  to ensure consistent interfaces across all API integrations.
  This is parallel to SourceAdapter but specifically for APIs.
  """

  @type api_config :: %{
          name: String.t(),
          slug: String.t(),
          priority: integer(),
          base_url: String.t(),
          api_key: String.t() | nil,
          api_secret: String.t() | nil,
          rate_limit: integer(),
          timeout: integer()
        }

  @type venue_data :: %{
          external_id: String.t(),
          name: String.t(),
          address: String.t() | nil,
          city: String.t() | nil,
          state: String.t() | nil,
          country: String.t() | nil,
          postal_code: String.t() | nil,
          latitude: float() | nil,
          longitude: float() | nil,
          timezone: String.t() | nil,
          metadata: map()
        }

  @type performer_data :: %{
          external_id: String.t(),
          name: String.t(),
          type: String.t() | nil,
          metadata: map()
        }

  @type event_data :: %{
          external_id: String.t(),
          title: String.t(),
          description: String.t() | nil,
          start_at: DateTime.t(),
          ends_at: DateTime.t() | nil,
          status: String.t(),
          is_ticketed: boolean(),
          venue_data: venue_data() | nil,
          performers: [performer_data()],
          metadata: map()
        }

  @type fetch_options :: %{
          optional(:page) => integer(),
          optional(:size) => integer(),
          optional(:radius) => integer(),
          optional(:unit) => String.t(),
          optional(:start_date) => Date.t(),
          optional(:end_date) => Date.t()
        }

  @doc """
  Returns the API configuration for this adapter.
  """
  @callback api_config() :: api_config()

  @doc """
  Fetches events by city coordinates and name.
  Returns a list of events with embedded venue and performer data.
  """
  @callback fetch_events_by_city(
              latitude :: float(),
              longitude :: float(),
              city_name :: String.t(),
              options :: fetch_options()
            ) :: {:ok, list(event_data())} | {:error, term()}

  @doc """
  Fetches detailed event information by external ID.
  """
  @callback fetch_event_details(event_id :: String.t()) ::
              {:ok, event_data()} | {:error, term()}

  @doc """
  Fetches venue details by external ID.
  """
  @callback fetch_venue_details(venue_id :: String.t()) ::
              {:ok, venue_data()} | {:error, term()}

  @doc """
  Fetches performer/attraction details by external ID.
  """
  @callback fetch_performer_details(performer_id :: String.t()) ::
              {:ok, performer_data()} | {:error, term()}

  @doc """
  Transforms raw API response to standardized event data.
  """
  @callback transform_event(raw_data :: map()) :: event_data()

  @doc """
  Transforms raw API response to standardized venue data.
  """
  @callback transform_venue(raw_data :: map()) :: venue_data()

  @doc """
  Transforms raw API response to standardized performer data.
  """
  @callback transform_performer(raw_data :: map()) :: performer_data()

  @doc """
  Validates API response for errors.
  """
  @callback validate_response(response :: map()) :: :ok | {:error, String.t()}

  @optional_callbacks [
    fetch_venue_details: 1,
    fetch_performer_details: 1
  ]
end
