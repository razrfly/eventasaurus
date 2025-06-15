defmodule EventasaurusApp.Repo.Migrations.CreateStripeConnectAccounts do
  use Ecto.Migration

  def change do
    create table(:stripe_connect_accounts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :stripe_user_id, :string, null: false
      add :connected_at, :utc_datetime, null: false
      add :disconnected_at, :utc_datetime

      timestamps()
    end

    create unique_index(:stripe_connect_accounts, [:stripe_user_id])
    create unique_index(:stripe_connect_accounts, [:user_id], where: "disconnected_at IS NULL")
  end
end
