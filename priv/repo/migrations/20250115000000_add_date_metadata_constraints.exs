defmodule Eventasaurus.Repo.Migrations.AddDateMetadataConstraints do
  use Ecto.Migration

  def up do
    # Add check constraint to ensure poll options with date metadata have proper structure
    # Note: Simplified to avoid subquery limitation - applies to all poll options with date metadata
    execute """
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
    )
    """

    # Add partial index for date_selection poll options to improve query performance
    create index(:poll_options, ["(metadata->>'date')", :poll_id],
           name: :poll_options_date_metadata_idx,
           where: "metadata ? 'date'")

    # Add index for efficient lookup of poll options by date
    create index(:poll_options, ["(metadata->>'date')"],
           name: :poll_options_date_value_idx,
           where: "metadata ? 'date'")
  end

  def down do
    # Remove indexes
    drop index(:poll_options, ["(metadata->>'date')"], name: :poll_options_date_value_idx)
    drop index(:poll_options, ["(metadata->>'date')", :poll_id], name: :poll_options_date_metadata_idx)

    # Remove constraint
    execute "ALTER TABLE poll_options DROP CONSTRAINT IF EXISTS valid_date_metadata_structure"
  end
end
