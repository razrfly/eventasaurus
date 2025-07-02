defmodule Eventasaurus.Services.PosthogService do
  @moduledoc """
  PostHog Analytics Service for retrieving event analytics data.

  Provides cached access to PostHog API data with error handling and fallback values.
  Uses GenServer for 5-minute caching to prevent excessive API calls.
  """

  use GenServer
  require Logger

  @api_base "https://eu.i.posthog.com/api"
  @cache_ttl_ms 5 * 60 * 1000  # 5 minutes

  # Client API

  @doc """
  Starts the PostHog service GenServer.
  """
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Gets comprehensive event analytics for a specific event.

  Returns cached data if available and fresh, otherwise fetches from PostHog API.
  Note: Requires POSTHOG_PROJECT_ID environment variable to be set.

  ## Parameters

    * `event_id` - The event ID to get analytics for
    * `date_range` - Number of days to look back (default: 7)

  ## Returns

    * `{:ok, analytics_data}` - Success with analytics map
    * `{:error, reason}` - Error with reason

  ## Examples

      iex> PosthogService.get_analytics(123, 7)
      {:ok, %{unique_visitors: 45, registrations: 12, ...}}

      iex> PosthogService.get_analytics(123, 30)
      {:error, :no_api_key}

  """
  def get_analytics(event_id, date_range \\ 7) do
    GenServer.call(__MODULE__, {:get_analytics, event_id, date_range}, 10000)
  end

  @doc """
  Gets unique page visitors for an event.
  """
  @spec get_unique_visitors(String.t(), integer()) :: {:ok, integer()} | {:error, any()}
  def get_unique_visitors(event_id, date_range \\ 7) do
    case get_analytics(event_id, date_range) do
      {:ok, analytics} -> {:ok, analytics.unique_visitors}
      error -> error
    end
  end

  @doc """
  Gets registration conversion rate for an event.
  """
  @spec get_registration_rate(String.t(), integer()) :: {:ok, float()} | {:error, any()}
  def get_registration_rate(event_id, date_range \\ 7) do
    case get_analytics(event_id, date_range) do
      {:ok, analytics} -> {:ok, analytics.registration_rate}
      error -> error
    end
  end

  @doc """
  Clears the cache for a specific event or all cached data.
  """
  @spec clear_cache(String.t() | :all) :: :ok
  def clear_cache(event_id_or_all) do
    GenServer.cast(__MODULE__, {:clear_cache, event_id_or_all})
  end

  # GenServer Callbacks

  @impl true
  def init(:ok) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get_analytics, event_id, date_range}, _from, state) do
    cache_key = "analytics_#{event_id}_#{date_range}"
    current_time = System.monotonic_time(:millisecond)

    case Map.get(state, cache_key) do
      %{timestamp: ts, data: data} ->
        if current_time - ts < @cache_ttl_ms do
          {:reply, {:ok, data}, state}
        else
          fetch_and_cache_analytics(event_id, date_range, current_time, state, cache_key)
        end
      _ ->
        fetch_and_cache_analytics(event_id, date_range, current_time, state, cache_key)
    end
  end

  defp fetch_and_cache_analytics(event_id, date_range, current_time, state, cache_key) do
    case fetch_analytics_from_api(event_id, date_range) do
      {:ok, analytics_data} ->
        updated_state = Map.put(state, cache_key, %{
          timestamp: current_time,
          data: analytics_data
        })
        {:reply, {:ok, analytics_data}, updated_state}
      {:error, reason} ->
        # Return analytics data with error information for graceful degradation
        error_analytics = %{
          unique_visitors: 0,
          registrations: 0,
          votes_cast: 0,
          ticket_checkouts: 0,
          registration_rate: 0.0,
          checkout_conversion_rate: 0.0,
          error: format_error_message(reason),
          has_error: true
        }
        {:reply, {:ok, error_analytics}, state}
    end
  end

  @impl true
  def handle_cast({:clear_cache, :all}, _state) do
    Logger.info("Clearing all PostHog cache")
    {:noreply, %{}}
  end

  @impl true
  def handle_cast({:clear_cache, event_id}, state) when is_binary(event_id) do
    Logger.info("Clearing PostHog cache for event #{event_id}")

    cache = state |> Enum.filter(fn {key, _} -> not String.starts_with?(key, "analytics_#{event_id}_") end) |> Enum.into(%{})

    {:noreply, cache}
  end

  # Private Functions

  defp format_error_message(reason) do
    case reason do
      :no_api_key ->
        "PostHog private API key not configured - analytics unavailable"
      :no_project_id ->
        "PostHog project ID missing - please contact support"
      {:api_error, 403} ->
        "PostHog authentication failed - please check private API key permissions"
      {:api_error, status} ->
        "PostHog API error (#{status}) - analytics temporarily unavailable"
      _ ->
        "Analytics temporarily unavailable"
    end
  end

  defp fetch_analytics_from_api(event_id, date_range) do
    api_key = get_api_key()
    project_id = get_project_id()

    cond do
      !api_key ->
        Logger.warning("PostHog private API key not configured - analytics will be unavailable")
        {:error, :no_api_key}

      !project_id ->
        Logger.warning("PostHog project ID not configured - analytics will be unavailable. Please set POSTHOG_PROJECT_ID environment variable")
        {:error, :no_project_id}

      true ->
        with {:ok, visitors} <- fetch_unique_visitors(event_id, date_range, api_key),
             {:ok, registrations} <- fetch_registrations(event_id, date_range, api_key),
             {:ok, votes} <- fetch_votes(event_id, date_range, api_key),
             {:ok, checkouts} <- fetch_checkouts(event_id, date_range, api_key) do

          registration_rate = if visitors > 0, do: (registrations / visitors) * 100, else: 0.0
          checkout_rate = if registrations > 0, do: (checkouts / registrations) * 100, else: 0.0

          {:ok, %{
            unique_visitors: visitors,
            registrations: registrations,
            votes_cast: votes,
            ticket_checkouts: checkouts,
            registration_rate: Float.round(registration_rate, 1),
            checkout_conversion_rate: Float.round(checkout_rate, 1)
          }}
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp fetch_unique_visitors(event_id, date_range, api_key) do
    # Use PostHog's query API with HogQL for unique visitors
    current_time = current_time_string()

    query_params = %{
      "query" => %{
        "kind" => "HogQLQuery",
        "query" => "SELECT count(DISTINCT person_id) FROM events WHERE event = 'event_page_viewed' AND properties.event_id = '#{event_id}' AND timestamp >= '#{days_ago(date_range)}' AND timestamp <= '#{current_time}'"
      }
    }

    case make_api_request("/query/", query_params, api_key) do
      {:ok, response} ->
        count = extract_count_from_hogql_response(response)
        {:ok, count}
      error -> error
    end
  end

  defp fetch_registrations(event_id, date_range, api_key) do
    # Use PostHog's query API with HogQL for registrations
    current_time = current_time_string()

    query_params = %{
      "query" => %{
        "kind" => "HogQLQuery",
        "query" => "SELECT count(*) FROM events WHERE event = 'event_registration_completed' AND properties.event_id = '#{event_id}' AND timestamp >= '#{days_ago(date_range)}' AND timestamp <= '#{current_time}'"
      }
    }

    case make_api_request("/query/", query_params, api_key) do
      {:ok, response} ->
        count = extract_count_from_hogql_response(response)
        {:ok, count}
      error -> error
    end
  end

  defp fetch_votes(event_id, date_range, api_key) do
    # Use PostHog's query API with HogQL for votes
    current_time = current_time_string()

    query_params = %{
      "query" => %{
        "kind" => "HogQLQuery",
        "query" => "SELECT count(*) FROM events WHERE event = 'event_date_vote_cast' AND properties.event_id = '#{event_id}' AND timestamp >= '#{days_ago(date_range)}' AND timestamp <= '#{current_time}'"
      }
    }

    case make_api_request("/query/", query_params, api_key) do
      {:ok, response} ->
        count = extract_count_from_hogql_response(response)
        {:ok, count}
      error -> error
    end
  end

  defp fetch_checkouts(event_id, date_range, api_key) do
    # Use PostHog's query API with HogQL for checkouts
    current_time = current_time_string()

    query_params = %{
      "query" => %{
        "kind" => "HogQLQuery",
        "query" => "SELECT count(*) FROM events WHERE event = 'ticket_checkout_initiated' AND properties.event_id = '#{event_id}' AND timestamp >= '#{days_ago(date_range)}' AND timestamp <= '#{current_time}'"
      }
    }

    case make_api_request("/query/", query_params, api_key) do
      {:ok, response} ->
        count = extract_count_from_hogql_response(response)
        {:ok, count}
      error -> error
    end
  end

  defp make_api_request(endpoint, query_params, api_key) do
    project_id = get_project_id()

    if project_id do
      # Use the correct PostHog API format with project ID
      url = "#{@api_base}/projects/#{project_id}#{endpoint}"
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      # Convert query params to JSON body for POST request
      body = Jason.encode!(query_params)

      case HTTPoison.post(url, body, headers, timeout: 10000, recv_timeout: 10000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, data} -> {:ok, data}
            {:error, _} -> {:error, :invalid_json}
          end
        {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
          Logger.error("PostHog API returned status #{status_code}: #{body}")
          {:error, {:api_error, status_code}}
        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("PostHog API request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    else
      {:error, :no_project_id}
    end
  end

  defp extract_count_from_hogql_response(response) do
    # PostHog HogQL response format: {"results": [[123]], "columns": ["count()"], "types": ["Integer"]}
    case response do
      %{"results" => [[count]]} when is_integer(count) ->
        count
      %{"results" => results} when is_list(results) ->
        # Handle multiple rows by summing if needed
        results
        |> List.flatten()
        |> Enum.filter(&is_integer/1)
        |> Enum.sum()
      _ ->
        Logger.warning("Unexpected PostHog response format: #{inspect(response)}")
        0
    end
  end

  defp calculate_rate(numerator, denominator) do
    if denominator > 0 do
      Float.round(numerator / denominator * 100, 1)
    else
      0.0
    end
  end

  defp days_ago(days) do
    # PostHog HogQL expects simple timestamp format: 'YYYY-MM-DD HH:MM:SS'
    DateTime.utc_now()
    |> DateTime.add(-days * 24 * 60 * 60, :second)
    |> DateTime.truncate(:second)
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
  end

  defp current_time_string() do
    # PostHog HogQL expects simple timestamp format: 'YYYY-MM-DD HH:MM:SS'
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
  end

  defp get_api_key do
    System.get_env("POSTHOG_PRIVATE_API_KEY")
  end

  defp get_project_id do
    System.get_env("POSTHOG_PROJECT_ID")
  end
end
