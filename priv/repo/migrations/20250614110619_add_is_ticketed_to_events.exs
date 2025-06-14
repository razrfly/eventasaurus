defmodule EventasaurusApp.Repo.Migrations.AddIsTicketedToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :is_ticketed, :boolean, default: false, null: false
    end
  end
end
