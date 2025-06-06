# Deployment Guide

## 🔄 Latest Changes: Enhanced Authentication Flow

**Version**: June 2025 - Authentication Flow Enhancement  
**Critical Changes**: Event registration now uses email confirmation flow with proper user sync

### What Changed:
- Event registration authentication switched from Supabase admin API to standard `/auth/v1/otp` endpoint
- Added email confirmation requirement for new users during event registration  
- Enhanced `/auth/callback` to complete event registration after email confirmation
- Improved security by eliminating admin API bypass of email verification

### Key Files Modified:
- `lib/eventasaurus_app/auth/client.ex` - OTP flow with event context
- `lib/eventasaurus_app/events.ex` - Enhanced user creation with event context
- `lib/eventasaurus_web/controllers/auth/auth_controller.ex` - Callback handling
- `lib/eventasaurus_web/live/public_event_live.ex` - UI feedback for email confirmation

---

## Environment Variables

### Required Variables
- `SUPABASE_URL` - Your Supabase project URL
- `SUPABASE_ANON_KEY` - Your Supabase anonymous key
- `SUPABASE_DATABASE_URL` - Database connection string from Supabase
- `SECRET_KEY_BASE` - Phoenix secret key base

### Optional Variables
- `POOL_SIZE` - Database connection pool size (default: 5)
- `SITE_URL` - Your site URL (default: "https://eventasaur.us")
- `SSL_VERIFY_PEER` - Enable SSL certificate verification (default: false)

## 🚀 Pre-Deployment Checklist

### 1. Code Quality Verification
- [ ] Run full test suite: `mix test`
- [ ] Run Credo static analysis: `mix credo --strict`
- [ ] Verify authentication flow tests pass
- [ ] Check for any compilation warnings

### 2. Environment Preparation  
- [ ] Backup current production database state
- [ ] Tag current git commit for easy rollback
- [ ] Verify Supabase email templates are configured
- [ ] Test Supabase email delivery in staging environment

### 3. Supabase Configuration Verification
- [ ] Confirm email confirmation is enabled in Supabase Auth settings
- [ ] Verify email rate limiting is appropriate for your traffic
- [ ] Check email templates include proper callback URLs: `{SITE_URL}/auth/callback`
- [ ] Test email delivery in production environment

### 4. Feature Flag Setup (if applicable)
```elixir
# Add to runtime.exs if implementing feature flags
config :eventasaurus, :auth_features,
  email_confirmation_flow: System.get_env("ENABLE_EMAIL_CONFIRMATION", "true") == "true"
```

---

## 📋 Deployment Process

### Phase 1: Deploy Code Changes
```bash
# 1. Tag current version for rollback
git tag -a v-pre-auth-enhancement -m "Pre-authentication enhancement"

# 2. Deploy new version  
fly deploy

# 3. Monitor logs during deployment
fly logs -a your-app-name
```

### Phase 2: Verify Authentication Flows
```bash
# Test both authentication flows in production:

# 1. Regular user signup (should work as before)
# 2. Event registration for new users (should show email confirmation)
# 3. Event registration for existing users (should work immediately)
```

### Phase 3: Monitor Key Metrics
- Authentication success rate
- Email delivery rate  
- User confirmation rate
- Error logs for authentication failures

---

## 🔄 Rollback Plan

### Immediate Rollback (< 30 minutes after deployment)

If critical issues are detected:

```bash
# 1. Quick rollback to previous deployment
fly deployments list
fly deploy --image [previous-deployment-image]

# Or rollback to tagged version
git checkout v-pre-auth-enhancement
fly deploy
```

### Full Rollback Procedure

If deeper issues require code changes:

#### Step 1: Revert Code Changes
```bash
# Revert authentication files to previous versions
git revert [commit-hash-of-auth-changes]

# Or reset to previous tag
git reset --hard v-pre-auth-enhancement
```

#### Step 2: Address Data Inconsistencies
```sql
-- Check for any incomplete user records created during deployment
SELECT id, email, created_at 
FROM users 
WHERE created_at > 'DEPLOYMENT_TIMESTAMP'
AND id NOT IN (SELECT user_id FROM participants);

-- If needed, clean up incomplete registrations
-- (Only if you're confident these are test/incomplete registrations)
```

#### Step 3: Communication Plan
```text
Subject: Temporary Authentication Issue - Rolling Back

We're experiencing an issue with event registration and are rolling back 
to the previous version. This will take approximately 15 minutes.

During this time:
- Existing registrations remain intact
- New registrations may be temporarily unavailable
- Existing users can still access events they're registered for

We'll send an update once the rollback is complete.
```

#### Step 4: Redeploy Previous Version
```bash
fly deploy
```

#### Step 5: Verify Rollback Success
- [ ] Test regular user signup
- [ ] Test event registration flow
- [ ] Check error logs are clear
- [ ] Verify email delivery is working

---

## 🔍 Post-Deployment Monitoring

### Immediate Checks (First 30 minutes)
- [ ] Smoke test both authentication flows
- [ ] Check application logs for errors
- [ ] Verify email delivery works
- [ ] Test session management

### 24-Hour Monitoring
- [ ] Authentication success rate metrics
- [ ] Email bounce rate
- [ ] User confirmation completion rate
- [ ] Database query performance

