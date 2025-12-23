defmodule EventasaurusApp.Repo.Migrations.CreateUserPerformerFollows do
  use Ecto.Migration

  def change do
    create table(:user_performer_follows) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :performer_id, references(:performers, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:user_performer_follows, [:user_id, :performer_id])
    create index(:user_performer_follows, [:performer_id])
  end
end
