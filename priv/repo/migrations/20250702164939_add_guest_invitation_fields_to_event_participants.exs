defmodule EventasaurusApp.Repo.Migrations.AddGuestInvitationFieldsToEventParticipants do
  use Ecto.Migration

  def change do
    alter table(:event_participants) do
      # Track who invited this participant (nullable since existing participants won't have this)
      add :invited_by_user_id, references(:users, on_delete: :nilify_all), null: true

      # Track when the invitation was sent
      add :invited_at, :utc_datetime, null: true

      # Optional custom invitation message
      add :invitation_message, :text, null: true
    end

    # Add index for queries filtering by invited_by_user_id
    create index(:event_participants, [:invited_by_user_id])

    # Add index for queries filtering by invited_at (for sorting/filtering by invitation date)
    create index(:event_participants, [:invited_at])
  end
end
