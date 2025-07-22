defmodule EventasaurusApp.Repo.Migrations.AddEventParticipantsCompositeIndex do
  use Ecto.Migration

  def change do
    create index(:event_participants, [:event_id, :deleted_at])
  end
end