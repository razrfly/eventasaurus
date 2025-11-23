defmodule EventasaurusApp.Venues.CategoryMapper do
  @moduledoc """
  Smart venue-to-category mapping for Unsplash city image selection.

  This module determines which city image category best represents a venue
  based on its type, metadata, and name.

  ## Category Priority

  1. **Explicit Override**: metadata["unsplash_category"] or metadata[:unsplash_category]
  2. **Venue Type Mapping**: Based on venue_type and metadata
  3. **Name Pattern Matching**: Keywords in venue name
  4. **Default Fallback**: "general"

  ## Supported Categories

  - **general**: Default, most popular city images
  - **architecture**: Buildings, modern structures
  - **historic**: Historic buildings, monuments, heritage sites
  - **old_town**: Medieval areas, old town squares
  - **city_landmarks**: Famous landmarks, tourist attractions

  ## Manual Category Override

  To manually set a venue's category, add "unsplash_category" to the venue's metadata:

      venue
      |> Venue.changeset(%{metadata: %{"unsplash_category" => "historic"}})
      |> Repo.update()

  Valid override values: "general", "architecture", "historic", "old_town", "city_landmarks"
  """

  alias EventasaurusApp.Venues.Venue

  @doc """
  Determine the best category for a venue.

  Returns category name as a string.

  ## Examples

      iex> CategoryMapper.determine_category(theater_venue)
      "historic"

      iex> CategoryMapper.determine_category(modern_club)
      "architecture"

      iex> CategoryMapper.determine_category(generic_venue)
      "general"
  """
  def determine_category(%Venue{} = venue) do
    cond do
      # Priority 1: Explicit override in metadata
      has_category_override?(venue) ->
        get_category_override(venue)

      # Priority 2: Venue type mapping
      category = map_by_venue_type(venue) ->
        category

      # Priority 3: Name pattern matching
      category = map_by_name_patterns(venue) ->
        category

      # Priority 4: Default fallback
      true ->
        "general"
    end
  end

  # Check if venue has explicit category override in metadata
  defp has_category_override?(%Venue{metadata: metadata}) when is_map(metadata) do
    Map.has_key?(metadata, "unsplash_category") || Map.has_key?(metadata, :unsplash_category)
  end

  defp has_category_override?(_), do: false

  # Get category override from metadata
  defp get_category_override(%Venue{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, "unsplash_category") || Map.get(metadata, :unsplash_category) || "general"
  end

  defp get_category_override(_), do: "general"

  # Map venue type to category
  defp map_by_venue_type(%Venue{venue_type: "city"}), do: "city_landmarks"

  defp map_by_venue_type(%Venue{metadata: metadata}) when is_map(metadata) do
    cond do
      # Cultural venues
      is_cultural_venue?(metadata) ->
        "historic"

      # Historic sites
      is_historic_site?(metadata) ->
        "historic"

      # Modern/contemporary spaces
      is_modern_space?(metadata) ->
        "architecture"

      # No match from metadata
      true ->
        nil
    end
  end

  defp map_by_venue_type(_), do: nil

  # Check if venue is a cultural venue
  defp is_cultural_venue?(metadata) do
    venue_category = get_metadata_field(metadata, "category")
    venue_type = get_metadata_field(metadata, "venue_type")

    cultural_keywords = [
      "theater",
      "theatre",
      "opera",
      "museum",
      "gallery",
      "concert hall",
      "philharmonic",
      "symphony"
    ]

    has_keyword?(venue_category, cultural_keywords) ||
      has_keyword?(venue_type, cultural_keywords)
  end

  # Check if venue is historic
  defp is_historic_site?(metadata) do
    era = get_metadata_field(metadata, "era")
    category = get_metadata_field(metadata, "category")

    era == "historic" ||
      has_keyword?(category, ["monument", "historic", "heritage", "memorial", "castle", "palace"])
  end

  # Check if venue is modern/contemporary
  defp is_modern_space?(metadata) do
    architectural_style = get_metadata_field(metadata, "architectural_style")
    category = get_metadata_field(metadata, "category")

    architectural_style == "modern" ||
      has_keyword?(category, ["modern", "contemporary", "skyscraper", "tower"])
  end

  # Map by name patterns
  defp map_by_name_patterns(%Venue{name: name}) when is_binary(name) do
    name_lower = String.downcase(name)

    cond do
      # Old town patterns
      String.contains?(name_lower, "old town") ||
        String.contains?(name_lower, "medieval") ||
          String.contains?(name_lower, "stare miasto") ->
        "old_town"

      # Historic patterns
      String.contains?(name_lower, "historic") ||
        String.contains?(name_lower, "museum") ||
        String.contains?(name_lower, "monument") ||
        String.contains?(name_lower, "castle") ||
        String.contains?(name_lower, "palace") ||
        String.contains?(name_lower, "cathedral") ||
          String.contains?(name_lower, "church") ->
        "historic"

      # Landmark patterns
      String.contains?(name_lower, "tower") ||
        String.contains?(name_lower, "square") ||
        String.contains?(name_lower, "plaza") ||
          String.contains?(name_lower, "rynek") ->
        "city_landmarks"

      # Modern/architecture patterns
      String.contains?(name_lower, "arena") ||
        String.contains?(name_lower, "stadium") ||
        String.contains?(name_lower, "center") ||
        String.contains?(name_lower, "centre") ||
          String.contains?(name_lower, "complex") ->
        "architecture"

      # No pattern match
      true ->
        nil
    end
  end

  defp map_by_name_patterns(_), do: nil

  # Helper: Get metadata field (handles both string and atom keys)
  defp get_metadata_field(metadata, key) when is_map(metadata) do
    Map.get(metadata, key) || Map.get(metadata, String.to_atom(key))
  end

  defp get_metadata_field(_, _), do: nil

  # Helper: Check if value contains any keyword
  defp has_keyword?(value, keywords) when is_binary(value) do
    value_lower = String.downcase(value)
    Enum.any?(keywords, fn keyword -> String.contains?(value_lower, keyword) end)
  end

  defp has_keyword?(_, _), do: false

  @doc """
  Get fallback chain for a venue.

  Returns ordered list of categories to try, ending with "general".

  ## Examples

      iex> CategoryMapper.get_fallback_chain(historic_theater)
      ["historic", "general"]
  """
  def get_fallback_chain(%Venue{} = venue) do
    primary_category = determine_category(venue)

    # Always end with general as final fallback
    [primary_category, "general"]
    |> Enum.uniq()
  end
end
