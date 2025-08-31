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
    alias EventasaurusApp.Repo
    alias EventasaurusApp.Accounts.User
    
    @doc """
    Check for dev mode login and bypass normal auth if found.
    This runs BEFORE any normal authentication logic.
    """
    def init(opts), do: opts
    
    def call(conn, _opts) do
      # Only process if we have a dev mode login flag
      if get_session(conn, :dev_mode_login) == true do
        case get_session(conn, :current_user_id) do
          nil ->
            # Dev session corrupted, clear it
            conn
            |> delete_session(:dev_mode_login)
            |> delete_session(:current_user_id)
            
          user_id ->
            # Load the user and set auth_user directly
            case Repo.get(User, user_id) do
              nil ->
                # User doesn't exist, clear session
                conn
                |> delete_session(:dev_mode_login)
                |> delete_session(:current_user_id)
                
              user ->
                # SUCCESS: Set auth_user and skip all other auth
                # This completely bypasses the normal auth flow
                conn
                |> assign(:auth_user, user)
                |> assign(:dev_mode_auth, true)  # Flag to skip other auth checks
            end
        end
      else
        # Not a dev login, pass through to normal auth
        conn
      end
    end
  else
    # Production: this module does nothing
    def init(opts), do: opts
    def call(conn, _opts), do: conn
  end
end