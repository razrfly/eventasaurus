defmodule EventasaurusApp.Repo.Migrations.CreateExternalServiceCosts do
  use Ecto.Migration

  def change do
    create table(:external_service_costs) do
      # Service identification
      add :service_type, :string, null: false
      add :provider, :string, null: false
      add :operation, :string

      # Cost data
      add :cost_usd, :decimal, precision: 10, scale: 6, null: false
      add :units, :integer, default: 1
      add :unit_type, :string

      # Reference to source entity (polymorphic)
      add :reference_type, :string
      add :reference_id, :bigint

      # Flexible metadata
      add :metadata, :map, default: %{}

      # When the cost occurred (may differ from insert time)
      add :occurred_at, :utc_datetime_usec, null: false, default: fragment("NOW()")

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes for common query patterns
    create index(:external_service_costs, [:service_type])
    create index(:external_service_costs, [:provider])
    create index(:external_service_costs, [:occurred_at])
    create index(:external_service_costs, [:reference_type, :reference_id])

    # Composite index for dashboard queries (service type + time range)
    create index(:external_service_costs, [:service_type, :occurred_at])

    # Composite index for provider breakdown queries
    create index(:external_service_costs, [:provider, :occurred_at])
  end
end
