defmodule EventasaurusApp.Repo.Migrations.RemoveLegacyVenueLocationColumns do
  use Ecto.Migration

  def change do
    alter table(:venues) do
      remove :city, :string
      remove :country, :string
      remove :state, :string
    end
  end
end
