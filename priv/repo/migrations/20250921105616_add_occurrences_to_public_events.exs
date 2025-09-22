defmodule EventasaurusApp.Repo.Migrations.AddOccurrencesToPublicEvents do
  use Ecto.Migration

  def change do
    alter table(:public_events) do
      add :occurrences, :map
    end
  end
end