# Authentication Flow Documentation

## Overview

This document describes the enhanced authentication flow implemented in June 2025 for Eventasaurus. The system now uses a secure email confirmation process for event registration while maintaining backwards compatibility.

## Authentication Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          Event Registration Authentication Flow                  │
└─────────────────────────────────────────────────────────────────────────────────┘

User visits event page (/event-slug)
            │
            ▼
    ┌───────────────┐
    │ Submit Email  │
    │ for Event     │
    └───────┬───────┘
            │
            ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│                         Backend Processing                                   │
│                                                                               │
│ 1. Auth.Client.sign_in_with_otp(email, event_context)                       │
│    ├─ Uses /auth/v1/otp endpoint (NOT admin API)                            │
│    ├─ Includes event context in metadata                                     │
│    └─ Sets callback URL with event info                                      │
│                                                                               │
│ 2. Events.create_or_find_supabase_user(email, event_context)                │
│    ├─ Checks if user exists in local DB                                      │
│    ├─ If exists: Creates participant immediately                             │
│    └─ If new: Waits for email confirmation                                   │
└───────────────────────────────────────────────────────────────────────────────┘
            │
            ▼
    ┌───────────────┐
    │   Response    │
    │   Handling    │
    └───────┬───────┘
            │
   ┌────────┴────────┐
   │                 │
   ▼                 ▼
┌─────────────────┐ ┌─────────────────┐
│ Existing User   │ │    New User     │
│ {:ok, :signed}  │ │{:ok, :email_sent}│
└─────┬───────────┘ └─────┬───────────┘
      │                   │
      ▼                   ▼
┌─────────────────┐ ┌─────────────────┐
│ Show Success    │ │ Show "Check     │
│ "Registered!"   │ │ Your Email"     │
│                 │ │ Message         │
└─────────────────┘ └─────┬───────────┘
                          │
                          ▼
                    ┌─────────────────┐
                    │ User clicks     │
                    │ email link      │
                    └─────┬───────────┘
                          │
                          ▼
                ┌─────────────────────────┐
                │ /auth/callback Handler  │
                │                         │
                │ 1. Verifies session     │
                │ 2. Syncs user to DB     │
                │ 3. Completes event      │
                │    registration         │
                │ 4. Redirects to event   │
                └─────────────────────────┘
```

## Technical Implementation Details

### 1. Authentication Client (`lib/eventasaurus_app/auth/client.ex`)

```elixir
@impl true
def sign_in_with_otp(email, event_context \\ %{}) do
  site_url = Application.get_env(:eventasaurus, :site_url, "https://eventasaur.us")
  
  # Build callback URL with event context
  callback_url = case event_context do
    %{event_slug: slug, event_id: id} when is_binary(slug) and is_integer(id) ->
      "#{site_url}/auth/callback?type=event_registration&event_slug=#{slug}&event_id=#{id}"
    _ ->
      "#{site_url}/auth/callback"
  end
  
  # Call Supabase OTP endpoint
  http_client().post("/auth/v1/otp", %{
    email: email,
    options: %{
      emailRedirectTo: callback_url,
      shouldCreateUser: true
    }
  })
end
```

### 2. Events Module Integration (`lib/eventasaurus_app/events.ex`)

```elixir
def create_or_find_supabase_user(email, %Event{} = event, event_context \\ %{}) do
  case Repo.get_by(User, email: email) do
    nil ->
      # New user - send OTP email
      case Auth.Client.sign_in_with_otp(email, event_context) do
        {:ok, %{}} -> {:ok, :email_sent}
        {:error, reason} -> {:error, reason}
      end
    
    user ->
      # Existing user - register immediately
      case get_or_create_participant(user, event) do
        {:ok, participant} -> {:ok, :signed}
        {:error, reason} -> {:error, reason}
      end
  end
end
```

### 3. Callback Handler (`lib/eventasaurus_web/controllers/auth/auth_controller.ex`)

```elixir
def callback(conn, params) do
  case params do
    %{"type" => "event_registration", "event_slug" => slug, "event_id" => event_id} ->
      handle_event_registration_callback(conn, slug, event_id)
    _ ->
      handle_regular_callback(conn)
  end
end

