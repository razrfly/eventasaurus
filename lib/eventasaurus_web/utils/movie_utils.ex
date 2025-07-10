defmodule EventasaurusWeb.Utils.MovieUtils do
  @moduledoc """
  Provides standardized utility functions for movie data processing and normalization.
  Centralizes common operations performed on TMDB movie data to eliminate duplication.
  """

  require Logger
  alias EventasaurusWeb.Live.Components.RichDataDisplayComponent

  @doc """
  Extract image URL from movie data, supporting both string and atom keys.

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

      # Then try to extract from external_data poster images
      poll_option.external_data && is_map(poll_option.external_data) ->
        case get_in(poll_option.external_data, ["media", "images", "posters"]) do
          [first_poster | _] when is_map(first_poster) ->
            case first_poster["file_path"] do
              path when is_binary(path) -> "https://image.tmdb.org/t/p/w500#{path}"
              _ -> get_image_url(poll_option.external_data)
            end
          _ -> get_image_url(poll_option.external_data)
        end

      true ->
        nil
    end
  end

    def get_image_url(movie_data) when is_map(movie_data) do
    cond do
      # Try atom keys first - nested format
      is_map(movie_data) && is_map(movie_data[:poster_path]) && movie_data[:poster_path][:url] ->
        movie_data[:poster_path][:url]
      # Try string keys - nested format
      is_map(movie_data) && is_map(movie_data["poster_path"]) && movie_data["poster_path"]["url"] ->
        movie_data["poster_path"]["url"]
      # Try direct atom path
      is_map(movie_data) && is_binary(movie_data[:poster_path]) ->
        "https://image.tmdb.org/t/p/w500#{movie_data[:poster_path]}"
      # Try direct string path
      is_map(movie_data) && is_binary(movie_data["poster_path"]) ->
        "https://image.tmdb.org/t/p/w500#{movie_data["poster_path"]}"
      # Try images array format (from rich data)
      is_map(movie_data) && is_list(movie_data[:images]) && length(movie_data[:images]) > 0 ->
        first_image = List.first(movie_data[:images])
        cond do
          is_map(first_image) && first_image[:url] -> first_image[:url]
          is_map(first_image) && first_image["url"] -> first_image["url"]
          is_map(first_image) && Map.get(first_image, :url) -> Map.get(first_image, :url)
          true -> nil
        end
      # Try string key images array format
      is_map(movie_data) && is_list(movie_data["images"]) && length(movie_data["images"]) > 0 ->
        first_image = List.first(movie_data["images"])
        cond do
          is_map(first_image) && first_image[:url] -> first_image[:url]
          is_map(first_image) && first_image["url"] -> first_image["url"]
          is_map(first_image) && Map.get(first_image, :url) -> Map.get(first_image, :url)
          true -> nil
        end
      # Fallback to nil if no image found
      true -> nil
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
    release_date = movie_data[:release_date] ||
                   movie_data["release_date"] ||
                   get_in(movie_data, [:metadata, :release_date]) ||
                   get_in(movie_data, [:metadata, "release_date"]) ||
                   get_in(movie_data, ["metadata", "release_date"])

    case release_date do
      date_string when is_binary(date_string) ->
        case String.split(date_string, "-") do
          [year_str | _] ->
            case Integer.parse(year_str) do
              {year, _} -> year
              _ -> nil
            end
          _ -> nil
        end
      _ -> nil
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
    crew = movie_data[:crew] ||
           movie_data["crew"] ||
           get_in(movie_data, [:metadata, :crew]) ||
           get_in(movie_data, ["metadata", "crew"]) ||
           []

    case crew do
      crew_list when is_list(crew_list) ->
        director = Enum.find(crew_list, fn member ->
          (member[:job] == "Director" || member["job"] == "Director")
        end)

        case director do
          %{name: name} -> name
          %{"name" => name} -> name
          _ -> nil
        end
      _ -> nil
    end
  rescue
    _ -> nil
  end

  def get_director(_), do: nil

  @doc """
  Extract and format genre information.

  ## Examples

      iex> MovieUtils.get_genres(%{genres: [%{name: "Action"}, %{name: "Adventure"}]})
      "Action, Adventure"
  """
  def get_genres(movie_data) when is_map(movie_data) do
    genres = movie_data[:genres] ||
             movie_data["genres"] ||
             get_in(movie_data, [:metadata, :genres]) ||
             get_in(movie_data, ["metadata", "genres"]) ||
             []

    genres
    |> Enum.map(fn genre ->
      cond do
        is_map(genre) -> genre[:name] || genre["name"]
        is_binary(genre) -> genre
        true -> nil
      end
    end)
    |> Enum.filter(&(&1))
    |> Enum.join(", ")
  rescue
    _ -> ""
  end

  def get_genres(_), do: ""

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
      genres && genres != "" && genres
    ]
    |> Enum.filter(&(&1))
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

    # Add genre if available
    details = if genre, do: ["#{genre}"] ++ details, else: details

    # Combine base description with details
    case details do
      [] -> base_description
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
  """
  def get_poster_url(movie_data, size \\ "w500")

  def get_poster_url(movie_data, size) when is_map(movie_data) do
    poster_path = movie_data[:poster_path] ||
                  movie_data["poster_path"] ||
                  get_in(movie_data, [:metadata, :poster_path]) ||
                  get_in(movie_data, ["metadata", "poster_path"])

    case poster_path do
      path when is_binary(path) and path != "" ->
        RichDataDisplayComponent.tmdb_image_url(path, size)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  def get_poster_url(_, _), do: nil

  @doc """
  Extract backdrop URL using TMDB image service.
  """
  def get_backdrop_url(movie_data, size \\ "w1280")

  def get_backdrop_url(movie_data, size) when is_map(movie_data) do
    backdrop_path = movie_data[:backdrop_path] ||
                    movie_data["backdrop_path"] ||
                    get_in(movie_data, [:metadata, :backdrop_path]) ||
                    get_in(movie_data, ["metadata", "backdrop_path"])

    case backdrop_path do
      path when is_binary(path) and path != "" ->
        RichDataDisplayComponent.tmdb_image_url(path, size)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  def get_backdrop_url(_, _), do: nil

  # Private helper functions

  defp normalize_value(value) when is_map(value), do: normalize_movie_data(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value
end
