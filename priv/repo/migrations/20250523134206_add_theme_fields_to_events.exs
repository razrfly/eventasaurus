defmodule EventasaurusApp.Repo.Migrations.AddThemeFieldsToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      # Theme field as string in DB, will be Ecto.Enum in schema
      # Values: minimal, cosmic, velocity, retro, celebration, nature, professional
      add :theme, :string, default: "minimal", null: false
      add :theme_customizations, :map, default: %{}, null: false
    end

    # Add index for theme field for performance when filtering by theme
    create index(:events, [:theme])

    # Update any existing events to use the minimal theme (should already be default, but being explicit)
    execute "UPDATE events SET theme = 'minimal' WHERE theme IS NULL"
  end
end
