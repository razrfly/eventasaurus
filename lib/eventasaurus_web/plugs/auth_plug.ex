defmodule EventasaurusWeb.Plugs.AuthPlug do
  @moduledoc """
  Plug for handling authentication and session persistence.

  This plug provides several functions:

  1. `fetch_current_user` - Loads the current user from the session and assigns it to conn
  2. `require_authenticated_user` - Ensures the user is authenticated, redirects to login if not
  3. `redirect_if_user_is_authenticated` - Redirects to dashboard if already authenticated
  """

  import Plug.Conn
  import Phoenix.Controller

  # Import verified routes for ~p sigil
  use Phoenix.VerifiedRoutes,
    endpoint: EventasaurusWeb.Endpoint,
    router: EventasaurusWeb.Router,
    statics: EventasaurusWeb.static_paths()

  alias EventasaurusApp.Auth
  alias EventasaurusApp.Auth.Client

  # We'll use this in a future implementation for token expiry checks
  # For now we can just remove it since it's not being used
  # @refresh_window 300

  @doc """
  Fetches the current user from the session and assigns it to the connection.
  """
  def fetch_current_user(conn, _opts) do
    user = Auth.get_current_user(conn)
    assign(conn, :current_user, user)
  end

  @doc """
  Requires that a user is authenticated.

  If not authenticated, redirects to the login page with an error message.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn = maybe_refresh_token(conn)
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  @doc """
  Redirects to the dashboard if the user is already authenticated.

  Useful for login/registration pages that shouldn't be accessible if logged in.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: ~p"/dashboard")
      |> halt()
    else
      conn
    end
  end

  @doc """
  Attempts to refresh the access token if it's near expiration.

  Returns the updated connection with new tokens if refreshed,
  or redirects to login if refresh fails.
  """
  def maybe_refresh_token(conn) do
    refresh_token = get_session(conn, :refresh_token)

    # Only try to refresh if we have a refresh token
    if refresh_token do
      case Client.refresh_token(refresh_token) do
        {:ok, auth_data} ->
          # Extract the tokens from the response
          access_token = get_token_value(auth_data, "access_token")
          new_refresh_token = get_token_value(auth_data, "refresh_token")

          if access_token && new_refresh_token do
            # Update the session with the new tokens
            conn
            |> put_session(:access_token, access_token)
            |> put_session(:refresh_token, new_refresh_token)
            |> configure_session(renew: true)
          else
            # If tokens couldn't be extracted, clear the session and redirect
            Auth.clear_session(conn)
            |> put_flash(:error, "Your session has expired. Please log in again.")
            |> redirect(to: ~p"/login")
            |> halt()
          end

        {:error, _reason} ->
          # If refresh fails, clear the session and redirect to login
          Auth.clear_session(conn)
          |> put_flash(:error, "Your session has expired. Please log in again.")
          |> redirect(to: ~p"/login")
          |> halt()
      end
    else
      conn
    end
  end

  # Helper to get a token value from various response formats
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
