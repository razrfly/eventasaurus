defmodule EventasaurusApp.Repo.Migrations.CreatePerformers do
  use Ecto.Migration

  def up do
    create table(:performers) do
      add :name, :string, null: false
      add :normalized_name, :string
      add :slug, :string, null: false
      add :external_id, :string
      add :image_url, :string
      add :genre, :string
      add :metadata, :map, default: %{}
      add :source_id, :integer

      timestamps()
    end

    # Create normalization function for performers
    execute """
    CREATE OR REPLACE FUNCTION normalize_performer_name(text) RETURNS text AS $$
    BEGIN
      RETURN LOWER(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            COALESCE($1, ''),
            '[^a-z0-9]', '', 'gi'
          ),
          '\\s+', '', 'g'
        )
      );
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;
    """

    # Create trigger to auto-normalize performer names
    execute """
    CREATE OR REPLACE FUNCTION performers_normalize_trigger() RETURNS trigger AS $$
    BEGIN
      NEW.normalized_name = normalize_performer_name(NEW.name);
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER performers_normalize_name
    BEFORE INSERT OR UPDATE ON performers
    FOR EACH ROW
    EXECUTE FUNCTION performers_normalize_trigger();
    """

    create unique_index(:performers, [:slug])
    create unique_index(:performers, [:external_id, :source_id])
    create unique_index(:performers, [:normalized_name, :source_id])
  end

  def down do
    drop table(:performers)
    execute "DROP FUNCTION IF EXISTS normalize_performer_name(text);"
    execute "DROP FUNCTION IF EXISTS performers_normalize_trigger();"
  end
end