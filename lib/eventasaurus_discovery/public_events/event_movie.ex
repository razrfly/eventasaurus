defmodule EventasaurusDiscovery.PublicEvents.EventMovie do
  use Ecto.Schema
  import Ecto.Changeset

  schema "event_movies" do
    field(:metadata, :map, default: %{})

    belongs_to(:event, EventasaurusDiscovery.PublicEvents.PublicEvent)
    belongs_to(:movie, EventasaurusDiscovery.Movies.Movie)

    timestamps()
  end

  @doc false
  def changeset(event_movie, attrs) do
    event_movie
    |> cast(attrs, [:event_id, :movie_id, :metadata])
    |> validate_required([:event_id, :movie_id])
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:movie_id)
    |> unique_constraint([:event_id, :movie_id])
  end
end
