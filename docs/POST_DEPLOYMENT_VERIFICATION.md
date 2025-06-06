# Post-Deployment Verification Guide

## 🔍 Authentication Flow Enhancement - Verification Procedures

**Purpose**: Verify the enhanced authentication system is working correctly in production  
**Timeline**: Execute immediately after deployment  
**Duration**: 15-30 minutes

---

## 📋 Verification Checklist

### Phase 1: System Health (5 minutes)

#### 1.1 Application Status
```bash
# Check application is running
fly status --app eventasaurus

# Expected: Status should be "running"
# Expected: All instances healthy
```

#### 1.2 Basic Connectivity
```bash
# Test main site
curl -I https://eventasaur.us/
# Expected: HTTP/2 200 OK

# Test authentication endpoint
curl -I https://eventasaur.us/auth/callback
# Expected: HTTP/2 200 OK or 302 (redirect)
```

#### 1.3 Database Connectivity
```bash
# Test database connection
fly ssh console --app eventasaurus -C "/app/bin/eventasaurus eval 'EventasaurusApp.Repo.query(\"SELECT 1\")'"
# Expected: {:ok, %Postgrex.Result{...}}
```

### Phase 2: Authentication Flow Testing (15 minutes)

#### 2.1 New User Registration Flow

**Test Case**: Complete new user registration with email confirmation

1. **Navigate to Event Page**:
   - Visit: `https://eventasaur.us/{event-slug}` (use any public event)
   - Verify page loads correctly

2. **Initiate Registration**:
   - Click "Register for Event" button
   - Enter a **real email address** you can access
   - Enter your name
   - Click "Register"

3. **Verify Email Sent Response**:
   - ✅ Should see "Check your email" message
   - ✅ Modal should show email confirmation UI
   - ✅ No error messages displayed

4. **Check Email Delivery**:
   - Check your email inbox (may take 1-2 minutes)
   - ✅ Should receive confirmation email from Supabase
   - ✅ Email should contain confirmation link

5. **Complete Registration**:
   - Click the confirmation link in email
   - ✅ Should redirect to event page
   - ✅ Should show success message or registration confirmation
   - ✅ Should be logged in (check for user menu/logout option)

#### 2.2 Existing User Registration Flow

**Test Case**: Existing user registers for event (immediate success)

1. **Use Existing Account**:
   - Use an email that already has an account in the system
   - Or create an account first through normal signup

2. **Register for Event**:
   - Navigate to different event page
   - Click "Register for Event"
   - Enter existing user email and name
   - Click "Register"

3. **Verify Immediate Success**:
   - ✅ Should see immediate success message
   - ✅ No email confirmation required
   - ✅ Registration should complete instantly

#### 2.3 Error Handling Verification

**Test Case**: Invalid inputs and error scenarios

1. **Invalid Email Format**:
   - Try registering with "invalid-email"
   - ✅ Should show appropriate error message

2. **Empty Fields**:
   - Try submitting with empty name or email
   - ✅ Should show validation errors

3. **Network Error Simulation**:
   - If possible, test with poor network connection
   - ✅ Should handle gracefully with appropriate error messages

### Phase 3: Database Verification (5 minutes)

#### 3.1 User Creation Verification
```bash
# Connect to production database (if accessible)
fly ssh console --app eventasaurus

# In the console, check recent user registrations:
/app/bin/eventasaurus remote

# Run in IEx:
EventasaurusApp.Accounts.list_users() |> Enum.take(5)
# Expected: Should see recently created users

# Check event participants:
EventasaurusApp.Events.list_event_participants(event_id) |> Enum.take(5)
# Expected: Should see recent registrations
```

#### 3.2 Session Management
```bash
# Check active sessions (if session store is accessible)
# This depends on your session storage configuration
```

### Phase 4: Integration Testing (5 minutes)

#### 4.1 Authentication-Dependent Features

1. **User Dashboard** (if exists):
   - Login with test account
   - Navigate to user dashboard
   - ✅ Should load correctly with user data

2. **Event Management** (if user has permissions):
   - Test event creation/editing
   - ✅ Authentication should work seamlessly

3. **Logout/Login Cycle**:
   - Logout from test account
   - Login again
   - ✅ Should work without issues

---

## 🚨 Issue Detection & Response

### Common Issues and Solutions

#### Issue: Email Confirmation Not Working

**Symptoms**:
- Users report not receiving confirmation emails
- Email confirmation links don't work

**Immediate Checks**:
```bash
# Check application logs for email-related errors
fly logs --app eventasaurus | grep -i "email\|smtp\|supabase"

# Check Supabase dashboard:
# - Authentication → Settings → SMTP configuration
# - Authentication → Templates → Confirm signup template
```

**Resolution**:
1. Verify Supabase email settings
2. Check email template configuration
3. Test email delivery from Supabase dashboard

#### Issue: Authentication Callback Errors

**Symptoms**:
- Users get errors after clicking email confirmation links
- Callback endpoint returning 500 errors

