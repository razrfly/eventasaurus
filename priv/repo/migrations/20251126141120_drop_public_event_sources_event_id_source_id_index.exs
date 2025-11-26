defmodule EventasaurusApp.Repo.Migrations.DropPublicEventSourcesEventIdSourceIdIndex do
  use Ecto.Migration

  def change do
    # Drop the unique constraint on (event_id, source_id) to allow
    # multiple PublicEventSource records per event (needed for showtimes)
    drop_if_exists index(:public_event_sources, [:event_id, :source_id],
                        name: "public_event_sources_event_id_source_id_index")
  end
end
