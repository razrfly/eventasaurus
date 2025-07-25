defmodule EventasaurusApp.Repo.Migrations.AddIsVirtualToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :is_virtual, :boolean, default: false, null: false
    end
  end
end
