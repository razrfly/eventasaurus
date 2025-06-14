defmodule EventasaurusApp.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders) do
      add :quantity, :integer, null: false
      add :subtotal_cents, :integer, null: false
      add :tax_cents, :integer, default: 0, null: false
      add :total_cents, :integer, null: false
      add :currency, :string, default: "usd", null: false
      add :status, :string, default: "pending", null: false
      add :stripe_session_id, :string
      add :payment_reference, :string
      add :confirmed_at, :utc_datetime
      add :user_id, references(:users, on_delete: :restrict), null: false
      add :event_id, references(:events, on_delete: :restrict), null: false
      add :ticket_id, references(:tickets, on_delete: :restrict), null: false

      timestamps()
    end

    create index(:orders, [:user_id])
    create index(:orders, [:event_id])
    create index(:orders, [:ticket_id])
    create index(:orders, [:status])
    create unique_index(:orders, [:stripe_session_id], where: "stripe_session_id IS NOT NULL")

    create constraint(:orders, :quantity_positive, check: "quantity > 0")
    create constraint(:orders, :subtotal_non_negative, check: "subtotal_cents >= 0")
    create constraint(:orders, :tax_non_negative, check: "tax_cents >= 0")
    create constraint(:orders, :total_positive, check: "total_cents > 0")
    create constraint(:orders, :valid_status, check: "status IN ('pending', 'confirmed', 'refunded', 'canceled')")
  end
end
