defmodule EventasaurusApp.Repo.Migrations.AddTimezoneToCities do
  @moduledoc """
  Add timezone column to cities table.

  This eliminates runtime TzWorld lookups by pre-computing timezone at the city level.
  Cities almost always have a single timezone, and all venues in a city share it.

  See Issue #3334 for full analysis of why city-level is correct:
  - Country-level is wrong for multi-TZ countries (US has 6 TZ, AU has 3)
  - Venue-level is redundant (avg 2.1 venues per city)
  - City-level: 2,908 one-time lookups, then ZERO runtime TzWorld calls

  After migration, run: mix populate_city_timezones
  """
  use Ecto.Migration

  def change do
    alter table(:cities) do
      # IANA timezone identifier (e.g., "Europe/Warsaw", "America/Chicago")
      # Nullable initially - populated by mix task after migration
      add :timezone, :string
    end

    # Index for potential queries filtering by timezone
    create index(:cities, [:timezone])
  end
end
