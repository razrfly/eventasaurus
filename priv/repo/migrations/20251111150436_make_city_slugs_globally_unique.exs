defmodule EventasaurusApp.Repo.Migrations.MakeCitySlugsGloballyUnique do
  use Ecto.Migration

  def up do
    # Step 1: Find and fix duplicate slugs
    rename_duplicate_slugs()

    # Step 2: Drop old composite unique indexes (there are two duplicates)
    drop_if_exists unique_index(:cities, [:country_id, :slug], name: :cities_country_id_slug_index)
    drop_if_exists unique_index(:cities, [:slug, :country_id], name: :cities_slug_country_unique)

    # Step 3: Drop non-unique slug index
    drop_if_exists index(:cities, [:slug], name: :cities_slug_index)

    # Step 4: Add global unique index
    create unique_index(:cities, [:slug], name: :cities_slug_index)

    # Step 5: Add composite index for (name, country_id) lookups
    # This supports the new lookup pattern in venue_store.ex
    create index(:cities, [:name, :country_id], name: :cities_name_country_id_index)
  end

  def down do
    # Reverse: drop composite index for name lookups
    drop_if_exists index(:cities, [:name, :country_id], name: :cities_name_country_id_index)

    # Reverse: drop global unique index
    drop_if_exists unique_index(:cities, [:slug], name: :cities_slug_index)

    # Re-add non-unique index
    create index(:cities, [:slug], name: :cities_slug_index)

    # Re-add composite unique indexes
    create unique_index(:cities, [:country_id, :slug], name: :cities_country_id_slug_index)
    create unique_index(:cities, [:slug, :country_id], name: :cities_slug_country_unique)

    # Note: Cannot automatically reverse slug renames
    # Manual intervention required if rollback needed
  end

  defp rename_duplicate_slugs do
    # Get duplicate groups with IDs and country codes
    query = """
    SELECT
      c.slug,
      array_agg(c.id ORDER BY c.id) as city_ids,
      array_agg(co.code ORDER BY c.id) as country_codes
    FROM cities c
    JOIN countries co ON c.country_id = co.id
    GROUP BY c.slug
    HAVING COUNT(c.id) > 1
    """

    result = Ecto.Adapters.SQL.query!(repo(), query, [])

    # Process each duplicate group
    Enum.each(result.rows, fn [slug, city_ids, country_codes] ->
      # Skip the first city (lowest ID) - it keeps clean slug
      city_ids
      |> Enum.drop(1)
      |> Enum.zip(Enum.drop(country_codes, 1))
      |> Enum.each(fn {city_id, country_code} ->
        # Handle nil or blank country codes gracefully
        normalized_code =
          case country_code do
            binary when is_binary(binary) and binary != "" -> String.downcase(binary)
            _ -> "unknown"
          end

        candidate_slug = "#{slug}-#{normalized_code}"

        # Check if candidate slug already exists to prevent collision
        # Use microsecond precision to avoid collisions when processing multiple cities in same second
        new_slug =
          if slug_exists?(candidate_slug) do
            "#{candidate_slug}-#{System.system_time(:microsecond)}"
          else
            candidate_slug
          end

        IO.puts("Renaming city #{city_id}: #{slug} -> #{new_slug}")

        Ecto.Adapters.SQL.query!(repo(), "UPDATE cities SET slug = $1 WHERE id = $2", [
          new_slug,
          city_id
        ])
      end)
    end)
  end

  defp slug_exists?(slug) do
    result =
      Ecto.Adapters.SQL.query!(
        repo(),
        "SELECT 1 FROM cities WHERE slug = $1 LIMIT 1",
        [slug]
      )

    result.num_rows > 0
  end
end
