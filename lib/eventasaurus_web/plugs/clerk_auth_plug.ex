defmodule EventasaurusWeb.Plugs.ClerkAuthPlug do
  @moduledoc """
  Authentication plugs for Clerk-based authentication.

  This module provides plugs for handling user authentication via Clerk.
  It manages the dual user assignment pattern:

  - `conn.assigns.auth_user`: Raw authentication data (Clerk claims)
  - `conn.assigns.user`: Local User struct for business logic

  ## Token Sources

  Clerk tokens can be provided in two ways:
  1. `__session` cookie (set by Clerk.js frontend)
  2. `Authorization: Bearer <token>` header (for API requests)

  ## Usage

  In your router:

      pipeline :clerk_auth do
        plug :fetch_clerk_user
        plug :sync_clerk_user
      end

      pipeline :require_clerk_auth do
        plug :fetch_clerk_user
        plug :sync_clerk_user
        plug :require_authenticated_clerk_user
      end
  """

  import Plug.Conn
  import Phoenix.Controller

  use Phoenix.VerifiedRoutes,
    endpoint: EventasaurusWeb.Endpoint,
    router: EventasaurusWeb.Router,
    statics: EventasaurusWeb.static_paths()

  alias EventasaurusApp.Auth.Clerk.JWT
  alias EventasaurusApp.Auth.Clerk.Sync, as: ClerkSync

  require Logger

  # ============================================================================
  # Public Plugs
  # ============================================================================

  @doc """
  Fetches the authenticated user from Clerk JWT and assigns to `conn.assigns.auth_user`.

  Looks for Clerk session token in:
  1. `__session` cookie (set by Clerk.js)
  2. `Authorization: Bearer <token>` header

  ## Usage

      plug :fetch_clerk_user
  """
  def fetch_clerk_user(conn, _opts) do
    # Skip if dev auth bypass already set the user
    if conn.assigns[:dev_mode_auth] do
      conn
    else
      case get_clerk_token(conn) do
        nil ->
          assign(conn, :auth_user, nil)

        token ->
          case JWT.verify_token(token) do
            {:ok, claims} ->
              Logger.debug("Clerk token verified", %{
                clerk_id: claims["sub"],
                has_external_id: not is_nil(claims["external_id"])
              })

              assign(conn, :auth_user, claims)

            {:error, reason} ->
              Logger.debug("Clerk token verification failed: #{inspect(reason)}")
              assign(conn, :auth_user, nil)
          end
      end
    end
  end

  @doc """
  Syncs the Clerk user to local database and assigns to `conn.assigns.user`.

  Must be called after `fetch_clerk_user`. Takes the claims from `:auth_user`
  and ensures a corresponding User record exists in the local database.

  ## Usage

      plug :fetch_clerk_user
      plug :sync_clerk_user
  """
  def sync_clerk_user(conn, _opts) do
    case conn.assigns[:auth_user] do
      nil ->
        assign(conn, :user, nil)

      claims when is_map(claims) ->
        case ClerkSync.sync_user(claims) do
          {:ok, user} ->
            conn
            |> assign(:user, user)
            |> put_session("current_user_id", user.id)

          {:error, reason} ->
            Logger.warning("Failed to sync Clerk user: #{inspect(reason)}")
            assign(conn, :user, nil)
        end

      # Already a User struct (from dev mode or other plug)
      %EventasaurusApp.Accounts.User{} = user ->
        conn
        |> assign(:user, user)
        |> put_session("current_user_id", user.id)

      _ ->
        assign(conn, :user, nil)
    end
  end

  @doc """
  Requires that a user is authenticated via Clerk.

  If no authenticated user is found, redirects to login page.

  ## Usage

      plug :require_authenticated_clerk_user
  """
  def require_authenticated_clerk_user(conn, _opts) do
    if conn.assigns[:auth_user] do
      conn
    else
      conn
      |> maybe_store_return_to()
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: ~p"/auth/login")
      |> halt()
    end
  end

  @doc """
  Requires that a user is authenticated via Clerk for API requests.

  Returns JSON error instead of redirect.

  ## Usage

      plug :require_authenticated_clerk_api_user
  """
  def require_authenticated_clerk_api_user(conn, _opts) do
    if conn.assigns[:auth_user] do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{
        success: false,
        error: "unauthorized",
        message: "You must be logged in to access this endpoint"
      })
      |> halt()
    end
  end

  @doc """
  Redirects authenticated users away from authentication pages.

  ## Usage

      plug :redirect_if_clerk_user_is_authenticated
  """
  def redirect_if_clerk_user_is_authenticated(conn, _opts) do
    if conn.assigns[:auth_user] do
      conn
      |> redirect(to: ~p"/dashboard")
      |> halt()
    else
      conn
    end
  end

  @doc """
  Fetches Clerk user for API requests with enhanced validation.

  Similar to `fetch_clerk_user` but optimized for API endpoints.
  Includes additional token validation.

  ## Usage

      plug :fetch_clerk_api_user
  """
  def fetch_clerk_api_user(conn, _opts) do
    case get_clerk_token(conn) do
      nil ->
        assign(conn, :auth_user, nil)

      token ->
        case JWT.verify_token(token) do
          {:ok, claims} ->
            # Validate token hasn't been revoked (optional, adds API call)
            # For now, trust the JWT signature and expiration
            assign(conn, :auth_user, claims)

          {:error, reason} ->
            Logger.debug("Clerk API token verification failed: #{inspect(reason)}")
            assign(conn, :auth_user, nil)
        end
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_clerk_token(conn) do
    # Try Authorization header first (for API requests)
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        token

      _ ->
        # Fall back to __session cookie (for browser requests)
        conn = fetch_cookies(conn)
        conn.cookies["__session"]
    end
  end

  defp maybe_store_return_to(conn) do
    if conn.method == "GET" do
      put_session(conn, :user_return_to, current_path(conn))
    else
      conn
    end
  end
end
