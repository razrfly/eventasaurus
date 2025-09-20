defmodule EventasaurusApp.Repo.Migrations.RemoveDescriptionFromPublicEventsAfterViewDrop do
  use Ecto.Migration

  def change do
    alter table(:public_events) do
      remove :description, :string
    end
  end
end
