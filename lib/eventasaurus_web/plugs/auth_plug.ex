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

  # How long before token expiry should we attempt to refresh (in seconds)
  @refresh_window 300

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
      maybe_refresh_token(conn)
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
      |> redirect(to: ~p"/")
      |> halt()
    else
      conn
    end
  end

  @doc """
  Attempts to refresh the access token if it's near expiration.
  """
  defp maybe_refresh_token(conn) do
    refresh_token = get_session(conn, :refresh_token)

    # Get the current access token and check if it needs refreshing
    # In a real implementation, we'd check the token's expiry time
    # For now, we'll just always refresh it to demonstrate the flow
    if refresh_token do
      case Client.refresh_token(refresh_token) do
        {:ok, %{access_token: access_token, refresh_token: new_refresh_token}} ->
          # Update the session with the new tokens
          conn
          |> put_session(:access_token, access_token)
          |> put_session(:refresh_token, new_refresh_token)

        {:error, _reason} ->
          # If refresh fails, clear the session
          Auth.clear_session(conn)
          |> put_flash(:error, "Your session has expired. Please log in again.")
          |> redirect(to: ~p"/login")
          |> halt()
      end
    else
      conn
    end
  end
end
