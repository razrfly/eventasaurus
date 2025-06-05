# Deployment Guide

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

## Deployment Checklist

1. ✅ Set required environment variables
2. ✅ Configure SSL settings for your database provider
3. ✅ Verify database connectivity
4. ✅ Check application logs for SSL warnings
5. ✅ Test authentication flow
6. ✅ Confirm Phoenix socket origin settings 