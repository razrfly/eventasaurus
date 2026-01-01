defmodule EventasaurusApp.Repo do
  @moduledoc """
  Primary Ecto Repo for Eventasaurus (PgBouncer, port 6432).

  ## Connection Architecture (Issue #3119)

  - **Repo (this module)**: PgBouncer primary - DEFAULT for all traffic
  - **SessionRepo**: Direct primary - migrations and advisory locks only
  - **ReplicaRepo**: Direct replicas - long-running read-only background jobs

  ## Usage

  For most operations, use Repo directly (goes through PgBouncer):

      Repo.all(query)
      Repo.insert(changeset)

  For long-running READ-ONLY operations (stats caches, analytics), use replica:

      Repo.replica().all(heavy_aggregate_query)

  This offloads heavy reads to replicas, preserving primary capacity.
  """

  use Ecto.Repo,
    otp_app: :eventasaurus,
    adapter: Ecto.Adapters.Postgres

  use Ecto.SoftDelete.Repo

  @doc """
  Returns ReplicaRepo for long-running read-only operations.

  Routes to direct replica connections (port 5432) which:
  - Have their own 25-connection limit per replica (separate from primary)
  - Are ideal for heavy aggregates, stats caches, analytics
  - Offload read pressure from primary

  ## When to Use

  Use `Repo.replica()` for:
  - Stats cache refreshes (DiscoveryStatsCache, CityPageCache, etc.)
  - Admin dashboard analytics
  - Heavy aggregate queries
  - Any long-running READ-ONLY operation

  Use `Repo` directly for:
  - All writes (inserts, updates, deletes)
  - Short reads (web requests)
  - Reads immediately after writes
  - Transaction-critical operations

  ## Kill Switch

  Set `USE_REPLICA=false` to route all replica reads to primary.
  """
  @spec replica() :: module()
  def replica do
    cond do
      # Test environment: Use primary for Ecto sandbox compatibility
      Application.get_env(:eventasaurus, :environment) == :test ->
        __MODULE__

      # Kill switch: USE_REPLICA=false routes all reads to primary
      System.get_env("USE_REPLICA") == "false" ->
        __MODULE__

      # Production: Route to ReplicaRepo for long-running reads
      # Uses direct connections to replicas (separate from primary's 25-connection limit)
      # See issue #3119 for architecture details
      true ->
        EventasaurusApp.ReplicaRepo
    end
  end
end
