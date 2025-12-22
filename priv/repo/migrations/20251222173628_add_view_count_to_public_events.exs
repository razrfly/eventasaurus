defmodule EventasaurusApp.Repo.Migrations.AddViewCountToPublicEvents do
  use Ecto.Migration

  def change do
    alter table(:public_events) do
      add :posthog_view_count, :integer, default: 0
      add :posthog_synced_at, :utc_datetime
    end

    create index(:public_events, [:posthog_view_count])
  end
end