defp handle_event_registration_callback(conn, event_slug, event_id) do
  with {:ok, user} <- SupabaseSync.sync_user(conn),
       event_id <- String.to_integer(event_id),
       {:ok, event} <- Events.get_event(event_id),
       {:ok, _participant} <- Events.complete_event_registration_after_confirmation(user, event) do
    
    conn
    |> put_flash(:info, "Successfully registered for #{event.name}!")
    |> redirect(to: "/#{event_slug}")
  else
    {:error, :already_registered} ->
      conn
      |> put_flash(:info, "You're already registered for this event!")
      |> redirect(to: "/#{event_slug}")
    
    error ->
      Logger.error("Event registration callback failed: #{inspect(error)}")
      conn
      |> put_flash(:error, "Registration failed. Please try again.")
      |> redirect(to: "/#{event_slug}")
  end
end
```

## Security Improvements

### Before (Security Issues)
- Used Supabase admin API that bypassed email verification
- New users were created immediately without email confirmation
- Potential for spam registrations and unverified emails

### After (Enhanced Security)
- Uses standard `/auth/v1/otp` endpoint with email verification
- New users must confirm email before registration completes
- Maintains rate limiting and anti-spam protection
- Proper audit trail of authentication events

## User Experience Flow

### For Existing Users
1. User enters email on event page
2. System recognizes existing user
3. Participant record created immediately
4. User sees "Successfully registered!" message
5. **Flow remains unchanged and smooth**

### For New Users  
1. User enters email on event page
2. System detects new user
3. OTP email sent with event context
4. User sees "Check your email for confirmation" message
5. User clicks link in email
6. Auto-redirected to event page with registration completed
7. User sees "Successfully registered!" message

## Error Handling

### Common Error Scenarios

1. **Email delivery failure**
   - Supabase returns error
   - User sees "Email delivery failed, please try again"
   - System logs error for investigation

2. **Invalid email format**
   - Client-side validation prevents submission
   - Server-side validation provides clear error message

3. **Callback processing failure**
   - User redirected to event page with error message
   - Error logged with context for debugging
   - User can retry registration

4. **Network connectivity issues**
   - Client shows loading state during requests
   - Timeout handling with retry suggestion
   - Graceful degradation of user experience

## Testing Strategy

### Unit Tests
- Auth client OTP flow with event context
- Events module user creation logic
- Callback handler for different scenarios

### Integration Tests  
- Complete registration flow for new users
- Complete registration flow for existing users
- Error handling for various failure modes

### End-to-End Tests
- Browser automation testing complete user journey
- Email delivery and callback verification
- Cross-browser compatibility testing

## Monitoring and Alerting

### Key Metrics to Monitor
- Email delivery success rate (target: >98%)
- Email confirmation completion rate (target: >80%)
- Authentication error rate (target: <2%)
- Registration conversion rate (new vs existing users)

### Alert Conditions
- Email delivery failure rate >5% for 10 minutes
- Authentication errors >10 per minute
- Callback processing failures >5% for 5 minutes

### Dashboards
- Real-time authentication flow metrics
- Email delivery status monitoring
- User conversion funnel analysis

## Backward Compatibility

### Existing Users
- No impact on existing user authentication
- Login flow remains unchanged
- Session management unchanged

### Existing Event Registrations
- All existing registrations preserved
- No data migration required
- Participant records remain valid

### API Compatibility
- All existing API endpoints unchanged
- New functionality is additive only
- No breaking changes to external integrations

## Future Considerations

### Potential Enhancements
1. **SMS OTP Option**: Add phone-based OTP as alternative to email
2. **Social Login**: Integrate Google/Facebook OAuth for faster registration  
3. **Magic Links**: Replace OTP with passwordless magic links
4. **Progressive Enhancement**: Add offline support for registration

### Performance Optimizations
1. **Email Template Caching**: Cache Supabase email templates
2. **Batch Processing**: Handle multiple registrations more efficiently
3. **CDN Integration**: Improve callback URL performance
4. **Database Indexing**: Optimize queries for user lookup by email

### Security Hardening
1. **Rate Limiting**: Implement per-IP rate limiting for registration attempts
2. **CAPTCHA Integration**: Add CAPTCHA for high-risk registration patterns
3. **Email Verification**: Implement additional email verification steps
4. **Audit Logging**: Enhanced logging for compliance requirements 