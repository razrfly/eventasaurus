defmodule EventasaurusWeb.Dev.DevAuthPlug do
  @moduledoc """
  Development-only authentication bypass plug.

  This plug runs BEFORE the normal authentication system and provides
  a complete bypass when dev mode authentication is detected.

  In production, this module is replaced with a no-op that just passes
  the connection through unchanged.

  ## USE_PROD_DB Mode

  When connecting to a remote production database (USE_PROD_DB=true), the
  connection pool can become exhausted due to high latency. To avoid blocking
  every request with a database lookup, this plug caches the user struct
  directly in the session after the first successful load.
  """

  if Mix.env() == :dev do
    import Plug.Conn
    alias EventasaurusApp.Repo
    alias EventasaurusApp.Accounts.User

    @doc """
    Check for dev mode login and bypass normal auth if found.
    This runs BEFORE any normal authentication logic.
    """
    def init(opts), do: opts

    def call(conn, _opts) do
      require Logger
      # Only process if we have a dev mode login flag
      dev_mode_login = get_session(conn, "dev_mode_login")
      Logger.debug("🔧 DEV_AUTH_PLUG: dev_mode_login = #{inspect(dev_mode_login)}")

      if dev_mode_login == true do
        # First, check if we have a cached user struct in the session
        # This avoids hitting the DB on every request when USE_PROD_DB=true
        case get_session(conn, "dev_cached_user") do
          %User{id: cached_id} = cached_user ->
            # Verify cached user still exists in database (handles DB switch scenarios)
            case Repo.replica().get(User, cached_id) do
              nil ->
                # Cached user no longer exists - clear stale session
                Logger.warning(
                  "🔧 DEV_AUTH_PLUG: Cached user #{cached_id} not found in DB - clearing session"
                )

                conn
                |> delete_session("dev_mode_login")
                |> delete_session("current_user_id")
                |> delete_session("dev_cached_user")

              _user ->
                # Use cached user - it's valid
                Logger.debug("🔧 DEV_AUTH_PLUG: Using cached user #{cached_user.email}")

                conn
                |> assign(:auth_user, cached_user)
                |> assign(:dev_mode_auth, true)
            end

          _ ->
            # No cached user, need to load from DB (first request only)
            Logger.debug("🔧 DEV_AUTH_PLUG: Loading user from DB")
            load_and_cache_user(conn)
        end
      else
        # Not a dev login, pass through to normal auth
        Logger.debug("🔧 DEV_AUTH_PLUG: No dev login, passing through")
        conn
      end
    end

    # Load user from database and cache in session for future requests
    defp load_and_cache_user(conn) do
      case get_session(conn, "current_user_id") do
        nil ->
          # Dev session corrupted, clear it
          conn
          |> delete_session("dev_mode_login")
          |> delete_session("current_user_id")
          |> delete_session("dev_cached_user")

        user_id ->
          # Load the user - this only happens once per session
          case Repo.replica().get(User, user_id) do
            nil ->
              # User doesn't exist, clear session
              conn
              |> delete_session("dev_mode_login")
              |> delete_session("current_user_id")
              |> delete_session("dev_cached_user")

            user ->
              # SUCCESS: Cache user in session and set auth_user
              conn
              |> put_session("dev_cached_user", user)
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
