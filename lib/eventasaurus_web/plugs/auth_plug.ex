defmodule EventasaurusWeb.Plugs.AuthPlug do
  @moduledoc """
  Authentication plugs for Phoenix controllers.

  This module provides plugs for handling user authentication in controllers.
  It manages the dual user assignment pattern:

  - `conn.assigns.auth_user`: Raw authentication data from Supabase (internal use only)
  - Controllers should process this into a local User struct for business logic

  ## Available Plugs

  1. `fetch_auth_user` - Loads the authenticated user from the session and assigns it to conn
  2. `require_authenticated_user` - Ensures a user is authenticated or redirects to login
  3. `redirect_if_user_is_authenticated` - Redirects authenticated users away from auth pages
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
  Fetches the authenticated user from the session and assigns to `conn.assigns.auth_user`.

  This plug extracts the access token from the session and fetches the user data
  from Supabase. Controllers should process this raw data into a local User struct
  for business logic operations.

  ## Usage

      plug :fetch_auth_user
  """
  def fetch_auth_user(conn, _opts) do
    user = Auth.get_current_user(conn)
    assign(conn, :auth_user, user)
  end

  @doc """
  Processes the auth_user into a local User struct and assigns to `conn.assigns.user`.

  This plug takes the raw auth data from `:auth_user` and converts it into a
  proper User struct for use in templates and business logic.

  ## Usage

      plug :assign_user_struct
  """
  def assign_user_struct(conn, _opts) do
    user = case ensure_user_struct(conn.assigns[:auth_user]) do
      {:ok, user} -> user
      {:error, _} -> nil
    end
    assign(conn, :user, user)
  end

  @doc """
  Requires that a user is authenticated.

  If no authenticated user is found in `conn.assigns.auth_user`, redirects to login page.
  For LiveView routes, skips setting flash message since the LiveView auth hook will handle it.

  ## Usage

      plug :require_authenticated_user
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:auth_user] do
      conn = maybe_refresh_token(conn)
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: ~p"/auth/login")
      |> halt()
    end
  end

  @doc """
  Requires that a user is authenticated for API requests.

  If no authenticated user is found in `conn.assigns.auth_user`, returns JSON error.

  ## Usage

      plug :require_authenticated_api_user
  """
  def require_authenticated_api_user(conn, _opts) do
    if conn.assigns[:auth_user] do
      conn = maybe_refresh_token_api(conn)
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> Phoenix.Controller.json(%{
        success: false,
        error: "unauthorized",
        message: "You must be logged in to access this endpoint"
      })
      |> halt()
    end
  end

  @doc """
  Redirects authenticated users away from authentication pages.

  Useful for login/register pages that shouldn't be accessible to already
  authenticated users.

  ## Usage

      plug :redirect_if_user_is_authenticated
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:auth_user] do
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
            |> redirect(to: ~p"/auth/login")
            |> halt()
          end

        {:error, _reason} ->
          # If refresh fails, clear the session and redirect to login
          Auth.clear_session(conn)
          |> put_flash(:error, "Your session has expired. Please log in again.")
          |> redirect(to: ~p"/auth/login")
          |> halt()
      end
    else
      conn
    end
  end

  @doc """
  Attempts to refresh the access token if it's near expiration for API requests.

  Returns the updated connection with new tokens if refreshed,
  or returns JSON error if refresh fails.
  """
  def maybe_refresh_token_api(conn) do
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
            # If tokens couldn't be extracted, return JSON error
            conn
            |> put_status(:unauthorized)
            |> Phoenix.Controller.json(%{
              success: false,
              error: "session_expired",
              message: "Your session has expired. Please log in again."
            })
            |> halt()
          end

        {:error, _reason} ->
          # If refresh fails, return JSON error
          conn
          |> put_status(:unauthorized)
          |> Phoenix.Controller.json(%{
            success: false,
            error: "session_expired",
            message: "Your session has expired. Please log in again."
          })
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

  # Helper function to ensure we have a proper User struct
  defp ensure_user_struct(nil), do: {:error, :no_user}
  defp ensure_user_struct(%EventasaurusApp.Accounts.User{} = user), do: {:ok, user}
  defp ensure_user_struct(%{"id" => _supabase_id} = supabase_user) do
    EventasaurusApp.Accounts.find_or_create_from_supabase(supabase_user)
  end
  defp ensure_user_struct(_), do: {:error, :invalid_user_data}
end
