defmodule EventasaurusApp.Auth do
  @moduledoc """
  The Auth context provides functions for user authentication.
  It serves as a facade over the Supabase client implementation.
  """

  alias EventasaurusApp.Auth.Client
  import Plug.Conn
  require Logger

  @doc """
  Register a new user with email and password.
  """
  def register(email, password, name \\ nil) do
    Client.sign_up(email, password, name)
  end

  @doc """
  Authenticate a user with email and password.
  """
  def authenticate(email, password) do
    Client.sign_in(email, password)
  end

  @doc """
  Log out a user.
  """
  def logout(token) do
    Client.sign_out(token)
  end

  @doc """
  Request a password reset for a user.
  """
  def request_password_reset(email) do
    Client.reset_password(email)
  end

  @doc """
  Reset a user's password using the reset token.
  """
  def reset_password(token, new_password) do
    Client.update_password(token, new_password)
  end

  @doc """
  Store authentication tokens in the session.
  """
  def store_session(conn, auth_data) do
    # Add debug logging to see the structure of auth_data
    Logger.debug("Auth data: #{inspect(auth_data)}")

    # Extract tokens from auth_data which could have different formats
    access_token = extract_token(auth_data, :access_token)
    refresh_token = extract_token(auth_data, :refresh_token)

    Logger.debug("Extracted access_token: #{inspect(access_token)}")
    Logger.debug("Extracted refresh_token: #{inspect(refresh_token)}")

    # Only proceed if we have both tokens
    if access_token && refresh_token do
      conn = conn
      |> put_session(:access_token, access_token)
      |> put_session(:refresh_token, refresh_token)
      |> configure_session(renew: true)

      {:ok, conn}
    else
      {:error, :invalid_auth_data}
    end
  end

  # Helper to extract tokens from different response formats
  defp extract_token(auth_data, token_key) do
    cond do
      # Pattern 1: Using atom keys
      is_map(auth_data) && Map.has_key?(auth_data, token_key) ->
        Map.get(auth_data, token_key)

      # Pattern 2: Using string keys
      is_map(auth_data) && Map.has_key?(auth_data, to_string(token_key)) ->
        Map.get(auth_data, to_string(token_key))

      # Pattern 3: Using camelCase keys
      is_map(auth_data) && token_key == :access_token && Map.has_key?(auth_data, "accessToken") ->
        Map.get(auth_data, "accessToken")
      is_map(auth_data) && token_key == :refresh_token && Map.has_key?(auth_data, "refreshToken") ->
        Map.get(auth_data, "refreshToken")

      # Pattern 4: Supabase standard format
      is_map(auth_data) && token_key == :access_token && Map.has_key?(auth_data, "access_token") ->
        Map.get(auth_data, "access_token")
      is_map(auth_data) && token_key == :refresh_token && Map.has_key?(auth_data, "refresh_token") ->
        Map.get(auth_data, "refresh_token")

      # Pattern 5: Using different key names
      is_map(auth_data) && token_key == :access_token && Map.has_key?(auth_data, "token") ->
        Map.get(auth_data, "token")
      is_map(auth_data) && token_key == :access_token && Map.has_key?(auth_data, "jwt") ->
        Map.get(auth_data, "jwt")

      # No match found
      true ->
        nil
    end
  end

  @doc """
  Clear authentication tokens from the session.
  """
  def clear_session(conn) do
    conn = conn
      |> delete_session(:access_token)
      |> delete_session(:refresh_token)
      |> configure_session(drop: true)

    conn
  end

  @doc """
  Get the current user from the session.
  """
  def get_current_user(conn) do
    # If we have an access token, try to get the user data
    with token when is_binary(token) <- get_session(conn, :access_token),
         {:ok, user} <- Client.get_user(token) do
      user
    else
      _ -> nil
    end
  end
end
