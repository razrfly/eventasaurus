defmodule EventasaurusDiscovery.Sources.Sortiraparis.Helpers.CategoryMapperTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Sortiraparis.Helpers.CategoryMapper

  describe "map_category/1" do
    test "maps concert URLs to music" do
      url = "https://www.sortiraparis.com/concerts-music-festival/articles/123-event"
      assert CategoryMapper.map_category(url) == "music"
    end

    test "maps exhibition URLs to arts" do
      url = "https://www.sortiraparis.com/exhibit-museum/articles/456-louvre"
      assert CategoryMapper.map_category(url) == "arts"
    end

    test "maps theater URLs to performing-arts" do
      url = "https://www.sortiraparis.com/theater/articles/789-play"
      assert CategoryMapper.map_category(url) == "performing-arts"
    end

    test "maps shows URLs to performing-arts" do
      url = "https://www.sortiraparis.com/shows/articles/321-spectacle"
      assert CategoryMapper.map_category(url) == "performing-arts"
    end

    test "returns nil for unrecognized URLs" do
      url = "https://www.sortiraparis.com/unknown/articles/123"
      assert CategoryMapper.map_category(url) == nil
    end

    test "is case insensitive" do
      url = "https://www.sortiraparis.com/CONCERTS/articles/123"
      assert CategoryMapper.map_category(url) == "music"
    end

    test "handles invalid input" do
      assert CategoryMapper.map_category(nil) == nil
      assert CategoryMapper.map_category(123) == nil
    end
  end

  describe "map_category_with_fallback/2" do
    test "returns category when found" do
      url = "https://www.sortiraparis.com/concerts/articles/123"
      assert CategoryMapper.map_category_with_fallback(url) == "music"
    end

    test "returns fallback when not found" do
      url = "https://www.sortiraparis.com/unknown/articles/123"
      assert CategoryMapper.map_category_with_fallback(url, "other") == "other"
    end

    test "uses 'other' as default fallback" do
      url = "https://www.sortiraparis.com/unknown/articles/123"
      assert CategoryMapper.map_category_with_fallback(url) == "other"
    end
  end

  describe "batch_map_categories/1" do
    test "maps multiple URLs" do
      urls = [
        "/concerts/articles/123",
        "/theater/articles/456",
        "/unknown/articles/789"
      ]

      result = CategoryMapper.batch_map_categories(urls)
      assert length(result) == 3

      assert {"/concerts/articles/123", "music"} in result
      assert {"/theater/articles/456", "performing-arts"} in result
      assert {"/unknown/articles/789", nil} in result
    end

    test "handles empty list" do
      assert CategoryMapper.batch_map_categories([]) == []
    end

    test "handles invalid input" do
      assert CategoryMapper.batch_map_categories(nil) == []
    end
  end

  describe "available_categories/0" do
    test "returns list of unique categories" do
      categories = CategoryMapper.available_categories()

      assert is_list(categories)
      assert "music" in categories
      assert "arts" in categories
      assert "performing-arts" in categories
      assert "sports" in categories
      assert "film" in categories
    end

    test "returns sorted list" do
      categories = CategoryMapper.available_categories()
      assert categories == Enum.sort(categories)
    end
  end

  describe "patterns_for_category/1" do
    test "returns patterns for music category" do
      patterns = CategoryMapper.patterns_for_category("music")

      assert is_list(patterns)
      assert "concerts-music-festival" in patterns
      assert "concerts" in patterns
      assert "jazz" in patterns
    end

    test "returns patterns for arts category" do
      patterns = CategoryMapper.patterns_for_category("arts")

      assert "exhibit-museum" in patterns
      assert "exhibition" in patterns
      assert "museum" in patterns
    end

    test "returns empty list for unknown category" do
      assert CategoryMapper.patterns_for_category("unknown") == []
    end

    test "handles invalid input" do
      assert CategoryMapper.patterns_for_category(nil) == []
    end
  end

  describe "get_mapping_stats/0" do
    test "returns statistics about mappings" do
      stats = CategoryMapper.get_mapping_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :total_patterns)
      assert Map.has_key?(stats, :total_categories)
      assert Map.has_key?(stats, :patterns_per_category)

      assert stats.total_patterns > 0
      assert stats.total_categories > 0
      assert is_map(stats.patterns_per_category)
    end
  end

  describe "valid_category?/1" do
    test "validates known categories" do
      assert CategoryMapper.valid_category?("music") == true
      assert CategoryMapper.valid_category?("arts") == true
      assert CategoryMapper.valid_category?("performing-arts") == true
    end

    test "rejects unknown categories" do
      assert CategoryMapper.valid_category?("unknown") == false
    end

    test "handles invalid input" do
      assert CategoryMapper.valid_category?(nil) == false
      assert CategoryMapper.valid_category?(123) == false
    end
  end

  describe "extract_all_categories/1" do
    test "extracts multiple matching categories" do
      url = "/concerts-music-festival/theater/articles/123"
      categories = CategoryMapper.extract_all_categories(url)

      assert "music" in categories
      assert "performing-arts" in categories
    end

    test "returns unique categories" do
      url = "/concerts/jazz/rock/articles/123"
      categories = CategoryMapper.extract_all_categories(url)

      # All three patterns map to "music", should only return once
      assert categories == ["music"]
    end

    test "returns empty list for no matches" do
      url = "/unknown/articles/123"
      assert CategoryMapper.extract_all_categories(url) == []
    end
  end

  describe "get_primary_category/1" do
    test "returns music as highest priority" do
      categories = ["arts", "music", "sports"]
      assert CategoryMapper.get_primary_category(categories) == "music"
    end

    test "returns performing-arts when no music" do
      categories = ["arts", "performing-arts", "sports"]
      assert CategoryMapper.get_primary_category(categories) == "performing-arts"
    end

    test "returns first category when no priority match" do
      categories = ["family", "community"]
      assert CategoryMapper.get_primary_category(categories) == "family"
    end

    test "returns nil for empty list" do
      assert CategoryMapper.get_primary_category([]) == nil
    end

    test "handles invalid input" do
      assert CategoryMapper.get_primary_category(nil) == nil
    end
  end
end
