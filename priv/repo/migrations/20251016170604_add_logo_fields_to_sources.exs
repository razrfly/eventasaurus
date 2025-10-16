defmodule EventasaurusApp.Repo.Migrations.AddLogoUrlToSources do
  use Ecto.Migration

  def change do
    alter table(:sources) do
      add :logo_url, :string
    end
  end
end
