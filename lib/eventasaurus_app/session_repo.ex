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

  ### Fly Managed Postgres (Primary)
  Configured via `DATABASE_DIRECT_URL` environment variable, which bypasses PgBouncer
  and connects directly to Postgres for operations requiring persistent connections.

  ### Development
  Uses local PostgreSQL by default. Set `USE_PROD_DB=true` to connect to production.

  ## Usage

  - Automatically used by Oban (configured in runtime.exs)
  - Used by migration script (/app/bin/migrate)
  - Can be used directly for any operation requiring direct connection features
  """

  use Ecto.Repo,
    otp_app: :eventasaurus,
    adapter: Ecto.Adapters.Postgres
end
