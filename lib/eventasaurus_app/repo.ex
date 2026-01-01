defmodule EventasaurusApp.Repo do
  @moduledoc """
  Primary Ecto Repo for Eventasaurus.

  For read-heavy operations where eventual consistency is acceptable,
  use `replica/0` to route queries to read replicas:

      Repo.replica().all(query)

  The `replica/0` function handles:
  - Test environment: Returns primary Repo (sandbox compatibility)
  - Kill switch: USE_REPLICA=false routes to primary
  - Production: Returns ReplicaRepo (connects to PlanetScale replicas)
  """

  use Ecto.Repo,
    otp_app: :eventasaurus,
    adapter: Ecto.Adapters.Postgres

  use Ecto.SoftDelete.Repo

  @doc """
  Returns the appropriate repo for read operations.

  In production, returns ReplicaRepo which connects to PlanetScale read replicas.
  In test environment, returns the primary Repo for sandbox compatibility.
  Can be disabled with USE_REPLICA=false environment variable.

  ## Usage

      # Read from replica (eventual consistency OK)
      Repo.replica().all(from e in Event, where: e.published == true)

      # For reads after writes, use primary directly
      event = Repo.insert!(changeset)
      Repo.get!(Event, event.id)  # Primary, not replica

  ## When to Use

  Use replica for:
  - Admin dashboards and analytics
  - Background job reads (stats caches, monitoring)
  - Public listings where lag is acceptable
  - Heavy aggregate queries

  Use primary (default) for:
  - Authentication/session queries
  - Reads immediately after writes
  - Real-time collaborative features
  - Transaction-critical operations
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

      # Production: Temporarily route to PgBouncer primary for connection stability
      # Direct replica connections (ReplicaRepo) disabled pending Dedicated Replica PgBouncer
      # See issue #3080 Phase 4 for re-enabling with pooled replica access
      true ->
        __MODULE__
    end
  end
end
