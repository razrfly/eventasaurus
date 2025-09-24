defmodule Eventasaurus.Services.PosthogService do
  @moduledoc """
  PostHog Analytics Service for retrieving event analytics data.

  Provides cached access to PostHog API data with error handling and fallback values.
  Uses GenServer for 5-minute caching to prevent excessive API calls.
  """

  use GenServer
  require Logger

  @api_base "https://eu.i.posthog.com/api"
  # 15 minutes for analytics data
  @cache_ttl_ms 15 * 60 * 1000
  # Prevent unbounded cache growth
  @max_cache_entries 100

  # Client API

  @doc """
  Checks if PostHog is properly configured for event tracking.
  """
  def configured?() do
    !!get_api_key()
  end

  @doc """
  Checks if PostHog is properly configured for analytics.
  """
  def analytics_configured?() do
    !!(get_private_api_key() && get_project_id())
  end

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
    # Use a longer timeout for GenServer call to account for slow PostHog queries
    case GenServer.call(__MODULE__, {:get_analytics, event_id, date_range}, 35000) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, reason}
      other -> other
    end
  catch
    :exit, {:timeout, _} ->
      Logger.warning(
        "PostHog analytics GenServer timeout for event #{event_id}, returning cached or default values"
      )

      # Try to get from cache directly as a last resort
      case get_cached_analytics(event_id, date_range) do
        {:ok, data} ->
          Logger.info("Found stale cached data for event #{event_id}")
          {:ok, data}

        :not_found ->
          {:ok,
           %{
             unique_visitors: 0,
             registrations: 0,
             registration_rate: 0.0,
             date_votes: 0,
             ticket_checkouts: 0,
             checkout_conversion_rate: 0.0
           }}
      end
  end

  @doc """
  Gets cached analytics data directly, even if stale.
  Used as fallback when PostHog is slow or timing out.
  """
  def get_cached_analytics(event_id, date_range) do
    GenServer.call(__MODULE__, {:get_cached_analytics, event_id, date_range}, 1000)
  catch
    :exit, {:timeout, _} -> :not_found
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
  @spec track_guest_invitation_modal_opened(String.t(), String.t(), map()) ::
          {:ok, :sent} | {:error, any()}
  def track_guest_invitation_modal_opened(user_id, event_id, metadata \\ %{}) do
    properties =
      Map.merge(
        %{
          event_id: event_id,
          source: "guest_invitation_modal"
        },
        metadata
      )

    send_event("guest_invitation_modal_opened", user_id, properties)
  end

  @doc """
  Tracks when a historical participant is selected for invitation.
  """
  @spec track_historical_participant_selected(String.t(), String.t(), map()) ::
          {:ok, :sent} | {:error, any()}
  def track_historical_participant_selected(user_id, event_id, metadata \\ %{}) do
    properties =
      Map.merge(
        %{
          event_id: event_id,
          source: "historical_suggestions"
        },
        metadata
      )

    send_event("historical_participant_selected", user_id, properties)
  end

  @doc """
  Tracks when a guest is added directly to an event.
  """
  @spec track_guest_added_directly(String.t(), String.t(), map()) ::
          {:ok, :sent} | {:error, any()}
  def track_guest_added_directly(user_id, event_id, metadata \\ %{}) do
    properties =
      Map.merge(
        %{
          event_id: event_id,
          source: "direct_addition"
        },
        metadata
      )

    send_event("guest_added_directly", user_id, properties)
  end

  @doc """
  Tracks a custom event via PostHog.
  Alias for send_event/3 to match PostHog SDK naming conventions.
  """
  @spec capture(String.t(), String.t(), map()) :: {:ok, :sent} | {:error, any()}
  def capture(user_id, event_name, properties \\ %{}) do
    send_event(event_name, user_id, properties)
  end

  @doc """
  Sends a custom event to PostHog.
  """
  @spec send_event(String.t(), String.t(), map()) :: {:ok, :sent} | {:error, any()}
  def send_event(event_name, user_id, properties \\ %{}) do
    api_key = get_api_key()

    cond do
      !api_key ->
        # Log only once per application start, not for every event
        if not Application.get_env(:eventasaurus, :posthog_warning_logged, false) do
          Logger.info(
            "PostHog not configured - event tracking disabled. Set POSTHOG_PUBLIC_API_KEY to enable."
          )

          Application.put_env(:eventasaurus, :posthog_warning_logged, true)
        end

        {:error, :no_api_key}

      !user_id or user_id == "" ->
        # For anonymous users, we expect the caller to provide a consistent anonymous ID
        # This should be generated using AnonymousIdService
        Logger.warning(
          "PostHog event #{event_name} called without user_id. Use AnonymousIdService.get_user_identifier/2"
        )

        {:error, :no_user_id}

      true ->
        # Check if this is an anonymous ID
        is_anonymous = String.starts_with?(user_id, "anon_")

        properties_with_anon =
          if is_anonymous, do: Map.put(properties, :is_anonymous, true), else: properties

        Logger.debug("Tracking PostHog event #{event_name} for user: #{user_id}")
        send_event_to_posthog(event_name, user_id, properties_with_anon, api_key)
    end
  end

  # GenServer Callbacks

  @impl true
  def init(:ok) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get_cached_analytics, event_id, date_range}, _from, state) do
    cache_key = "analytics_#{event_id}_#{date_range}"

    case Map.get(state, cache_key) do
      %{data: data} ->
        # Return cached data even if stale
        {:reply, {:ok, data}, state}

      _ ->
        {:reply, :not_found, state}
    end
  end

  @impl true
  def handle_call({:get_analytics, event_id, date_range}, from, state) do
    cache_key = "analytics_#{event_id}_#{date_range}"
    pending_key = "pending_#{cache_key}"
    current_time = System.monotonic_time(:millisecond)

    case Map.get(state, cache_key) do
      %{timestamp: ts, data: data} ->
        if current_time - ts < @cache_ttl_ms do
          {:reply, {:ok, data}, state}
        else
          # Cache expired, check if we already have a pending request
          case Map.get(state, pending_key) do
            nil ->
              # No pending request, spawn async task and track it
              spawn_async_fetch(event_id, date_range, current_time, cache_key, from)
              updated_state = Map.put(state, pending_key, [from])
              {:noreply, updated_state}

            pending_requests ->
              # Add to existing pending requests queue
              updated_state = Map.put(state, pending_key, [from | pending_requests])
              {:noreply, updated_state}
          end
        end

      _ ->
        # No cache entry, check if we already have a pending request
        case Map.get(state, pending_key) do
          nil ->
            # No pending request, spawn async task and track it
            spawn_async_fetch(event_id, date_range, current_time, cache_key, from)
            updated_state = Map.put(state, pending_key, [from])
            {:noreply, updated_state}

          pending_requests ->
            # Add to existing pending requests queue
            updated_state = Map.put(state, pending_key, [from | pending_requests])
            {:noreply, updated_state}
        end
    end
  end

  @impl true
  def handle_cast(
        {:cache_analytics_result, cache_key, current_time, analytics_data, _from},
        state
      ) do
    pending_key = "pending_#{cache_key}"

    # Store the result
    updated_state =
      Map.put(state, cache_key, %{
        timestamp: current_time,
        data: analytics_data
      })

    # Reply to all pending requests
    case Map.get(state, pending_key) do
      nil ->
        # No pending requests (shouldn't happen but handle gracefully)
        :ok

      pending_requests ->
        Enum.each(pending_requests, fn from ->
          GenServer.reply(from, {:ok, analytics_data})
        end)
    end

    # Remove pending requests entry and clean up cache if needed
    final_state =
      updated_state
      |> Map.delete(pending_key)
      |> then(fn state ->
        if map_size(state) > @max_cache_entries do
          cleanup_old_cache_entries(state, current_time)
        else
          state
        end
      end)

    {:noreply, final_state}
  end

  @impl true
  def handle_cast({:cache_analytics_error, cache_key, reason, _from}, state) do
    pending_key = "pending_#{cache_key}"

    # Return error analytics data for graceful degradation
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

    # Reply to all pending requests for this specific cache_key
    case Map.get(state, pending_key) do
      nil ->
        # No pending requests (shouldn't happen but handle gracefully)
        {:noreply, state}

      pending_requests ->
        Enum.each(pending_requests, fn from ->
          GenServer.reply(from, {:ok, error_analytics})
        end)

        updated_state = Map.delete(state, pending_key)
        {:noreply, updated_state}
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

    cache =
      state
      |> Enum.filter(fn {key, _} -> not String.starts_with?(key, "analytics_#{event_id}_") end)
      |> Enum.into(%{})

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
    # Use private key for analytics
    api_key = get_private_api_key()
    project_id = get_project_id()

    cond do
      !api_key ->
        # Log only once per application start, not for every analytics call
        if not Application.get_env(:eventasaurus, :posthog_analytics_warning_logged, false) do
          Logger.info(
            "PostHog analytics not configured - private API key missing. Set POSTHOG_PRIVATE_API_KEY to enable."
          )

          Application.put_env(:eventasaurus, :posthog_analytics_warning_logged, true)
        end

        {:error, :no_api_key}

      !project_id ->
        if not Application.get_env(:eventasaurus, :posthog_project_warning_logged, false) do
          Logger.info(
            "PostHog analytics not configured - project ID missing. Set POSTHOG_PROJECT_ID to enable."
          )

          Application.put_env(:eventasaurus, :posthog_project_warning_logged, true)
        end

        {:error, :no_project_id}

      true ->
        # Validate and sanitize event_id to prevent injection
        case sanitize_event_id(event_id) do
          {:ok, safe_event_id} ->
            case fetch_all_analytics(safe_event_id, date_range, api_key) do
              {:ok,
               %{
                 visitors: visitors,
                 registrations: registrations,
                 votes: votes,
                 checkouts: checkouts
               }} ->
                registration_rate = calculate_rate(registrations, visitors)
                checkout_rate = calculate_rate(checkouts, registrations)

                {:ok,
                 %{
                   unique_visitors: visitors,
                   registrations: registrations,
                   votes_cast: votes,
                   ticket_checkouts: checkouts,
                   registration_rate: registration_rate,
                   checkout_conversion_rate: checkout_rate
                 }}

              {:error, reason} ->
                {:error, reason}
            end

          {:error, reason} ->
            Logger.debug("Invalid event_id provided for PostHog analytics: #{inspect(event_id)}")
            {:error, reason}
        end
    end
  end

  defp fetch_all_analytics(event_id, date_range, api_key) do
    # Sanitize event_id to prevent SQL injection
    sanitized_event_id = sanitize_for_sql(event_id)

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
        WHERE properties.event_id = '#{sanitized_event_id}'
          AND timestamp >= '#{days_ago(date_range)}'
          AND timestamp <= '#{current_time}'
        LIMIT 10000
        """
      }
    }

    case make_api_request("/query/", query_params, api_key) do
      {:ok, response} ->
        case parse_combined_analytics_response(response) do
          {:ok, metrics} -> {:ok, metrics}
          {:error, reason} -> {:error, reason}
        end

      {:error, {:request_failed, :timeout}} ->
        # Try a simpler query on timeout
        Logger.warning("PostHog analytics timeout, trying simplified query for event #{event_id}")
        fetch_simplified_analytics(event_id, date_range, api_key)

      error ->
        error
    end
  end

  defp fetch_simplified_analytics(event_id, date_range, api_key) do
    # Sanitize event_id to prevent SQL injection
    sanitized_event_id = sanitize_for_sql(event_id)

    # Much simpler query that should execute faster
    # Using LIMIT 1000 (vs 10000 in main query) for faster execution in timeout scenarios
    current_time = current_time_string()

    query_params = %{
      "query" => %{
        "kind" => "HogQLQuery",
        "query" => """
        SELECT
          count(DISTINCT person_id) as visitors
        FROM events
        WHERE properties.event_id = '#{sanitized_event_id}'
          AND event = 'event_page_viewed'
          AND timestamp >= '#{days_ago(date_range)}'
          AND timestamp <= '#{current_time}'
        LIMIT 1000
        """
      }
    }

    case make_api_request("/query/", query_params, api_key, 15000) do
      {:ok, response} ->
        case parse_simplified_analytics_response(response) do
          {:ok, visitors} ->
            # Return simplified metrics with only visitor count
            {:ok,
             %{
               visitors: visitors,
               registrations: 0,
               votes: 0,
               checkouts: 0
             }}

          {:error, reason} ->
            {:error, reason}
        end

      error ->
        error
    end
  end

  defp parse_simplified_analytics_response(response) do
    case response do
      %{"results" => [result]} when is_list(result) and length(result) == 1 ->
        [visitors] = result
        {:ok, visitors || 0}

      %{"results" => []} ->
        {:ok, 0}

      _ ->
        Logger.error("Unexpected simplified analytics response format: #{inspect(response)}")
        {:error, "Invalid response format from PostHog API"}
    end
  end

  defp parse_combined_analytics_response(response) do
    case response do
      %{"results" => [result]} when is_list(result) and length(result) == 4 ->
        [visitors, registrations, votes, checkouts] = result

        {:ok,
         %{
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

  defp make_api_request(endpoint, query_params, api_key, custom_timeout \\ nil) do
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

      # Use custom timeout if provided, otherwise default to 30 seconds for complex analytics queries
      timeout = custom_timeout || 30000

      case HTTPoison.post(url, body, headers, timeout: timeout, recv_timeout: timeout) do
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
    # PostHog event ingestion API endpoint - capture is at root level, not under /api
    url = "https://eu.i.posthog.com/capture/"

    # Build event payload according to PostHog format
    event_payload = %{
      api_key: api_key,
      event: event_name,
      distinct_id: user_id,
      properties:
        Map.merge(properties, %{
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
    start_time = System.monotonic_time(:millisecond)

    # Keep event tracking timeout shorter for better UX
    case HTTPoison.post(url, body, headers, timeout: 10000, recv_timeout: 10000) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Eventasaurus.Services.PosthogMonitor.record_success(:events, duration)
        Logger.debug("PostHog event sent successfully: #{event_name}")
        {:ok, :sent}

      {:ok, %HTTPoison.Response{status_code: 401, body: response_body}} ->
        Logger.warning(
          "PostHog authentication failed - check your API key configuration: #{response_body}"
        )

        {:error, {:api_error, 401}}

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        Logger.warning("PostHog event failed with status #{status_code}: #{response_body}")
        {:error, {:api_error, status_code}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("PostHog event request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp get_api_key do
    # For event tracking, use the project API key (same as public key in PostHog)
    System.get_env("POSTHOG_PUBLIC_API_KEY") || System.get_env("POSTHOG_API_KEY")
  end

  defp get_project_id do
    System.get_env("POSTHOG_PROJECT_ID")
  end

  defp get_private_api_key do
    # For analytics queries, use the personal/private API key
    System.get_env("POSTHOG_PRIVATE_API_KEY") || System.get_env("POSTHOG_PERSONAL_API_KEY")
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

  defp sanitize_for_sql(value) when is_binary(value) do
    # Escape single quotes and backslashes to prevent SQL injection
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "''")
  end

  defp sanitize_for_sql(value) when is_integer(value) do
    to_string(value)
  end

  defp sanitize_for_sql(_value) do
    # For any other type, return empty string to avoid injection
    ""
  end

  # Spawn async task to fetch analytics without blocking GenServer
  defp spawn_async_fetch(event_id, date_range, current_time, cache_key, from) do
    parent_pid = self()

    Task.start(fn ->
      case fetch_analytics_from_api(event_id, date_range) do
        {:ok, analytics_data} ->
          GenServer.cast(
            parent_pid,
            {:cache_analytics_result, cache_key, current_time, analytics_data, from}
          )

        {:error, reason} ->
          GenServer.cast(parent_pid, {:cache_analytics_error, cache_key, reason, from})
      end
    end)
  end

  # Clean up old cache entries to prevent unbounded growth
  defp cleanup_old_cache_entries(state, _current_time) do
    # Filter out pending_* entries since they don't have timestamp structure
    # and should be managed by async task completion handlers
    cache_entries =
      state
      |> Enum.filter(fn {key, value} ->
        # Only keep cache entries (not pending requests)
        not String.starts_with?(key, "pending_") and is_map(value) and
          Map.has_key?(value, :timestamp)
      end)
      |> Enum.sort_by(fn {_key, %{timestamp: ts}} -> ts end, :desc)
      # Remove oldest 10 entries
      |> Enum.take(@max_cache_entries - 10)

    # Preserve pending_* entries and add back the filtered cache entries
    pending_entries =
      state
      |> Enum.filter(fn {key, _value} ->
        String.starts_with?(key, "pending_")
      end)

    # Combine the kept cache entries with all pending entries
    cache_entries
    |> Enum.concat(pending_entries)
    |> Enum.into(%{})
  end
end
