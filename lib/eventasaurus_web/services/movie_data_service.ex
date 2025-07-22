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

    # Truncate description to fit within 1000 character limit
    # Leave some buffer for safety (980 chars max)
    truncated_description = if is_binary(enhanced_description) && String.length(enhanced_description) > 980 do
      # Truncate to 977 chars and add ellipsis
      truncated = String.slice(enhanced_description, 0, 977)
      
      # Try to find the last complete sentence within the truncated text
      # Find all positions of sentence endings
      sentence_endings = [". ", "! ", "? "]
      |> Enum.flat_map(fn pattern ->
        case :binary.matches(truncated, pattern) do
          [] -> []
          matches -> Enum.map(matches, fn {pos, _len} -> pos end)
        end
      end)
      |> Enum.filter(&(&1 > 800))  # Only consider if we keep at least 800 chars
      
      case sentence_endings do
        [] ->
          # No good sentence boundary found, truncate at word boundary
          words = String.split(truncated, " ")
          # Take words until we would exceed the limit
          {kept_words, _} = Enum.reduce_while(words, {[], 0}, fn word, {acc, len} ->
            new_len = len + String.length(word) + 1  # +1 for space
            if new_len > 977 do
              {:halt, {acc, len}}
            else
              {:cont, {acc ++ [word], new_len}}
            end
          end)
          Enum.join(kept_words, " ") <> "..."
          
        positions ->
          # Use the last sentence boundary
          last_pos = Enum.max(positions)
          String.slice(enhanced_description, 0, last_pos + 1)
      end
    else
      enhanced_description
    end

    # Handle both string and atom keys for title
    title = cond do
      is_map(rich_data) and Map.has_key?(rich_data, "title") -> rich_data["title"]
      is_map(rich_data) and Map.has_key?(rich_data, :title) -> rich_data[:title]
      true -> ""
    end

    %{
      "title" => title,
      "description" => truncated_description,
      "external_id" => to_string(movie_id),
      "external_data" => rich_data,
      "image_url" => image_url
    }
  end


end
