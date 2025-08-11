defmodule EventasaurusApp.Repo.Migrations.AddDonationFieldsToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :suggested_amounts, {:array, :integer}, default: [1000, 2500, 5000, 10000]
      add :allow_custom_amount, :boolean, default: true
      add :minimum_donation_amount, :integer
      add :maximum_donation_amount, :integer
      add :donation_message, :text
    end
  end
end
