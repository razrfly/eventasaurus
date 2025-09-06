defmodule EventasaurusApp.Repo.Migrations.AddPollsEventIdDeletedAtIndex do
  use Ecto.Migration

  def change do
    # Add composite index for optimal performance of poll count queries
    create index(:polls, [:event_id, :deleted_at], 
      name: :polls_event_id_deleted_at_index,
      comment: "Optimize poll count queries in event listings"
    )
  end
end
