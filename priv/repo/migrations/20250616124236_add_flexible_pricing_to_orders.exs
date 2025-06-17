defmodule EventasaurusApp.Repo.Migrations.AddFlexiblePricingToOrders do
  use Ecto.Migration

  def up do
    alter table(:orders) do
      # Store pricing snapshot as JSONB for flexible historical tracking
      add :pricing_snapshot, :map
    end
  end

  def down do
    alter table(:orders) do
      remove :pricing_snapshot
    end
  end
end
