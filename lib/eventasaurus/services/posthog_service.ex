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

      iex> PosthogService.get_event_analytics("123", 7)
      {:ok, %{
        unique_visitors: 150,
        registrations: 25,
        registration_rate: 16.7,
        votes_cast: 45,
        ticket_checkouts: 12,
        checkout_conversion_rate: 8.0
      }}
  """
  @spec get_event_analytics(String.t(), integer()) :: {:ok, map()} | {:error, any()}
  def get_event_analytics(event_id, date_range \\ 7) do
    GenServer.call(__MODULE__, {:get_analytics, event_id, date_range})
  end

  @doc """
  Gets unique page visitors for an event.
  """
  @spec get_unique_visitors(String.t(), integer()) :: {:ok, integer()} | {:error, any()}
  def get_unique_visitors(event_id, date_range \\ 7) do
    case get_event_analytics(event_id, date_range) do
      {:ok, analytics} -> {:ok, analytics.unique_visitors}
      error -> error
    end
  end

  @doc """
  Gets registration conversion rate for an event.
  """
  @spec get_registration_rate(String.t(), integer()) :: {:ok, float()} | {:error, any()}
  def get_registration_rate(event_id, date_range \\ 7) do
    case get_event_analytics(event_id, date_range) do
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
    {:ok, %{cache: %{}, cache_timestamps: %{}}}
  end

  @impl true
  def handle_call({:get_analytics, event_id, date_range}, _from, state) do
    cache_key = "#{event_id}_#{date_range}"

    case get_cached_data(state, cache_key) do
      {:hit, data} ->
        Logger.debug("PostHog cache hit for event #{event_id}")
        {:reply, {:ok, data}, state}

      :miss ->
        Logger.debug("PostHog cache miss for event #{event_id}, fetching from API")
        case fetch_analytics_from_api(event_id, date_range) do
          {:ok, data} ->
            new_state = cache_data(state, cache_key, data)
            {:reply, {:ok, data}, new_state}

          {:error, reason} ->
            Logger.error("PostHog API error for event #{event_id}: #{inspect(reason)}")
            fallback_data = get_fallback_analytics()
            {:reply, {:ok, fallback_data}, state}
        end
    end
  end

  @impl true
  def handle_cast({:clear_cache, :all}, _state) do
    Logger.info("Clearing all PostHog cache")
    {:noreply, %{cache: %{}, cache_timestamps: %{}}}
  end

  @impl true
  def handle_cast({:clear_cache, event_id}, state) when is_binary(event_id) do
    Logger.info("Clearing PostHog cache for event #{event_id}")

    cache = state.cache |> Enum.reject(fn {key, _} -> String.starts_with?(key, event_id) end) |> Enum.into(%{})
    timestamps = state.cache_timestamps |> Enum.reject(fn {key, _} -> String.starts_with?(key, event_id) end) |> Enum.into(%{})

    {:noreply, %{state | cache: cache, cache_timestamps: timestamps}}
  end

  # Private Functions

  defp get_cached_data(state, cache_key) do
    case {Map.get(state.cache, cache_key), Map.get(state.cache_timestamps, cache_key)} do
      {nil, _} -> :miss
      {_, nil} -> :miss
      {data, timestamp} ->
        if fresh?(timestamp) do
          {:hit, data}
        else
          :miss
        end
    end
  end

  defp fresh?(timestamp) do
    System.system_time(:millisecond) - timestamp < @cache_ttl_ms
  end

  defp cache_data(state, cache_key, data) do
    timestamp = System.system_time(:millisecond)

    %{
      state |
      cache: Map.put(state.cache, cache_key, data),
      cache_timestamps: Map.put(state.cache_timestamps, cache_key, timestamp)
    }
  end

  defp fetch_analytics_from_api(event_id, date_range) do
    api_key = get_api_key()
    project_id = get_project_id()

    cond do
      !api_key ->
        Logger.warning("PostHog API key not configured - analytics will be unavailable")
        {:error, :no_api_key}

      !project_id ->
        Logger.warning("PostHog project ID not configured - analytics will be unavailable. Please set POSTHOG_PROJECT_ID environment variable")
        {:error, :no_project_id}

      true ->
        with {:ok, visitors} <- fetch_unique_visitors(event_id, date_range, api_key),
             {:ok, registrations} <- fetch_registrations(event_id, date_range, api_key),
             {:ok, votes} <- fetch_votes(event_id, date_range, api_key),
             {:ok, checkouts} <- fetch_checkouts(event_id, date_range, api_key) do

          analytics = %{
            unique_visitors: visitors,
            registrations: registrations,
            registration_rate: calculate_rate(registrations, visitors),
            votes_cast: votes,
            ticket_checkouts: checkouts,
            checkout_conversion_rate: calculate_rate(checkouts, visitors)
          }

          {:ok, analytics}
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp fetch_unique_visitors(event_id, date_range, api_key) do
    query_params = %{
      event: "event_page_viewed",
      properties: [%{key: "event_id", value: event_id, operator: "exact"}],
      date_from: days_ago(date_range),
      date_to: Date.to_iso8601(Date.utc_today())
    }

    case make_api_request("/events/", query_params, api_key) do
      {:ok, response} ->
        count = count_unique_users(response)
        {:ok, count}
      error -> error
    end
  end

  defp fetch_registrations(event_id, date_range, api_key) do
    query_params = %{
      event: "event_registration_completed",
      properties: [%{key: "event_id", value: event_id, operator: "exact"}],
      date_from: days_ago(date_range),
      date_to: Date.to_iso8601(Date.utc_today())
    }

    case make_api_request("/events/", query_params, api_key) do
      {:ok, response} ->
        count = count_events(response)
        {:ok, count}
      error -> error
    end
  end

  defp fetch_votes(event_id, date_range, api_key) do
    query_params = %{
      event: "event_date_vote_cast",
      properties: [%{key: "event_id", value: event_id, operator: "exact"}],
      date_from: days_ago(date_range),
      date_to: Date.to_iso8601(Date.utc_today())
    }

    case make_api_request("/events/", query_params, api_key) do
      {:ok, response} ->
        count = count_events(response)
        {:ok, count}
      error -> error
    end
  end

  defp fetch_checkouts(event_id, date_range, api_key) do
    query_params = %{
      event: "ticket_checkout_initiated",
      properties: [%{key: "event_id", value: event_id, operator: "exact"}],
      date_from: days_ago(date_range),
      date_to: Date.to_iso8601(Date.utc_today())
    }

    case make_api_request("/events/", query_params, api_key) do
      {:ok, response} ->
        count = count_events(response)
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

      # Convert query params to URL parameters for GET request
      query_string = URI.encode_query(query_params)
      full_url = "#{url}?#{query_string}"

      case HTTPoison.get(full_url, headers, timeout: 10000, recv_timeout: 10000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, data} -> {:ok, data}
            {:error, _} -> {:error, :invalid_json}
          end

        {:ok, %HTTPoison.Response{status_code: status_code}} ->
          Logger.warning("PostHog API returned status #{status_code}")
          {:error, {:api_error, status_code}}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("PostHog API request failed: #{inspect(reason)}")
          {:error, {:http_error, reason}}
      end
    else
      Logger.warning("PostHog project ID not configured - skipping API request")
      {:error, :no_project_id}
    end
  end

  defp count_unique_users(response) do
    response
    |> Map.get("results", [])
    |> Enum.map(& &1["distinct_id"])
    |> Enum.uniq()
    |> length()
  end

  defp count_events(response) do
    response
    |> Map.get("results", [])
    |> length()
  end

  defp calculate_rate(numerator, denominator) do
    if denominator > 0 do
      Float.round(numerator / denominator * 100, 1)
    else
      0.0
    end
  end

  defp days_ago(days) do
    Date.utc_today()
    |> Date.add(-days)
    |> Date.to_iso8601()
  end

  defp get_api_key do
    System.get_env("POSTHOG_API_KEY")
  end

  defp get_project_id do
    System.get_env("POSTHOG_PROJECT_ID")
  end

  defp get_fallback_analytics do
    %{
      unique_visitors: 0,
      registrations: 0,
      registration_rate: 0.0,
      votes_cast: 0,
      ticket_checkouts: 0,
      checkout_conversion_rate: 0.0
    }
  end
end
