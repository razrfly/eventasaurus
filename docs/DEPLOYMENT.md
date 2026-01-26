# Deployment Guide

## Infrastructure

Eventasaurus is deployed on **Fly.io** with:
- **Fly Managed Postgres (MPG)** - Production database
- **Clerk** - Authentication provider
- **Cloudflare** - CDN and DNS

## Environment Variables

### Required Variables
- `DATABASE_URL` - PostgreSQL connection string (provided by Fly MPG)
- `SECRET_KEY_BASE` - Phoenix secret key base
- `CLERK_SECRET_KEY` - Clerk authentication secret
- `CLERK_PUBLISHABLE_KEY` - Clerk frontend key

### Optional Variables
- `POOL_SIZE` - Database connection pool size (default: 5)
- `SITE_URL` - Your site URL (default: "https://eventasaur.us")
- `PHX_HOST` - Phoenix host configuration

## Database Configuration

### Fly Managed Postgres

The application uses Fly Managed Postgres for production:

- **Cluster ID**: `k1v53olmn9pr8q6p`
- **Database**: `eventasaurus`
- **Organization**: `teamups`

### Connection Configuration

```elixir
config :eventasaurus, EventasaurusApp.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5"),
  queue_target: 5000,
  queue_interval: 30000,
  ssl: true
```

### Connecting to Production Database

```bash
# Via fly mpg connect
fly mpg connect k1v53olmn9pr8q6p -d eventasaurus

# Via app SSH (recommended - uses app's connection pool)
fly ssh console -a eventasaurus -C '/app/bin/eventasaurus rpc "
{:ok, result} = Ecto.Adapters.SQL.query(EventasaurusApp.ObanRepo, \"SELECT 1\")
IO.inspect(result)
"'
```

### Syncing Production to Local

Use the `mix db.sync_production` task to sync production data to local development:

```bash
# Full sync (export + import)
mix db.sync_production

# Export only (save dump for later import)
mix db.sync_production --export-only

# Import from existing dump
mix db.sync_production --import-only --dump-path priv/dumps/eventasaurus_20250126.dump
```

See CLAUDE.md for detailed usage and options.

## Deployment Checklist

### Pre-Deployment
1. ✅ Run tests: `mix test`
2. ✅ Check formatting: `mix format --check-formatted`
3. ✅ Compile without warnings: `mix compile --warnings-as-errors`
4. ✅ Run migrations locally to test

### Deployment
1. ✅ Set required environment variables via `fly secrets set`
2. ✅ Deploy: `fly deploy`
3. ✅ Run migrations: `fly ssh console -C '/app/bin/eventasaurus migrate'`
4. ✅ Check application logs: `fly logs`

### Post-Deployment
1. ✅ Verify health check endpoint
2. ✅ Test authentication flow
3. ✅ Check Oban job processing
4. ✅ Verify CDN caching behavior

## Secrets Management

```bash
# List current secrets
fly secrets list -a eventasaurus

# Set a secret
fly secrets set MY_SECRET=value -a eventasaurus

# Deploy after setting secrets (if not auto-deployed)
fly deploy -a eventasaurus
```

## Monitoring

### Application Logs
```bash
fly logs -a eventasaurus
```

### Database Status
```bash
fly mpg status k1v53olmn9pr8q6p
```

### Machine Status
```bash
fly status -a eventasaurus
fly machine list -a eventasaurus
```

## Troubleshooting

### Database Connection Errors
- Verify `DATABASE_URL` is set correctly: `fly secrets list`
- Check MPG cluster status: `fly mpg status k1v53olmn9pr8q6p`
- Test connection via proxy: `fly mpg connect k1v53olmn9pr8q6p -d eventasaurus`

### Migration Failures
- Check migration status: `fly ssh console -C '/app/bin/eventasaurus eval "Ecto.Migrator.migrations(EventasaurusApp.Repo)"'`
- Run migrations manually: `fly ssh console -C '/app/bin/eventasaurus migrate'`

### Authentication Issues
- Verify Clerk keys are set correctly
- Check Clerk dashboard for webhook status
- Verify `PHX_HOST` matches your domain

### Asset/CDN Issues
- Clear Cloudflare cache if serving stale assets
- Check `cache_manifest.json` was generated
- Verify asset digests in HTML responses
