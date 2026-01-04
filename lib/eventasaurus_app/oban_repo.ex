defmodule EventasaurusApp.ObanRepo do
  @moduledoc """
  Dedicated Ecto Repo for Oban background job processing.

  ## Why a Dedicated Pool?

  Oban job processing can exhaust the shared connection pool when:
  - Scrapers spawn hundreds of jobs simultaneously (midnight cron)
  - All jobs compete for connections with web requests
  - Connection pool exhaustion causes jobs to pile up indefinitely

  This dedicated pool isolates Oban from web traffic:
  - ObanRepo: pool_size 5 - dedicated for job fetching and execution
  - Repo: pool_size 10 - dedicated for web requests and LiveView
  - Both use PgBouncer (port 6432), not direct connections

  ## Architecture (Issue #3160)

  ```
  Web Requests ──► Repo (pool: 10) ──► PgBouncer ──► PostgreSQL
  Oban Jobs ────► ObanRepo (pool: 5) ──► PgBouncer ──► PostgreSQL
  Migrations ───► SessionRepo (pool: 1) ──► Direct ──► PostgreSQL
  Heavy Reads ──► ReplicaRepo (pool: 3) ──► Direct ──► Replicas
  ```

  The key insight: PgBouncer can handle hundreds of client connections
  efficiently. Separating Repo and ObanRepo prevents job stampedes from
  blocking web requests, and vice versa.

  ## Configuration

  Configured in `config/runtime.exs` with the same PgBouncer connection
  settings as Repo, but a separate pool. Pool size can be tuned via
  the `OBAN_POOL_SIZE` environment variable (default: 5).
  """

  use Ecto.Repo,
    otp_app: :eventasaurus,
    adapter: Ecto.Adapters.Postgres
end
