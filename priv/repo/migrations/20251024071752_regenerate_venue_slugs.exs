defmodule EventasaurusApp.Repo.Migrations.RegenerateVenueSlugs do
  use Ecto.Migration
  import Ecto.Query
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

    # Now that all venues have slugs, add NOT NULL constraint
    alter table(:venues) do
      modify :slug, :string, null: false
    end
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
    alias EventasaurusApp.Venues.Venue
    alias EventasaurusDiscovery.Locations.City

    Logger.info("Starting venue slug regeneration...")

    # Get total count for progress tracking
    total = Repo.aggregate(Venue, :count, :id)
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
    alias EventasaurusApp.Venues.Venue

    # Count venues with nil slugs
    nil_slug_count =
      from(v in Venue,
        where: is_nil(v.slug),
        select: count(v.id)
      )
      |> Repo.one()

    if nil_slug_count > 0 do
      # Get sample of venues with nil slugs for debugging
      sample_venues =
        from(v in Venue,
          where: is_nil(v.slug),
          select: {v.id, v.name},
          limit: 5
        )
        |> Repo.all()

      raise """
      Migration halted: Found #{nil_slug_count} venues with nil slugs.
      Cannot add NOT NULL constraint.

      Sample venues with nil slugs:
      #{Enum.map_join(sample_venues, "\n", fn {id, name} -> "  - ID: #{id}, Name: #{name}" end)}

      Please investigate why these venues failed slug regeneration.
      """
    end

    Logger.info("✅ Verified all venues have non-nil slugs")
  end

  defp process_venues_in_batches(batch_size, total) do
    alias EventasaurusApp.Repo
    alias EventasaurusApp.Venues.Venue

    # Process in batches using offset
    0..total
    |> Stream.chunk_every(batch_size)
    |> Enum.reduce({0, 0, 0}, fn batch_indexes, {updated, skipped, errors} ->
      offset = List.first(batch_indexes) || 0

      venues =
        from(v in Venue,
          order_by: [asc: v.id],
          limit: ^batch_size,
          offset: ^offset,
          preload: [city_ref: :country]
        )
        |> Repo.all()

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

  defp regenerate_venue_slug(venue) do
    alias EventasaurusApp.Repo
    alias EventasaurusApp.Venues.Venue

    # Force slug regeneration by setting slug to nil and updating
    changeset =
      venue
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:slug, nil)
      |> Venue.Slug.maybe_generate_slug()

    # Only update if slug actually changed
    new_slug = Ecto.Changeset.get_field(changeset, :slug)

    if new_slug != venue.slug do
      case Repo.update(changeset) do
        {:ok, updated_venue} ->
          {:ok, updated_venue}

        {:error, changeset} ->
          {:error, changeset.errors}
      end
    else
      {:skipped, "Slug unchanged"}
    end
  end
end
