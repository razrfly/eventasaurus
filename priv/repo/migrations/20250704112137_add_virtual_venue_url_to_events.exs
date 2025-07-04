defmodule EventasaurusApp.Repo.Migrations.AddVirtualVenueUrlToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :virtual_venue_url, :string
    end
  end
end
