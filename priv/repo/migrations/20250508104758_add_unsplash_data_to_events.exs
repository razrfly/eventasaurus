defmodule EventasaurusApp.Repo.Migrations.AddUnsplashDataToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :unsplash_data, :map
    end
  end
end
