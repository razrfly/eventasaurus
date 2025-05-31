defmodule Eventasaurus.Repo.Migrations.CreateEventDateVotes do
  use Ecto.Migration

  def up do
    create table(:event_date_votes) do
      add :event_date_option_id, references(:event_date_options, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :vote_type, :string, null: false

      timestamps()
    end

    create index(:event_date_votes, [:event_date_option_id])
    create index(:event_date_votes, [:user_id])

    # Ensure one vote per user per date option
    create unique_index(:event_date_votes, [:event_date_option_id, :user_id])

    # Index for finding votes by type for analytics
    create index(:event_date_votes, [:vote_type])

    # Add constraint to enforce valid vote types
    execute "ALTER TABLE event_date_votes ADD CONSTRAINT valid_vote_type CHECK (vote_type IN ('yes', 'if_need_be', 'no'))"
  end

  def down do
    # Drop constraint first
    execute "ALTER TABLE event_date_votes DROP CONSTRAINT valid_vote_type"

    drop table(:event_date_votes)
  end
end
