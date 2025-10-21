defmodule EventasaurusApp.Repo.Migrations.AddOccurrencesToPublicEvents do
  use Ecto.Migration

  def change do
    alter table(:public_events) do
      add :occurrences, :jsonb, default: "{}"
    end
  end
end