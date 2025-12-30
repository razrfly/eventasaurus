defmodule EventasaurusDiscovery.Metrics.ErrorCategoriesTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Metrics.ErrorCategories

  describe "identity matching" do
    test "category atoms pass through unchanged" do
      # All 13 categories should be recognized as themselves
      categories = [
        :validation_error,
        :parsing_error,
        :data_quality_error,
        :data_integrity_error,
        :dependency_error,
        :network_error,
        :rate_limit_error,
        :authentication_error,
        :geocoding_error,
        :venue_error,
        :performer_error,
        :tmdb_error,
        :uncategorized_error
      ]

      for category <- categories do
        assert ErrorCategories.categorize_error(category) == category,
               "Expected #{category} to pass through unchanged"
      end
    end
  end

  describe "atom pattern matching" do
    test "dependency error atoms" do
      assert ErrorCategories.categorize_error(:movie_not_ready) == :dependency_error
      assert ErrorCategories.categorize_error(:movie_not_found) == :dependency_error
      assert ErrorCategories.categorize_error(:venue_not_ready) == :dependency_error
      assert ErrorCategories.categorize_error(:not_ready) == :dependency_error
    end

    test "validation error atoms" do
      assert ErrorCategories.categorize_error(:missing_external_id) == :validation_error
      assert ErrorCategories.categorize_error(:missing_title) == :validation_error
      assert ErrorCategories.categorize_error(:invalid_date) == :validation_error
      assert ErrorCategories.categorize_error(:validation_failed) == :validation_error
    end

    test "network error atoms" do
      assert ErrorCategories.categorize_error(:timeout) == :network_error
      assert ErrorCategories.categorize_error(:connection_refused) == :network_error
      assert ErrorCategories.categorize_error(:econnrefused) == :network_error
    end

    test "parsing error atoms" do
      assert ErrorCategories.categorize_error(:parse_error) == :parsing_error
      assert ErrorCategories.categorize_error(:json_decode_error) == :parsing_error
      assert ErrorCategories.categorize_error(:html_parse_error) == :parsing_error
    end

    test "performer error atoms" do
      assert ErrorCategories.categorize_error(:performer_not_found) == :performer_error
      assert ErrorCategories.categorize_error(:performer_ambiguous) == :performer_error
    end

    test "venue error atoms" do
      assert ErrorCategories.categorize_error(:venue_not_found) == :venue_error
      assert ErrorCategories.categorize_error(:venue_creation_failed) == :venue_error
    end

    test "tmdb error atoms" do
      assert ErrorCategories.categorize_error(:tmdb_not_found) == :tmdb_error
      assert ErrorCategories.categorize_error(:tmdb_no_results) == :tmdb_error
      assert ErrorCategories.categorize_error(:no_tmdb_match) == :tmdb_error
    end
  end

  describe "string pattern matching" do
    test "validation errors from strings" do
      assert ErrorCategories.categorize_error("Event title is required") == :validation_error

      assert ErrorCategories.categorize_error("Missing required field: venue") ==
               :validation_error

      assert ErrorCategories.categorize_error("Invalid date format") == :validation_error
    end

    test "network errors from strings" do
      assert ErrorCategories.categorize_error("Connection timeout after 30s") == :network_error
      assert ErrorCategories.categorize_error("HTTP 500 Internal Server Error") == :network_error
    end

    test "rate limit errors from strings" do
      assert ErrorCategories.categorize_error("HTTP 429 - Too Many Requests") == :rate_limit_error
      assert ErrorCategories.categorize_error("Rate limit exceeded") == :rate_limit_error
    end

    test "authentication errors from strings" do
      assert ErrorCategories.categorize_error("HTTP 401 Unauthorized") == :authentication_error
      assert ErrorCategories.categorize_error("HTTP 403 Forbidden") == :authentication_error
    end
  end

  describe "categories/0" do
    test "returns all 13 categories" do
      categories = ErrorCategories.categories()

      assert length(categories) == 13
      assert :validation_error in categories
      assert :parsing_error in categories
      assert :data_quality_error in categories
      assert :data_integrity_error in categories
      assert :dependency_error in categories
      assert :network_error in categories
      assert :rate_limit_error in categories
      assert :authentication_error in categories
      assert :geocoding_error in categories
      assert :venue_error in categories
      assert :performer_error in categories
      assert :tmdb_error in categories
      assert :uncategorized_error in categories
    end
  end
end
