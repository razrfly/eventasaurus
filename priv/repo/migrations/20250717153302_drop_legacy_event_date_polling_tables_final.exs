defmodule EventasaurusApp.Repo.Migrations.DropLegacyEventDatePollingTablesFinal do
  use Ecto.Migration

  def up do
    # Drop tables in reverse dependency order to avoid foreign key constraint issues
    
    # 1. Drop event_date_votes table first (depends on event_date_options)
    # Remove the constraint first if table exists
    execute """
    DO $$
    BEGIN
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'event_date_votes') THEN
            ALTER TABLE event_date_votes DROP CONSTRAINT IF EXISTS valid_vote_type;
        END IF;
    END $$;
    """
    drop_if_exists table(:event_date_votes)

    # 2. Drop event_date_options table (depends on event_date_polls)
    drop_if_exists table(:event_date_options)

    # 3. Drop event_date_polls table (depends on events and users, but those remain)
    drop_if_exists table(:event_date_polls)
  end

  def down do
    # Recreate tables in dependency order for rollback
    
    # 1. Recreate event_date_polls table first
    create table(:event_date_polls) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, on_delete: :delete_all), null: false
      add :voting_deadline, :utc_datetime
      add :finalized_date, :date

      timestamps()
    end

    create index(:event_date_polls, [:created_by_id])
    create unique_index(:event_date_polls, [:event_id])
    create index(:event_date_polls, [:voting_deadline])

    # 2. Recreate event_date_options table
    create table(:event_date_options) do
      add :event_date_poll_id, references(:event_date_polls, on_delete: :delete_all), null: false
      add :date, :date, null: false

      timestamps()
    end

    create index(:event_date_options, [:event_date_poll_id])
    create unique_index(:event_date_options, [:event_date_poll_id, :date])
    create index(:event_date_options, [:date])

    # 3. Recreate event_date_votes table
    create table(:event_date_votes) do
      add :event_date_option_id, references(:event_date_options, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :vote_type, :string, null: false

      timestamps()
    end

    create index(:event_date_votes, [:event_date_option_id])
    create index(:event_date_votes, [:user_id])
    create unique_index(:event_date_votes, [:event_date_option_id, :user_id])
    create index(:event_date_votes, [:vote_type])

    # Recreate the constraint
    execute "ALTER TABLE event_date_votes ADD CONSTRAINT valid_vote_type CHECK (vote_type IN ('yes', 'if_need_be', 'no'))"
  end
end
