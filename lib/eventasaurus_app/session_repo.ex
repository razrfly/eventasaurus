defmodule EventasaurusApp.SessionRepo do
  @moduledoc """
  Dedicated Ecto Repo for direct database connections (Session Mode).

  This repo uses a direct database connection (bypassing PgBouncer/connection pooler) to support
  PostgreSQL features that require persistent connections:

  - Oban background job processing (advisory locks, LISTEN/NOTIFY)
  - Ecto migrations (long-running transactions, DDL operations)
  - Advisory locks (venue/event deduplication)
  - Prepared statements (performance optimization)
  - Future: cursors, temporary tables

  The main `EventasaurusApp.Repo` uses PgBouncer (port 6432) for scalable
  web request handling, while this SessionRepo uses direct connections (port 5432)
  for features that require them.

  ## Configuration

  ### PlanetScale (Primary)
  Uses direct port (5432) constructed from PLANETSCALE_* environment variables:
  - PLANETSCALE_DATABASE_HOST
  - PLANETSCALE_DATABASE
  - PLANETSCALE_DATABASE_USERNAME
  - PLANETSCALE_DATABASE_PASSWORD
  - PLANETSCALE_DATABASE_PORT (default: 5432)

  ### Supabase (Legacy/Fallback)
  Configured via `SUPABASE_SESSION_DATABASE_URL` environment variable pointing to:
  `postgresql://postgres:[PASSWORD]@db.[PROJECT_REF].supabase.co:5432/postgres`

  ## Usage

  - Automatically used by Oban (configured in runtime.exs)
  - Used by migration script (/app/bin/migrate)
  - Can be used directly for any operation requiring direct connection features
  """

  use Ecto.Repo,
    otp_app: :eventasaurus,
    adapter: Ecto.Adapters.Postgres
end
