defmodule EventasaurusApp.Repo.Migrations.AddStateToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :state, :string, default: "confirmed", null: false
    end

    # Add index for performance when filtering by state
    create index(:events, [:state])

    # Set existing events to confirmed state
    execute "UPDATE events SET state = 'confirmed' WHERE state IS NULL"
  end
end
