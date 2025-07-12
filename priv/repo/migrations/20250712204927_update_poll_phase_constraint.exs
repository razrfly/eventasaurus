defmodule EventasaurusApp.Repo.Migrations.UpdatePollPhaseConstraint do
  use Ecto.Migration

  def up do
    # Drop the old constraint
    execute "ALTER TABLE polls DROP CONSTRAINT IF EXISTS valid_phase"

    # Add the new constraint with additional phases
    execute """
    ALTER TABLE polls ADD CONSTRAINT valid_phase
    CHECK (phase IN ('list_building', 'voting', 'voting_with_suggestions', 'voting_only', 'closed'))
    """
  end

  def down do
    # Drop the new constraint
    execute "ALTER TABLE polls DROP CONSTRAINT IF EXISTS valid_phase"

    # Restore the old constraint (for rollback)
    execute """
    ALTER TABLE polls ADD CONSTRAINT valid_phase
    CHECK (phase IN ('list_building', 'voting', 'closed'))
    """
  end
end
