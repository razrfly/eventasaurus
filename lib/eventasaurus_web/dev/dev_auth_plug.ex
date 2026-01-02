defmodule EventasaurusWeb.Dev.DevAuthPlug do
  @moduledoc """
  Development-only authentication bypass plug.

  This plug runs BEFORE the normal authentication system and provides
  a complete bypass when dev mode authentication is detected.

  In production, this module is replaced with a no-op that just passes
  the connection through unchanged.
  """

  if Mix.env() == :dev do
    import Plug.Conn
    require Logger
    alias EventasaurusApp.Repo
    alias EventasaurusApp.Accounts.User

    @doc """
    Check for dev mode login and bypass normal auth if found.
    This runs BEFORE any normal authentication logic.
    """
    def init(opts), do: opts

    def call(conn, _opts) do
      # Skip dev auth for readonly sessions (cacheable anonymous requests)
      # These are definitionally anonymous so no need to check for dev login
      if conn.assigns[:readonly_session] do
        conn
      else
        call_with_session(conn)
      end
    end

    defp call_with_session(conn) do
      # Only process if we have a dev mode login flag
      dev_mode_login = get_session(conn, "dev_mode_login")

      if dev_mode_login == true do
        # Load user from database using current_user_id
        # NOTE: We intentionally do NOT cache the User struct in the session
        # because Ecto schemas are too large and cause cookie overflow (4KB limit)
        load_user(conn)
      else
        # Not a dev login, pass through to normal auth
        conn
      end
    end

    # Load user from database on each request
    # This is fine for dev mode - the slight overhead is acceptable
    defp load_user(conn) do
      case get_session(conn, "current_user_id") do
        nil ->
          # Dev session corrupted, clear it
          conn
          |> delete_session("dev_mode_login")
          |> delete_session("current_user_id")

        user_id ->
          case Repo.replica().get(User, user_id) do
            nil ->
              # User doesn't exist, clear session
              conn
              |> delete_session("dev_mode_login")
              |> delete_session("current_user_id")

            user ->
              # Set auth_user for the request
              conn
              |> assign(:auth_user, user)
              |> assign(:dev_mode_auth, true)
          end
      end
    end
  else
    # Production: this module does nothing
    def init(opts), do: opts
    def call(conn, _opts), do: conn
  end
end
