defmodule EventasaurusApp.Repo.Migrations.PopulateAllCountriesFromLibrary do
  use Ecto.Migration

  def up do
    # Import all countries from the 'countries' library
    # This provides ISO 3166 country data

    for country <- Countries.all() do
      # Generate a URL-friendly slug using country code to ensure uniqueness
      # This prevents collisions between countries with similar names (e.g., "Congo" variations)
      slug =
        country.name
        |> String.downcase()
        |> String.replace(~r/[^\w\s-]/, "")
        |> String.replace(~r/\s+/, "-")
        |> then(fn base_slug -> "#{base_slug}-#{String.downcase(country.alpha2)}" end)

      now = DateTime.utc_now()

      repo().query!(
        """
        INSERT INTO countries (name, code, slug, inserted_at, updated_at)
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (code) DO UPDATE SET
          name = EXCLUDED.name,
          slug = EXCLUDED.slug,
          updated_at = EXCLUDED.updated_at
        """,
        [country.name, country.alpha2, slug, now, now]
      )
    end
  end

  def down do
    # Don't delete countries on rollback as they might be referenced by cities
    # If you need to clean up, do it manually
    :ok
  end
end
