defmodule EventasaurusWeb.Services.MovieDataService do
  @moduledoc """
  Shared service for preparing movie data consistently across all interfaces.
  Ensures admin and public interfaces save identical data structures.
  """

    alias EventasaurusWeb.Utils.MovieUtils

  @doc """
  Prepares movie option data in a consistent format for both admin and public interfaces.
  Uses the existing MovieUtils functions to ensure identical data structure.
  """
  def prepare_movie_option_data(movie_id, rich_data) do
    # Extract image URL directly from TMDB data for better reliability
    image_url = extract_image_url(rich_data)

    # Use existing MovieUtils functions that were already working in the public interface
    year = MovieUtils.get_release_year(rich_data)
    director = MovieUtils.get_director(rich_data)
    genre = MovieUtils.get_genres(rich_data)

    # Extract base description from TMDB data (usually in overview field)
    # Handle both string and atom keys and multiple possible locations
    base_description = cond do
      # Check overview field (most common for TMDB)
      is_map(rich_data) and Map.has_key?(rich_data, "overview") -> rich_data["overview"]
      is_map(rich_data) and Map.has_key?(rich_data, :overview) -> rich_data[:overview]
      # Check metadata.overview
      is_map(rich_data) and get_in(rich_data, ["metadata", "overview"]) -> get_in(rich_data, ["metadata", "overview"])
      is_map(rich_data) and get_in(rich_data, [:metadata, "overview"]) -> get_in(rich_data, [:metadata, "overview"])
      is_map(rich_data) and get_in(rich_data, [:metadata, :overview]) -> get_in(rich_data, [:metadata, :overview])
      # Fallback to description field
      is_map(rich_data) and Map.has_key?(rich_data, "description") -> rich_data["description"]
      is_map(rich_data) and Map.has_key?(rich_data, :description) -> rich_data[:description]
      true -> ""
    end

    enhanced_description = MovieUtils.build_enhanced_description(
      base_description,
      year,
      director,
      genre
    )

    # Handle both string and atom keys for title
    title = cond do
      is_map(rich_data) and Map.has_key?(rich_data, "title") -> rich_data["title"]
      is_map(rich_data) and Map.has_key?(rich_data, :title) -> rich_data[:title]
      true -> ""
    end

    %{
      "title" => title,
      "description" => enhanced_description,
      "external_id" => to_string(movie_id),
      "external_data" => rich_data,
      "image_url" => image_url
    }
  end

  # Extract image URL from TMDB rich data - handles multiple data structures
  defp extract_image_url(rich_data) do
    require Logger
    Logger.debug("extract_image_url called with rich_data keys: #{inspect(Map.keys(rich_data))}")

    cond do
      # Check TMDB media.images.posters structure with atom keys (most common from admin interface)
      is_map(rich_data) and Map.has_key?(rich_data, :media) and is_map(rich_data[:media]) and
      Map.has_key?(rich_data[:media], :images) and is_map(rich_data[:media][:images]) and
      Map.has_key?(rich_data[:media][:images], :posters) and is_list(rich_data[:media][:images][:posters]) and
      length(rich_data[:media][:images][:posters]) > 0 ->
        first_poster = List.first(rich_data[:media][:images][:posters])
        Logger.debug("Found atom key poster structure, first_poster: #{inspect(first_poster)}")
        if is_map(first_poster) and Map.has_key?(first_poster, :file_path) and first_poster[:file_path] do
          result = "https://image.tmdb.org/t/p/w500#{first_poster[:file_path]}"
          Logger.debug("Constructed image URL from atom keys: #{result}")
          result
        else
          Logger.debug("First poster missing file_path (atom key)")
          nil
        end

      # Check TMDB media.images.posters structure with string keys (fallback)
      is_map(rich_data) and Map.has_key?(rich_data, "media") and is_map(rich_data["media"]) and
      Map.has_key?(rich_data["media"], "images") and is_map(rich_data["media"]["images"]) and
      Map.has_key?(rich_data["media"]["images"], "posters") and is_list(rich_data["media"]["images"]["posters"]) and
      length(rich_data["media"]["images"]["posters"]) > 0 ->
        first_poster = List.first(rich_data["media"]["images"]["posters"])
        Logger.debug("Found string key poster structure, first_poster: #{inspect(first_poster)}")
        if is_map(first_poster) and Map.has_key?(first_poster, "file_path") and first_poster["file_path"] do
          result = "https://image.tmdb.org/t/p/w500#{first_poster["file_path"]}"
          Logger.debug("Constructed image URL from string keys: #{result}")
          result
        else
          Logger.debug("First poster missing file_path (string key)")
          nil
        end

      # Check if rich_data is a map with string keys
      is_map(rich_data) and Map.has_key?(rich_data, "poster_path") and rich_data["poster_path"] ->
        result = "https://image.tmdb.org/t/p/w500#{rich_data["poster_path"]}"
        Logger.debug("Direct poster_path (string key): #{result}")
        result

      # Check if rich_data is a map with atom keys
      is_map(rich_data) and Map.has_key?(rich_data, :poster_path) and rich_data[:poster_path] ->
        result = "https://image.tmdb.org/t/p/w500#{rich_data[:poster_path]}"
        Logger.debug("Direct poster_path (atom key): #{result}")
        result

      # Check nested metadata structure with string keys
      is_map(rich_data) and Map.has_key?(rich_data, "metadata") and is_map(rich_data["metadata"]) ->
        metadata = rich_data["metadata"]
        if metadata["poster_path"] do
          result = "https://image.tmdb.org/t/p/w500#{metadata["poster_path"]}"
          Logger.debug("Metadata poster_path (string key): #{result}")
          result
        else
          Logger.debug("Metadata missing poster_path (string key)")
          nil
        end

      # Check nested metadata with atom keys
      is_map(rich_data) and Map.has_key?(rich_data, :metadata) and is_map(rich_data[:metadata]) ->
        metadata = rich_data[:metadata]
        if metadata[:poster_path] do
          result = "https://image.tmdb.org/t/p/w500#{metadata[:poster_path]}"
          Logger.debug("Metadata poster_path (atom key): #{result}")
          result
        else
          Logger.debug("Metadata missing poster_path (atom key)")
          nil
        end

      true ->
        Logger.debug("No image URL found in rich_data")
        nil
    end
  end
end
