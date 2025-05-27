# PublicEventLive Test Audit & Plan

## Current State Analysis

### What We Have (Current Tests)
The current test file has 12 tests covering:
1. Anonymous user - register button display
2. Anonymous user - registration modal opening  
3. Anonymous user - non-existent event redirect
4. Anonymous user - reserved slug redirect
5. Authenticated user (not registered) - one-click register button display
6. Authenticated user (not registered) - user info display
7. Authenticated user (not registered) - one-click register functionality
8. Authenticated user (registered) - "You're In" status display
9. Authenticated user (cancelled) - "You're Not Going" status display
10. Event organizer - "Event Organizer" status display

### What the Spec Requires (Based on EVENT_REGISTRATION_SPEC.md & SMART_REGISTRATION_FLOW.md)

#### Registration States:
1. **:not_authenticated** - Anonymous users see "Register Now" button
2. **:not_registered** - Authenticated users see "One-Click Register" button  
3. **:registered** - Users see "You're In" with calendar/share buttons
4. **:cancelled** - Users see "You're Not Going" with "Register Again" button
5. **:organizer** - Organizers see "Event Organizer" with management options

#### UI Elements Per State:
- **Anonymous (:not_authenticated)**:
  - "Register Now" button
  - Opens registration modal on click
  - Modal has name/email form
  
- **Authenticated Not Registered (:not_registered)**:
  - User avatar, name, email display
  - "One-Click Register" button
  - No modal needed
  
- **Authenticated Registered (:registered)**:
  - "You're In" heading with checkmark
  - "You're registered for this event" text
  - "Add to Calendar" button
  - "Share" button  
  - "Can't attend? Cancel registration" link
  - If just registered: email verification notice
  
- **Authenticated Cancelled (:cancelled)**:
  - "You're Not Going" heading
  - "We hope to see you next time!" text
  - "Register Again" button
  - "Changed your mind? You can register again." text
  
- **Organizer (:organizer)**:
  - "Event Organizer" heading
  - "Add to Calendar" and "Share" buttons
  - "Manage Event" link

### Problems with Current Tests

1. **Authentication Setup Broken**: Tests are setting `test_user` in session but LiveView isn't recognizing it
2. **Inconsistent Expectations**: Tests expect text that doesn't match actual UI
3. **Missing Edge Cases**: No tests for error conditions, loading states, etc.
4. **Incomplete Coverage**: Missing tests for modal functionality, form validation, etc.

## Comprehensive Test Plan

### Phase 1: Basic Authentication & State Display (5 tests)
1. **Anonymous user shows register button**
   - Verify "Register Now" button appears
   - Verify "One-Click Register" does NOT appear
   
2. **Authenticated user (not registered) shows one-click register**
   - Verify user info (avatar, name, email) displays
   - Verify "One-Click Register" button appears
   - Verify "Register Now" does NOT appear
   
3. **Authenticated user (registered) shows you're in status**
   - Register user first
   - Verify "You're In" heading appears
   - Verify "You're registered for this event" text
   - Verify registration buttons do NOT appear
   
4. **Authenticated user (cancelled) shows you're not going**
   - Register then cancel user
   - Verify "You're Not Going" heading
   - Verify "Register Again" button appears
   
5. **Event organizer shows organizer status**
   - Make user an organizer
   - Verify "Event Organizer" heading
   - Verify no registration buttons appear

### Phase 2: Interactive Functionality (5 tests)
6. **Anonymous user registration modal opens**
   - Click "Register Now" button
   - Verify modal appears with form
   
7. **One-click register works for authenticated user**
   - Click "One-Click Register" button
   - Verify status changes to "You're In"
   - Verify database registration created
   
8. **Cancel registration works**
   - Start with registered user
   - Click cancel link
   - Verify status changes to "You're Not Going"
   
9. **Re-register works for cancelled user**
   - Start with cancelled user
   - Click "Register Again"
   - Verify status changes to "You're In"
   
10. **Registration modal form submission works**
    - Open modal, fill form, submit
    - Verify success state appears

### Phase 3: Edge Cases & Error Handling (5 tests)
11. **Non-existent event redirects**
    - Visit invalid slug
    - Verify redirect to home with error
    
12. **Reserved slug redirects**
    - Visit reserved slug (admin, api, etc.)
    - Verify redirect to home with error
    
13. **Already registered user gets error on one-click register**
    - Try to register already registered user
    - Verify error message appears
    
14. **Organizer cannot register for own event**
    - Organizer tries to register
    - Verify appropriate error message
    
15. **Registration modal validation works**
    - Submit empty form
    - Verify validation errors appear

### Phase 4: UI Elements & Integration (5 tests)
16. **Registered user sees calendar buttons**
    - Verify "Add to Calendar" button exists
    - Verify "Share" button exists
    
17. **Just registered user sees email verification notice**
    - Register new user via modal
    - Verify email verification UI appears
    
18. **Existing user registration doesn't show verification**
    - Existing user does one-click register
    - Verify NO email verification UI
    
19. **Modal closes properly**
    - Open modal, click close/overlay
    - Verify modal disappears
    
20. **Form validation prevents submission**
    - Enter invalid email
    - Verify form doesn't submit

## Implementation Strategy

### Step 1: Fix Authentication Setup
- Remove broken `test_user` session approach
- Use proper LiveView test authentication patterns
- Ensure `current_user` is properly assigned

### Step 2: Implement Tests in Batches
- Start with Phase 1 (5 basic tests)
- Verify each batch works before moving to next
- Fix any authentication/setup issues immediately

### Step 3: Validate Against Actual UI
- Run each test and compare with actual rendered HTML
- Update expectations to match real implementation
- Don't assume what text should be there - verify it

### Step 4: Add Missing Functionality Tests
- Test actual button clicks and state changes
- Verify database changes occur
- Test error conditions and edge cases

## Success Criteria

- All tests pass consistently
- Tests accurately reflect actual UI behavior  
- Authentication setup works reliably
- Coverage includes all registration states
- Edge cases and error conditions tested
- Tests are maintainable and clear

## Files to Modify

1. **test/eventasaurus_web/live/public_event_live_test.exs** - Complete rewrite
2. **lib/eventasaurus_web/live/auth_hooks.ex** - Remove test_user hack if needed
3. **test/support/conn_case.ex** - Add proper auth helpers if needed

## Next Steps

1. Delete current test file content
2. Start with Phase 1 tests only
3. Fix authentication setup
4. Verify tests pass before adding more
5. Incrementally add remaining phases 