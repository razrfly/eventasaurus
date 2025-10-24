defmodule EventasaurusDiscovery.Sources.Sortiraparis.ConfigTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Sortiraparis.Config

  describe "base configuration" do
    test "returns correct base_url" do
      assert Config.base_url() == "https://www.sortiraparis.com"
    end

    test "returns correct sitemap_url" do
      assert Config.sitemap_url() == "https://www.sortiraparis.com/sitemap-index.xml"
    end

    test "returns conservative rate_limit" do
      assert Config.rate_limit() == 5
    end

    test "returns appropriate timeout" do
      assert Config.timeout() == 10_000
    end
  end

  describe "sitemap_urls/0" do
    test "returns list of English sitemap URLs" do
      urls = Config.sitemap_urls()

      assert is_list(urls)
      assert length(urls) == 4

      assert "https://www.sortiraparis.com/sitemap-en-1.xml" in urls
      assert "https://www.sortiraparis.com/sitemap-en-2.xml" in urls
      assert "https://www.sortiraparis.com/sitemap-en-3.xml" in urls
      assert "https://www.sortiraparis.com/sitemap-en-4.xml" in urls
    end
  end

  describe "build_url/1" do
    test "handles absolute URLs" do
      url = "https://www.sortiraparis.com/articles/123-event"
      assert Config.build_url(url) == url
    end

    test "handles relative URLs with leading slash" do
      path = "/articles/123-event"
      assert Config.build_url(path) == "https://www.sortiraparis.com/articles/123-event"
    end

    test "handles relative URLs without leading slash" do
      path = "articles/123-event"
      assert Config.build_url(path) == "https://www.sortiraparis.com/articles/123-event"
    end

    test "handles http URLs" do
      url = "http://www.sortiraparis.com/articles/123-event"
      assert Config.build_url(url) == url
    end
  end

  describe "extract_article_id/1" do
    test "extracts ID from full URL" do
      url = "https://www.sortiraparis.com/articles/319282-indochine-concert"
      assert Config.extract_article_id(url) == "319282"
    end

    test "extracts ID from relative URL" do
      url = "/articles/319282-indochine-concert"
      assert Config.extract_article_id(url) == "319282"
    end

    test "extracts ID from URL with query parameters" do
      url = "/articles/319282-indochine-concert?ref=homepage"
      assert Config.extract_article_id(url) == "319282"
    end

    test "returns nil for URL without article ID" do
      url = "/concerts-music-festival"
      assert Config.extract_article_id(url) == nil
    end

    test "returns nil for invalid URL format" do
      url = "/guides/best-restaurants"
      assert Config.extract_article_id(url) == nil
    end
  end

  describe "generate_external_id/1" do
    test "generates correct external_id format" do
      assert Config.generate_external_id("319282") == "sortiraparis_319282"
    end

    test "handles numeric article IDs" do
      assert Config.generate_external_id("123") == "sortiraparis_123"
    end

    test "handles long article IDs" do
      assert Config.generate_external_id("999999") == "sortiraparis_999999"
    end
  end

  describe "headers/0" do
    test "returns list of headers" do
      headers = Config.headers()
      assert is_list(headers)
    end

    test "includes browser-like User-Agent" do
      headers = Config.headers()
      {_key, user_agent} = Enum.find(headers, fn {k, _v} -> k == "User-Agent" end)

      assert String.contains?(user_agent, "Mozilla")
      assert String.contains?(user_agent, "Chrome")
    end

    test "includes Accept header" do
      headers = Config.headers()
      assert {"Accept", _value} = Enum.find(headers, fn {k, _v} -> k == "Accept" end)
    end

    test "includes Accept-Language header" do
      headers = Config.headers()
      {_key, lang} = Enum.find(headers, fn {k, _v} -> k == "Accept-Language" end)
      assert String.contains?(lang, "en")
    end

    test "includes Referer header" do
      headers = Config.headers()
      assert {"Referer", "https://www.sortiraparis.com"} in headers
    end

    test "includes Upgrade-Insecure-Requests header" do
      headers = Config.headers()
      assert {"Upgrade-Insecure-Requests", "1"} in headers
    end
  end

  describe "event_categories/0" do
    test "returns list of event category patterns" do
      categories = Config.event_categories()

      assert is_list(categories)
      assert "concerts-music-festival" in categories
      assert "exhibit-museum" in categories
      assert "shows" in categories
      assert "theater" in categories
    end
  end

  describe "exclude_patterns/0" do
    test "returns list of exclude patterns" do
      patterns = Config.exclude_patterns()

      assert is_list(patterns)
      assert "guides" in patterns
      assert "/news/" in patterns
      assert "where-to-eat" in patterns
    end
  end

  describe "is_event_url?/1" do
    test "returns true for concert URLs" do
      url =
        "https://www.sortiraparis.com/concerts-music-festival/articles/319282-indochine-concert"

      assert Config.is_event_url?(url) == true
    end

    test "returns true for exhibition URLs" do
      url = "https://www.sortiraparis.com/exhibit-museum/articles/123-art-exhibition"
      assert Config.is_event_url?(url) == true
    end

    test "returns true for show URLs" do
      url = "https://www.sortiraparis.com/shows/articles/456-magic-show"
      assert Config.is_event_url?(url) == true
    end

    test "returns true for theater URLs" do
      url = "https://www.sortiraparis.com/theater/articles/789-shakespeare-play"
      assert Config.is_event_url?(url) == true
    end

    test "returns false for guide URLs" do
      url = "https://www.sortiraparis.com/guides/best-restaurants-paris"
      assert Config.is_event_url?(url) == false
    end

    test "returns false for news URLs" do
      url = "https://www.sortiraparis.com/news/paris-latest-updates"
      assert Config.is_event_url?(url) == false
    end

    test "returns false for where-to-eat URLs" do
      url = "https://www.sortiraparis.com/where-to-eat/restaurant-review"
      assert Config.is_event_url?(url) == false
    end

    test "returns false for what-to-do URLs" do
      url = "https://www.sortiraparis.com/what-to-do/activities-paris"
      assert Config.is_event_url?(url) == false
    end

    test "returns false for best-of URLs" do
      url = "https://www.sortiraparis.com/best-of/top-concerts-paris"
      assert Config.is_event_url?(url) == false
    end

    test "returns false for top- URLs" do
      url = "https://www.sortiraparis.com/top-things-to-do"
      assert Config.is_event_url?(url) == false
    end

    test "returns false when event category present but also has exclude pattern" do
      url = "https://www.sortiraparis.com/concerts-music-festival/guides/best-concerts"
      assert Config.is_event_url?(url) == false
    end

    test "returns false for URLs without event categories" do
      url = "https://www.sortiraparis.com/about-us"
      assert Config.is_event_url?(url) == false
    end
  end
end
