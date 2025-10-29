defmodule EventasaurusApp.Repo.Migrations.AddAlternateNamesToCities do
  use Ecto.Migration

  def change do
    alter table(:cities) do
      add :alternate_names, {:array, :string}, default: []
    end

    # GIN index for fast array searches
    # Allows efficient queries like: WHERE 'Warszawa' = ANY(alternate_names)
    create index(:cities, [:alternate_names],
      using: :gin,
      name: :cities_alternate_names_gin_index
    )
  end
end
