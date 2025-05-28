defmodule EventasaurusApp.Auth do
  @moduledoc """
  Main authentication interface for the application.
  Provides functions to authenticate users, store sessions,
  and retrieve the current user.
  """

  alias EventasaurusApp.Auth.{AuthHelper, Client}
  alias Plug.Conn

  @doc """
  Registers a new user with email, password, and name.

  Returns `{:ok, auth_data}` on success or `{:error, reason}` on failure.
  """
  def register(email, password, name) do
    AuthHelper.register_user(email, password, name)
  end

  @doc """
  Authenticates a user with email and password.

  Returns `{:ok, auth_data}` on success or `{:error, reason}` on failure.
  """
  def authenticate(email, password) do
    AuthHelper.authenticate_user(email, password)
  end

  @doc """
  Stores authentication data in the session.

  Returns `{:ok, conn}` on success or `{:error, reason}` on failure.
  """
  def store_session(conn, auth_data) do
    # Extract token from auth_data, handling potential formats
    token = extract_token(auth_data)

    if token do
      {:ok, Conn.put_session(conn, :access_token, token)}
    else
      {:error, :invalid_token}
    end
  end

  @doc """
  Clears all session data.
  """
  def clear_session(conn) do
    Conn.configure_session(conn, drop: true)
  end

  @doc """
  Gets the current user based on the access token in the session.

  Returns user data or nil if not authenticated.
  """
  def get_current_user(conn) do
    case Conn.get_session(conn, :access_token) do
      nil -> nil
      token ->
        case AuthHelper.get_current_user(token) do
          {:ok, user} -> user
          _ -> nil
        end
    end
  end

  @doc """
  Logs out a user by invalidating their token.

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  def logout(token) when is_binary(token) do
    Client.sign_out(token)
  end

  def logout(_), do: {:error, :invalid_token}

  @doc """
  Requests a password reset for the given email.

  Returns `{:ok, %{email: email}}` on success or `{:error, reason}` on failure.
  """
  def request_password_reset(email) do
    Client.reset_password(email)
  end

  @doc """
  Resets a password using a reset token.

  Returns `{:ok, _}` on success or `{:error, reason}` on failure.
  """
  def reset_password(token, new_password) do
    Client.update_password(token, new_password)
  end

  @doc """
  Signs up a new user with email, password, and additional metadata.

  This is an alias for register/3 but matches the naming convention
  used in the controllers.
  """
  def sign_up_with_email_and_password(email, password, metadata \\ %{}) do
    name = Map.get(metadata, :name, "")
    register(email, password, name)
  end

  @doc """
  Updates a user's password using a reset token.

  This is an alias for reset_password/2 but matches the naming convention
  used in the controllers.
  """
  def update_user_password(token, new_password) do
    reset_password(token, new_password)
  end

  @doc """
  Signs in a user with email and password.

  This is an alias for authenticate/2 but matches the naming convention
  used in the controllers.
  """
  def sign_in_with_email_and_password(email, password) do
    authenticate(email, password)
  end

  # Helper function to extract the token from different formats
  defp extract_token(auth_data) do
    cond do
      is_binary(auth_data) ->
        auth_data
      is_map(auth_data) && Map.has_key?(auth_data, :access_token) ->
        auth_data.access_token
      is_map(auth_data) && Map.has_key?(auth_data, "access_token") ->
        auth_data["access_token"]
      true ->
        nil
    end
  end
end
