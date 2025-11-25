defmodule EventasaurusDiscovery.Movies.Movie.Slug do
  use EctoAutoslugField.Slug, from: :title, to: :slug

  def build_slug(sources, changeset) do
    # Get the default slug from sources
    slug = super(sources, changeset)

    # Add randomness to ensure uniqueness (same pattern as PublicEvent)
    "#{slug}-#{random_suffix()}"
  end

  defp random_suffix do
    :rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")
  end
end

defmodule EventasaurusDiscovery.Movies.Movie do
  use Ecto.Schema
  import Ecto.Changeset
  alias EventasaurusDiscovery.Movies.Movie.Slug

  schema "movies" do
    field(:tmdb_id, :integer)
    field(:title, :string)
    field(:original_title, :string)
    field(:slug, Slug.Type)
    field(:overview, :string)
    field(:poster_url, :string)
    field(:backdrop_url, :string)
    field(:release_date, :date)
    field(:runtime, :integer)
    field(:metadata, :map, default: %{})

    # Virtual field for convenient access to TMDb metadata nested in metadata map
    field(:tmdb_metadata, :map, virtual: true)

    many_to_many(:public_events, EventasaurusDiscovery.PublicEvents.PublicEvent,
      join_through: EventasaurusDiscovery.PublicEvents.EventMovie,
      on_replace: :delete
    )

    timestamps()
  end

  @doc false
  def changeset(movie, attrs) do
    movie
    |> cast(attrs, [
      :tmdb_id,
      :title,
      :original_title,
      :overview,
      :poster_url,
      :backdrop_url,
      :release_date,
      :runtime,
      :metadata
    ])
    |> validate_required([:tmdb_id, :title])
    |> sanitize_utf8()
    |> Slug.maybe_generate_slug()
    |> unique_constraint(:tmdb_id)
    |> unique_constraint(:slug)
  end

  defp sanitize_utf8(changeset) do
    changeset
    |> update_change(:title, &EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8/1)
    |> update_change(:original_title, &EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8/1)
    |> update_change(:overview, &EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8/1)
  end
end
