defmodule EventasaurusApp.Repo.Migrations.CreateTickets do
  use Ecto.Migration

  def change do
    create table(:tickets) do
      add :title, :string, null: false
      add :description, :text
      add :price_cents, :integer, null: false
      add :currency, :string, default: "usd", null: false
      add :quantity, :integer, null: false
      add :starts_at, :utc_datetime
      add :ends_at, :utc_datetime
      add :tippable, :boolean, default: false, null: false
      add :event_id, references(:events, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:tickets, [:event_id])
    create constraint(:tickets, :price_cents_positive, check: "price_cents > 0")
    create constraint(:tickets, :quantity_positive, check: "quantity > 0")
  end
end
