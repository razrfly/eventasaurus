defmodule EventasaurusApp.Repo.Migrations.AddPaymentMethodFieldsToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :payment_method_type, :string, default: "stripe_only"
      add :payment_instructions, :text
    end
  end
end
