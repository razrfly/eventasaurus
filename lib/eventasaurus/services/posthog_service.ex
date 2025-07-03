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

  # Event Tracking Functions

  @doc """
  Tracks when a guest invitation modal is opened.
  """
  @spec track_guest_invitation_modal_opened(String.t(), String.t(), map()) :: {:ok, :sent} | {:error, any()}
  def track_guest_invitation_modal_opened(user_id, event_id, metadata \\ %{}) do
    properties = Map.merge(%{
      event_id: event_id,
      source: "guest_invitation_modal"
    }, metadata)

    send_event("guest_invitation_modal_opened", user_id, properties)
  end

  @doc """
  Tracks when a historical participant is selected for invitation.
  """
  @spec track_historical_participant_selected(String.t(), String.t(), map()) :: {:ok, :sent} | {:error, any()}
  def track_historical_participant_selected(user_id, event_id, metadata \\ %{}) do
    properties = Map.merge(%{
      event_id: event_id,
      source: "historical_suggestions"
    }, metadata)

    send_event("historical_participant_selected", user_id, properties)
  end

  @doc """
  Tracks when a guest is added directly to an event.
  """
  @spec track_guest_added_directly(String.t(), String.t(), map()) :: {:ok, :sent} | {:error, any()}
  def track_guest_added_directly(user_id, event_id, metadata \\ %{}) do
    properties = Map.merge(%{
      event_id: event_id,
      source: "direct_addition"
    }, metadata)

    send_event("guest_added_directly", user_id, properties)
  end

  @doc """
  Sends a custom event to PostHog.
  """
  @spec send_event(String.t(), String.t(), map()) :: {:ok, :sent} | {:error, any()}
  def send_event(event_name, user_id, properties \\ %{}) do
    api_key = get_api_key()

    cond do
      !api_key ->
        Logger.warning("PostHog API key not configured - event tracking disabled")
        {:error, :no_api_key}

      !user_id or user_id == "" ->
        Logger.warning("Invalid user_id for PostHog event: #{event_name}")
        {:error, :invalid_user_id}

      true ->
        send_event_to_posthog(event_name, user_id, properties, api_key)
    end
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
        # Validate and sanitize event_id to prevent injection
        case sanitize_event_id(event_id) do
          {:ok, safe_event_id} ->
            case fetch_all_analytics(safe_event_id, date_range, api_key) do
              {:ok, %{visitors: visitors, registrations: registrations, votes: votes, checkouts: checkouts}} ->
                registration_rate = calculate_rate(registrations, visitors)
                checkout_rate = calculate_rate(checkouts, registrations)

                {:ok, %{
                  unique_visitors: visitors,
                  registrations: registrations,
                  votes_cast: votes,
                  ticket_checkouts: checkouts,
                  registration_rate: registration_rate,
                  checkout_conversion_rate: checkout_rate
                }}

              {:error, reason} -> {:error, reason}
            end

          {:error, reason} ->
            Logger.error("Invalid event_id provided: #{inspect(event_id)}")
            {:error, reason}
        end
    end
  end

  defp fetch_all_analytics(event_id, date_range, api_key) do
    # Combined query to get all metrics in a single API call
    current_time = current_time_string()

    query_params = %{
      "query" => %{
        "kind" => "HogQLQuery",
        "query" => """
        SELECT
          count(DISTINCT CASE WHEN event = 'event_page_viewed' THEN person_id ELSE NULL END) as visitors,
          count(CASE WHEN event = 'event_registration_completed' THEN 1 ELSE NULL END) as registrations,
          count(CASE WHEN event = 'event_date_vote_cast' THEN 1 ELSE NULL END) as votes,
          count(CASE WHEN event = 'ticket_checkout_initiated' THEN 1 ELSE NULL END) as checkouts
        FROM events
        WHERE properties.event_id = '#{event_id}'
          AND timestamp >= '#{days_ago(date_range)}'
          AND timestamp <= '#{current_time}'
        """
      }
    }

    case make_api_request("/query/", query_params, api_key) do
      {:ok, response} ->
        case parse_combined_analytics_response(response) do
          {:ok, metrics} -> {:ok, metrics}
          {:error, reason} -> {:error, reason}
        end
      error -> error
    end
  end

  defp parse_combined_analytics_response(response) do
    case response do
      %{"results" => [result]} when is_list(result) and length(result) == 4 ->
        [visitors, registrations, votes, checkouts] = result
        {:ok, %{
          visitors: visitors || 0,
          registrations: registrations || 0,
          votes: votes || 0,
          checkouts: checkouts || 0
        }}

      %{"results" => []} ->
        {:ok, %{visitors: 0, registrations: 0, votes: 0, checkouts: 0}}

      _ ->
        Logger.error("Unexpected combined analytics response format: #{inspect(response)}")
        {:error, "Invalid response format from PostHog API"}
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

  defp send_event_to_posthog(event_name, user_id, properties, api_key) do
    # PostHog event ingestion API endpoint
    url = "#{@api_base}/capture/"

    # Build event payload according to PostHog format
    event_payload = %{
      api_key: api_key,
      event: event_name,
      distinct_id: user_id,
      properties: Map.merge(properties, %{
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "$lib" => "eventasaurus-backend",
        "$lib_version" => "0.1.0"
      })
    }

    headers = [
      {"Content-Type", "application/json"},
      {"User-Agent", "Eventasaurus Backend/0.1.0"}
    ]

    body = Jason.encode!(event_payload)

    case HTTPoison.post(url, body, headers, timeout: 5000, recv_timeout: 5000) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        Logger.debug("PostHog event sent successfully: #{event_name}")
        {:ok, :sent}

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        Logger.warning("PostHog event failed with status #{status_code}: #{response_body}")
        {:error, {:api_error, status_code}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("PostHog event request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp get_api_key do
    System.get_env("POSTHOG_PRIVATE_API_KEY")
  end

  defp get_project_id do
    System.get_env("POSTHOG_PROJECT_ID")
  end

  defp sanitize_event_id(event_id) when is_binary(event_id) do
    # Only allow alphanumeric characters, hyphens, and underscores
    if String.match?(event_id, ~r/^[a-zA-Z0-9_-]+$/) do
      {:ok, event_id}
    else
      {:error, :invalid_event_id}
    end
  end

  defp sanitize_event_id(event_id) when is_integer(event_id) do
    {:ok, to_string(event_id)}
  end

  defp sanitize_event_id(_event_id) do
    {:error, :invalid_event_id}
  end
end
