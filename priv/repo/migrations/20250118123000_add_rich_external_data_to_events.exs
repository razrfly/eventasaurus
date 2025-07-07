defmodule EventasaurusApp.Repo.Migrations.AddRichExternalDataToEvents do
  use Ecto.Migration

  def up do
    # Add the new rich_external_data field as JSONB for comprehensive external API data
    alter table(:events) do
      add :rich_external_data, :map, default: %{}, null: false
    end

    # Add GIN index for efficient JSONB queries
    create index(:events, [:rich_external_data], using: :gin, name: :events_rich_external_data_gin_idx)

    # Add partial indexes for common query patterns
    execute """
    CREATE INDEX events_tmdb_data_idx ON events
    USING gin((rich_external_data->'tmdb'))
    WHERE rich_external_data ? 'tmdb'
    """

    execute """
    CREATE INDEX events_external_provider_idx ON events ((rich_external_data ? 'tmdb'))
    WHERE rich_external_data != '{}'::jsonb
    """
  end

  def down do
    # Drop custom indexes first
    execute "DROP INDEX IF EXISTS events_tmdb_data_idx"
    execute "DROP INDEX IF EXISTS events_external_provider_idx"

    # Drop the GIN index
    drop index(:events, [:rich_external_data], name: :events_rich_external_data_gin_idx)

    # Remove the column
    alter table(:events) do
      remove :rich_external_data
    end
  end
end
