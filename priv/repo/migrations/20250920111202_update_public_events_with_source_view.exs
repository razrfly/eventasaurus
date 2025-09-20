defmodule EventasaurusApp.Repo.Migrations.UpdatePublicEventsWithSourceView do
  use Ecto.Migration

  def change do
    # Drop the view that depends on description column
    execute "DROP VIEW IF EXISTS public_events_with_source CASCADE"

    # The view will be recreated later to include description_translations from public_event_sources
  end
end
