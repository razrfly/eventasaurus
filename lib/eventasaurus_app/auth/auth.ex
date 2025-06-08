defmodule EventasaurusApp.Auth do
  @moduledoc """
  Main authentication interface for the application.
  Provides functions to authenticate users, store sessions,
  and retrieve the current user.
  """

  alias EventasaurusApp.Auth.{AuthHelper, Client}
  alias Plug.Conn
  alias Phoenix.PubSub

  require Logger

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

  @doc """
  Exchange OAuth authorization code for session tokens.

  Handles the complete OAuth callback flow by exchanging the authorization
  code for tokens and syncing the user with our local database.

  Returns `{:ok, %{user: user, access_token: token}}` on success or `{:error, reason}` on failure.
  """
  def exchange_oauth_code(code) do
    AuthHelper.exchange_oauth_code(code)
  end

  @doc """
  Get OAuth authorization URL for a social provider.

  Returns the authorization URL that users should be redirected to for social login.

  ## Parameters
    - provider: "facebook" | "twitter" | other supported provider
    - redirect_to: Optional URL to redirect to after authentication
    - scopes: Optional scopes to request from the provider

  ## Returns
    The OAuth authorization URL string
  """
  def get_oauth_url(provider, redirect_to \\ nil, scopes \\ nil) do
    AuthHelper.get_oauth_url(provider, redirect_to, scopes)
  end

  @doc """
  Refreshes an expired session using a refresh token.

  Returns `{:ok, new_auth_data}` on success or `{:error, reason}` on failure.
  """
  def refresh_session(refresh_token) do
    case Client.refresh_session(refresh_token) do
      {:ok, auth_data} ->
        Logger.debug("Successfully refreshed session")
        {:ok, auth_data}
      {:error, reason} ->
        Logger.warning("Failed to refresh session: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Validates a session token without making external API calls.

  Performs basic validation checks on the token format.
  For full validation, use AuthHelper.get_current_user/1.
  """
  def validate_session_token(token) when is_binary(token) do
    # Basic JWT format validation
    case String.split(token, ".") do
      [_header, _payload, _signature] -> {:ok, :valid_format}
      _ -> {:error, :invalid_format}
    end
  end
  def validate_session_token(_), do: {:error, :invalid_token}

  @doc """
  Broadcasts authentication events to subscribed LiveView processes.

  Events include: :logged_in, :logged_out, :session_refreshed, :session_expired
  """
  def broadcast_auth_event(user_id, event, metadata \\ %{}) do
    topic = "user_auth:#{user_id}"
    message = {:auth_event, event, metadata}

    case PubSub.broadcast(EventasaurusApp.PubSub, topic, message) do
      :ok ->
        Logger.debug("Broadcasted auth event #{event} for user #{user_id}")
        :ok
      {:error, reason} ->
        Logger.error("Failed to broadcast auth event: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Subscribes the current process to authentication events for a user.
  """
  def subscribe_to_auth_events(user_id) do
    topic = "user_auth:#{user_id}"
    PubSub.subscribe(EventasaurusApp.PubSub, topic)
  end

  @doc """
  Enhanced logout that broadcasts the logout event and clears session.
  """
  def logout_with_broadcast(conn, user_id) do
    # Get the token before clearing session
    token = Conn.get_session(conn, :access_token)

    # Broadcast logout event
    broadcast_auth_event(user_id, :logged_out)

    # Clear the session
    conn = clear_session(conn)

    # Invalidate the token with Supabase
    if token do
      case logout(token) do
        :ok -> {:ok, conn}
        {:error, reason} ->
          Logger.warning("Failed to invalidate token with Supabase: #{inspect(reason)}")
          # Still return success since session is cleared locally
          {:ok, conn}
      end
    else
      {:ok, conn}
    end
  end

  @doc """
  Stores authentication data in session and broadcasts login event.
  """
  def store_session_with_broadcast(conn, auth_data, user_id) do
    case store_session(conn, auth_data) do
      {:ok, conn} ->
        broadcast_auth_event(user_id, :logged_in)
        {:ok, conn}
      error ->
        error
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
end
