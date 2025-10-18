defmodule EventasaurusDiscovery.Sources.Sortiraparis.Extractors.SitemapExtractorTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Sortiraparis.Extractors.SitemapExtractor

  describe "extract_urls/1" do
    test "extracts URLs from valid sitemap XML" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url>
          <loc>https://www.sortiraparis.com/articles/319282-indochine-concert</loc>
        </url>
        <url>
          <loc>https://www.sortiraparis.com/articles/123-louvre-exhibition</loc>
        </url>
      </urlset>
      """

      assert {:ok, urls} = SitemapExtractor.extract_urls(xml)
      assert length(urls) == 2
      assert "https://www.sortiraparis.com/articles/319282-indochine-concert" in urls
      assert "https://www.sortiraparis.com/articles/123-louvre-exhibition" in urls
    end

    test "handles empty sitemap" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      </urlset>
      """

      assert {:ok, urls} = SitemapExtractor.extract_urls(xml)
      assert urls == []
    end

    test "handles malformed XML gracefully" do
      xml = "<invalid>xml</invalid>"

      assert {:ok, urls} = SitemapExtractor.extract_urls(xml)
      assert urls == []
    end

    test "filters out invalid URLs" do
      xml = """
      <urlset>
        <url><loc>https://www.sortiraparis.com/valid</loc></url>
        <url><loc>not-a-url</loc></url>
        <url><loc></loc></url>
      </urlset>
      """

      assert {:ok, urls} = SitemapExtractor.extract_urls(xml)
      assert length(urls) == 1
      assert "https://www.sortiraparis.com/valid" in urls
    end

    test "returns error for non-binary input" do
      assert {:error, :invalid_xml_content} = SitemapExtractor.extract_urls(nil)
      assert {:error, :invalid_xml_content} = SitemapExtractor.extract_urls(123)
    end
  end

  describe "extract_urls_with_metadata/1" do
    test "extracts URLs with full metadata" do
      xml = """
      <urlset>
        <url>
          <loc>https://www.sortiraparis.com/articles/123</loc>
          <lastmod>2025-01-15T10:30:00+00:00</lastmod>
          <changefreq>weekly</changefreq>
          <priority>0.8</priority>
        </url>
      </urlset>
      """

      assert {:ok, [entry]} = SitemapExtractor.extract_urls_with_metadata(xml)
      assert entry.url == "https://www.sortiraparis.com/articles/123"
      assert entry.change_frequency == "weekly"
      assert entry.priority == 0.8
      assert entry.last_modified != nil
    end

    test "handles missing metadata gracefully" do
      xml = """
      <urlset>
        <url>
          <loc>https://www.sortiraparis.com/articles/123</loc>
        </url>
      </urlset>
      """

      assert {:ok, [entry]} = SitemapExtractor.extract_urls_with_metadata(xml)
      assert entry.url == "https://www.sortiraparis.com/articles/123"
      assert entry.change_frequency == nil
      assert entry.priority == nil
      assert entry.last_modified == nil
    end

    test "parses date-only lastmod" do
      xml = """
      <urlset>
        <url>
          <loc>https://www.sortiraparis.com/articles/123</loc>
          <lastmod>2025-01-15</lastmod>
        </url>
      </urlset>
      """

      assert {:ok, [entry]} = SitemapExtractor.extract_urls_with_metadata(xml)
      assert entry.last_modified != nil
    end
  end

  describe "extract_sitemap_index_urls/1" do
    test "extracts sitemap URLs from index" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <sitemap>
          <loc>https://www.sortiraparis.com/sitemap-en-1.xml</loc>
          <lastmod>2025-01-15</lastmod>
        </sitemap>
        <sitemap>
          <loc>https://www.sortiraparis.com/sitemap-en-2.xml</loc>
          <lastmod>2025-01-15</lastmod>
        </sitemap>
      </sitemapindex>
      """

      assert {:ok, urls} = SitemapExtractor.extract_sitemap_index_urls(xml)
      assert length(urls) == 2
      assert "https://www.sortiraparis.com/sitemap-en-1.xml" in urls
      assert "https://www.sortiraparis.com/sitemap-en-2.xml" in urls
    end

    test "handles empty sitemap index" do
      xml = """
      <sitemapindex>
      </sitemapindex>
      """

      assert {:ok, urls} = SitemapExtractor.extract_sitemap_index_urls(xml)
      assert urls == []
    end
  end
end
