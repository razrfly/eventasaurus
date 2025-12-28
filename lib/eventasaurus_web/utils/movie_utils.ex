defmodule EventasaurusWeb.Utils.MovieUtils do
  @moduledoc """
  Provides standardized utility functions for movie data processing and normalization.
  Centralizes common operations performed on TMDB movie data to eliminate duplication.
  """

  require Logger
  alias EventasaurusApp.Images.MovieImageResolver
  alias Eventasaurus.Integrations.Cinegraph

  @doc """
  Extract image URL from movie data, supporting both string and atom keys.

  Uses MovieImageResolver to check cache first (via tmdb_id lookup),
  falling back to raw TMDB URL if not cached.

  ## Examples

      iex> MovieUtils.get_image_url(%{poster_path: %{url: "https://example.com/poster.jpg"}})
      "https://example.com/poster.jpg"

      iex> MovieUtils.get_image_url(%{"poster_path" => "/abc123.jpg"})
      "https://image.tmdb.org/t/p/w500/abc123.jpg"
  """
  def get_image_url(%{__struct__: EventasaurusApp.Events.PollOption} = poll_option) do
    # Handle PollOption structs specifically
    cond do
      # First, try the direct image_url field
      poll_option.image_url && poll_option.image_url != "" ->
        poll_option.image_url

      # Then try to extract from external_data using MovieImageResolver
      poll_option.external_data && is_map(poll_option.external_data) ->
        MovieImageResolver.get_poster_url(poll_option.external_data)

      true ->
        nil
    end
  end

  def get_image_url(movie_data) when is_map(movie_data) do
    # Check for pre-existing URL formats first (these are already resolved URLs)
    cond do
      # Try atom keys first - nested format with pre-resolved URL
      is_map(movie_data[:poster_path]) && movie_data[:poster_path][:url] ->
        movie_data[:poster_path][:url]

      # Try string keys - nested format with pre-resolved URL
      is_map(movie_data["poster_path"]) && movie_data["poster_path"]["url"] ->
        movie_data["poster_path"]["url"]

      # Try images array format (from rich data) with pre-resolved URLs
      is_list(movie_data[:images]) && length(movie_data[:images]) > 0 ->
        first_image = List.first(movie_data[:images])

        cond do
          is_map(first_image) && first_image[:url] -> first_image[:url]
          is_map(first_image) && first_image["url"] -> first_image["url"]
          is_map(first_image) && Map.get(first_image, :url) -> Map.get(first_image, :url)
          true -> MovieImageResolver.get_poster_url(movie_data)
        end

      # Try string key images array format with pre-resolved URLs
      is_list(movie_data["images"]) && length(movie_data["images"]) > 0 ->
        first_image = List.first(movie_data["images"])

        cond do
          is_map(first_image) && first_image[:url] -> first_image[:url]
          is_map(first_image) && first_image["url"] -> first_image["url"]
          is_map(first_image) && Map.get(first_image, :url) -> Map.get(first_image, :url)
          true -> MovieImageResolver.get_poster_url(movie_data)
        end

      # Default: use MovieImageResolver which handles TMDB paths with cache
      true ->
        MovieImageResolver.get_poster_url(movie_data)
    end
  rescue
    _ -> nil
  end

  def get_image_url(_), do: nil

  @doc """
  Extract release year from movie data.

  ## Examples

      iex> MovieUtils.get_release_year(%{release_date: "2023-05-15"})
      2023

      iex> MovieUtils.get_release_year(%{"metadata" => %{"release_date" => "2023-05-15"}})
      2023
  """
  def get_release_year(movie_data) when is_map(movie_data) do
    # Primary: Look in metadata.release_date (admin interface saves it here)
    release_date =
      get_in(movie_data, ["metadata", "release_date"]) ||
        movie_data["release_date"] ||
        movie_data[:release_date] ||
        get_in(movie_data, [:metadata, :release_date]) ||
        get_in(movie_data, [:metadata, "release_date"]) ||
        get_in(movie_data, ["metadata", :release_date])

    case release_date do
      date_string when is_binary(date_string) ->
        case String.split(date_string, "-") do
          [year_str | _] ->
            case Integer.parse(year_str) do
              {year, _} -> year
              _ -> nil
            end

          _ ->
            nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  def get_release_year(_), do: nil

  @doc """
  Extract title from movie data, supporting both string and atom keys.

  ## Examples

      iex> MovieUtils.get_title(%{title: "Movie Title"})
      "Movie Title"

      iex> MovieUtils.get_title(%{"name" => "TV Show"})
      "TV Show"
  """
  def get_title(movie_data) when is_map(movie_data) do
    movie_data[:title] ||
      movie_data["title"] ||
      movie_data[:name] ||
      movie_data["name"] ||
      get_in(movie_data, [:metadata, :title]) ||
      get_in(movie_data, ["metadata", "title"]) ||
      get_in(movie_data, [:metadata, "original_title"]) ||
      get_in(movie_data, ["metadata", "original_title"]) ||
      "Unknown Title"
  rescue
    _ -> "Unknown Title"
  end

  def get_title(_), do: "Unknown Title"

  @doc """
  Extract director information from crew data.

  ## Examples

      iex> MovieUtils.get_director(%{crew: [%{job: "Director", name: "Christopher Nolan"}]})
      "Christopher Nolan"
  """
  def get_director(movie_data) when is_map(movie_data) do
    # Primary: Look for crew in the root level (admin interface saves it here)
    crew =
      movie_data["crew"] ||
        movie_data[:crew] ||
        get_in(movie_data, ["metadata", "crew"]) ||
        get_in(movie_data, [:metadata, :crew]) ||
        get_in(movie_data, ["metadata", :crew]) ||
        []

    case crew do
      crew_list when is_list(crew_list) ->
        director =
          Enum.find(crew_list, fn member ->
            is_map(member) and (member["job"] == "Director" || member[:job] == "Director")
          end)

        case director do
          %{"name" => name} when is_binary(name) -> name
          %{name: name} when is_binary(name) -> name
          _ -> nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  def get_director(_), do: nil

  @doc """
  Extract and format genre information.

  ## Examples

      iex> MovieUtils.get_genres(%{genres: [%{name: "Action"}, %{name: "Adventure"}]})
      ["Action", "Adventure"]
  """
  def get_genres(movie_data) when is_map(movie_data) do
    # Primary: Look in metadata.genres (admin interface saves it here)
    genres =
      get_in(movie_data, ["metadata", "genres"]) ||
        movie_data["genres"] ||
        movie_data[:genres] ||
        get_in(movie_data, [:metadata, :genres]) ||
        get_in(movie_data, [:metadata, "genres"]) ||
        []

    case genres do
      genres_list when is_list(genres_list) ->
        genres_list
        |> Enum.map(fn genre ->
          cond do
            is_map(genre) -> genre["name"] || genre[:name]
            is_binary(genre) -> genre
            true -> nil
          end
        end)
        |> Enum.filter(&is_binary/1)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  def get_genres(_), do: []

  @doc """
  Convert all movie data to consistent atom keys.

  ## Examples

      iex> MovieUtils.normalize_movie_data(%{"title" => "Movie", "year" => 2023})
      %{title: "Movie", year: 2023}
  """
  def normalize_movie_data(movie_data) when is_map(movie_data) do
    movie_data
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      atom_key = if is_binary(key), do: String.to_atom(key), else: key
      normalized_value = normalize_value(value)
      Map.put(acc, atom_key, normalized_value)
    end)
  rescue
    _ -> movie_data
  end

  def normalize_movie_data(data), do: data

  @doc """
  Build enhanced movie description with metadata.

  ## Examples

      iex> MovieUtils.build_enhanced_description(%{title: "Movie", release_date: "2023-05-15"})
      "2023 • Movie"
  """
  def build_enhanced_description(movie_data) when is_map(movie_data) do
    year = get_release_year(movie_data)
    director = get_director(movie_data)
    genres = get_genres(movie_data)

    [
      year && "#{year}",
      director && "Dir: #{director}",
      is_list(genres) && length(genres) > 0 && Enum.join(genres, ", ")
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" • ")
  rescue
    _ -> ""
  end

  def build_enhanced_description(_), do: ""

  @doc """
  Build enhanced description from individual components.
  """
  def build_enhanced_description(base_description, year, director, genre) do
    details = []

    # Add year if available
    details = if year, do: ["#{year}"] ++ details, else: details

    # Add director if available
    details = if director, do: ["Directed by #{director}"] ++ details, else: details

    # Add genre if available - handle both list and string formats
    details =
      cond do
        is_list(genre) and length(genre) > 0 -> [Enum.join(genre, ", ")] ++ details
        is_binary(genre) and genre != "" -> ["#{genre}"] ++ details
        true -> details
      end

    # Combine base description with details
    case details do
      [] ->
        base_description

      _ ->
        details_line = Enum.join(details, " • ")

        case base_description do
          desc when is_binary(desc) and desc != "" -> "#{details_line}\n\n#{desc}"
          _ -> details_line
        end
    end
  rescue
    _ -> base_description || ""
  end

  @doc """
  Extract poster URL using TMDB image service.

  Uses MovieImageResolver to check cache first (via tmdb_id lookup),
  falling back to raw TMDB URL if not cached.
  """
  def get_poster_url(movie_data) when is_map(movie_data) do
    MovieImageResolver.get_poster_url(movie_data)
  rescue
    _ -> nil
  end

  def get_poster_url(_), do: nil

  @doc """
  Extract backdrop URL using TMDB image service.

  Uses MovieImageResolver to check cache first (via tmdb_id lookup),
  falling back to raw TMDB URL if not cached.
  """
  def get_backdrop_url(movie_data) when is_map(movie_data) do
    MovieImageResolver.get_backdrop_url(movie_data)
  rescue
    _ -> nil
  end

  def get_backdrop_url(_), do: nil

  @doc """
  Extract movie external URLs (TMDB, IMDb) from movie data.

  ## Examples

      iex> MovieUtils.get_movie_urls(%{external_data: %{external_urls: %{tmdb: "https://themoviedb.org/movie/123", imdb: "https://imdb.com/title/tt123"}}})
      %{tmdb: "https://themoviedb.org/movie/123", imdb: "https://imdb.com/title/tt123"}
  """
  def get_movie_urls(%{__struct__: EventasaurusApp.Events.PollOption} = poll_option) do
    # Handle PollOption structs specifically
    cond do
      # First, try to extract from external_data
      poll_option.external_data && is_map(poll_option.external_data) ->
        get_movie_urls(poll_option.external_data)

      true ->
        %{}
    end
  end

  def get_movie_urls(movie_data) when is_map(movie_data) do
    cond do
      # Try external_urls structure (from rich data provider)
      is_map(movie_data) && is_map(movie_data["external_urls"]) ->
        movie_data["external_urls"]

      # Try atom keys
      is_map(movie_data) && is_map(movie_data[:external_urls]) ->
        movie_data[:external_urls]

      # Fallback to empty map
      true ->
        %{}
    end
  rescue
    _ -> %{}
  end

  def get_movie_urls(_), do: %{}

  @doc """
  Extract TMDB ID from movie data, supporting various data structures.

  ## Examples

      iex> MovieUtils.get_tmdb_id(%{metadata: %{tmdb_id: 12345}})
      12345

      iex> MovieUtils.get_tmdb_id(%{"metadata" => %{"tmdb_id" => 12345}})
      12345
  """
  @spec get_tmdb_id(map() | struct() | any()) :: integer() | nil
  def get_tmdb_id(%{__struct__: EventasaurusApp.Events.PollOption} = poll_option) do
    # Handle PollOption structs - check metadata first, then external_data
    cond do
      poll_option.metadata && is_map(poll_option.metadata) ->
        extract_tmdb_id_from_map(poll_option.metadata)

      poll_option.external_data && is_map(poll_option.external_data) ->
        get_tmdb_id(poll_option.external_data)

      true ->
        nil
    end
  end

  def get_tmdb_id(movie_data) when is_map(movie_data) do
    extract_tmdb_id_from_map(movie_data)
  end

  def get_tmdb_id(_), do: nil

  defp extract_tmdb_id_from_map(data) when is_map(data) do
    # Try various locations where tmdb_id might be stored
    # Note: We only look for explicit tmdb_id fields to avoid false positives
    # from generic "id" fields that could be database IDs or other identifiers
    tmdb_id =
      data["tmdb_id"] ||
        data[:tmdb_id] ||
        get_in(data, ["metadata", "tmdb_id"]) ||
        get_in(data, [:metadata, :tmdb_id])

    # Ensure we return a valid integer
    case tmdb_id do
      id when is_integer(id) and id > 0 ->
        id

      id when is_binary(id) ->
        case Integer.parse(id) do
          {parsed_id, _} when parsed_id > 0 -> parsed_id
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp extract_tmdb_id_from_map(_), do: nil

  @doc """
  Get the primary movie URL (prefers Cinegraph, falls back to TMDB/IMDb).

  Cinegraph URLs are preferred when a valid TMDB ID is available, as they
  provide a better user experience on our partner site.

  ## Examples

      iex> MovieUtils.get_primary_movie_url(%{metadata: %{tmdb_id: 12345}})
      "https://cinegraph.org/movies/tmdb/12345"

      iex> MovieUtils.get_primary_movie_url(%{external_data: %{external_urls: %{tmdb: "https://themoviedb.org/movie/123"}}})
      "https://themoviedb.org/movie/123"
  """
  @spec get_primary_movie_url(map() | struct()) :: String.t() | nil
  def get_primary_movie_url(movie_data) do
    # First, try to get Cinegraph URL using tmdb_id
    tmdb_id = get_tmdb_id(movie_data)

    if tmdb_id && Cinegraph.linkable?(%{tmdb_id: tmdb_id}) do
      Cinegraph.movie_url(%{tmdb_id: tmdb_id})
    else
      # Fall back to external URLs
      urls = get_movie_urls(movie_data)

      cond do
        # Fall back to TMDB URL (string or atom key)
        urls["tmdb"] && is_binary(urls["tmdb"]) -> urls["tmdb"]
        urls[:tmdb] && is_binary(urls[:tmdb]) -> urls[:tmdb]
        # Fall back to IMDb URL (string or atom key)
        urls["imdb"] && is_binary(urls["imdb"]) -> urls["imdb"]
        urls[:imdb] && is_binary(urls[:imdb]) -> urls[:imdb]
        # No URL found
        true -> nil
      end
    end
  end

  # Private helper functions

  defp normalize_value(value) when is_map(value), do: normalize_movie_data(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value
end
