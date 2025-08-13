defmodule EventasaurusApp.Repo.Migrations.AddPrivacySettingsToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :privacy_settings, :map, default: %{}
    end
  end
end
