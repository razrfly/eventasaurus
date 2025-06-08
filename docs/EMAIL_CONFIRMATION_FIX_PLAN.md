# Email Confirmation Fix - Correct Approach

## Problem Statement

**Current Issue**: Event registration creates user accounts that bypass email confirmation, while regular signup properly sends confirmation emails.

**Root Cause**: Event registration uses `/auth/v1/admin/users` endpoint with `email_confirm: true`, bypassing the `auto_confirm_email: false` configuration. Regular signup uses `/auth/v1/signup` endpoint that respects email confirmation settings.

**Impact**: Event registrants get temporary passwords they never receive and can't access their accounts.

## Previous Failed Approach (Abandoned)

**What We Tried**: Replace admin API with OTP (`signInWithOtp()`) 
**Why It Failed**: 
- OTP flow only creates Supabase auth account AFTER email confirmation
- We were rolling back the transaction for new users, so no participant record was created
- Users got "registration successful" messages but weren't actually registered for events
- Even after email confirmation, users still weren't registered for events
- **This broke core functionality - users weren't getting registered at all**

## Correct Approach (Option B)

**Strategy**: Keep using admin API for immediate account creation, but ensure email confirmation is required for account access.

### Core Implementation Plan

1. **Modify Admin User Creation**
   - Use `/auth/v1/admin/users` endpoint (keeps immediate account creation)
   - Set `email_confirm: false` in the request payload
   - This creates the account but marks it as unconfirmed
   - User must confirm email to access the account

2. **Maintain Current Registration Flow**
   - User submits registration → immediately create Supabase account
   - Immediately create participant record (user IS registered)
   - Send confirmation email for account access (not registration)

3. **Update Client Method**
   ```elixir
   def admin_create_user_with_confirmation_required(email, password, user_metadata) do
     payload = %{
       email: email,
       password: password,
       user_metadata: user_metadata,
       email_confirm: false  # KEY CHANGE: Require email confirmation
     }
     # Rest of implementation using /auth/v1/admin/users endpoint
   end
   ```

### Detailed Implementation Steps

#### Step 1: Update Auth Client
- Add new method `admin_create_user_with_confirmation_required/3`
- Modify existing `admin_create_user/3` to use `email_confirm: false`
- OR create new method and update callers

#### Step 2: Update Events Module
- Modify `create_or_find_supabase_user/2` to use the updated admin method
- Ensure participant record is ALWAYS created for new registrations
- No transaction rollbacks for new users

#### Step 3: Update UI Messaging
- Change success message to: "Registration successful! Please check your email to activate your account."
- Clarify that they're registered for the event but need to confirm email for account access

#### Step 4: Add Callback Handling (Optional Enhancement)
- Add route to handle post-confirmation redirects
- Could redirect to event page after confirmation
- Show "Your account is now active" message

### Expected Flow After Fix

**New User Registration:**
1. User fills out event registration form
2. System creates Supabase account with `email_confirm: false`
3. System creates participant record (user IS registered for event)
4. System sends confirmation email automatically (Supabase behavior)
5. User sees: "Registration successful! Check email to activate account"
6. User clicks email link → account becomes active
7. User can now log in and access their account

**Existing User Registration:**
1. User fills out registration form
2. System finds existing Supabase account
3. System creates participant record
4. User sees normal registration success message
5. User can log in immediately (account already confirmed)

### Benefits of This Approach

✅ **Users are actually registered** - participant record created immediately
✅ **Email confirmation required** - respects security settings  
✅ **Clear user flow** - registration vs account activation are separate
✅ **Backward compatible** - existing users work normally
✅ **Consistent with signup** - both flows require email confirmation
✅ **Immediate feedback** - users know they're registered for event

### Key Files to Modify

1. `lib/eventasaurus_app/auth/client.ex` - Update admin_create_user method
2. `lib/eventasaurus_app/auth/client_behaviour.ex` - Update callback spec
3. `lib/eventasaurus_app/events.ex` - Verify no changes needed to registration flow
4. LiveView components - Update success messaging

### Testing Requirements

1. **Unit Tests**
   - Test admin_create_user with email_confirm: false
   - Verify Supabase API payload is correct
   - Test error handling

2. **Integration Tests**
   - New user registration creates participant record
   - Existing user registration works normally
   - Email confirmation emails are sent
   - Post-confirmation account access works

3. **Manual Testing**
   - Register new user → verify participant created + email sent
   - Confirm email → verify account becomes active
   - Test login after confirmation
   - Verify existing users unaffected

### Deployment Considerations

- **Zero downtime** - users continue registering normally
- **No data migration** - only code changes
- **Rollback safe** - can revert to current admin_create_user easily
- **Monitor email delivery** - ensure confirmation emails are sent

### Success Criteria

1. New event registrants receive confirmation emails
2. New registrants are immediately added to participant lists
3. Account access requires email confirmation
4. Existing users continue working normally
5. No orphaned accounts or missing registrations

---

## Technical Implementation Notes

### Supabase Admin API Payload
```json
{
  "email": "user@example.com",
  "password": "temporary_password_123",
  "user_metadata": {
    "name": "User Name"
  },
  "email_confirm": false  // KEY: This triggers confirmation email
}
```

### Response Handling
- Account created immediately (has Supabase ID)
- `email_confirmed_at` will be null until confirmation
- Supabase automatically sends confirmation email
- User can't sign in until email confirmed

This approach fixes the core issue while maintaining data integrity and improving user experience. 