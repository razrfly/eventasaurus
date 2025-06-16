defmodule EventasaurusApp.Repo.Migrations.AddFlexiblePricingToTickets do
  use Ecto.Migration

  def up do
    # Rename existing price_cents to base_price_cents
    rename table(:tickets), :price_cents, to: :base_price_cents

    # Add new pricing fields
    alter table(:tickets) do
      add :minimum_price_cents, :integer, null: false, default: 0
      add :suggested_price_cents, :integer
      add :pricing_model, :string, null: false, default: "fixed"
    end

    # Add constraints
    create constraint(:tickets, :base_price_cents_non_negative, check: "base_price_cents >= 0")
    create constraint(:tickets, :minimum_price_cents_non_negative, check: "minimum_price_cents >= 0")
    create constraint(:tickets, :suggested_price_cents_non_negative, check: "suggested_price_cents IS NULL OR suggested_price_cents >= 0")
    create constraint(:tickets, :valid_pricing_model, check: "pricing_model IN ('fixed', 'flexible', 'dynamic')")
    create constraint(:tickets, :flexible_pricing_logic, check: "pricing_model != 'flexible' OR minimum_price_cents <= base_price_cents")

    # Update the old constraint name to match the new column name
    drop constraint(:tickets, :price_cents_positive)
  end

  def down do
    # Remove new constraints
    drop constraint(:tickets, :base_price_cents_non_negative)
    drop constraint(:tickets, :minimum_price_cents_non_negative)
    drop constraint(:tickets, :suggested_price_cents_non_negative)
    drop constraint(:tickets, :valid_pricing_model)
    drop constraint(:tickets, :flexible_pricing_logic)

    # Remove new fields
    alter table(:tickets) do
      remove :minimum_price_cents
      remove :suggested_price_cents
      remove :pricing_model
    end

    # Rename base_price_cents back to price_cents
    rename table(:tickets), :base_price_cents, to: :price_cents

    # Restore the original constraint
    create constraint(:tickets, :price_cents_positive, check: "price_cents > 0")
  end
end
