defmodule EventasaurusDiscovery.Movies.Movie.Slug do
  use EctoAutoslugField.Slug, from: [:title, :tmdb_id], to: :slug

  # Slug format: title-tmdb_id (e.g., "home-alone-771")
  # TMDB ID ensures uniqueness even when titles are the same (e.g., two movies named "Brother")
  def build_slug(sources, _changeset) do
    [title, tmdb_id] = sources

    title_slug =
      title
      |> Slug.slugify()

    "#{title_slug}-#{tmdb_id}"
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
    # Legacy slug preserved for backwards compatibility with old URLs
    # Can be removed after ~6 months (added Dec 2025)
    field(:legacy_slug, :string)
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
