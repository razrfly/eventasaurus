defmodule EventasaurusApp.Repo.Migrations.AddPollNumber do
  use Ecto.Migration

  def up do
    # Add number column (nullable initially for backfill)
    alter table(:polls) do
      add :number, :integer
    end

    flush()

    # Backfill existing polls using ROW_NUMBER() window function
    # Each event's polls are numbered sequentially based on creation order
    execute """
    WITH numbered_polls AS (
      SELECT
        id,
        ROW_NUMBER() OVER (
          PARTITION BY event_id
          ORDER BY inserted_at, id
        ) as seq
      FROM polls
    )
    UPDATE polls
    SET number = numbered_polls.seq
    FROM numbered_polls
    WHERE polls.id = numbered_polls.id
    """

    # Create unique constraint to prevent duplicate numbers per event
    create unique_index(:polls, [:event_id, :number])

    # Make column required now that all polls have numbers
    alter table(:polls) do
      modify :number, :integer, null: false
    end
  end

  def down do
    alter table(:polls) do
      remove :number
    end
  end
end
