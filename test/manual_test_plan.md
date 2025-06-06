# Manual Test Plan: Event Registration Email Fix

## Overview
This manual test plan covers comprehensive testing of the authentication fix that ensures new users receive confirmation emails during event registration.

## Test Environment Setup

### Prerequisites
- [ ] Elixir/Phoenix development environment running
- [ ] Supabase instance configured with `auto_confirm_email: false`
- [ ] Access to email service (check Supabase email settings)
- [ ] Browser with developer tools available
- [ ] Network monitoring tools (optional)

### Test Data Preparation
- [ ] Create test events with different visibility settings
- [ ] Have existing user accounts for testing existing user flows
- [ ] Prepare fresh email addresses for new user testing
- [ ] Set up different event types (regular events, polls, etc.)

## Critical Test Scenarios

### Scenario 1: New User Event Registration (Primary Fix)
**Expected:** New users receive confirmation emails and cannot complete registration until confirmed

**Steps:**
1. **Setup**
   - Use a fresh email address not in the system
   - Navigate to a public event page
   - Ensure you're not logged in

2. **Registration Process**
   - Click "Register for Event" button
   - Fill in name and new email address
   - Click "Register" button

3. **Immediate Verification**
   - [ ] Form shows loading state during submission
   - [ ] Success message appears: "Registration started! Check your email to confirm..."
   - [ ] Modal closes after success message
   - [ ] User is NOT immediately shown as registered
   - [ ] No participant record exists in database yet

4. **Email Verification**
   - [ ] Confirmation email arrives in inbox (check spam folder)
   - [ ] Email contains confirmation link
   - [ ] Email sender is from Supabase/your domain
   - [ ] Email content is appropriate and professional

5. **Post-Confirmation** (After clicking email link)
   - [ ] User is redirected to confirmation page
   - [ ] User account is created in Supabase with confirmed email
   - [ ] User can now sign in normally
   - [ ] Event registration can be completed

### Scenario 2: Existing User Event Registration
**Expected:** Existing users register immediately without email confirmation

**Steps:**
1. **Setup**
   - Use email address of existing confirmed user
   - Navigate to event page while not logged in

2. **Registration Process**
   - Click "Register for Event" button
   - Fill in name and existing email address
   - Click "Register" button

3. **Verification**
   - [ ] Success message appears: "Great! You're now registered for [Event Name]"
   - [ ] User is immediately registered (appears in participant list)
   - [ ] No additional email confirmation required
   - [ ] Registration is complete and functional

### Scenario 3: Authenticated User Registration
**Expected:** Logged-in users see streamlined registration

**Steps:**
1. **Setup**
   - Log in as existing user
   - Navigate to event page

2. **Registration Process**
   - [ ] Shows one-click registration (no form modal)
   - [ ] Click register button
   - [ ] Immediate registration success

### Scenario 4: Duplicate Registration Prevention
**Expected:** Users cannot register twice for the same event

**Steps:**
1. Register user for event (using Scenario 1 or 2)
2. Attempt to register same email again
3. **Verification**
   - [ ] Error message: "You're already registered for this event"
   - [ ] No duplicate participant records created
   - [ ] User shown as already registered

### Scenario 5: Voting Registration (OTP Flow)
**Expected:** New users voting in polls receive confirmation emails

**Steps:**
1. **Setup**
   - Navigate to event with polls
   - Use fresh email address

2. **Voting Process**
   - Submit vote with new email
   - **Verification:**
     - [ ] Email confirmation message appears
     - [ ] No vote recorded until email confirmed
     - [ ] Email arrives with confirmation link

### Scenario 6: Error Handling
**Expected:** Graceful handling of various error conditions

**Test Cases:**
1. **Invalid Email Format**
   - Enter "invalid-email" in registration form
   - [ ] Client-side validation prevents submission
   - [ ] Clear error message shown

2. **Service Unavailable**
   - Test during Supabase maintenance (or simulate)
   - [ ] Appropriate error message shown
   - [ ] User can retry registration
   - [ ] No incomplete records created

3. **Network Issues**
   - Simulate slow/failed network
   - [ ] Loading states handled properly
   - [ ] Timeout errors handled gracefully
   - [ ] User notified of issues

## Performance & UX Testing

### Loading States
- [ ] Registration button shows loading state during submission
- [ ] Form is disabled during processing
- [ ] Multiple rapid clicks don't cause issues
- [ ] Reasonable response times (< 3 seconds normal operation)

