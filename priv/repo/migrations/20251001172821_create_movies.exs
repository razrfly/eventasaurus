defmodule EventasaurusApp.Repo.Migrations.CreateMovies do
  use Ecto.Migration

  def up do
    create table(:movies) do
      add :tmdb_id, :integer, null: false
      add :title, :string, null: false
      add :original_title, :string
      add :slug, :string, null: false
      add :overview, :text
      add :poster_url, :string
      add :backdrop_url, :string
      add :release_date, :date
      add :runtime, :integer
      add :metadata, :map, default: %{}

      timestamps()
    end

    create unique_index(:movies, [:tmdb_id])
    create unique_index(:movies, [:slug])

    create table(:event_movies) do
      add :event_id, references(:public_events, on_delete: :delete_all), null: false
      add :movie_id, references(:movies, on_delete: :delete_all), null: false
      add :metadata, :map, default: %{}

      timestamps()
    end

    create unique_index(:event_movies, [:event_id, :movie_id])
    create index(:event_movies, [:movie_id])
  end

  def down do
    drop table(:event_movies)
    drop table(:movies)
  end
end
