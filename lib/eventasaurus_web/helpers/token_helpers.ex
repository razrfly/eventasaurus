defmodule EventasaurusWeb.TokenHelpers do
  @moduledoc """
  Helper functions for managing authentication tokens, including
  refresh logic and token extraction from various response formats.
  """

  @doc """
  Get the current valid access token, handling token refresh scenarios.

  Checks if a token needs to be refreshed (expires within 10 minutes)
  and attempts to refresh it if possible.
  """
  def get_current_valid_token(session) do
    require Logger
    token = session["access_token"]
    refresh_token = session["refresh_token"]
    token_expires_at = session["token_expires_at"]

    # Log if token is missing from session
    if is_nil(token) do
      Logger.warning("No access_token found in session. Session keys: #{inspect(Map.keys(session))}")
    end

    # Check if we need to refresh the token
    if token && refresh_token && token_expires_at && should_refresh_token?(token_expires_at) do
      Logger.debug("Token needs refresh, attempting to refresh...")

      case EventasaurusApp.Auth.Client.refresh_token(refresh_token) do
        {:ok, auth_data} ->
          # Extract the new access token
          new_token = get_token_value(auth_data, "access_token")

          if new_token do
            Logger.debug("Token refreshed successfully")
            new_token
          else
            Logger.warning("Failed to extract new token from refresh response, using old token")
            token
          end

        {:error, reason} ->
          # Refresh failed, use original token
          Logger.warning("Token refresh failed: #{inspect(reason)}, using old token")
          token
      end
    else
      # Token is still valid or no refresh available
      token
    end
  end

  # Check if a token should be refreshed based on its expiration time
  defp should_refresh_token?(expires_at_iso) when is_binary(expires_at_iso) do
    case DateTime.from_iso8601(expires_at_iso) do
      {:ok, expires_at, _} ->
        # Refresh if token expires in next 10 minutes
        refresh_threshold = DateTime.utc_now() |> DateTime.add(600, :second)
        DateTime.compare(refresh_threshold, expires_at) == :gt

      _ ->
        false
    end
  end

  defp should_refresh_token?(_), do: false

  # Helper to extract token value from various response formats
  defp get_token_value(auth_data, key) do
    cond do
      is_map(auth_data) && Map.has_key?(auth_data, key) ->
        Map.get(auth_data, key)

      is_map(auth_data) && Map.has_key?(auth_data, String.to_atom(key)) ->
        Map.get(auth_data, String.to_atom(key))

      is_map(auth_data) && key == "access_token" && Map.has_key?(auth_data, "token") ->
        Map.get(auth_data, "token")

      true ->
        nil
    end
  end
end
