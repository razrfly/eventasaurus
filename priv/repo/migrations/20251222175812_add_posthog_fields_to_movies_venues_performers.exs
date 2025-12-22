defmodule EventasaurusApp.Repo.Migrations.AddPosthogFieldsToMoviesVenuesPerformers do
  use Ecto.Migration

  def change do
    # Add PostHog analytics fields to movies table
    alter table(:movies) do
      add :posthog_view_count, :integer, default: 0
      add :posthog_synced_at, :utc_datetime
    end

    create index(:movies, [:posthog_view_count])

    # Add PostHog analytics fields to venues table
    alter table(:venues) do
      add :posthog_view_count, :integer, default: 0
      add :posthog_synced_at, :utc_datetime
    end

    create index(:venues, [:posthog_view_count])

    # Add PostHog analytics fields to performers table
    alter table(:performers) do
      add :posthog_view_count, :integer, default: 0
      add :posthog_synced_at, :utc_datetime
    end

    create index(:performers, [:posthog_view_count])
  end
end
