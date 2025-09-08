defmodule EventasaurusWeb.SpotifyController do
  @moduledoc """
  Controller for Spotify API integration endpoints.
  
  Provides access token management for client-side Spotify API calls.
  This allows the frontend to make direct API calls while keeping
  credentials secure on the server side.
  """
  
  use EventasaurusWeb, :controller
  require Logger

  @doc """
  Get a Spotify access token for client-side API calls.
  
  Returns a client credentials access token that can be used
  for search operations and public data access.
  """
  def get_token(conn, _params) do
    case get_client_credentials_token() do
      {:ok, token_data} ->
        conn
        |> put_status(:ok)
        |> json(token_data)
        
      {:error, reason} ->
        Logger.error("Failed to get Spotify token: #{inspect(reason)}")
        
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "Spotify service temporarily unavailable"})
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_client_credentials_token do
    client_id = System.get_env("SPOTIFY_CLIENT_ID")
    client_secret = System.get_env("SPOTIFY_CLIENT_SECRET")

    if is_nil(client_id) or is_nil(client_secret) do
      {:error, "Spotify credentials not configured"}
    else
      request_token(client_id, client_secret)
    end
  end

  defp request_token(client_id, client_secret) do
    auth_url = "https://accounts.spotify.com/api/token"
    credentials = Base.encode64("#{client_id}:#{client_secret}")
    
    headers = [
      {"Authorization", "Basic #{credentials}"},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    body = "grant_type=client_credentials"

    case HTTPoison.post(auth_url, body, headers, timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"access_token" => token, "expires_in" => expires_in}} ->
            {:ok, %{
              access_token: token,
              expires_in: expires_in,
              token_type: "Bearer"
            }}
          
          {:error, _} ->
            {:error, "Failed to parse Spotify auth response"}
        end
      
      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        Logger.error("Spotify auth failed: #{status} - #{body}")
        {:error, "Spotify authentication failed with status #{status}"}
      
      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Spotify auth request failed: #{inspect(reason)}")
        {:error, "Network error during Spotify authentication"}
    end
  end
end