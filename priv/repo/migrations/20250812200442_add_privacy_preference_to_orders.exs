defmodule EventasaurusApp.Repo.Migrations.AddPrivacyPreferenceToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :privacy_preference, :string, default: "default"
    end
  end
end
