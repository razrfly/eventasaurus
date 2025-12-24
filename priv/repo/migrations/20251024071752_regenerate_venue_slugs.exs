defmodule EventasaurusApp.Repo.Migrations.RegenerateVenueSlugs do
  use Ecto.Migration
  require Logger

  @moduledoc """
  Regenerates all venue slugs using the new progressive disambiguation strategy.

  This migration updates all existing venues to use the new slug format:
  - name only (if unique)
  - name-city (if duplicate)
  - name-timestamp (fallback)

  Old format: venue-name-{city_id}-{random}
  New format: venue-name or venue-name-{city-slug}

  After regenerating all slugs, adds NOT NULL constraint to ensure data integrity.
  """

  def up do
    # Use code execution for data migration
    execute(&regenerate_all_venue_slugs/0)

    # Verify all slugs are non-null before adding constraint
    execute(&verify_no_nil_slugs/0)

    # Drop views that depend on venues.slug before altering the column
    execute("DROP VIEW IF EXISTS trivia_events_export")
    execute("DROP VIEW IF EXISTS public_events_view")

    # Now that all venues have slugs, add NOT NULL constraint
    alter table(:venues) do
      modify :slug, :string, null: false
    end

    # Recreate the views
    execute(&create_public_events_view/0)
    execute(&create_trivia_events_export_view/0)
  end

  def down do
    # Remove NOT NULL constraint
    alter table(:venues) do
      modify :slug, :string, null: true
    end

    # This migration is not reversible for slug regeneration since we're discarding the old slug format
    # Old slugs are not preserved
    :ok
  end

  defp regenerate_all_venue_slugs do
    alias EventasaurusApp.Repo

    Logger.info("Starting venue slug regeneration...")

    # Get total count for progress tracking using raw SQL to avoid schema issues
    {:ok, %{rows: [[total]]}} = Repo.query("SELECT COUNT(*) FROM venues")
    Logger.info("Found #{total} venues to process")

    # Process venues in batches to avoid memory issues
    # Each batch commits separately to reduce lock contention
    batch_size = 100

    {updated, skipped, errors} = process_venues_in_batches(batch_size, total)

    Logger.info("""
    Venue slug regeneration complete!
    - Updated: #{updated}
    - Skipped: #{skipped}
    - Errors: #{errors}
    """)

    # Halt migration if any errors occurred
    if errors > 0 do
      raise """
      Migration halted: Failed to regenerate #{errors} venue slugs.
      Cannot proceed with NOT NULL constraint. Please investigate failed venues.
      Check logs above for specific error details.
      """
    end
  end

  defp verify_no_nil_slugs do
    alias EventasaurusApp.Repo

    # Count venues with nil slugs using raw SQL to avoid schema issues
    {:ok, %{rows: [[nil_slug_count]]}} =
      Repo.query("SELECT COUNT(*) FROM venues WHERE slug IS NULL")

    if nil_slug_count > 0 do
      # Get sample of venues with nil slugs for debugging
      {:ok, %{rows: sample_rows}} =
        Repo.query("SELECT id, name FROM venues WHERE slug IS NULL LIMIT 5")

      raise """
      Migration halted: Found #{nil_slug_count} venues with nil slugs.
      Cannot add NOT NULL constraint.

      Sample venues with nil slugs:
      #{Enum.map_join(sample_rows, "\n", fn [id, name] -> "  - ID: #{id}, Name: #{name}" end)}

      Please investigate why these venues failed slug regeneration.
      """
    end

    Logger.info("✅ Verified all venues have non-nil slugs")
  end

  defp process_venues_in_batches(batch_size, total) do
    alias EventasaurusApp.Repo

    # Process in batches using offset
    # NOTE: Using raw SQL to avoid schema dependency issues during migrations
    0..total
    |> Stream.chunk_every(batch_size)
    |> Enum.reduce({0, 0, 0}, fn batch_indexes, {updated, skipped, errors} ->
      offset = List.first(batch_indexes) || 0

      # Use raw SQL query to avoid schema column dependency issues
      {:ok, %{rows: venue_rows, columns: columns}} =
        Repo.query(
          """
          SELECT v.id, v.name, v.slug, v.city_id,
                 c.slug as city_slug, c.name as city_name,
                 co.code as country_code
          FROM venues v
          LEFT JOIN cities c ON v.city_id = c.id
          LEFT JOIN countries co ON c.country_id = co.id
          ORDER BY v.id
          LIMIT $1 OFFSET $2
          """,
          [batch_size, offset]
        )

      # Convert rows to maps for easier access
      venues =
        Enum.map(venue_rows, fn row ->
          columns
          |> Enum.zip(row)
          |> Map.new(fn {col, val} -> {String.to_atom(col), val} end)
        end)

      # Process each venue in the batch within a transaction
      batch_result =
        Repo.transaction(fn ->
          Enum.reduce(venues, {0, 0, 0}, fn venue, {u, s, e} ->
            case regenerate_venue_slug(venue) do
              {:ok, _} ->
                processed_so_far = offset + u + s + e + 1

                if rem(processed_so_far, 50) == 0 do
                  Logger.info("Processed #{processed_so_far}/#{total} venues...")
                end

                {u + 1, s, e}

              {:skipped, _} ->
                {u, s + 1, e}

              {:error, reason} ->
                Logger.warning("Failed to update venue #{venue.id}: #{inspect(reason)}")
                {u, s, e + 1}
            end
          end)
        end)

      # Extract result from transaction
      batch_result =
        case batch_result do
          {:ok, result} -> result
          {:error, _} -> {0, 0, length(venues)}
        end

      {
        updated + elem(batch_result, 0),
        skipped + elem(batch_result, 1),
        errors + elem(batch_result, 2)
      }
    end)
  end

  defp regenerate_venue_slug(venue_map) do
    alias EventasaurusApp.Repo

    # Generate new slug using the same algorithm as Venue.Slug
    # but without loading the full Venue schema
    new_slug = generate_venue_slug(venue_map)

    cond do
      is_nil(new_slug) ->
        {:error, "Slug generation returned nil for venue #{venue_map.id} (#{venue_map.name})"}

      new_slug == venue_map.slug ->
        {:skipped, "Slug unchanged"}

      true ->
        case Repo.query(
               "UPDATE venues SET slug = $1, updated_at = NOW() WHERE id = $2",
               [new_slug, venue_map.id]
             ) do
          {:ok, _} ->
            {:ok, new_slug}

          {:error, error} ->
            {:error, error}
        end
    end
  end

  # Generate slug using the progressive disambiguation strategy
  # Replicates Venue.Slug logic without needing the full schema
  defp generate_venue_slug(venue_map) do
    alias EventasaurusApp.Repo

    base_slug = Slug.slugify(venue_map.name)

    if base_slug == "" or is_nil(base_slug) do
      nil
    else
      # Try base slug first
      if slug_available?(base_slug, venue_map.id) do
        base_slug
      else
        # Try with city disambiguation
        city_slug = venue_map[:city_slug]

        if city_slug do
          disambiguated = "#{base_slug}-#{city_slug}"

          if slug_available?(disambiguated, venue_map.id) do
            disambiguated
          else
            # Fallback to timestamp
            "#{base_slug}-#{System.system_time(:second)}"
          end
        else
          # No city, fallback to timestamp
          "#{base_slug}-#{System.system_time(:second)}"
        end
      end
    end
  end

  defp slug_available?(slug, venue_id) do
    alias EventasaurusApp.Repo

    {:ok, %{rows: [[count]]}} =
      Repo.query(
        "SELECT COUNT(*) FROM venues WHERE slug = $1 AND id != $2",
        [slug, venue_id]
      )

    count == 0
  end

  defp create_public_events_view do
    """
    CREATE VIEW public_events_view AS
    SELECT
      pe.id,
      pe.slug,
      pe.title,
      pe.title_translations,
      pe.starts_at,
      pe.ends_at,
      pe.venue_id,
      pe.category_id,
      pes.min_price,
      pes.max_price,
      pes.currency,
      pes.is_free,
      pe.inserted_at,
      pe.updated_at,
      pes.id AS source_id,
      pes.description_translations,
      pes.image_url,
      pes.source_url,
      pes.external_id,
      pes.metadata AS source_metadata,
      pes.last_seen_at AS source_last_seen_at,
      v.name AS venue_name,
      v.slug AS venue_slug,
      v.address AS venue_address,
      v.latitude AS venue_latitude,
      v.longitude AS venue_longitude,
      v.venue_type,
      c.id AS city_id,
      c.name AS city_name,
      c.slug AS city_slug,
      co.id AS country_id,
      co.name AS country_name,
      co.code AS country_code,
      cat.name AS category_name,
      cat.slug AS category_slug,
      cat.translations AS category_translations,
      cat.icon AS category_icon,
      cat.color AS category_color
    FROM public_events pe
    LEFT JOIN LATERAL (
      SELECT *
      FROM public_event_sources
      WHERE event_id = pe.id
      ORDER BY
        COALESCE(
          CASE
            WHEN metadata->>'priority' ~ '^[0-9]+$'
            THEN (metadata->>'priority')::integer
            ELSE NULL
          END,
          10
        ),
        last_seen_at DESC
      LIMIT 1
    ) pes ON true
    LEFT JOIN venues v ON pe.venue_id = v.id
    LEFT JOIN cities c ON v.city_id = c.id
    LEFT JOIN countries co ON c.country_id = co.id
    LEFT JOIN categories cat ON pe.category_id = cat.id
    """
  end

  defp create_trivia_events_export_view do
    """
    CREATE VIEW trivia_events_export AS
    SELECT
      pe.id,
      pe.title AS name,

      -- Extract day_of_week from pattern (1=Monday, 7=Sunday)
      CASE (pe.occurrences->'pattern'->'days_of_week'->0)::text
        WHEN '"monday"' THEN 1
        WHEN '"tuesday"' THEN 2
        WHEN '"wednesday"' THEN 3
        WHEN '"thursday"' THEN 4
        WHEN '"friday"' THEN 5
        WHEN '"saturday"' THEN 6
        WHEN '"sunday"' THEN 7
      END AS day_of_week,

      -- Extract start_time from pattern
      (pe.occurrences->'pattern'->>'time')::time AS start_time,

      -- Extract timezone from pattern
      pe.occurrences->'pattern'->>'timezone' AS timezone,

      -- Map frequency to enum
      LOWER(pe.occurrences->'pattern'->>'frequency') AS frequency,

      -- Convert price to cents (handle NULL and free events)
      CASE
        WHEN pes.is_free THEN 0
        WHEN pes.min_price IS NOT NULL THEN (pes.min_price * 100)::integer
        ELSE NULL
      END AS entry_fee_cents,

      -- Get description (prefer English, fallback to any language)
      COALESCE(
        pes.description_translations->>'en',
        pes.description_translations->>
          (SELECT jsonb_object_keys(pes.description_translations) LIMIT 1),
        ''
      ) AS description,

      -- Get hero_image (source image OR first venue image when available)
      COALESCE(
        pes.image_url,
        v.venue_images->0->>'url'
      ) AS hero_image,

      pe.venue_id,

      -- Get first performer (optional)
      (SELECT pep.performer_id
       FROM public_event_performers pep
       WHERE pep.event_id = pe.id
       LIMIT 1) AS performer_id,

      -- Source information
      s.id AS source_id,
      s.name AS source_name,
      s.slug AS source_slug,
      s.logo_url AS source_logo_url,
      s.website_url AS source_website_url,

      -- Venue information (complete)
      v.name AS venue_name,
      v.slug AS venue_slug,
      v.address AS venue_address,
      v.latitude AS venue_latitude,
      v.longitude AS venue_longitude,
      v.metadata->'geocoding'->'raw_response'->>'postcode' AS venue_postcode,
      v.metadata->'geocoding'->'raw_response'->>'place_id' AS venue_place_id,
      v.metadata AS venue_metadata,
      v.venue_images AS venue_images,

      -- City information
      v.city_id,
      c.slug AS city_slug,
      c.name AS city_name,
      c.latitude AS city_latitude,
      c.longitude AS city_longitude,
      c.unsplash_gallery AS city_images,

      -- Country information
      co.id AS country_id,
      co.name AS country_name,
      co.code AS country_code,

      -- Metadata
      pes.source_url,
      pe.inserted_at,
      pe.updated_at

    FROM public_events pe
    INNER JOIN venues v ON v.id = pe.venue_id
    LEFT JOIN cities c ON c.id = v.city_id
    LEFT JOIN countries co ON co.id = c.country_id
    LEFT JOIN LATERAL (
      SELECT * FROM public_event_sources pes2
      WHERE pes2.event_id = pe.id
      ORDER BY pes2.last_seen_at DESC
      LIMIT 1
    ) pes ON true
    INNER JOIN sources s ON s.id = pes.source_id
    WHERE
      -- Filter by trusted trivia sources
      s.slug IN (
        'question-one',
        'quizmeisters',
        'inquizition',
        'speed-quizzing',
        'pubquiz-pl',
        'geeks-who-drink'
      )
      -- Double-check: must have trivia category
      AND EXISTS (
        SELECT 1 FROM public_event_categories pec
        INNER JOIN categories cat ON cat.id = pec.category_id
        WHERE pec.event_id = pe.id AND cat.slug = 'trivia'
      )
      -- Ensure single category only (trivia-only events)
      AND (SELECT COUNT(*) FROM public_event_categories WHERE event_id = pe.id) = 1
      -- Only events with pattern data
      AND pe.occurrences->'pattern' IS NOT NULL
      AND pe.occurrences->'pattern'->'days_of_week' IS NOT NULL
      AND jsonb_array_length(pe.occurrences->'pattern'->'days_of_week') > 0
    """
  end
end
