defmodule EventasaurusApp.JobRepo do
  @moduledoc """
  Dedicated Ecto Repo for Oban job business logic with direct PostgreSQL connection.

  ## Why Direct Connection?

  PgBouncer in transaction mode kills queries exceeding 30 seconds. Oban jobs
  frequently run longer queries:
  - City page aggregation: 30-90s with 800+ events
  - Materialized view refreshes: 30-60s
  - Heavy sync jobs: 20-60s with external API calls + DB writes

  This repo bypasses PgBouncer and connects directly to PostgreSQL, allowing
  jobs to run as long as needed without timeout issues.

  ## Architecture (Issue #3353)

  ```
  Web Requests ──► Repo (pool: 10) ──► PgBouncer ──► PostgreSQL
  Oban Jobs ────► JobRepo (pool: 20) ──► Direct ──► PostgreSQL
  Migrations ───► SessionRepo (pool: 1) ──► Direct ──► PostgreSQL
  ```

  Key insight: Web requests are short and concurrent (benefit from PgBouncer).
  Job queries can be long-running (need direct connection without timeout).

  ## Usage

  All Oban job code should use JobRepo instead of Repo:

      # In job modules:
      alias EventasaurusApp.JobRepo

      def perform(%Oban.Job{args: args}) do
        JobRepo.all(from e in Event, where: ...)
        JobRepo.insert(changeset)
      end

  ## Configuration

  Configured in `config/runtime.exs` with `DATABASE_DIRECT_URL` (bypasses PgBouncer).
  Pool size defaults to 20, tunable via `JOB_POOL_SIZE` environment variable.

  Pool size rationale: Max concurrent Oban workers is ~18, plus headroom for
  transactions that span multiple operations. Direct connections don't multiplex
  like PgBouncer, so each checkout holds one PostgreSQL connection.
  """

  use Ecto.Repo,
    otp_app: :eventasaurus,
    adapter: Ecto.Adapters.Postgres

  use Ecto.SoftDelete.Repo
end
