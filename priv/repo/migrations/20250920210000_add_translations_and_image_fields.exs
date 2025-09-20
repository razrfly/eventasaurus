defmodule EventasaurusApp.Repo.Migrations.AddTranslationsAndImageFields do
  use Ecto.Migration

  def up do
    # First drop any existing views that depend on the description column
    execute "DROP VIEW IF EXISTS public_events_with_source CASCADE"
    execute "DROP VIEW IF EXISTS public_events_with_category CASCADE"

    # Add translation fields to public_events
    alter table(:public_events) do
      add :title_translations, :map
      remove :description, :text  # Remove description as it will be in sources
    end

    # Add translation and image fields to public_event_sources
    alter table(:public_event_sources) do
      add :description_translations, :map
      add :image_url, :text
    end
  end

  def down do
    # Re-add description column
    alter table(:public_events) do
      add :description, :text
      remove :title_translations
    end

    # Remove translation and image fields from sources
    alter table(:public_event_sources) do
      remove :description_translations
      remove :image_url
    end
  end
end