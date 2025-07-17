# Sentry Testing Guide for Eventasaurus

## Overview

This guide provides step-by-step instructions for testing Sentry integration in your Eventasaurus application. Follow these steps to ensure Sentry is properly configured and working in both development and production environments.

## Prerequisites

- Sentry DSN configured in your environment (set as `SENTRY_DSN` environment variable)
- For production testing: authenticated admin access to the application
- For local testing: development environment running

## Testing Methods

### 1. Health Check Testing (Recommended First Step)

Check if Sentry is properly configured:

```bash
# Check Sentry configuration status
curl -X GET "https://your-app.fly.dev/api/health/sentry"
```

**Expected Response:**
```json
{
  "sentry_configured": true,
  "environment": "prod",
  "timestamp": "2025-07-17T10:30:00Z"
}
```

**If Sentry is not configured:**
```json
{
  "sentry_configured": false,
  "environment": "prod", 
  "timestamp": "2025-07-17T10:30:00Z"
}
```

### 2. Development Testing

For local development and testing:

```bash
# Test error capture
curl -X GET "http://localhost:4000/dev/sentry/test-error"

# Test message capture  
curl -X GET "http://localhost:4000/dev/sentry/test-message"
```

**Expected Responses:**
- Error test: `{"error": "Test error sent to Sentry"}`
- Message test: `{"message": "Test message sent to Sentry"}`

### 3. Production Testing (Secure)

For production environments, use the secure admin endpoint:

```bash
# Replace YOUR_AUTH_TOKEN with your actual authentication token
curl -X POST "https://your-app.fly.dev/api/admin/sentry-test" \
  -H "Authorization: Bearer YOUR_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-sentry-test: production-test"
```

**Expected Success Response:**
```json
{
  "success": true,
  "message": "Production test error sent to Sentry",
  "event_id": "abc123def456",
  "timestamp": "2025-07-17T10:30:00Z",
  "environment": "prod"
}
```

**Expected Error Response (if Sentry fails):**
```json
{
  "error": "Failed to send test error to Sentry",
  "reason": "connection timeout",
  "timestamp": "2025-07-17T10:30:00Z"
}
```

## Automated Testing with Script

Use the provided test script for comprehensive testing:

```bash
# Set your Sentry DSN
export SENTRY_DSN="your-sentry-dsn-here"

# Run automated tests
./test_sentry_prod.sh
```

**Script tests:**
1. Production mode with valid Sentry DSN
2. Production mode without DSN (graceful degradation)
3. Production mode with invalid DSN (proper error handling)

## Verifying Results in Sentry

After running tests, verify in your Sentry dashboard:

1. **Login to Sentry**: Go to https://sentry.io
2. **Navigate to your project**: Find your Eventasaurus project
3. **Check Issues**: Look for recent test errors/messages
4. **Verify details**: Confirm environment, timestamp, and stack traces

### What to Look For:

- **Test Errors**: Should appear as "Production Sentry Test Error" or "ArithmeticError" (division by zero)
- **Test Messages**: Should appear as "Test message from Eventasaurus"
- **Environment**: Should match your testing environment (dev/prod)
- **Timestamp**: Should match when you ran the test

## Production Deployment Verification

After deploying to production:

1. **Health Check**: Verify Sentry configuration
2. **Monitor Logs**: Check application logs for Sentry initialization
3. **Test Endpoint**: Use secure production test endpoint once
4. **Monitor Dashboard**: Confirm test appears in Sentry within 1-2 minutes

## Troubleshooting

### Common Issues:

#### Sentry Not Configured
```json
{"sentry_configured": false, ...}
```
**Solution**: Set `SENTRY_DSN` environment variable in your deployment

#### Rate Limited
```json
{"error": "rate_limit_exceeded", ...}
```
**Solution**: Wait 60 seconds and try again (health check limited to 10 requests/minute)

#### Unauthorized Access
```json
{"error": "Production test endpoint requires proper environment and headers"}
```
**Solution**: Ensure you're using:
- Production environment
- Valid authentication token
- Required header: `x-sentry-test: production-test`

#### Connection Errors
```json
{"error": "Failed to send test error to Sentry", "reason": "connection timeout"}
```
**Solution**: 
- Check network connectivity
- Verify Sentry DSN is correct
- Check Sentry service status

## Security Notes

- **Production endpoint** is protected by:
  - Authentication required
  - Special header required (`x-sentry-test: production-test`)
  - Rate limiting (60 requests/minute)
  - Audit logging of all attempts

- **All test attempts are logged** with:
  - IP address
  - User agent
  - User ID (if authenticated)
  - Timestamp
  - Success/failure status

## Monitoring and Alerts

### Log Monitoring
Monitor application logs for:
- `"Production Sentry test triggered"` - Successful test attempts
- `"Unauthorized access attempt to production Sentry test endpoint"` - Security alerts
- `"Failed to send production test error to Sentry"` - Integration issues

### Sentry Alerts
Set up alerts in Sentry for:
- High error rates
- New error types
- Integration failures

## Integration with CI/CD

Add Sentry testing to your deployment pipeline:

```yaml
# Example GitHub Actions step
- name: Test Sentry Integration
  run: |
    export SENTRY_DSN="${{ secrets.SENTRY_DSN }}"
    ./test_sentry_prod.sh
```

## Best Practices

1. **Test after each deployment**: Verify Sentry is working
2. **Monitor regularly**: Check Sentry dashboard weekly
3. **Keep DSN secure**: Store in environment variables, not code
4. **Limit production testing**: Only test when necessary
5. **Monitor logs**: Watch for unauthorized access attempts

## Getting Help

If you encounter issues:

1. Check the [Sentry documentation](https://docs.sentry.io)
2. Review application logs for error details
3. Verify environment variables are set correctly
4. Test with health check endpoint first
5. Contact your team's system administrator

## Environment Variables Reference

Required environment variables:

```bash
# Production
SENTRY_DSN=https://your-dsn@sentry.io/project-id

# Development (optional - can use same DSN)
SENTRY_DSN=https://your-dsn@sentry.io/project-id
```

## Quick Reference Commands

```bash
# Health check
curl -X GET "https://your-app.fly.dev/api/health/sentry"

# Production test (replace YOUR_AUTH_TOKEN)
curl -X POST "https://your-app.fly.dev/api/admin/sentry-test" \
  -H "Authorization: Bearer YOUR_AUTH_TOKEN" \
  -H "x-sentry-test: production-test"

# Development test
curl -X GET "http://localhost:4000/dev/sentry/test-error"

# Automated testing
export SENTRY_DSN="your-dsn" && ./test_sentry_prod.sh
```