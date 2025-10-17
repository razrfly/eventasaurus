defmodule EventasaurusDiscovery.Sources.Sortiraparis.Helpers.UrlFilterTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Sortiraparis.Helpers.UrlFilter

  describe "filter_event_urls/1" do
    test "filters event URLs from mixed list" do
      urls = [
        "https://www.sortiraparis.com/concerts-music-festival/articles/123-event",
        "https://www.sortiraparis.com/guides/best-restaurants",
        "https://www.sortiraparis.com/theater/articles/456-play"
      ]

      assert {:ok, filtered_urls, stats} = UrlFilter.filter_event_urls(urls)
      assert length(filtered_urls) == 2
      assert stats.total == 3
      assert stats.filtered == 2
      assert stats.excluded == 1
    end

    test "removes duplicates" do
      urls = [
        "https://www.sortiraparis.com/concerts-music-festival/articles/123",
        "https://www.sortiraparis.com/concerts-music-festival/articles/123",
        "https://www.sortiraparis.com/theater/articles/456"
      ]

      assert {:ok, filtered_urls, stats} = UrlFilter.filter_event_urls(urls)
      assert length(filtered_urls) == 2
      assert stats.duplicates_removed == 1
    end

    test "handles empty list" do
      assert {:ok, [], stats} = UrlFilter.filter_event_urls([])
      assert stats.total == 0
      assert stats.filtered == 0
    end

    test "returns error for invalid input" do
      assert {:error, :invalid_url_list} = UrlFilter.filter_event_urls(nil)
      assert {:error, :invalid_url_list} = UrlFilter.filter_event_urls("not a list")
    end
  end

  describe "filter_with_patterns/2" do
    test "filters with custom patterns" do
      urls = [
        "https://example.com/concerts/event",
        "https://example.com/news/article",
        "https://example.com/theater/show"
      ]

      options = [
        include_patterns: ["concerts", "theater"],
        exclude_patterns: ["news"]
      ]

      assert {:ok, filtered_urls, _stats} = UrlFilter.filter_with_patterns(urls, options)
      assert length(filtered_urls) == 2
      assert "https://example.com/concerts/event" in filtered_urls
      assert "https://example.com/theater/show" in filtered_urls
    end

    test "supports case insensitive matching by default" do
      urls = ["https://example.com/CONCERTS/EVENT"]

      options = [include_patterns: ["concerts"]]

      assert {:ok, [url], _stats} = UrlFilter.filter_with_patterns(urls, options)
      assert url == "https://example.com/CONCERTS/EVENT"
    end

    test "supports case sensitive matching" do
      urls = ["https://example.com/CONCERTS/event"]

      options = [include_patterns: ["concerts"], case_sensitive: true]

      assert {:ok, [], _stats} = UrlFilter.filter_with_patterns(urls, options)
    end
  end

  describe "normalize_url/2" do
    test "converts http to https" do
      assert UrlFilter.normalize_url("http://example.com/page") == "https://example.com/page"
    end

    test "removes trailing slash" do
      assert UrlFilter.normalize_url("https://example.com/page/") == "https://example.com/page"
    end

    test "removes fragment" do
      assert UrlFilter.normalize_url("https://example.com/page#section") ==
               "https://example.com/page"
    end

    test "optionally removes query parameters" do
      assert UrlFilter.normalize_url("https://example.com/page?ref=home", remove_query: true) ==
               "https://example.com/page"
    end

    test "keeps query parameters by default" do
      assert UrlFilter.normalize_url("https://example.com/page?ref=home") ==
               "https://example.com/page?ref=home"
    end

    test "returns nil for invalid input" do
      assert UrlFilter.normalize_url(nil) == nil
      assert UrlFilter.normalize_url(123) == nil
    end
  end

  describe "normalize_urls/2" do
    test "batch normalizes URLs" do
      urls = [
        "http://example.com/page/",
        "https://example.com/other#section"
      ]

      normalized = UrlFilter.normalize_urls(urls)
      assert length(normalized) == 2
      assert "https://example.com/page" in normalized
      assert "https://example.com/other" in normalized
    end

    test "filters out invalid URLs" do
      urls = ["https://example.com/page", nil, "https://example.com/other"]

      normalized = UrlFilter.normalize_urls(urls)
      assert length(normalized) == 2
    end
  end

  describe "extract_article_ids/1" do
    test "extracts article IDs from URLs" do
      urls = [
        "https://www.sortiraparis.com/articles/123-event",
        "https://www.sortiraparis.com/articles/456-show"
      ]

      result = UrlFilter.extract_article_ids(urls)
      assert length(result) == 2
      assert {"https://www.sortiraparis.com/articles/123-event", "123"} in result
      assert {"https://www.sortiraparis.com/articles/456-show", "456"} in result
    end

    test "filters URLs without article IDs" do
      urls = [
        "https://www.sortiraparis.com/articles/123-event",
        "https://www.sortiraparis.com/guides/best-of"
      ]

      result = UrlFilter.extract_article_ids(urls)
      assert length(result) == 1
    end

    test "handles empty list" do
      assert UrlFilter.extract_article_ids([]) == []
    end

    test "handles invalid input" do
      assert UrlFilter.extract_article_ids(nil) == []
    end
  end
end
