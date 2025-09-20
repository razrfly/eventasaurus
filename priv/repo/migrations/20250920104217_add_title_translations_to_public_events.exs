defmodule EventasaurusApp.Repo.Migrations.AddTitleTranslationsToPublicEvents do
  use Ecto.Migration

  def change do
    alter table(:public_events) do
      add :title_translations, :map
    end
  end
end
