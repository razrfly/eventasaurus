defmodule EventasaurusApp.Repo.Migrations.AddStripeConnectToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :stripe_connect_account_id, references(:stripe_connect_accounts, on_delete: :restrict)
      add :application_fee_amount, :integer, default: 0
    end

    create index(:orders, [:stripe_connect_account_id])
  end
end
