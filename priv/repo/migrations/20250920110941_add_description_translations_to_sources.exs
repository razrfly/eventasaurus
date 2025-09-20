defmodule EventasaurusApp.Repo.Migrations.AddDescriptionTranslationsToSources do
  use Ecto.Migration

  def change do
    alter table(:public_event_sources) do
      add :description_translations, :map
    end
  end
end