### Key Metrics to Watch
```elixir
# Example monitoring queries
# Authentication success rate
SELECT 
  DATE(created_at) as date,
  COUNT(*) as total_attempts,
  COUNT(CASE WHEN confirmed_at IS NOT NULL THEN 1 END) as confirmed
FROM users 
WHERE created_at >= NOW() - INTERVAL '7 days'
GROUP BY DATE(created_at);

# Event registration completion rate  
SELECT 
  COUNT(*) as registrations_started,
  COUNT(CASE WHEN user_id IS NOT NULL THEN 1 END) as completed
FROM participants 
WHERE created_at >= NOW() - INTERVAL '24 hours';
```

---

## SSL Configuration

### SSL_VERIFY_PEER Environment Variable

**Default Behavior**: SSL certificate verification is **disabled** (`verify_none`) for Supabase compatibility.

**Purpose**: The `SSL_VERIFY_PEER` environment variable controls database SSL certificate verification.

**Values**:
- `SSL_VERIFY_PEER=true` - Enables SSL certificate verification (`verify_peer`)
- `SSL_VERIFY_PEER=false` or unset - Disables SSL verification (`verify_none`) - **Default**

### Why SSL Verification is Disabled by Default

**Supabase Compatibility**: Supabase uses cloud-managed SSL certificates that may not work with standard certificate verification in containerized environments like Fly.io.

**Production Considerations**:
- Supabase provides secure, managed database connections
- Cloud-managed certificates don't require custom CA bundles
- Disabling verification is a common practice with managed database services
- The connection is still encrypted (SSL/TLS is still active)

### Security Guidelines

#### ✅ **SAFE to use `SSL_VERIFY_PEER=false` when**:
- Using Supabase (recommended)
- Using other managed database services (RDS, Cloud SQL, etc.)
- Deploying to containerized environments (Docker, Fly.io, etc.)

#### ⚠️ **CONSIDER enabling `SSL_VERIFY_PEER=true` when**:
- Using self-managed PostgreSQL with proper CA certificates
- Corporate environments with custom certificate authorities
- Specific compliance requirements mandate certificate verification

#### 🚨 **MONITORING**:
- The application logs a warning when SSL verification is disabled
- Monitor deployment logs to ensure this is intentional
- Review SSL settings during security audits

### Setting SSL Verification

#### Development/Testing
```bash
# In .env file
SSL_VERIFY_PEER=false  # Default - works with Supabase
```

#### Production (Fly.io)
```bash
# Set via fly secrets
fly secrets set SSL_VERIFY_PEER=false

# Or to enable verification (may cause connection issues with Supabase)
fly secrets set SSL_VERIFY_PEER=true
```

### Troubleshooting SSL Issues

#### Connection Errors with SSL_VERIFY_PEER=true
If you encounter errors like:
```
(DBConnection.ConnectionError) failed to connect: options cannot be combined: [{verify,verify_peer}, {cacerts,undefined}]
```

**Solution**: Set `SSL_VERIFY_PEER=false` (or leave unset) for Supabase connections.

#### Certificate Verification Failures
If you need certificate verification, ensure:
1. Your environment has access to CA certificate bundles
2. Custom certificates are properly configured
3. Network policies allow certificate validation

### Example Configurations

#### Supabase (Recommended)
```bash
SUPABASE_DATABASE_URL=postgresql://postgres:[password]@[host]:5432/postgres
SSL_VERIFY_PEER=false  # Or leave unset
```

#### Self-Managed PostgreSQL
```bash
DATABASE_URL=postgresql://user:pass@your-server:5432/database
SSL_VERIFY_PEER=true  # Only if you have proper CA certificates
```

## Database Configuration

The application uses the following database configuration:

```elixir
config :eventasaurus, EventasaurusApp.Repo,
  url: System.get_env("SUPABASE_DATABASE_URL"),
  database: "postgres",
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5"),
  queue_target: 5000,
  queue_interval: 30000,
  ssl: true,
  ssl_opts: [verify: ssl_verify]  # Controlled by SSL_VERIFY_PEER
```

---

## ⚠️ Troubleshooting Common Issues

### Authentication Flow Problems

**Issue**: New users not receiving confirmation emails
```bash
# Check Supabase logs
# Verify SITE_URL is correct in environment
# Check email templates in Supabase dashboard
```

**Issue**: Callback not completing registration
```bash
# Check logs for callback errors:
fly logs -a your-app-name | grep "auth/callback"

# Verify event context in callback URL
```

**Issue**: Users getting 500 errors during registration
```bash
# Most likely: Missing case clause in LiveView
# Check lib/eventasaurus_web/live/public_event_live.ex
# Ensure all authentication states are handled
```

### Quick Diagnostic Commands
```bash
# Check recent authentication errors
fly logs -a your-app-name | grep -i "auth\|error" | tail -20

# Monitor real-time authentication flow
fly logs -a your-app-name -f | grep "auth"

# Check database connectivity
fly ssh console -C "mix run -e 'EventasaurusApp.Repo.query!(\"SELECT 1\")'"
```

---

## 📊 Success Metrics

### Deployment Success Indicators
- [ ] Zero 5xx errors in first hour
- [ ] Authentication success rate > 95%
- [ ] Email delivery rate > 98%
- [ ] User confirmation completion rate > 80%
- [ ] No increase in support tickets

### Long-term Success Metrics
- Improved security posture (no admin API usage)
- Maintained user experience (smooth registration flow)
- Better data consistency (proper user/participant sync)
- Reduced authentication-related support tickets

---

## 📞 Emergency Contacts

During deployment window, ensure these contacts are available:
- **Primary Developer**: [Your contact]
- **DevOps Lead**: [Contact if applicable]  
- **Supabase Support**: [If enterprise plan]

**Escalation Path**: If rollback doesn't resolve issues within 30 minutes, contact Supabase support for authentication service status. 