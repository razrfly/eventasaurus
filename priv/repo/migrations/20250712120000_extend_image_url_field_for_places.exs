defmodule Eventasaurus.Repo.Migrations.ExtendImageUrlFieldForPlaces do
  use Ecto.Migration

  def up do
    # Change image_url from varchar(255) to text to support longer Google Places photo URLs
    alter table(:poll_options) do
      modify :image_url, :text
    end
  end

  def down do
    # Revert back to varchar(255) - WARNING: This will truncate existing long URLs
    alter table(:poll_options) do
      modify :image_url, :string
    end
  end
end
