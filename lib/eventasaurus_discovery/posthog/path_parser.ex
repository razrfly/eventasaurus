defmodule EventasaurusDiscovery.PostHog.PathParser do
  @moduledoc """
  Parses PostHog pathname properties to extract event/movie/venue identifiers.

  Used by PostHogPopularitySyncWorker to map pageview data to database records.

  ## Examples

      iex> PathParser.parse("/e/jazz-concert-krakow")
      {:event, "jazz-concert-krakow"}

      iex> PathParser.parse("/c/krakow/e/jazz-concert")
      {:event, "jazz-concert"}

      iex> PathParser.parse("/c/krakow")
      :skip

  """

  @doc """
  Parse pathname to extract entity type and slug.

  Returns:
  - `{:event, slug}` for event detail pages
  - `{:movie, slug}` for movie detail pages (future)
  - `{:venue, slug}` for venue detail pages (future)
  - `{:performer, slug}` for performer detail pages (future)
  - `:skip` for listing pages or unrecognized paths
  """
  @spec parse(String.t()) :: {:event | :movie | :venue | :performer, String.t()} | :skip
  def parse(pathname) when is_binary(pathname) do
    cond do
      # Direct event page: /e/{slug}
      match = Regex.run(~r"^/e/([^/]+)$", pathname) ->
        {:event, Enum.at(match, 1)}

      # City-scoped event page: /c/{city}/e/{slug}
      match = Regex.run(~r"^/c/[^/]+/e/([^/]+)$", pathname) ->
        {:event, Enum.at(match, 1)}

      # Direct movie page: /m/{slug} (future)
      match = Regex.run(~r"^/m/([^/]+)$", pathname) ->
        {:movie, Enum.at(match, 1)}

      # City-scoped movie page: /c/{city}/m/{slug} (future)
      match = Regex.run(~r"^/c/[^/]+/m/([^/]+)$", pathname) ->
        {:movie, Enum.at(match, 1)}

      # Venue page: /v/{slug} (future)
      match = Regex.run(~r"^/v/([^/]+)$", pathname) ->
        {:venue, Enum.at(match, 1)}

      # Performer page: /p/{slug} (future)
      match = Regex.run(~r"^/p/([^/]+)$", pathname) ->
        {:performer, Enum.at(match, 1)}

      true ->
        :skip
    end
  end

  def parse(_), do: :skip

  @doc """
  Filters a list of {path, count} tuples to only include event paths.

  Returns a list of {slug, count} tuples for events only.
  """
  @spec filter_events([{String.t(), integer()}]) :: [{String.t(), integer()}]
  def filter_events(path_counts), do: filter_by_type(path_counts, :event)

  @doc """
  Filters a list of {path, count} tuples to only include movie paths.

  Returns a list of {slug, count} tuples for movies only.
  """
  @spec filter_movies([{String.t(), integer()}]) :: [{String.t(), integer()}]
  def filter_movies(path_counts), do: filter_by_type(path_counts, :movie)

  @doc """
  Filters a list of {path, count} tuples to only include venue paths.

  Returns a list of {slug, count} tuples for venues only.
  """
  @spec filter_venues([{String.t(), integer()}]) :: [{String.t(), integer()}]
  def filter_venues(path_counts), do: filter_by_type(path_counts, :venue)

  @doc """
  Filters a list of {path, count} tuples to only include performer paths.

  Returns a list of {slug, count} tuples for performers only.
  """
  @spec filter_performers([{String.t(), integer()}]) :: [{String.t(), integer()}]
  def filter_performers(path_counts), do: filter_by_type(path_counts, :performer)

  # Generic filter by entity type
  defp filter_by_type(path_counts, entity_type) when is_list(path_counts) do
    path_counts
    |> Enum.map(fn {path, count} -> {parse(path), count} end)
    |> Enum.filter(fn
      {{^entity_type, _slug}, _count} -> true
      _ -> false
    end)
    |> Enum.map(fn {{^entity_type, slug}, count} -> {slug, count} end)
  end

  @doc """
  Aggregates view counts by slug, summing counts for duplicate slugs.

  This handles cases where the same event is viewed via different URL patterns
  (e.g., /e/slug and /c/city/e/slug).
  """
  @spec aggregate_by_slug([{String.t(), integer()}]) :: %{String.t() => integer()}
  def aggregate_by_slug(slug_counts) when is_list(slug_counts) do
    slug_counts
    |> Enum.group_by(fn {slug, _count} -> slug end)
    |> Enum.map(fn {slug, entries} ->
      total_count = entries |> Enum.map(fn {_slug, count} -> count end) |> Enum.sum()
      {slug, total_count}
    end)
    |> Map.new()
  end
end
