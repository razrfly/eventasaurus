defmodule EventasaurusApp.Repo.Migrations.PopulateAllCountriesFromLibrary do
  use Ecto.Migration

  def up do
    # Import all countries from the 'countries' library
    # This provides ISO 3166 country data

    for country <- Countries.all() do
      # Generate a URL-friendly slug
      slug = country.name
        |> String.downcase()
        |> String.replace(~r/[^\w\s-]/, "")
        |> String.replace(~r/\s+/, "-")

      execute """
      INSERT INTO countries (name, code, slug, inserted_at, updated_at)
      VALUES ('#{escape_string(country.name)}', '#{country.alpha2}', '#{slug}', NOW(), NOW())
      ON CONFLICT (code) DO UPDATE SET
        name = EXCLUDED.name,
        slug = EXCLUDED.slug,
        updated_at = NOW()
      """
    end
  end

  def down do
    # Don't delete countries on rollback as they might be referenced by cities
    # If you need to clean up, do it manually
    :ok
  end

  defp escape_string(str) do
    String.replace(str, "'", "''")
  end
end
