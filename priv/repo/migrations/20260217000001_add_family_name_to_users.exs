defmodule EventasaurusApp.Repo.Migrations.AddFamilyNameToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:family_name, :string)
    end

    create(index(:users, [:family_name]))
  end
end
