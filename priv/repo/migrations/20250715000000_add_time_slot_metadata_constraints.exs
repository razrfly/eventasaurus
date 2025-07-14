defmodule Eventasaurus.Repo.Migrations.AddTimeSlotMetadataConstraints do
  use Ecto.Migration

  def up do
    # Add check constraint for time slot validation in date_selection polls
    execute """
    ALTER TABLE poll_options
    ADD CONSTRAINT valid_time_metadata_for_date_selection
    CHECK (
      CASE WHEN EXISTS (
        SELECT 1 FROM polls
        WHERE polls.id = poll_options.poll_id
        AND polls.poll_type = 'date_selection'
      )
      THEN (
        -- Basic metadata validation (existing)
        metadata IS NOT NULL
        AND metadata ? 'date'
        AND metadata ? 'display_date'
        AND metadata ? 'date_type'

        -- Time configuration validation
        AND (
          -- If time_enabled is true, validate time constraints
          CASE WHEN (metadata->>'time_enabled')::boolean = true
          THEN (
            metadata ? 'time_slots'
            AND metadata ? 'all_day'
            AND (metadata->>'all_day')::boolean = false
            AND jsonb_array_length(metadata->'time_slots') > 0
            AND (
              -- Validate each time slot has required fields
              SELECT bool_and(
                slot ? 'start_time'
                AND slot ? 'end_time'
                AND length(slot->>'start_time') > 0
                AND length(slot->>'end_time') > 0
                AND (slot->>'start_time') ~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$'
                AND (slot->>'end_time') ~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$'
              )
              FROM jsonb_array_elements(metadata->'time_slots') AS slot
            )
          )
          -- If time_enabled is false or null, ensure all_day is true (backward compatibility)
          WHEN (metadata->>'time_enabled')::boolean = false OR metadata->>'time_enabled' IS NULL
          THEN (
            (metadata->>'all_day')::boolean = true OR metadata->>'all_day' IS NULL
          )
          ELSE true
          END
        )

        -- Duration constraints if present
        AND (
          metadata->>'duration_minutes' IS NULL
          OR (
            (metadata->>'duration_minutes')::integer > 0
            AND (metadata->>'duration_minutes')::integer <= 1440
          )
        )
      )
      ELSE true
      END
    )
    """

    # Add partial index for time-enabled poll options to improve query performance
    create index(:poll_options, ["(metadata->>'time_enabled')", :poll_id],
           name: :poll_options_time_enabled_idx,
           where: "metadata ? 'time_enabled' AND (metadata->>'time_enabled')::boolean = true")

    # Add GIN index for time slots to enable efficient querying
    execute """
    CREATE INDEX CONCURRENTLY poll_options_time_slots_gin_idx
    ON poll_options USING GIN ((metadata->'time_slots'))
    WHERE metadata ? 'time_slots' AND jsonb_array_length(metadata->'time_slots') > 0
    """

    # Add index for timezone-based queries
    execute """
    CREATE INDEX CONCURRENTLY poll_options_timezone_idx
    ON poll_options USING BTREE (((metadata->'time_slots'->0->>'timezone')))
    WHERE metadata ? 'time_slots' AND jsonb_array_length(metadata->'time_slots') > 0
    """
  end

  def down do
    # Remove indexes
    execute "DROP INDEX CONCURRENTLY IF EXISTS poll_options_timezone_idx"
    execute "DROP INDEX CONCURRENTLY IF EXISTS poll_options_time_slots_gin_idx"
    drop index(:poll_options, ["(metadata->>'time_enabled')", :poll_id],
               name: :poll_options_time_enabled_idx)

    # Remove constraint
    execute "ALTER TABLE poll_options DROP CONSTRAINT IF EXISTS valid_time_metadata_for_date_selection"
  end
end
