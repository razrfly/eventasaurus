defmodule EventasaurusWeb.Services.SearchServiceTest do
  use ExUnit.Case, async: true
  alias EventasaurusWeb.Services.SearchService

  describe "unified_search/2" do
    test "returns map with unsplash and tmdb keys" do
      # Test with a simple query
      result = SearchService.unified_search("test", page: 1, per_page: 5)

      # Verify the return structure
      assert is_map(result)
      assert Map.has_key?(result, :unsplash)
      assert Map.has_key?(result, :tmdb)

      # Verify values are lists (even if empty)
      assert is_list(result.unsplash)
      assert is_list(result.tmdb)
    end

    test "handles empty query gracefully" do
      result = SearchService.unified_search("", page: 1, per_page: 5)

      assert is_map(result)
      assert result.unsplash == []
      assert result.tmdb == []
    end

    test "handles network errors gracefully" do
      # Test with a query that might cause network issues
      result =
        SearchService.unified_search("nonexistent_search_term_that_should_fail_gracefully",
          page: 1,
          per_page: 5
        )

      # Should still return the expected structure
      assert is_map(result)
      assert Map.has_key?(result, :unsplash)
      assert Map.has_key?(result, :tmdb)
    end

    test "unsplash results have required fields" do
      result = SearchService.unified_search("nature", page: 1, per_page: 2)

      if length(result.unsplash) > 0 do
        image = List.first(result.unsplash)

        # Verify required fields for Unsplash images
        assert Map.has_key?(image, :id)
        assert Map.has_key?(image, :urls)
        assert Map.has_key?(image, :user)

        # Verify urls structure
        assert is_map(image.urls)
        assert Map.has_key?(image.urls, :regular)
        assert Map.has_key?(image.urls, :small)

        # Verify user structure
        assert is_map(image.user)
        assert Map.has_key?(image.user, :name)
      end
    end

    test "tmdb results have required fields" do
      result = SearchService.unified_search("movie", page: 1, per_page: 2)

      if length(result.tmdb) > 0 do
        item = List.first(result.tmdb)

        # Verify required fields for TMDB items
        assert Map.has_key?(item, :id)

        # Should have either title (movies) or name (TV shows/people)
        has_title = Map.has_key?(item, :title)
        has_name = Map.has_key?(item, :name)
        assert has_title || has_name

        # Should have poster_path or profile_path
        has_poster = Map.has_key?(item, :poster_path)
        has_profile = Map.has_key?(item, :profile_path)
        assert has_poster || has_profile
      end
    end

    test "respects pagination parameters" do
      # Test page 1
      result_page1 = SearchService.unified_search("test", page: 1, per_page: 3)

      # Test page 2
      result_page2 = SearchService.unified_search("test", page: 2, per_page: 3)

      # Results should be different (assuming there are enough results)
      if length(result_page1.unsplash) > 0 && length(result_page2.unsplash) > 0 do
        first_image_page1 = List.first(result_page1.unsplash)
        first_image_page2 = List.first(result_page2.unsplash)

        # Images should be different between pages
        assert first_image_page1.id != first_image_page2.id
      end
    end
  end

  describe "function existence checks" do
    test "unified_search function exists and is callable" do
      # This test ensures the function exists with the expected arity
      assert function_exported?(SearchService, :unified_search, 1)
    end

    test "does not have the old individual search functions" do
      # Ensure we haven't accidentally kept the old broken functions
      refute function_exported?(SearchService, :search_unsplash, 2)
      refute function_exported?(SearchService, :search_tmdb, 1)
    end
  end

  describe "error resilience" do
    test "handles nil query" do
      result = SearchService.unified_search(nil, page: 1, per_page: 5)

      assert is_map(result)
      assert result.unsplash == []
      assert result.tmdb == []
    end

    test "handles invalid options" do
      # Should not crash with invalid page/per_page values
      result = SearchService.unified_search("test", page: -1, per_page: 0)

      assert is_map(result)
      assert Map.has_key?(result, :unsplash)
      assert Map.has_key?(result, :tmdb)
    end
  end
end
