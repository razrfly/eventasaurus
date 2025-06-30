defmodule Eventasaurus.Services.PosthogService do
  @moduledoc """
  Service for tracking events to PostHog analytics platform.

  Provides async event tracking to avoid blocking the main application flow.
  Handles errors gracefully and logs issues for debugging.
  """

  require Logger

  @doc """
  Track an event for a specific user.

  ## Parameters
  - distinct_id: User identifier (typically user.id or supabase_id)
  - event_name: Name of the event to track
  - properties: Map of additional properties to include with the event

  ## Examples
      PosthogService.track_event("user_123", "event_created", %{event_id: 456})
      PosthogService.track_event("user_123", "auth_login", %{method: "email"})
  """
  def track_event(distinct_id, event_name, properties \\ %{}) do
    config = Application.get_env(:eventasaurus, :posthog, [])

    if config[:api_key] do
      Task.start(fn ->
        send_event(distinct_id, event_name, properties, config)
      end)
    else
      Logger.warning("PostHog API key not configured, skipping event: #{event_name}")
      :ok
    end
  end

  @doc """
  Identify a user with their properties.

  Call this when a user logs in or when you want to update user properties.

  ## Parameters
  - distinct_id: User identifier
  - properties: Map of user properties to set

  ## Examples
      PosthogService.identify_user("user_123", %{email: "user@example.com", name: "John Doe"})
  """
  def identify_user(distinct_id, properties \\ %{}) do
    config = Application.get_env(:eventasaurus, :posthog, [])

    if config[:api_key] do
      Task.start(fn ->
        send_identify(distinct_id, properties, config)
      end)
    else
      Logger.warning("PostHog API key not configured, skipping identify for: #{distinct_id}")
      :ok
    end
  end

  @doc """
  Reset/clear user session.

  Call this when a user logs out to clear their session.
  """
  def reset_user(distinct_id) do
    config = Application.get_env(:eventasaurus, :posthog, [])

    if config[:api_key] do
      Task.start(fn ->
        send_reset(distinct_id, config)
      end)
    else
      Logger.warning("PostHog API key not configured, skipping reset for: #{distinct_id}")
      :ok
    end
  end

  # Private functions for HTTP requests

  defp send_event(distinct_id, event_name, properties, config) do
    payload = %{
      "api_key" => config[:api_key],
      "event" => event_name,
      "distinct_id" => to_string(distinct_id),
      "properties" => Map.merge(properties, %{
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "$lib" => "eventasaurus-elixir"
      })
    }

    case make_request("#{config[:host]}/capture/", payload) do
      {:ok, %{status_code: 200}} ->
        Logger.debug("PostHog event tracked: #{event_name} for #{distinct_id}")
        :ok
      {:ok, response} ->
        Logger.error("PostHog tracking failed with status #{response.status_code}: #{event_name}")
        :error
      {:error, reason} ->
        Logger.error("PostHog tracking failed: #{inspect(reason)} for event: #{event_name}")
        :error
    end
  end

  defp send_identify(distinct_id, properties, config) do
    payload = %{
      "api_key" => config[:api_key],
      "distinct_id" => to_string(distinct_id),
      "$set" => properties
    }

    case make_request("#{config[:host]}/engage/", payload) do
      {:ok, %{status_code: 200}} ->
        Logger.debug("PostHog user identified: #{distinct_id}")
        :ok
      {:ok, response} ->
        Logger.error("PostHog identify failed with status #{response.status_code}")
        :error
      {:error, reason} ->
        Logger.error("PostHog identify failed: #{inspect(reason)}")
        :error
    end
  end

  defp send_reset(distinct_id, config) do
    # PostHog doesn't have a specific reset endpoint, but we can track a logout event
    send_event(distinct_id, "$logout", %{}, config)
  end

  defp make_request(url, payload) do
    headers = [{"Content-Type", "application/json"}]
    body = Jason.encode!(payload)

    HTTPoison.post(url, body, headers, recv_timeout: 5000, timeout: 5000)
  rescue
    e ->
      Logger.error("PostHog request exception: #{inspect(e)}")
      {:error, e}
  end
end
