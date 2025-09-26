defmodule EventasaurusApp.Repo.Migrations.AddUniqueConstraintsToCitiesAndCountries do
  use Ecto.Migration

  def change do
    # Add unique constraints to prevent duplicate countries
    create unique_index(:countries, [:code], name: :countries_code_unique)
    create unique_index(:countries, [:slug], name: :countries_slug_unique)

    # Add unique constraint for city slugs within the same country
    # This prevents duplicate cities like having two "Kraków" cities
    create unique_index(:cities, [:slug, :country_id], name: :cities_slug_country_unique)
  end
end
