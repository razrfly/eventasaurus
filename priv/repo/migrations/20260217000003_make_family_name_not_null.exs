defmodule EventasaurusApp.Repo.Migrations.MakeFamilyNameNotNull do
  use Ecto.Migration

  def change do
    alter table(:users) do
      modify(:family_name, :string, null: false, from: {:string, null: true})
    end
  end
end
