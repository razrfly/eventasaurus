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
    # Use existing MovieUtils function for consistent image URL extraction
    image_url = MovieUtils.get_image_url(rich_data)

    # Use existing MovieUtils functions that were already working in the public interface
    year = MovieUtils.get_release_year(rich_data)
    director = MovieUtils.get_director(rich_data)
    genre = MovieUtils.get_genres(rich_data)

    # Extract base description from TMDB data (usually in overview field)
    # Handle both string and atom keys and multiple possible locations
    base_description =
      cond do
        # Check overview field (most common for TMDB)
        is_map(rich_data) and Map.has_key?(rich_data, "overview") ->
          rich_data["overview"]

        is_map(rich_data) and Map.has_key?(rich_data, :overview) ->
          rich_data[:overview]

        # Check metadata.overview
        is_map(rich_data) and get_in(rich_data, ["metadata", "overview"]) ->
          get_in(rich_data, ["metadata", "overview"])

        is_map(rich_data) and get_in(rich_data, [:metadata, "overview"]) ->
          get_in(rich_data, [:metadata, "overview"])

        is_map(rich_data) and get_in(rich_data, [:metadata, :overview]) ->
          get_in(rich_data, [:metadata, :overview])

        # Fallback to description field
        is_map(rich_data) and Map.has_key?(rich_data, "description") ->
          rich_data["description"]

        is_map(rich_data) and Map.has_key?(rich_data, :description) ->
          rich_data[:description]

        true ->
          ""
      end

    enhanced_description =
      MovieUtils.build_enhanced_description(
        base_description,
        year,
        director,
        genre
      )

    # Handle both string and atom keys for title
    title =
      cond do
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
end
