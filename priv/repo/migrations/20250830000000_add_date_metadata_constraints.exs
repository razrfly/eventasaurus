defmodule Eventasaurus.Repo.Migrations.AddDateMetadataConstraints do
  use Ecto.Migration

  def up do
    # Add check constraint to ensure poll options with date metadata have proper structure
    # Note: Simplified to avoid subquery limitation - applies to all poll options with date metadata
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.constraint_column_usage 
        WHERE table_name = 'poll_options' 
        AND constraint_name = 'valid_date_metadata_structure'
      ) THEN
        ALTER TABLE poll_options
        ADD CONSTRAINT valid_date_metadata_structure
        CHECK (
          CASE WHEN metadata ? 'date'
          THEN (
            metadata IS NOT NULL
            AND metadata ? 'display_date'
            AND metadata ? 'date_type'
            AND (metadata->>'date') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
            AND length(metadata->>'display_date') > 0
            AND (metadata->>'date_type') IN ('single_date', 'date_range', 'recurring_date')
          )
          ELSE true
          END
        );
      END IF;
    END $$;
    """

    # Add partial index for date_selection poll options to improve query performance
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_indexes 
        WHERE tablename = 'poll_options' 
        AND indexname = 'poll_options_date_metadata_idx'
      ) THEN
        CREATE INDEX poll_options_date_metadata_idx 
        ON poll_options ((metadata->>'date'), poll_id) 
        WHERE metadata ? 'date';
      END IF;
    END $$;
    """

    # Add index for efficient lookup of poll options by date
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_indexes 
        WHERE tablename = 'poll_options' 
        AND indexname = 'poll_options_date_value_idx'
      ) THEN
        CREATE INDEX poll_options_date_value_idx 
        ON poll_options ((metadata->>'date')) 
        WHERE metadata ? 'date';
      END IF;
    END $$;
    """
  end

  def down do
    # Remove indexes
    drop index(:poll_options, ["(metadata->>'date')"], name: :poll_options_date_value_idx)
    drop index(:poll_options, ["(metadata->>'date')", :poll_id], name: :poll_options_date_metadata_idx)

    # Remove constraint
    execute "ALTER TABLE poll_options DROP CONSTRAINT IF EXISTS valid_date_metadata_structure"
  end
end
