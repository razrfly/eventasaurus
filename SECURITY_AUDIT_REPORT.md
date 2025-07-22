# Security Audit Report: Authentication & Authorization Vulnerabilities

**Date**: 2025-01-22  
**Scope**: Authentication middleware, API endpoints, frontend state management, and session handling  
**Focus**: Potential race conditions and bypassed authentication checks  

## Executive Summary

This security audit examined the Eventasaurus codebase for authentication and authorization vulnerabilities, particularly focusing on scenarios where users might be able to perform actions after their session has expired but before the system realizes they're no longer authenticated.

**Key Findings**:
- ✅ **Good**: Comprehensive authentication middleware with proper security measures
- ⚠️ **Medium Risk**: Potential race conditions between frontend state and backend validation
- ⚠️ **Medium Risk**: Session management complexities could lead to timing vulnerabilities
- ✅ **Good**: Most API endpoints properly implement authentication checks

## Detailed Findings

### 1. Authentication Middleware Analysis ✅

**Location**: `lib/eventasaurus_web/plugs/auth_plug.ex`

**Strengths**:
- Comprehensive authentication plugs with proper session validation
- Token refresh functionality with graceful handling
- Enhanced JWT validation and expiration checking
- Input sanitization and security logging
- Proper error handling for both browser and API requests

**Router Configuration** (`lib/eventasaurus_web/router.ex`):
- Well-structured pipeline architecture
- Proper use of authentication pipelines (`:authenticated`, `:api_authenticated`)
- LiveView sessions properly configured with auth hooks

### 2. Frontend Authentication State Management ⚠️

**Location**: `assets/js/app.js`, LiveView files

**Potential Vulnerabilities**:

1. **Client-Side Token Handling**:
   ```javascript
   // Line 461 in app.js - Tokens in URL fragments
   if (hash && hash.includes('access_token')) {
     const accessToken = params.get('access_token');
     const refreshToken = params.get('refresh_token');
   }
   ```
   - **Risk**: Tokens exposed in browser history and client-side JavaScript
   - **Impact**: Medium - Tokens could be extracted from browser history

2. **Session State Synchronization**:
   - Frontend may cache authentication state while backend session expires
   - No real-time session validation on frontend actions
   - **Risk**: User could initiate actions before frontend realizes session expired

### 3. Race Condition Analysis ⚠️

**Identified Scenarios**:

1. **Async Form Submissions**:
   - User submits form → Session expires during processing → Action completes without auth check
   - **Location**: Various controllers and LiveViews
   - **Risk Level**: Medium

2. **LiveView Mount vs. Authentication Check**:
   ```elixir
   # In EventManageLive.mount/3
   case socket.assigns[:user] do
     nil -> redirect(to: "/auth/login")
     user -> # Continue with logic
   ```
   - **Risk**: Brief window where user assignment might be stale

3. **Token Refresh Race Condition**:
   - Multiple simultaneous requests could trigger multiple refresh attempts
   - **Location**: `auth_plug.ex` lines 298-333, 341-384
   - **Risk**: Could lead to token confusion or session corruption

### 4. API Endpoint Authentication Review

**Well-Protected Endpoints** ✅:
- `/api/events/*` - Uses `:api_authenticated` pipeline
- `/api/users/search` - Enhanced security with permission checks
- `/api/orders/*` - Proper user ownership validation
- `/api/stripe/*` - HTTPS enforcement + authentication

**Potentially Vulnerable Patterns**:

1. **Public Search Endpoint**:
   ```elixir
   # search_controller.ex - No authentication required
   def unified(conn, params) do
     # Public endpoint - could be abused for data gathering
   ```
   - **Risk**: Low - But could be used for reconnaissance

2. **CSRF Token Handling**:
   - Some endpoints rely on session-based CSRF tokens
   - **Risk**: If session expires but CSRF token is cached, actions might still process

### 5. Session Management Complexities ⚠️

**Location**: `lib/eventasaurus_app/auth/auth.ex`

**Potential Issues**:

1. **Token Extraction Logic**:
   ```elixir
   defp extract_token(auth_data) do
     cond do
       is_binary(auth_data) -> auth_data
       is_map(auth_data) && Map.has_key?(auth_data, :access_token) -> auth_data.access_token
       # Multiple extraction methods could lead to confusion
   ```

2. **Session Duration Configuration**:
   ```elixir
   defp configure_session_duration(conn, remember_me) do
     if remember_me do
       max_age = 30 * 24 * 60 * 60  # 30 days
       configure_session(conn, max_age: max_age, renew: true)
   ```
   - **Risk**: Long session durations increase exposure window

## High-Priority Vulnerabilities

### 🚨 CRITICAL: Potential Authentication Bypass in LiveViews

**Issue**: Race condition between frontend state and backend validation could allow actions to process before authentication is fully validated.

**Evidence**: User reports being able to "edit things" or "change status" even when logged out, with the system realizing authentication failure after the action appears to complete.

**Location**: LiveView mount functions and event handlers

**Example Scenario**:
1. User opens EventManageLive page while authenticated
2. Session expires due to timeout
3. User performs action (edit event, change status)
4. Frontend allows action based on cached state
5. Backend processes action before checking current auth status
6. System eventually realizes user is not authenticated

