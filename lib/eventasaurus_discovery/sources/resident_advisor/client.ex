defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.Client do
  @moduledoc """
  GraphQL client for Resident Advisor API.

  Handles communication with RA's public GraphQL endpoint, including:
  - Event listing queries with filtering and pagination
  - Venue detail queries (if available)
  - Error handling and retry logic
  - Rate limiting compliance
  """

  require Logger
  alias EventasaurusDiscovery.Sources.ResidentAdvisor.Config

  @doc """
  Fetch events from Resident Advisor GraphQL API.

  ## Parameters
  - `area_id` - Integer area ID (e.g., 34 for London)
  - `date_from` - Start date in ISO format (e.g., "2025-10-06")
  - `date_to` - End date in ISO format (e.g., "2025-11-06")
  - `page` - Page number (starts at 1)
  - `page_size` - Number of results per page (default: 20)

  ## Returns
  - `{:ok, data}` - GraphQL data response
  - `{:error, reason}` - Error details

  ## Examples

      iex> Client.fetch_events(34, "2025-10-06", "2025-11-06", 1, 20)
      {:ok, %{"eventListings" => %{"data" => [...]}}}
  """
  def fetch_events(area_id, date_from, date_to, page \\ 1, page_size \\ 20) do
    query = build_event_listing_query()
    variables = build_event_variables(area_id, date_from, date_to, page, page_size)

    execute_graphql(query, variables, "GET_EVENT_LISTINGS")
  end

  @doc """
  Fetch venue details by venue ID.

  NOTE: This query structure may need adjustment based on actual RA GraphQL schema.
  Currently returns an error as the exact schema is unknown.

  ## Parameters
  - `venue_id` - Venue ID from event data

  ## Returns
  - `{:ok, venue_data}` - Venue details (may include coordinates)
  - `{:error, reason}` - Error if query not supported or venue not found
  """
  def fetch_venue_details(venue_id) do
    query = build_venue_detail_query()
    variables = %{"venueId" => venue_id}

    case execute_graphql(query, variables, "VENUE_DETAIL") do
      {:ok, %{"venue" => venue}} -> {:ok, venue}
      {:ok, _other} -> {:error, :venue_query_not_supported}
      error -> error
    end
  end

  # Private functions

  defp execute_graphql(query, variables, operation_name) do
    body =
      Jason.encode!(%{
        query: query,
        variables: variables,
        operationName: operation_name
      })

    case HTTPoison.post(
           Config.graphql_endpoint(),
           body,
           headers(),
           timeout: Config.timeout(),
           recv_timeout: Config.timeout()
         ) do
      {:ok, %{status_code: 200, body: response_body}} ->
        handle_graphql_response(response_body)

      {:ok, %{status_code: 429}} ->
        Logger.warning("RA GraphQL rate limited (429)")
        {:error, :rate_limited}

      {:ok, %{status_code: 403}} ->
        Logger.error("RA GraphQL forbidden (403) - check headers/user-agent")
        {:error, :forbidden}

      {:ok, %{status_code: status}} ->
        Logger.error("RA GraphQL HTTP error: #{status}")
        {:error, {:http_error, status}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("RA GraphQL request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp handle_graphql_response(response_body) do
    case Jason.decode(response_body) do
      {:ok, %{"data" => data}} when not is_nil(data) ->
        {:ok, data}

      {:ok, %{"errors" => errors}} ->
        Logger.error("RA GraphQL errors: #{inspect(errors)}")
        {:error, {:graphql_errors, errors}}

      {:ok, unexpected} ->
        Logger.error("RA GraphQL unexpected response: #{inspect(unexpected)}")
        {:error, {:unexpected_response, unexpected}}

      {:error, decode_error} ->
        Logger.error("RA GraphQL JSON decode failed: #{inspect(decode_error)}")
        {:error, {:decode_failed, decode_error}}
    end
  end

  defp headers do
    [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"},
      {"Referer", "https://ra.co/events"}
    ]
  end

  defp build_event_listing_query do
    """
    query GET_EVENT_LISTINGS($filters: FilterInputDtoInput, $filterOptions: FilterOptionsInputDtoInput, $page: Int, $pageSize: Int) {
      eventListings(filters: $filters, filterOptions: $filterOptions, pageSize: $pageSize, page: $page) {
        data {
          id
          listingDate
          event {
            id
            date
            startTime
            endTime
            title
            contentUrl
            flyerFront
            isTicketed
            attending
            queueItEnabled
            newEventForm
            images {
              id
              filename
              alt
              type
              crop
            }
            pick {
              id
              blurb
            }
            venue {
              id
              name
              contentUrl
              live
            }
            promoters {
              id
              name
            }
            artists {
              id
              name
              image
              contentUrl
              country {
                id
                name
                urlCode
              }
            }
          }
        }
      }
    }
    """
  end

  defp build_event_variables(area_id, date_from, date_to, page, page_size) do
    %{
      "filters" => %{
        "areas" => %{
          "eq" => area_id
        },
        "listingDate" => %{
          "gte" => date_from,
          "lte" => date_to
        }
      },
      "filterOptions" => %{
        "genre" => true
      },
      "page" => page,
      "pageSize" => page_size
    }
  end

  defp build_venue_detail_query do
    """
    query VENUE_DETAIL($venueId: ID!) {
      venue(id: $venueId) {
        id
        name
        contentUrl
        live
      }
    }
    """
  end
end
