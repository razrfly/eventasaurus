defmodule EventasaurusWeb.Services.MovieDataAdapter do
  @moduledoc """
  Unified movie data adapter that handles movie data transformations 
  for both polling and activity systems.
  
  This service normalizes movie data from multiple sources (TMDB API, curated data)
  and provides consistent formatting for different storage patterns.
  """

  alias EventasaurusWeb.Services.MovieConfig
  require Logger

  @doc """
  Normalizes movie data from various sources into a consistent format.
  
  Handles data from:
  - TMDB API responses (TmdbService.get_popular_movies/1)
  - Curated data (DevSeeds.CuratedData.movies/0)
  - Manual input
  
  Returns a standardized movie data map with all required fields.
  """
  def normalize_movie_data(movie_data, source \\ :auto) do
    source = detect_source(movie_data, source)
    
    case source do
      :tmdb -> normalize_tmdb_movie(movie_data)
      :curated -> normalize_curated_movie(movie_data)
      :manual -> normalize_manual_movie(movie_data)
      _ -> 
        Logger.warning("Unknown movie data source for: #{inspect(movie_data)}")
        normalize_fallback_movie(movie_data)
    end
    |> ensure_image_url()
    |> ensure_required_fields()
  end

  @doc """
  Builds attributes for creating a PollOption with movie data.
  """
  def build_poll_option_attrs(movie_data, poll_id, user_id) do
    normalized = normalize_movie_data(movie_data)
    
    %{
      poll_id: poll_id,
      title: normalized.title,
      description: build_poll_option_description(normalized),
      suggested_by_id: user_id,
      image_url: normalized.image_url,
      metadata: build_poll_metadata(normalized)
    }
  end

  @doc """
  Builds metadata for EventActivity with movie data.
  """
  def build_activity_metadata(movie_data) do
    normalized = normalize_movie_data(movie_data)
    
    %{
      "title" => normalized.title,
      "overview" => normalized.overview,
      "tmdb_id" => normalized.tmdb_id,
      "year" => normalized.year,
      "genre" => normalized.genre,
      "rating" => normalized.rating,
      "poster_path" => normalized.poster_path,
      "poster_url" => normalized.image_url,  # UI expects "poster_url"
      "api_source" => normalized.source,
      "seeded_at" => DateTime.utc_now()
    }
  end

  @doc """
  Ensures movie data has a proper image URL.
  """
  def ensure_image_url(movie_data) when is_map(movie_data) do
    case Map.get(movie_data, :image_url) do
      url when is_binary(url) -> movie_data
      _ ->
        case Map.get(movie_data, :poster_path) do
          poster_path when is_binary(poster_path) ->
            Map.put(movie_data, :image_url, MovieConfig.build_image_url(poster_path, "w500"))
          _ ->
            Map.put(movie_data, :image_url, nil)
        end
    end
  end

  @doc """
  Validates that movie data is compatible between polling and activity systems.
  """
  def validate_compatibility(poll_movie_metadata, activity_movie_metadata) do
    poll_keys = MapSet.new(Map.keys(poll_movie_metadata))
    activity_keys = MapSet.new(Map.keys(activity_movie_metadata))
    
    common_keys = MapSet.intersection(poll_keys, activity_keys)
    
    incompatible_fields = 
      common_keys
      |> Enum.filter(fn key ->
        poll_value = Map.get(poll_movie_metadata, key)
        activity_value = Map.get(activity_movie_metadata, key)
        poll_value != activity_value
      end)
    
    if Enum.empty?(incompatible_fields) do
      :ok
    else
      {:error, {:incompatible_fields, incompatible_fields}}
    end
  end

  @doc """
  Converts a poll option with movie metadata to activity metadata format.
  """
  def poll_to_activity_format(poll_option) do
    movie_data = %{
      title: poll_option.title,
      tmdb_id: get_in(poll_option.metadata, ["tmdb_id"]),
      poster_path: get_in(poll_option.metadata, ["poster_path"]),
      year: get_in(poll_option.metadata, ["year"]),
      genre: get_in(poll_option.metadata, ["genre"]),
      rating: get_in(poll_option.metadata, ["rating"]),
      overview: poll_option.description,
      image_url: poll_option.image_url,
      source: get_in(poll_option.metadata, ["api_source"]) || "poll_option"
    }
    
    build_activity_metadata(movie_data)
  end

  # Private functions

  defp detect_source(movie_data, :auto) do
    cond do
      # TMDB API data has specific structure
      Map.has_key?(movie_data, :vote_average) || 
      Map.has_key?(movie_data, :popularity) ||
      Map.has_key?(movie_data, "vote_average") -> :tmdb
      
      # Curated data has specific structure
      Map.has_key?(movie_data, :description) && 
      Map.has_key?(movie_data, :year) -> :curated
      
      # Manual or unknown
      true -> :manual
    end
  end
  defp detect_source(_movie_data, source), do: source

  defp normalize_tmdb_movie(movie_data) do
    %{
      tmdb_id: movie_data[:tmdb_id] || movie_data["id"],
      title: movie_data[:title] || movie_data["title"],
      overview: movie_data[:overview] || movie_data["overview"],
      year: extract_year_from_release_date(movie_data[:release_date] || movie_data["release_date"]),
      genre: extract_genre_from_ids(movie_data[:genre_ids] || movie_data["genre_ids"]),
      rating: movie_data[:vote_average] || movie_data["vote_average"],
      poster_path: movie_data[:poster_path] || movie_data["poster_path"],
      backdrop_path: movie_data[:backdrop_path] || movie_data["backdrop_path"],
      source: "tmdb"
    }
  end

  defp normalize_curated_movie(movie_data) do
    %{
      tmdb_id: movie_data[:tmdb_id] || movie_data["tmdb_id"],
      title: movie_data[:title] || movie_data["title"],
      overview: movie_data[:description] || movie_data["description"],
      year: movie_data[:year] || movie_data["year"],
      genre: movie_data[:genre] || movie_data["genre"],
      rating: movie_data[:rating] || movie_data["rating"],
      poster_path: movie_data[:poster_path] || movie_data["poster_path"],
      backdrop_path: movie_data[:backdrop_path] || movie_data["backdrop_path"],
      source: "curated"
    }
  end

  defp normalize_manual_movie(movie_data) do
    %{
      tmdb_id: movie_data[:tmdb_id] || movie_data[:id] || movie_data["tmdb_id"] || movie_data["id"],
      title: movie_data[:title] || movie_data["title"],
      overview: movie_data[:overview] || movie_data[:description] || movie_data["overview"] || movie_data["description"],
      year: movie_data[:year] || movie_data["year"] || extract_year_from_release_date(movie_data[:release_date] || movie_data["release_date"]),
      genre: movie_data[:genre] || movie_data["genre"] || "General",
      rating: movie_data[:rating] || movie_data[:vote_average] || movie_data["rating"] || movie_data["vote_average"],
      poster_path: movie_data[:poster_path] || movie_data["poster_path"],
      backdrop_path: movie_data[:backdrop_path] || movie_data["backdrop_path"],
      source: "manual"
    }
  end

  defp normalize_fallback_movie(movie_data) do
    %{
      tmdb_id: nil,
      title: to_string(movie_data[:title] || movie_data["title"] || "Unknown Movie"),
      overview: to_string(movie_data[:overview] || movie_data[:description] || movie_data["overview"] || movie_data["description"] || "No description available"),
      year: movie_data[:year] || movie_data["year"],
      genre: movie_data[:genre] || movie_data["genre"] || "General",
      rating: movie_data[:rating] || movie_data["rating"],
      poster_path: nil,
      backdrop_path: nil,
      source: "fallback"
    }
  end

  defp ensure_required_fields(movie_data) do
    movie_data
    |> Map.put_new(:title, "Unknown Movie")
    |> Map.put_new(:overview, "No description available")
    |> Map.put_new(:genre, "General")
    |> Map.put_new(:year, "Unknown")
    |> Map.put_new(:source, "unknown")
  end

  defp extract_year_from_release_date(nil), do: nil
  defp extract_year_from_release_date(""), do: nil
  defp extract_year_from_release_date(date_string) when is_binary(date_string) do
    case String.split(date_string, "-") do
      [year | _] when byte_size(year) == 4 -> year
      _ -> nil
    end
  end
  defp extract_year_from_release_date(_), do: nil

  defp extract_genre_from_ids([]), do: "General"
  defp extract_genre_from_ids([genre_id | _]) when is_integer(genre_id) do
    # Basic genre mapping for common TMDB genre IDs
    case genre_id do
      28 -> "Action"
      12 -> "Adventure" 
      16 -> "Animation"
      35 -> "Comedy"
      80 -> "Crime"
      18 -> "Drama"
      14 -> "Fantasy"
      27 -> "Horror"
      9648 -> "Mystery"
      10749 -> "Romance"
      878 -> "Sci-Fi"
      53 -> "Thriller"
      _ -> "General"
    end
  end
  defp extract_genre_from_ids(_), do: "General"

  defp build_poll_option_description(normalized) do
    year_text = if normalized.year, do: " (#{normalized.year})", else: ""
    genre_text = if normalized.genre, do: ", #{normalized.genre}", else: ""
    rating_text = if normalized.rating, do: " • #{normalized.rating}⭐", else: ""
    
    "#{normalized.overview}#{year_text}#{genre_text}#{rating_text}"
  end

  defp build_poll_metadata(normalized) do
    %{
      "tmdb_id" => normalized.tmdb_id,
      "year" => normalized.year,
      "genre" => normalized.genre,
      "rating" => normalized.rating,
      "poster_path" => normalized.poster_path,
      "backdrop_path" => normalized.backdrop_path,
      "is_movie" => true,
      "api_source" => normalized.source
    }
  end
end