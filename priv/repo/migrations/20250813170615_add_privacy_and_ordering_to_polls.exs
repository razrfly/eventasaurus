defmodule EventasaurusApp.Repo.Migrations.AddPrivacyAndOrderingToPolls do
  use Ecto.Migration

  def up do
    # Add privacy_settings column if it doesn't exist
    execute """
    ALTER TABLE polls 
    ADD COLUMN IF NOT EXISTS privacy_settings jsonb DEFAULT '{}' NOT NULL
    """

    # Add order_index column if it doesn't exist
    execute """
    ALTER TABLE polls 
    ADD COLUMN IF NOT EXISTS order_index integer DEFAULT 0 NOT NULL
    """

    # Create index if it doesn't exist
    execute """
    CREATE INDEX IF NOT EXISTS polls_event_id_order_index_active 
    ON polls (event_id, order_index) 
    WHERE deleted_at IS NULL
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS polls_event_id_order_index_active"
    execute "ALTER TABLE polls DROP COLUMN IF EXISTS order_index"
    execute "ALTER TABLE polls DROP COLUMN IF EXISTS privacy_settings"
  end
end