### Mobile Testing
- [ ] Registration modal works on mobile browsers
- [ ] Email confirmation flow works on mobile
- [ ] Touch interactions work properly
- [ ] Forms are accessible on small screens

### Accessibility Testing
- [ ] Screen reader can navigate registration form
- [ ] All form elements have proper labels
- [ ] Error messages are announced by screen readers
- [ ] Keyboard navigation works throughout flow

## Database Verification

### Data Integrity Checks
- [ ] No orphaned participant records for unconfirmed users
- [ ] Supabase user records match local user records
- [ ] Event participant counts are accurate
- [ ] No duplicate registrations exist

### Audit Trail
- [ ] Registration attempts are logged appropriately
- [ ] Email delivery status is tracked
- [ ] Error conditions are logged for debugging

## Email Testing

### Email Delivery
- [ ] Emails arrive in reasonable time (< 5 minutes)
- [ ] Emails not marked as spam
- [ ] Email formatting is correct
- [ ] Links in emails work properly
- [ ] Unsubscribe mechanisms work (if applicable)

### Email Content
- [ ] Event name appears correctly
- [ ] Confirmation link is prominent
- [ ] Instructions are clear
- [ ] Branding is consistent
- [ ] Contact information is available

## Cross-Browser Testing

### Browser Compatibility
- [ ] Chrome (latest)
- [ ] Firefox (latest)  
- [ ] Safari (latest)
- [ ] Edge (latest)
- [ ] Mobile browsers (iOS Safari, Chrome Mobile)

### Feature Testing per Browser
- [ ] Registration modal functionality
- [ ] Form validation
- [ ] Email confirmation flow
- [ ] Error handling

## Security Testing

### Input Validation
- [ ] SQL injection attempts are blocked
- [ ] XSS attempts are sanitized
- [ ] Email format validation is enforced
- [ ] Rate limiting prevents abuse

### Authentication Security
- [ ] Email confirmation tokens are secure
- [ ] Tokens expire appropriately
- [ ] No user enumeration possible
- [ ] Sessions are handled securely

## Regression Testing

### Existing Functionality
- [ ] Regular signup flow still works
- [ ] User login/logout works
- [ ] Password reset flow works
- [ ] Admin functions remain intact
- [ ] Other event features work normally

### Performance Impact
- [ ] Page load times unchanged
- [ ] Database query performance acceptable
- [ ] No memory leaks in long-running sessions

## Test Results Documentation

### Test Execution Log
```
Date: ___________
Tester: ___________
Environment: ___________

Scenario 1 - New User Registration:
  ✅ Registration form displays correctly
  ✅ Email confirmation sent
  ❌ Confirmation email delayed (5+ minutes)
  
Action Items:
- Investigate email delivery delays
- Check Supabase email queue settings
```

### Bug Reports
Use the following template for any issues found:

```markdown
## Bug Report #001

**Title:** Email confirmation not received

**Severity:** High
**Priority:** High

**Steps to Reproduce:**
1. Navigate to event page
2. Fill registration form with new email
3. Submit form

**Expected Result:** 
Confirmation email arrives within 5 minutes

**Actual Result:**
No email received after 15 minutes

**Environment:**
- Browser: Chrome 120.0
- OS: macOS 14.0
- Supabase Environment: Development

**Additional Notes:**
Checked spam folder, email service logs
```

## Success Criteria

### Primary Goals
- [ ] 100% of new users receive confirmation emails
- [ ] 0% of unconfirmed users can complete registration
- [ ] Existing user flow maintains current functionality
- [ ] No regression in other features

### Performance Goals
- [ ] Registration response time < 3 seconds
- [ ] Email delivery time < 5 minutes
- [ ] No memory leaks during extended testing
- [ ] Database performance remains acceptable

### User Experience Goals
- [ ] Clear feedback for all user actions
- [ ] Graceful error handling
- [ ] Intuitive flow for all user types
- [ ] Mobile-friendly interface

## Post-Testing Actions

### Before Production Deployment
- [ ] All critical scenarios pass
- [ ] Performance requirements met
- [ ] Security testing completed
- [ ] Cross-browser compatibility verified

### Monitoring Setup
- [ ] Email delivery monitoring enabled
- [ ] Error logging configured
- [ ] User registration metrics tracked
- [ ] Performance monitoring active

### Documentation Updates
- [ ] User documentation updated
- [ ] Admin documentation updated  
- [ ] API documentation current
- [ ] Troubleshooting guides updated 