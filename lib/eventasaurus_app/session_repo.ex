defmodule EventasaurusApp.SessionRepo do
  @moduledoc """
  Dedicated Ecto Repo for Session Mode database connections.

  This repo uses a direct database connection (bypassing Supavisor pooler) to support
  PostgreSQL features that require persistent connections:

  - Oban background job processing (advisory locks)
  - Ecto migrations (long-running transactions)
  - Advisory locks (venue/event deduplication)
  - Prepared statements (performance optimization)
  - Future: LISTEN/NOTIFY, cursors, temporary tables

  The main `EventasaurusApp.Repo` uses Transaction mode (pgbouncer) for scalable
  web request handling, while this SessionRepo provides dedicated persistent connections
  for features that require them.

  ## Configuration

  Configured via `SUPABASE_SESSION_DATABASE_URL` environment variable pointing to:
  `postgresql://postgres:[PASSWORD]@db.[PROJECT_REF].supabase.co:5432/postgres`

  ## Usage

  - Automatically used by Oban (configured in config.exs)
  - Used by migration script (/app/bin/migrate)
  - Can be used directly for any operation requiring Session mode features
  """

  use Ecto.Repo,
    otp_app: :eventasaurus,
    adapter: Ecto.Adapters.Postgres
end