### 🚨 HIGH: Frontend Form Submission Race Condition

**Issue**: Forms may submit successfully even when session has expired, with authentication check happening after form processing begins.

**Affected Areas**:
- Event editing forms
- User status changes
- Organizer management actions

## Recommended Fixes

### Immediate Actions (High Priority)

1. **Implement Real-Time Authentication Validation**:
   ```elixir
   # Add to all sensitive LiveView event handlers
   def handle_event("sensitive_action", _params, socket) do
     case validate_current_authentication(socket) do
       {:ok, socket} -> # Proceed with action
       {:error, :expired} -> 
         {:noreply, 
          socket 
          |> put_flash(:error, "Your session has expired. Please log in again.")
          |> redirect(to: "/auth/login")}
     end
   end
   ```

2. **Add Pre-Action Authentication Checks**:
   ```elixir
   # Add to form submission handlers
   plug :require_fresh_authentication when action in [:update, :delete, :create]
   
   def require_fresh_authentication(conn, _opts) do
     case validate_token_freshness(conn, max_age: 300) do  # 5 minutes
       :ok -> conn
       :expired -> 
         conn
         |> put_status(:unauthorized)
         |> json(%{error: "Session expired", action: "reauthenticate"})
         |> halt()
     end
   end
   ```

3. **Frontend Token Validation**:
   ```javascript
   // Add to critical form submissions
   function validateAuthBeforeSubmit() {
     return fetch('/api/auth/validate-token', {
       method: 'GET',
       credentials: 'include'
     }).then(response => {
       if (!response.ok) {
         window.location.href = '/auth/login';
         return false;
       }
       return true;
     });
   }
   ```

### Medium Priority Fixes

4. **Implement Token Refresh Mutex**:
   ```elixir
   # Prevent multiple simultaneous token refreshes
   defp maybe_refresh_token_with_lock(conn) do
     case :global.set_lock({:token_refresh, get_session(conn, :user_id)}, [node()], 5000) do
       true -> 
         result = maybe_refresh_token(conn)
         :global.del_lock({:token_refresh, get_session(conn, :user_id)})
         result
       false -> 
         # Another refresh in progress, wait and retry
         :timer.sleep(100)
         conn
     end
   end
   ```

5. **Add Session Activity Monitoring**:
   ```elixir
   plug :update_last_activity
   
   def update_last_activity(conn, _opts) do
     if conn.assigns[:user] do
       put_session(conn, :last_activity, System.system_time(:second))
     else
       conn
     end
   end
   ```

6. **Enhanced Frontend Session Management**:
   ```javascript
   // Add session heartbeat
   setInterval(() => {
     fetch('/api/auth/heartbeat', {
       method: 'POST',
       credentials: 'include'
     }).then(response => {
       if (!response.ok) {
         // Session expired, redirect to login
         window.location.href = '/auth/login?expired=true';
       }
     });
   }, 60000); // Check every minute
   ```

### Low Priority Improvements

7. **Secure Token Storage**:
   - Move tokens from URL fragments to secure HTTP-only cookies
   - Implement secure token exchange endpoint

8. **Add Comprehensive Audit Logging**:
   ```elixir
   def log_security_event(conn, event_type, details) do
     Logger.warning("Security Event: #{event_type}", [
       event_type: event_type,
       user_id: get_user_id(conn),
       remote_ip: get_remote_ip(conn),
       user_agent: get_user_agent(conn),
       session_id: get_session_id(conn),
       details: details,
       timestamp: DateTime.utc_now()
     ])
   end
   ```

## Implementation Priority

### Phase 1 (Immediate - Week 1)
- [ ] Add real-time auth validation to all LiveView sensitive actions
- [ ] Implement pre-action authentication checks for critical API endpoints
- [ ] Add frontend token validation for form submissions

### Phase 2 (High Priority - Week 2)
- [ ] Implement token refresh mutex to prevent race conditions
- [ ] Add session activity monitoring
- [ ] Enhanced frontend session management with heartbeat

### Phase 3 (Medium Priority - Month 1)
- [ ] Move to secure token storage mechanism
- [ ] Implement comprehensive audit logging
- [ ] Add automated security testing

## Testing Recommendations

1. **Automated Tests**:
   ```elixir
   test "rejects actions when session expires mid-request" do
     # Test race condition scenarios
   end
   
   test "validates authentication before processing sensitive actions" do
     # Test authentication bypass attempts
   end
   ```

2. **Manual Testing Scenarios**:
   - Open application, let session expire, attempt actions
   - Test multiple simultaneous token refresh attempts
   - Validate behavior when network connectivity is poor

## Conclusion

The Eventasaurus application has a solid foundation for authentication and authorization, but there are several areas where race conditions and timing issues could allow unauthorized actions to be processed. The recommended fixes focus on adding real-time validation and preventing the specific scenario described by the user where actions appear to succeed before the system realizes authentication has expired.

Implementing the Phase 1 fixes should immediately resolve the reported issue where users can perform actions after their session expires.