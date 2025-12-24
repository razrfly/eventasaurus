defmodule EventasaurusApp.Repo.Migrations.CreateUserVenueFollows do
  use Ecto.Migration

  def change do
    create table(:user_venue_follows) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :venue_id, references(:venues, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:user_venue_follows, [:user_id, :venue_id])
    create index(:user_venue_follows, [:venue_id])
  end
end
