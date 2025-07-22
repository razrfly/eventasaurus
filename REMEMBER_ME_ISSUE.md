# "Remember Me" Session Persistence Issue

## Problem Summary

The "Remember me" checkbox on the login form is supposed to keep users logged in for 30 days when checked (which is the default state). However, sessions are expiring within 24 hours regardless of this setting, forcing users to log in daily.

## Root Cause Analysis

After analyzing the authentication system, I've identified the primary issue:

### 1. Session Cookie Configuration Conflict

The application has conflicting session configurations:

#### In `lib/eventasaurus_web/endpoint.ex`:
```elixir
@session_options [
  store: :cookie,
  key: "_eventasaurus_key",
  signing_salt: "ouM7Fmf1",
  max_age: 30 * 24 * 60 * 60,  # 30 days default
  same_site: "Lax",
  secure: Application.compile_env(:eventasaurus, :environment) == :prod,
  http_only: true
]
```

#### In `lib/eventasaurus_app/auth/auth.ex`:
```elixir
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
```

### 2. Token Refresh Issues

The application uses JWT tokens from Supabase which have their own expiration times (typically 1 hour for access tokens). While the code attempts to handle token refresh in `auth_plug.ex`, the session cookie itself might be getting overwritten or not properly persisting the "remember me" preference across token refreshes.

### 3. Session Renewal on Every Request

In `auth_plug.ex`, when tokens are refreshed:
```elixir
conn
|> put_session(:access_token, access_token)
|> put_session(:refresh_token, new_refresh_token)
|> configure_session(renew: true)  # This might reset the max_age
```

The `configure_session(renew: true)` call without specifying `max_age` might be resetting the session duration to the default Phoenix session behavior.

## Recommended Fixes

### Fix 1: Preserve Remember Me State During Token Refresh

Store the remember_me preference in the session and use it during token refresh:

```elixir
# In auth.ex - store_session function
def store_session(conn, auth_data, remember_me \\ true) do
  # ... existing code ...
  conn = conn
  |> put_session(:access_token, token)
  |> maybe_put_refresh_token(refresh_token)
  |> put_session(:remember_me, remember_me)  # Store the preference
  |> configure_session_duration(remember_me)
  # ...
end

# In auth_plug.ex - maybe_refresh_token function
def maybe_refresh_token(conn) do
  refresh_token = get_session(conn, :refresh_token)
  remember_me = get_session(conn, :remember_me) || true  # Default to true
  
  if refresh_token do
    case Client.refresh_token(refresh_token) do
      {:ok, auth_data} ->
        # ... existing token extraction ...
        if access_token && new_refresh_token do
          # Preserve the remember_me setting
          max_age = if remember_me, do: 30 * 24 * 60 * 60, else: nil
          
          conn
          |> put_session(:access_token, access_token)
          |> put_session(:refresh_token, new_refresh_token)
          |> configure_session(renew: true, max_age: max_age)
        else
          # ... error handling ...
        end
```

### Fix 2: Use Server-Side Session Store

Consider using a server-side session store (like Redis or database-backed sessions) instead of cookie-based sessions for better control over session lifetime:

```elixir
# In endpoint.ex
@session_options [
  store: :ets,  # or :redis, :mnesia, or custom store
  key: "_eventasaurus_key",
  table: :session,
  max_age: 30 * 24 * 60 * 60,
  # ... other options
]
```

### Fix 3: Implement Proper Session Extension Logic

Add a dedicated session extension mechanism that runs on each authenticated request:

```elixir
# In auth_plug.ex
def extend_session_if_remember_me(conn, _opts) do
  if get_session(conn, :remember_me) == true do
    configure_session(conn, renew: true, max_age: 30 * 24 * 60 * 60)
  else
    conn
  end
end
```

### Fix 4: Add Session Lifetime Monitoring

Add logging to track when sessions are created and their expected expiration:

```elixir
def store_session(conn, auth_data, remember_me \\ true) do
  # ... existing code ...
  
  session_expires_at = if remember_me do
    DateTime.utc_now() |> DateTime.add(30 * 24 * 60 * 60, :second)
  else
    nil
  end
  
  Logger.info("Session created with remember_me=#{remember_me}, expires_at=#{session_expires_at}")
  
  conn = conn
  |> put_session(:session_created_at, DateTime.utc_now())
  |> put_session(:session_expires_at, session_expires_at)
  # ...
end
```

## Testing the Fix

1. Create test cases that verify session persistence:
   - Login with "remember me" checked
   - Wait 25 hours (or mock time)
   - Verify session is still valid
   - Verify token refresh preserves session duration

2. Add monitoring to track session lifetimes in production

3. Consider adding a "Session will expire in X days" indicator in the UI

## Additional Considerations

1. **Security**: While 30-day sessions improve UX, ensure proper security measures:
   - Implement session invalidation on password change
   - Add ability to view/revoke active sessions
   - Consider shorter durations for sensitive operations

2. **Browser Behavior**: Some browsers may clear cookies despite settings:
   - Test across different browsers
   - Consider localStorage/sessionStorage for remember_me preference backup

3. **Token vs Session Lifetime**: Clarify the relationship between:
   - JWT token expiration (1 hour)
   - Refresh token expiration (varies)
   - Session cookie expiration (30 days when remember_me=true)

## Files Affected

- `lib/eventasaurus_web/endpoint.ex` - Session configuration
- `lib/eventasaurus_app/auth/auth.ex` - Session storage logic
- `lib/eventasaurus_web/plugs/auth_plug.ex` - Token refresh logic
- `lib/eventasaurus_web/controllers/auth/auth_controller.ex` - Login handling

## Priority

High - This is a significant UX issue affecting all users who expect to stay logged in.