**Immediate Checks**:
```bash
# Check callback-specific logs
fly logs --app eventasaurus | grep -i "callback\|auth"

# Test callback endpoint directly
curl -v "https://eventasaur.us/auth/callback?access_token=test"
```

**Resolution**:
1. Check environment variables (SUPABASE_URL, etc.)
2. Verify Supabase redirect URL configuration
3. Check for any recent configuration changes

#### Issue: Database Connection Problems

**Symptoms**:
- Registration attempts fail with database errors
- Application logs show connection issues

**Immediate Checks**:
```bash
# Check database connectivity
fly ssh console --app eventasaurus -C "/app/bin/eventasaurus eval 'EventasaurusApp.Repo.query(\"SELECT 1\")'"

# Check database pool status
fly logs --app eventasaurus | grep -i "database\|pool\|connection"
```

**Resolution**:
1. Verify SUPABASE_DATABASE_URL is correct
2. Check database pool configuration
3. Verify SSL settings

---

## 📊 Success Metrics

### Technical Metrics

| Metric | Target | Verification Method |
|--------|--------|-------------------|
| **Application Uptime** | 100% | `fly status` |
| **Response Time** | < 2s | Manual testing |
| **Email Delivery** | < 2 min | Test registration |
| **Error Rate** | < 1% | Log analysis |
| **Database Queries** | < 500ms | Performance monitoring |

### User Experience Metrics

| Metric | Target | Verification Method |
|--------|--------|-------------------|
| **Registration Success** | > 95% | Test multiple scenarios |
| **Email Confirmation** | Works | End-to-end test |
| **Error Messages** | Clear & helpful | Error scenario testing |
| **UI Responsiveness** | Smooth | Manual testing |

---

## 🔍 Monitoring Setup

### Real-time Monitoring Commands

```bash
# Continuous log monitoring
fly logs --app eventasaurus --follow | grep -E "(ERROR|WARN|auth|registration)"

# Application status monitoring
watch -n 30 'fly status --app eventasaurus'

# Resource usage monitoring
fly metrics --app eventasaurus
```

### Automated Health Checks

Create a simple monitoring script:

```bash
#!/bin/bash
# health_check.sh

echo "🔍 Health Check - $(date)"

# Basic connectivity
if curl -f -s https://eventasaur.us/ > /dev/null; then
    echo "✅ Main site: OK"
else
    echo "❌ Main site: FAILED"
fi

# Auth endpoint
if curl -f -s https://eventasaur.us/auth/callback > /dev/null; then
    echo "✅ Auth endpoint: OK"
else
    echo "❌ Auth endpoint: FAILED"
fi

# Database (requires fly CLI)
if fly ssh console --app eventasaurus -C "/app/bin/eventasaurus eval 'EventasaurusApp.Repo.query(\"SELECT 1\")'" 2>/dev/null | grep -q "ok"; then
    echo "✅ Database: OK"
else
    echo "❌ Database: FAILED"
fi
```

### Long-term Monitoring

Set up monitoring for:
- **Error rates**: Track authentication failures
- **Performance**: Monitor response times
- **User feedback**: Watch for support tickets
- **Email delivery**: Monitor bounce rates

---

## ✅ Verification Completion

### Sign-off Checklist

- [ ] **System Health**: All services running normally
- [ ] **New User Flow**: Email confirmation working end-to-end
- [ ] **Existing User Flow**: Immediate registration working
- [ ] **Error Handling**: Appropriate error messages displayed
- [ ] **Database**: User and participant records created correctly
- [ ] **Performance**: Response times within acceptable limits
- [ ] **Monitoring**: Health checks and logging working

### Documentation Updates

After successful verification:

1. **Update Deployment Summary**:
   - Mark deployment as successful
   - Record any issues encountered and resolutions
   - Note performance observations

2. **Create Incident Response Plan**:
   - Document any issues found during verification
   - Create runbooks for common problems
   - Update monitoring procedures

3. **User Communication**:
   - Notify stakeholders of successful deployment
   - Update user documentation if needed
   - Plan user feedback collection

---

## 📞 Escalation Procedures

### If Critical Issues Found

**Immediate Actions**:
1. **Document the issue** with screenshots/logs
2. **Assess impact** (how many users affected?)
3. **Decide on rollback** if issue is severe

**Rollback Decision Matrix**:
- **Critical**: Authentication completely broken → Immediate rollback
- **Major**: Email delivery failing → Investigate first, rollback if no quick fix
- **Minor**: UI issues or edge cases → Fix in next deployment

**Rollback Execution**:
```bash
# Quick rollback
fly releases --app eventasaurus
fly releases rollback <previous-version> --app eventasaurus

# Monitor rollback
fly logs --app eventasaurus --follow
```

---

**Verification Date**: ________________  
**Verified By**: ________________  
**Issues Found**: ________________  
**Resolution Status**: ________________  
**Final Sign-off**: ________________ 