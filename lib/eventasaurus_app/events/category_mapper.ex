defmodule EventasaurusApp.Events.CategoryMapper do
  @moduledoc """
  Smart event-to-category mapping for Unsplash city image selection.

  This module determines which city image category best represents an event
  based on its source, categories, venue, title, and description.

  ## Category Priority

  1. **Source-specific mapping**: Speed Quizzing, Inquizition, etc.
  2. **Event category mapping**: Based on event categories
  3. **Venue category fallback**: Delegate to venue CategoryMapper
  4. **Title/description patterns**: Keywords in event content
  5. **Default fallback**: "general"

  ## Supported Categories

  - **general**: Default, most popular city images
  - **architecture**: Buildings, modern structures
  - **historic**: Historic buildings, monuments, heritage sites
  - **old_town**: Medieval areas, old town squares
  - **city_landmarks**: Famous landmarks, tourist attractions

  ## Examples

      iex> CategoryMapper.determine_category(trivia_event)
      "general"

      iex> CategoryMapper.determine_category(theater_event)
      "historic"

      iex> CategoryMapper.determine_category(sports_event)
      "architecture"
  """

  alias EventasaurusApp.Venues.CategoryMapper, as: VenueCategoryMapper

  @doc """
  Determine the best Unsplash category for an event.

  Returns category name as a string.

  ## Examples

      iex> CategoryMapper.determine_category(event)
      "general"
  """
  def determine_category(event) when is_map(event) do
    cond do
      # Priority 1: Source-specific mapping (trivia, quizzes, etc.)
      category = map_by_source(event) ->
        category

      # Priority 2: Event category mapping
      category = map_by_event_categories(event) ->
        category

      # Priority 3: Venue category fallback
      category = map_by_venue(event) ->
        category

      # Priority 4: Title/description patterns
      category = map_by_title_patterns(event) ->
        category

      # Priority 5: Default fallback
      true ->
        "general"
    end
  end

  @doc """
  Get fallback chain for an event.

  Returns ordered list of categories to try, ending with "general".

  ## Examples

      iex> CategoryMapper.get_fallback_chain(event)
      ["city_landmarks", "general"]
  """
  def get_fallback_chain(event) when is_map(event) do
    primary_category = determine_category(event)

    # Always end with general as final fallback
    [primary_category, "general"]
    |> Enum.uniq()
  end

  # Map by event source (Speed Quizzing, Inquizition, etc.)
  defp map_by_source(%{sources: sources}) when is_list(sources) and length(sources) > 0 do
    # Get first source's source_slug or name
    first_source = List.first(sources)

    cond do
      # Trivia/Quiz sources → general or city_landmarks
      is_trivia_source?(first_source) ->
        "general"

      # Music/Concert sources → architecture
      is_music_source?(first_source) ->
        "architecture"

      # Theater/Opera sources → historic
      is_theater_source?(first_source) ->
        "historic"

      # Sports sources → architecture
      is_sports_source?(first_source) ->
        "architecture"

      # Food/Dining sources → general
      is_food_source?(first_source) ->
        "general"

      # Tours/Walking sources → city_landmarks
      is_tour_source?(first_source) ->
        "city_landmarks"

      true ->
        nil
    end
  end

  defp map_by_source(_), do: nil

  # Check if source is trivia/quiz related
  defp is_trivia_source?(source) do
    source_slug = get_source_slug(source)
    source_name = get_source_name(source)

    trivia_keywords = ["quiz", "trivia", "inquizition", "speed-quizzing", "pubquiz"]

    has_keyword?(source_slug, trivia_keywords) ||
      has_keyword?(source_name, trivia_keywords)
  end

  # Check if source is music/concert related
  defp is_music_source?(source) do
    source_slug = get_source_slug(source)
    source_name = get_source_name(source)

    music_keywords = [
      "concert",
      "music",
      "festival",
      "resident-advisor",
      "bandsintown",
      "songkick"
    ]

    has_keyword?(source_slug, music_keywords) ||
      has_keyword?(source_name, music_keywords)
  end

  # Check if source is theater/opera related
  defp is_theater_source?(source) do
    source_slug = get_source_slug(source)
    source_name = get_source_name(source)

    theater_keywords = ["theater", "theatre", "opera", "philharmonic", "symphony"]

    has_keyword?(source_slug, theater_keywords) ||
      has_keyword?(source_name, theater_keywords)
  end

  # Check if source is sports related
  defp is_sports_source?(source) do
    source_slug = get_source_slug(source)
    source_name = get_source_name(source)

    sports_keywords = ["sports", "game", "match", "arena"]

    has_keyword?(source_slug, sports_keywords) ||
      has_keyword?(source_name, sports_keywords)
  end

  # Check if source is food/dining related
  defp is_food_source?(source) do
    source_slug = get_source_slug(source)
    source_name = get_source_name(source)

    food_keywords = ["food", "dining", "restaurant", "culinary", "tasting"]

    has_keyword?(source_slug, food_keywords) ||
      has_keyword?(source_name, food_keywords)
  end

  # Check if source is tour/walking related
  defp is_tour_source?(source) do
    source_slug = get_source_slug(source)
    source_name = get_source_name(source)

    tour_keywords = ["tour", "walk", "walking", "sightseeing", "explore"]

    has_keyword?(source_slug, tour_keywords) ||
      has_keyword?(source_name, tour_keywords)
  end

  # Map by event categories (from many-to-many relationship)
  defp map_by_event_categories(%{categories: categories})
       when is_list(categories) and length(categories) > 0 do
    # Get first category name
    first_category = List.first(categories)
    category_name = if is_map(first_category), do: first_category.name, else: nil

    case category_name do
      name when is_binary(name) ->
        name_lower = String.downcase(name)

        cond do
          # Theater/Opera/Culture → historic
          String.contains?(name_lower, "theater") or
            String.contains?(name_lower, "theatre") or
            String.contains?(name_lower, "opera") or
            String.contains?(name_lower, "culture") or
              String.contains?(name_lower, "museum") ->
            "historic"

          # Music/Concerts → architecture
          String.contains?(name_lower, "music") or
            String.contains?(name_lower, "concert") or
              String.contains?(name_lower, "festival") ->
            "architecture"

          # Sports → architecture
          String.contains?(name_lower, "sports") or
              String.contains?(name_lower, "game") ->
            "architecture"

          # Tours/Sightseeing → city_landmarks
          String.contains?(name_lower, "tour") or
            String.contains?(name_lower, "sightseeing") or
              String.contains?(name_lower, "walking") ->
            "city_landmarks"

          # Historic/Heritage → historic
          String.contains?(name_lower, "historic") or
              String.contains?(name_lower, "heritage") ->
            "historic"

          # Default
          true ->
            nil
        end

      _ ->
        nil
    end
  end

  defp map_by_event_categories(_), do: nil

  # Map by venue category (fallback to venue's category)
  defp map_by_venue(%{venue: venue}) when is_map(venue) and not is_nil(venue) do
    # Use venue's CategoryMapper to determine category
    VenueCategoryMapper.determine_category(venue)
  end

  defp map_by_venue(_), do: nil

  # Map by title/description patterns
  defp map_by_title_patterns(%{title: title}) when is_binary(title) do
    title_lower = String.downcase(title)

    cond do
      # Quiz/Trivia patterns
      String.contains?(title_lower, "quiz") or
        String.contains?(title_lower, "trivia") or
          String.contains?(title_lower, "pub quiz") ->
        "general"

      # Historic patterns
      String.contains?(title_lower, "historic") or
        String.contains?(title_lower, "museum") or
        String.contains?(title_lower, "monument") or
        String.contains?(title_lower, "castle") or
        String.contains?(title_lower, "palace") or
        String.contains?(title_lower, "cathedral") or
          String.contains?(title_lower, "church") ->
        "historic"

      # Tour patterns
      String.contains?(title_lower, "tour") or
        String.contains?(title_lower, "walking") or
          String.contains?(title_lower, "sightseeing") ->
        "city_landmarks"

      # Music patterns
      String.contains?(title_lower, "concert") or
        String.contains?(title_lower, "music") or
        String.contains?(title_lower, "band") or
          String.contains?(title_lower, "festival") ->
        "architecture"

      # Sports patterns
      String.contains?(title_lower, "game") or
        String.contains?(title_lower, "match") or
          String.contains?(title_lower, "sports") ->
        "architecture"

      # No pattern match
      true ->
        nil
    end
  end

  defp map_by_title_patterns(_), do: nil

  # Helper: Get source slug from source
  defp get_source_slug(%{source_slug: slug}) when is_binary(slug), do: slug
  defp get_source_slug(%{"source_slug" => slug}) when is_binary(slug), do: slug
  defp get_source_slug(_), do: ""

  # Helper: Get source name from source
  defp get_source_name(%{source_name: name}) when is_binary(name), do: name
  defp get_source_name(%{"source_name" => name}) when is_binary(name), do: name
  defp get_source_name(%{name: name}) when is_binary(name), do: name
  defp get_source_name(%{"name" => name}) when is_binary(name), do: name
  defp get_source_name(_), do: ""

  # Helper: Check if value contains any keyword
  defp has_keyword?(value, keywords) when is_binary(value) do
    value_lower = String.downcase(value)
    Enum.any?(keywords, fn keyword -> String.contains?(value_lower, keyword) end)
  end

  defp has_keyword?(_, _), do: false
end
