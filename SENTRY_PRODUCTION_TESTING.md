# Sentry Production Testing Guide

> **📖 For comprehensive testing instructions, see [SENTRY_TESTING_GUIDE.md](./SENTRY_TESTING_GUIDE.md)**

## 🚀 How to Test Sentry in Production

### 1. **Pre-Deployment Testing**

#### Local Production Mode Test:
```bash
# Run the test script
./test_sentry_prod.sh
```

#### Manual Local Testing:
```bash
# Test with real Sentry DSN
export MIX_ENV=prod
export SENTRY_DSN="https://your-sentry-dsn@sentry.io/project-id"
export SECRET_KEY_BASE=$(mix phx.gen.secret)
# ... other required env vars
mix deps.get --only prod
mix compile
mix phx.server
```

### 2. **Production Health Check**

Check if Sentry is properly configured:
```bash
curl https://your-domain.com/api/health/sentry
```

Expected Response:
```json
{
  "sentry_configured": true,
  "environment": "prod",
  "timestamp": "2025-01-17T..."
}
```

### 3. **Production Error Testing**

#### Safe Production Test (Authenticated):
```bash
# Requires authentication and special header
curl -X POST https://your-domain.com/api/admin/sentry-test \
  -H "Authorization: Bearer YOUR_AUTH_TOKEN" \
  -H "X-Sentry-Test: production-test" \
  -H "Content-Type: application/json"
```

Expected Response:
```json
{
  "error": "Production test error sent to Sentry",
  "timestamp": "2025-01-17T...",
  "environment": "prod"
}
```

### 4. **Deployment Verification Steps**

#### Step 1: Set Environment Variable
```bash
# In your deployment environment
export SENTRY_DSN="https://your-sentry-dsn@sentry.io/project-id"
```

#### Step 2: Deploy and Check Health
```bash
# After deployment
curl https://your-domain.com/api/health/sentry
```

#### Step 3: Monitor Sentry Dashboard
1. Go to your Sentry dashboard
2. Navigate to Issues
3. Trigger a test error
4. Verify the error appears in Sentry

### 5. **Real-World Testing Scenarios**

#### Database Connection Error:
```bash
# Temporarily break database connection
export SUPABASE_DATABASE_URL="invalid_url"
# Deploy and monitor Sentry for connection errors
```

#### Memory/Performance Issues:
```bash
# Monitor Sentry for performance data
# Check for memory leaks or slow queries
```

### 6. **Monitoring and Alerts**

#### Set up Sentry Alerts:
1. **Error Rate Threshold**: Alert when error rate > 5%
2. **New Error Types**: Alert on new error patterns
3. **Performance Degradation**: Alert on slow endpoints

#### Key Metrics to Monitor:
- Error frequency
- Error types and patterns
- Performance degradation
- User impact

### 7. **Rollback Testing**

Test that the application works properly when Sentry is unavailable:

```bash
# Test without Sentry DSN
unset SENTRY_DSN
# Application should continue working normally
```

### 8. **Security Considerations**

- ✅ Test endpoints require authentication in production
- ✅ Special headers required for production tests
- ✅ No sensitive data in error messages
- ✅ Proper error sanitization

### 9. **Expected Production Errors to Test**

1. **500 Internal Server Error**
2. **Database Connection Timeout**
3. **External API Failures**
4. **Memory Allocation Issues**
5. **Authentication Failures**

### 10. **Post-Deployment Checklist**

- [ ] Health check endpoint returns `sentry_configured: true`
- [ ] Test error appears in Sentry dashboard
- [ ] Error includes proper stack trace
- [ ] Error includes environment context
- [ ] Performance data is being collected
- [ ] Alerts are configured and working
- [ ] Team notifications are set up

## 🔧 Troubleshooting

### Common Issues:

1. **Sentry not configured**: Check `SENTRY_DSN` environment variable
2. **Errors not appearing**: Verify DSN format and network connectivity
3. **Missing stack traces**: Ensure `sentry.package_source_code` runs in build
4. **Performance issues**: Monitor Sentry overhead in production

### Debug Commands:
```bash
# Check Sentry configuration
curl https://your-domain.com/api/health/sentry

# Check environment variables (be careful with sensitive data)
env | grep SENTRY

# Test error logging
logger error "Test Sentry error logging"
```

## 🎯 Success Criteria

Sentry is working correctly in production when:
- ✅ Health check shows `sentry_configured: true`
- ✅ Test errors appear in Sentry dashboard within 30 seconds
- ✅ Stack traces include source code context
- ✅ Performance data is collected
- ✅ Alerts trigger correctly
- ✅ Application continues working when Sentry is unavailable