defmodule EventasaurusApp.Repo do
  @moduledoc """
  Primary Ecto Repo for Eventasaurus.

  ## Connection Architecture (Fly Managed Postgres)

  - **Repo (this module)**: PgBouncer pooled connection - DEFAULT for all traffic
  - **ObanRepo**: PgBouncer pooled connection - Dedicated pool for Oban jobs
  - **SessionRepo**: Direct connection - Migrations and advisory locks only

  ## Usage

  For most operations, use Repo directly (goes through PgBouncer):

      Repo.all(query)
      Repo.insert(changeset)

  For backwards compatibility, `Repo.replica()` returns this module.
  Fly MPG basic plan doesn't have separate read replicas (the HA replica
  is for failover only, not read scaling).
  """

  use Ecto.Repo,
    otp_app: :eventasaurus,
    adapter: Ecto.Adapters.Postgres

  use Ecto.SoftDelete.Repo

  @doc """
  Returns the Repo to use for read operations.

  On Fly Managed Postgres basic plan, there are no separate read replicas
  (the replica is for HA failover only). All reads go through the primary.

  This function exists for backwards compatibility with code that calls
  `Repo.replica()` for heavy read operations.

  ## Note

  If you upgrade to a Fly MPG plan with read replicas in the future,
  you can update this function to route to a ReplicaRepo.
  """
  @spec replica() :: module()
  def replica do
    # Fly MPG basic plan doesn't have read replicas
    # All reads go through primary via PgBouncer
    __MODULE__
  end
end
