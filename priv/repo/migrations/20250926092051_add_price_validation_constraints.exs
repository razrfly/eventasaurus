defmodule EventasaurusApp.Repo.Migrations.AddPriceValidationConstraints do
  use Ecto.Migration

  def change do
    # Ensure prices are non-negative
    create constraint(:public_event_sources, :non_negative_prices,
      check: "(min_price IS NULL OR min_price >= 0) AND (max_price IS NULL OR max_price >= 0)")

    # Ensure min_price <= max_price when both are present
    create constraint(:public_event_sources, :price_range_order,
      check: "(min_price IS NULL OR max_price IS NULL OR min_price <= max_price)")

    # Add a constraint for valid currency codes (3 chars or NULL)
    create constraint(:public_event_sources, :valid_currency_code,
      check: "(currency IS NULL OR LENGTH(currency) = 3)")
  end
end