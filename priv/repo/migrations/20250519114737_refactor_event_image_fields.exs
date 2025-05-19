defmodule EventasaurusApp.Repo.Migrations.RefactorEventImageFields do
  use Ecto.Migration

  def change do
    alter table(:events) do
      remove :unsplash_data, :map
      add :external_image_data, :map
    end
  end
end
