defmodule EventasaurusApp.Auth.ServerAuth do
  @moduledoc """
  Server-side Supabase authentication handling.

  This module implements the authorization code flow instead of the implicit flow,
  eliminating the need for client-side JavaScript token handling.
  """

  require Logger

  @doc """
  Exchange an authorization code for tokens using OAuth2 standard flow.

  This is the secure, server-side equivalent of client-side token extraction.
  Uses proper OAuth2 authorization code flow with Basic authentication.
  """
  def exchange_code_for_tokens(code) do
    url = "#{get_auth_url()}/token?grant_type=authorization_code"

    # Get the site URL from config for redirect_uri parameter
    site_url = get_config()[:auth][:site_url] || "https://eventasaur.us"
    redirect_uri = "#{site_url}/auth/callback"

    # Use form-encoded body for OAuth2 standard
    body =
      URI.encode_query(%{
        "grant_type" => "authorization_code",
        "code" => code,
        "redirect_uri" => redirect_uri
      })

    # Use OAuth2 Basic authentication with client credentials
    api_key = get_api_key()
    service_key = get_service_role_key() || api_key
    basic_auth = Base.encode64("#{api_key}:#{service_key}")

    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Authorization", "Basic #{basic_auth}"},
      {"Accept", "application/json"}
    ]

    Logger.info("Exchanging authorization code for tokens: #{url}")

    case HTTPoison.post(url, body, headers, timeout: 5_000, recv_timeout: 8_000) do
      {:ok, %{status_code: 200, body: response_body}} ->
        with {:ok, response} <- Jason.decode(response_body) do
          Logger.info("Successfully exchanged code for tokens")
          {:ok, response}
        else
          {:error, decode_err} ->
            Logger.error("JSON decode error during code exchange: #{inspect(decode_err)}")
            {:error, %{message: "Invalid response from authentication service"}}
        end

      {:ok, %{status_code: status, body: response_body}} ->
        Logger.error("Code exchange failed with status #{status}: #{response_body}")
        {:error, %{status: status, message: "Failed to exchange code for tokens"}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP error during code exchange: #{inspect(reason)}")
        {:error, %{message: "Network error during authentication"}}
    end
  end

  @doc """
  Generate a password reset request with proper redirect URL.

  For now, this continues using the implicit flow but ensures proper redirect configuration.
  The authorization code flow will be implemented after testing the redirect fix.
  """
  def request_password_reset(email) do
    url = "#{get_auth_url()}/recover"

    # Get the site URL from config for redirect
    site_url = get_config()[:auth][:site_url] || "https://eventasaur.us"
    redirect_url = "#{site_url}/auth/callback"

    body =
      Jason.encode!(%{
        email: email,
        redirect_to: redirect_url
      })

    headers = [
      {"Content-Type", "application/json"},
      {"apikey", get_api_key()}
    ]

    Logger.info(
      "Requesting password reset with proper redirect: #{url} with redirect_to: #{redirect_url}"
    )

    case HTTPoison.post(url, body, headers, timeout: 5_000, recv_timeout: 8_000) do
      {:ok, %{status_code: status}} when status in [200, 204] ->
        Logger.info("Password reset request successful for email: #{email}")
        {:ok, %{email: email}}

      {:ok, %{status_code: status, body: response_body}} ->
        Logger.error("Password reset request failed with status #{status}: #{response_body}")
        {:error, %{status: status, message: "Failed to request password reset"}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP error during password reset request: #{inspect(reason)}")
        {:error, %{message: "Network error during password reset request"}}
    end
  end

  @doc """
  Get user information from access token using server-side API.

  This replaces client-side user data fetching.
  """
  def get_user_from_token(access_token) do
    url = "#{get_auth_url()}/user"

    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"apikey", get_api_key()}
    ]

    case HTTPoison.get(url, headers, timeout: 5_000, recv_timeout: 8_000) do
      {:ok, %{status_code: 200, body: response_body}} ->
        with {:ok, user} <- Jason.decode(response_body) do
          Logger.debug("Successfully retrieved user data")
          {:ok, user}
        else
          {:error, decode_err} ->
            Logger.error("JSON decode error getting user data: #{inspect(decode_err)}")
            {:error, %{message: "Invalid user response"}}
        end

      {:ok, %{status_code: status, body: response_body}} ->
        Logger.error("Failed to get user data with status #{status}: #{response_body}")
        {:error, %{status: status, message: "Failed to get user data"}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP error getting user data: #{inspect(reason)}")
        {:error, %{message: "Network error getting user data"}}
    end
  end

  @doc """
  Update user password using server-side API with recovery token.
  """
  def update_password_with_recovery(access_token, new_password) do
    url = "#{get_auth_url()}/user"

    body =
      Jason.encode!(%{
        password: new_password
      })

    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{access_token}"},
      {"apikey", get_api_key()}
    ]

    Logger.info("Updating password with recovery token")

    case HTTPoison.put(url, body, headers, timeout: 5_000, recv_timeout: 8_000) do
      {:ok, %{status_code: 200, body: response_body}} ->
        with {:ok, user} <- Jason.decode(response_body) do
          Logger.info("Password updated successfully")
          {:ok, user}
        else
          {:error, decode_err} ->
            Logger.error("JSON decode error updating password: #{inspect(decode_err)}")
            {:error, %{message: "Invalid response from authentication service"}}
        end

      {:ok, %{status_code: status, body: response_body}} ->
        Logger.error("Password update failed with status #{status}: #{response_body}")
        {:error, %{status: status, message: "Failed to update password"}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("HTTP error updating password: #{inspect(reason)}")
        {:error, %{message: "Network error updating password"}}
    end
  end

  # Private helper functions

  defp get_config do
    Application.get_env(:eventasaurus, :supabase)
  end

  defp get_auth_url do
    config = get_config()
    "#{config[:url]}/auth/v1"
  end

  defp get_api_key do
    get_config()[:api_key]
  end

  defp get_service_role_key do
    get_config()[:service_role_key]
  end
end
