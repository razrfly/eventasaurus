defmodule EventasaurusApp.Auth do
  @moduledoc """
  Main authentication interface for the application.
  Provides functions to authenticate users, store sessions,
  and retrieve the current user.
  """

  import Plug.Conn
  alias EventasaurusApp.Auth.{AuthHelper, Client}

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
  Stores authentication data in the session with configurable duration.

  Returns `{:ok, conn}` on success or `{:error, reason}` on failure.

  When remember_me is true, sessions persist for 30 days.
  When remember_me is false, sessions expire when browser closes.
  """
  def store_session(conn, auth_data, remember_me \\ true) do
    # Extract token from auth_data, handling potential formats
    token = extract_token(auth_data)
    refresh_token = extract_refresh_token(auth_data)

    if token do
      conn = conn
      |> put_session(:access_token, token)
      |> maybe_put_refresh_token(refresh_token)
      |> configure_session_duration(remember_me)

      {:ok, conn}
    else
      {:error, :invalid_token}
    end
  end

  @doc """
  Clears all session data.
  """
  def clear_session(conn) do
    configure_session(conn, drop: true)
  end

  @doc """
  Gets the current user based on the access token in the session.

  Returns user data or nil if not authenticated.
  """
  def get_current_user(conn) do
    case get_session(conn, :access_token) do
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
  Updates the current authenticated user's password.

  This function is used during password recovery when the user is temporarily
  authenticated via a recovery token.

  Returns `{:ok, result}` on success or `{:error, reason}` on failure.
  """
  def update_current_user_password(conn, new_password) do
    access_token = get_session(conn, :access_token)

    if access_token do
      Client.update_user_password(access_token, new_password)
    else
      {:error, :no_authentication_token}
    end
  end

  @doc """
  Resets a password using a reset token.

  Returns `{:ok, result}` on success or `{:error, reason}` on failure.
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

  @doc """
  Sign in with Facebook OAuth using authorization code.

  Returns `{:ok, auth_data}` on success or `{:error, reason}` on failure.
  """
  def sign_in_with_facebook_oauth(code) do
    Client.sign_in_with_facebook_oauth(code)
  end

  @doc """
  Generate Facebook OAuth login URL.

  Returns the URL string to redirect users to Facebook authentication.
  """
  def get_facebook_oauth_url do
    Client.get_facebook_oauth_url()
  end

  @doc """
  Link a Facebook account to the current authenticated user.

  Returns `{:ok, user_data}` on success or `{:error, reason}` on failure.
  """
  def link_facebook_account(conn, facebook_oauth_code) do
    access_token = get_session(conn, :access_token)

    if access_token do
      Client.link_facebook_account(access_token, facebook_oauth_code)
    else
      {:error, :no_authentication_token}
    end
  end

  @doc """
  Unlink a Facebook account from the current authenticated user.

  Returns `{:ok, %{}}` on success or `{:error, reason}` on failure.
  """
  def unlink_facebook_account(conn, identity_id) do
    access_token = get_session(conn, :access_token)

    if access_token do
      Client.unlink_facebook_account(access_token, identity_id)
    else
      {:error, :no_authentication_token}
    end
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

  # Helper function to extract refresh token from auth data
  defp extract_refresh_token(auth_data) do
    cond do
      is_map(auth_data) && Map.has_key?(auth_data, :refresh_token) ->
        auth_data.refresh_token
      is_map(auth_data) && Map.has_key?(auth_data, "refresh_token") ->
        auth_data["refresh_token"]
      true ->
        nil
    end
  end

  # Helper function to store refresh token if available
  defp maybe_put_refresh_token(conn, nil), do: conn
  defp maybe_put_refresh_token(conn, refresh_token) do
    put_session(conn, :refresh_token, refresh_token)
  end

  # Helper function to configure session duration based on remember_me preference
  defp configure_session_duration(conn, remember_me) do
    if remember_me do
      # Remember me: persistent session for 30 days
      max_age = 30 * 24 * 60 * 60  # 30 days in seconds
      configure_session(conn, max_age: max_age, renew: true)
    else
      # Don't remember: session cookie (expires when browser closes)
      configure_session(conn, max_age: nil, renew: true)
    end
  end
end
