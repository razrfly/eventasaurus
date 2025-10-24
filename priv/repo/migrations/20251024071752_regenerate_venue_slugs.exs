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
  """

  def up do
    # Use code execution for data migration
    execute(&regenerate_all_venue_slugs/0)
  end

  def down do
    # This migration is not reversible since we're discarding the old slug format
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
    batch_size = 100

    result =
      Repo.transaction(fn ->
        process_venues_in_batches(batch_size, total)
      end, timeout: :infinity)

    case result do
      {:ok, {updated, skipped, errors}} ->
        Logger.info("""
        Venue slug regeneration complete!
        - Updated: #{updated}
        - Skipped: #{skipped}
        - Errors: #{errors}
        """)

      {:error, reason} ->
        Logger.error("Venue slug regeneration failed: #{inspect(reason)}")
        raise "Migration failed: #{inspect(reason)}"
    end
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
          limit: ^batch_size,
          offset: ^offset,
          preload: [city_ref: :country]
        )
        |> Repo.all()

      # Process each venue in the batch
      batch_result =
        Enum.reduce(venues, {0, 0, 0}, fn venue, {u, s, e} ->
          case regenerate_venue_slug(venue) do
            {:ok, _} ->
              if rem(u + s + e + 1, 50) == 0 do
                Logger.info("Processed #{u + s + e + 1}/#{total} venues...")
              end
              {u + 1, s, e}
            {:skipped, _} -> {u, s + 1, e}
            {:error, reason} ->
              Logger.warning("Failed to update venue #{venue.id}: #{inspect(reason)}")
              {u, s, e + 1}
          end
        end)

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
