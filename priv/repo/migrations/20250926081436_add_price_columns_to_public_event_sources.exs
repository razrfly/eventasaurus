defmodule EventasaurusApp.Repo.Migrations.AddPriceColumnsToPublicEventSources do
  use Ecto.Migration

  def change do
    alter table(:public_event_sources) do
      add :min_price, :decimal, precision: 10, scale: 2
      add :max_price, :decimal, precision: 10, scale: 2
      add :currency, :string, size: 3
      add :is_free, :boolean, default: false, null: false
    end

    # Add check constraint to ensure is_free can't be true when prices exist
    create constraint(:public_event_sources, :is_free_price_consistency,
      check: "NOT (is_free = true AND (min_price IS NOT NULL OR max_price IS NOT NULL))")

    # Create indexes for price queries
    create index(:public_event_sources, [:min_price])
    create index(:public_event_sources, [:max_price])
    create index(:public_event_sources, [:event_id, :min_price])
    create index(:public_event_sources, [:is_free])

    # We're not removing columns from public_events yet to maintain backward compatibility
    # That can be done in a future migration once everything is working
  end
end