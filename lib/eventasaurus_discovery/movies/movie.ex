defmodule EventasaurusDiscovery.Movies.Movie.Slug do
  use EctoAutoslugField.Slug, from: [:title, :tmdb_id], to: :slug

  # Slug format: title-tmdb_id (e.g., "home-alone-771")
  # TMDB ID ensures uniqueness even when titles are the same (e.g., two movies named "Brother")
  #
  # EctoAutoslugField only passes non-nil values from the `from` list, so we need to handle
  # cases where title might be nil (receives [tmdb_id] instead of [title, tmdb_id])
  def build_slug(sources, changeset) do
    {title, tmdb_id} = extract_slug_parts(sources, changeset)

    case {title, tmdb_id} do
      {nil, nil} ->
        # Neither title nor tmdb_id available - cannot generate slug
        nil

      {nil, id} ->
        # Only tmdb_id available - use "movie-{id}" as fallback
        "movie-#{id}"

      {t, nil} ->
        # Only title available - just use slugified title
        Slug.slugify(t)

      {t, id} ->
        # Both available - standard format
        "#{Slug.slugify(t)}-#{id}"
    end
  end

  # Extract title and tmdb_id from sources list, handling EctoAutoslugField's
  # behavior of filtering out nil values.
  #
  # Also handles edge cases where tmdb_id might be passed as a single-element list
  # (e.g., [1280941] instead of 1280941) due to upstream data formatting issues.
  defp extract_slug_parts(sources, changeset) do
    case sources do
      [title, tmdb_id] when is_binary(title) and is_integer(tmdb_id) ->
        {title, tmdb_id}

      [title, tmdb_id] when is_binary(title) ->
        {title, parse_tmdb_id(tmdb_id)}

      [single] when is_integer(single) ->
        # Only tmdb_id was non-nil, try to get title from changeset
        title = Ecto.Changeset.get_field(changeset, :title)
        {title, single}

      [single] when is_binary(single) ->
        # Only title was non-nil, try to get tmdb_id from changeset
        tmdb_id = Ecto.Changeset.get_field(changeset, :tmdb_id)
        {single, parse_tmdb_id(tmdb_id)}

      [] ->
        # Both were nil, try to get from changeset
        title = Ecto.Changeset.get_field(changeset, :title)
        tmdb_id = Ecto.Changeset.get_field(changeset, :tmdb_id)
        {title, parse_tmdb_id(tmdb_id)}

      _ ->
        # Fallback: try to get from changeset for any unmatched pattern
        title = Ecto.Changeset.get_field(changeset, :title)
        tmdb_id = Ecto.Changeset.get_field(changeset, :tmdb_id)
        {title, parse_tmdb_id(tmdb_id)}
    end
  end

  # Parse tmdb_id from various formats, with defensive handling for lists
  defp parse_tmdb_id(id) when is_integer(id), do: id

  defp parse_tmdb_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_tmdb_id([id]) when is_integer(id), do: id

  defp parse_tmdb_id([id]) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_tmdb_id(_), do: nil
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

    # External IDs from different providers
    field(:imdb_id, :string)

    # Provider tracking - which service successfully matched this movie
    # Values: "tmdb", "omdb", "imdb", "now_playing"
    field(:matched_by_provider, :string)
    field(:matched_at, :utc_datetime)

    # Virtual field for convenient access to TMDb metadata nested in metadata map
    field(:tmdb_metadata, :map, virtual: true)

    many_to_many(:public_events, EventasaurusDiscovery.PublicEvents.PublicEvent,
      join_through: EventasaurusDiscovery.PublicEvents.EventMovie,
      on_replace: :delete
    )

    # PostHog popularity tracking (synced by PostHogPopularitySyncWorker)
    field(:posthog_view_count, :integer, default: 0)
    field(:posthog_synced_at, :utc_datetime)

    timestamps()
  end

  @doc false
  def changeset(movie, attrs) do
    # Normalize attrs before cast to ensure tmdb_id is an integer
    normalized_attrs = normalize_attrs(attrs)

    movie
    |> cast(normalized_attrs, [
      :tmdb_id,
      :title,
      :original_title,
      :overview,
      :poster_url,
      :backdrop_url,
      :release_date,
      :runtime,
      :metadata,
      :imdb_id,
      :matched_by_provider,
      :matched_at
    ])
    |> validate_required([:tmdb_id, :title])
    |> sanitize_utf8()
    |> Slug.maybe_generate_slug()
    |> unique_constraint(:tmdb_id)
    |> unique_constraint(:slug)
    |> unique_constraint(:imdb_id)
  end

  # Normalize attrs to handle edge cases like list-wrapped tmdb_id
  defp normalize_attrs(attrs) when is_map(attrs) do
    case Map.get(attrs, :tmdb_id) || Map.get(attrs, "tmdb_id") do
      [id] when is_integer(id) ->
        # Unwrap single-element list
        update_tmdb_id(attrs, id)

      [id] when is_binary(id) ->
        # Unwrap and parse string, or leave as-is if invalid (let cast/validation handle it)
        case Integer.parse(id) do
          {int, ""} -> update_tmdb_id(attrs, int)
          _ -> attrs
        end

      id when is_binary(id) ->
        # Parse string to integer, or leave as-is if invalid
        case Integer.parse(id) do
          {int, ""} -> update_tmdb_id(attrs, int)
          _ -> attrs
        end

      _ ->
        # Already an integer or nil, no change needed
        attrs
    end
  end

  defp normalize_attrs(attrs), do: attrs

  defp update_tmdb_id(attrs, id) do
    cond do
      Map.has_key?(attrs, :tmdb_id) -> Map.put(attrs, :tmdb_id, id)
      Map.has_key?(attrs, "tmdb_id") -> Map.put(attrs, "tmdb_id", id)
      true -> attrs
    end
  end

  defp sanitize_utf8(changeset) do
    changeset
    |> update_change(:title, &EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8/1)
    |> update_change(:original_title, &EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8/1)
    |> update_change(:overview, &EventasaurusDiscovery.Utils.UTF8.ensure_valid_utf8/1)
  end
end
