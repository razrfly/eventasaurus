defmodule EventasaurusDiscovery.Sources.Sortiraparis.Helpers.CategoryMapper do
  @moduledoc """
  Maps Sortiraparis URL categories to unified event categories.

  ## Unified Category System

  Eventasaurus uses a standardized category system across all sources:
  - `music` - Concerts, live music, music festivals
  - `arts` - Art exhibitions, museum events, visual arts
  - `performing-arts` - Theater, dance, opera, performance
  - `sports` - Sports events and competitions
  - `film` - Cinema, film screenings, film festivals
  - `food-drink` - Food events, tastings, culinary experiences
  - `nightlife` - Clubs, DJ events, parties
  - `community` - Community events, meetups
  - `family` - Family-friendly events, kids activities
  - `other` - Uncategorized events

  ## Sortiraparis URL Patterns

  URL segments indicate event type:
  - `/concerts-music-festival/` → `music`
  - `/exhibit-museum/` → `arts`
  - `/shows/` → `performing-arts`
  - `/theater/` → `performing-arts`

  ## Usage

      iex> map_category("https://www.sortiraparis.com/concerts-music-festival/articles/123-indochine")
      "music"

      iex> map_category("/exhibit-museum/articles/456-louvre")
      "arts"

      iex> map_category("/unknown-category/articles/789-event")
      nil
  """

  require Logger

  @category_mapping %{
    # Music & Concerts
    "concerts-music-festival" => "music",
    "concerts" => "music",
    "music-festival" => "music",
    "jazz" => "music",
    "rock" => "music",
    "electro" => "music",
    "classical-music" => "music",

    # Arts & Exhibitions
    "exhibit-museum" => "arts",
    "exhibition" => "arts",
    "museum" => "arts",
    "art-gallery" => "arts",
    "contemporary-art" => "arts",

    # Performing Arts
    "shows" => "performing-arts",
    "theater" => "performing-arts",
    "theatre" => "performing-arts",
    "dance" => "performing-arts",
    "opera" => "performing-arts",
    "ballet" => "performing-arts",
    "circus" => "performing-arts",
    "comedy" => "performing-arts",
    "stand-up" => "performing-arts",

    # Film & Cinema
    "cinema" => "film",
    "movie" => "film",
    "film-screening" => "film",
    "film-festival" => "film",

    # Sports
    "sports" => "sports",
    "sport" => "sports",
    "football" => "sports",
    "rugby" => "sports",
    "tennis" => "sports",
    "running" => "sports",
    "marathon" => "sports",

    # Food & Drink
    "food" => "food-drink",
    "restaurant" => "food-drink",
    "tasting" => "food-drink",
    "wine" => "food-drink",
    "gastronomy" => "food-drink",

    # Nightlife
    "nightlife" => "nightlife",
    "club" => "nightlife",
    "dj" => "nightlife",
    "party" => "nightlife",

    # Family & Kids
    "family" => "family",
    "kids" => "family",
    "children" => "family",
    "animation" => "family",

    # Community
    "community" => "community",
    "meetup" => "community",
    "conference" => "community",
    "workshop" => "community",
    "seminar" => "community"
  }

  @doc """
  Map URL to unified category.

  Returns the unified category name or `nil` if no match found.

  ## Examples

      iex> map_category("https://www.sortiraparis.com/concerts-music-festival/articles/123-event")
      "music"

      iex> map_category("/theater/articles/456-play")
      "performing-arts"

      iex> map_category("/unknown/articles/789")
      nil
  """
  def map_category(url) when is_binary(url) do
    url_lower = String.downcase(url)

    # Try to find matching pattern in URL
    Enum.find_value(@category_mapping, fn {pattern, category} ->
      if String.contains?(url_lower, pattern) do
        category
      end
    end)
  end

  def map_category(_), do: nil

  @doc """
  Map URL to unified category with fallback.

  Returns the category or the fallback value if no match found.

  ## Examples

      iex> map_category_with_fallback("/concerts/articles/123", "other")
      "music"

      iex> map_category_with_fallback("/unknown/articles/123", "other")
      "other"
  """
  def map_category_with_fallback(url, fallback \\ "other") do
    map_category(url) || fallback
  end

  @doc """
  Batch map categories for multiple URLs.

  Returns a list of {url, category} tuples.

  ## Examples

      iex> urls = ["/concerts/articles/123", "/theater/articles/456"]
      iex> batch_map_categories(urls)
      [
        {"/concerts/articles/123", "music"},
        {"/theater/articles/456", "performing-arts"}
      ]
  """
  def batch_map_categories(urls) when is_list(urls) do
    urls
    |> Enum.map(fn url ->
      {url, map_category(url)}
    end)
  end

  def batch_map_categories(_), do: []

  @doc """
  Get all available unified categories.

  Returns a list of category strings.

  ## Examples

      iex> available_categories()
      ["music", "arts", "performing-arts", "sports", ...]
  """
  def available_categories do
    @category_mapping
    |> Map.values()
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Get all Sortiraparis patterns that map to a specific category.

  ## Examples

      iex> patterns_for_category("music")
      ["concerts-music-festival", "concerts", "music-festival", "jazz", ...]
  """
  def patterns_for_category(category) when is_binary(category) do
    @category_mapping
    |> Enum.filter(fn {_pattern, cat} -> cat == category end)
    |> Enum.map(fn {pattern, _cat} -> pattern end)
    |> Enum.sort()
  end

  def patterns_for_category(_), do: []

  @doc """
  Get category mapping statistics.

  Returns a map with:
  - Total patterns
  - Categories count
  - Patterns per category

  ## Examples

      iex> get_mapping_stats()
      %{
        total_patterns: 35,
        total_categories: 10,
        patterns_per_category: %{"music" => 7, "arts" => 5, ...}
      }
  """
  def get_mapping_stats do
    patterns_per_category =
      @category_mapping
      |> Enum.group_by(fn {_pattern, category} -> category end)
      |> Enum.map(fn {category, patterns} -> {category, length(patterns)} end)
      |> Enum.into(%{})

    %{
      total_patterns: map_size(@category_mapping),
      total_categories: length(available_categories()),
      patterns_per_category: patterns_per_category
    }
  end

  @doc """
  Validate that a category is a valid unified category.

  ## Examples

      iex> valid_category?("music")
      true

      iex> valid_category?("invalid")
      false
  """
  def valid_category?(category) when is_binary(category) do
    category in available_categories()
  end

  def valid_category?(_), do: false

  @doc """
  Extract all possible categories from a URL.

  Returns a list of all matching categories (can be multiple).

  ## Examples

      iex> extract_all_categories("/concerts-music-festival/theater/articles/123")
      ["music", "performing-arts"]
  """
  def extract_all_categories(url) when is_binary(url) do
    url_lower = String.downcase(url)

    @category_mapping
    |> Enum.filter(fn {pattern, _category} ->
      String.contains?(url_lower, pattern)
    end)
    |> Enum.map(fn {_pattern, category} -> category end)
    |> Enum.uniq()
  end

  def extract_all_categories(_), do: []

  @doc """
  Get the primary category from multiple matches.

  Priority order:
  1. music
  2. performing-arts
  3. arts
  4. sports
  5. film
  6. other categories

  ## Examples

      iex> get_primary_category(["music", "performing-arts"])
      "music"

      iex> get_primary_category(["arts", "film"])
      "arts"
  """
  def get_primary_category(categories) when is_list(categories) and length(categories) > 0 do
    priority_order = [
      "music",
      "performing-arts",
      "arts",
      "sports",
      "film",
      "food-drink",
      "nightlife",
      "family",
      "community",
      "other"
    ]

    Enum.find(priority_order, List.first(categories), fn priority_cat ->
      priority_cat in categories
    end)
  end

  def get_primary_category([]), do: nil
  def get_primary_category(_), do: nil
end
