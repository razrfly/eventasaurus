defmodule Eventasaurus.CDNTest do
  use ExUnit.Case, async: false

  alias Eventasaurus.CDN

  # Store original config to restore after tests
  setup do
    original_cdn = Application.get_env(:eventasaurus, :cdn, nil)

    on_exit(fn ->
      if is_nil(original_cdn) do
        Application.delete_env(:eventasaurus, :cdn)
      else
        Application.put_env(:eventasaurus, :cdn, original_cdn)
      end
    end)

    :ok
  end

  describe "url/2 when CDN is disabled" do
    setup do
      Application.put_env(:eventasaurus, :cdn, enabled: false, domain: "cdn.wombie.com")
      :ok
    end

    test "returns original URL unchanged" do
      url = "https://example.com/image.jpg"
      assert CDN.url(url) == url
    end

    test "returns original URL even with transformation options" do
      url = "https://example.com/image.jpg"
      assert CDN.url(url, width: 800, quality: 90) == url
    end

    test "handles nil URL" do
      assert CDN.url(nil) == nil
    end

    test "handles empty string URL" do
      assert CDN.url("") == ""
    end
  end

  describe "url/2 when CDN is enabled" do
    setup do
      Application.put_env(:eventasaurus, :cdn, enabled: true, domain: "cdn.wombie.com")
      :ok
    end

    test "wraps URL without transformations" do
      url = "https://example.com/image.jpg"
      result = CDN.url(url)

      assert result == "https://cdn.wombie.com/cdn-cgi/image/https://example.com/image.jpg"
    end

    test "wraps URL with single transformation option" do
      url = "https://example.com/image.jpg"
      result = CDN.url(url, width: 800)

      assert result ==
               "https://cdn.wombie.com/cdn-cgi/image/width=800/https://example.com/image.jpg"
    end

    test "wraps URL with multiple transformation options" do
      url = "https://example.com/image.jpg"
      result = CDN.url(url, width: 800, quality: 90)

      # Options can be in any order, so we check both possibilities
      assert result in [
               "https://cdn.wombie.com/cdn-cgi/image/width=800,quality=90/https://example.com/image.jpg",
               "https://cdn.wombie.com/cdn-cgi/image/quality=90,width=800/https://example.com/image.jpg"
             ]
    end

    test "normalizes width option from 'w' to 'width'" do
      url = "https://example.com/image.jpg"
      result = CDN.url(url, w: 800)

      assert String.contains?(result, "width=800")
    end

    test "normalizes height option from 'h' to 'height'" do
      url = "https://example.com/image.jpg"
      result = CDN.url(url, h: 600)

      assert String.contains?(result, "height=600")
    end

    test "normalizes quality option from 'q' to 'quality'" do
      url = "https://example.com/image.jpg"
      result = CDN.url(url, q: 85)

      assert String.contains?(result, "quality=85")
    end

    test "normalizes format option from 'f' to 'format'" do
      url = "https://example.com/image.jpg"
      result = CDN.url(url, f: "webp")

      assert String.contains?(result, "format=webp")
    end

    test "supports fit option" do
      url = "https://example.com/image.jpg"
      result = CDN.url(url, fit: "cover")

      assert String.contains?(result, "fit=cover")
    end

    test "supports dpr option" do
      url = "https://example.com/image.jpg"
      result = CDN.url(url, dpr: 2)

      assert String.contains?(result, "dpr=2")
    end

    test "ignores unknown options" do
      url = "https://example.com/image.jpg"
      result = CDN.url(url, width: 800, unknown_option: "value")

      assert String.contains?(result, "width=800")
      refute String.contains?(result, "unknown_option")
    end

    test "handles complex transformation combination" do
      url = "https://example.com/image.jpg"
      result = CDN.url(url, width: 1200, height: 800, fit: "cover", quality: 85, format: "webp")

      assert String.starts_with?(result, "https://cdn.wombie.com/cdn-cgi/image/")
      assert String.ends_with?(result, "/https://example.com/image.jpg")
      assert String.contains?(result, "width=1200")
      assert String.contains?(result, "height=800")
      assert String.contains?(result, "fit=cover")
      assert String.contains?(result, "quality=85")
      assert String.contains?(result, "format=webp")
    end

    test "does not double-wrap already CDN URLs" do
      cdn_url =
        "https://cdn.wombie.com/cdn-cgi/image/width=800/https://example.com/image.jpg"

      result = CDN.url(cdn_url)

      # Should return the URL unchanged, not wrap it again
      assert result == cdn_url
    end

    test "does not wrap Unsplash URLs (they have their own CDN)" do
      unsplash_url = "https://images.unsplash.com/photo-1234?w=800&q=85&fit=crop"

      result = CDN.url(unsplash_url, width: 1200, quality: 90)

      # Unsplash URLs should be returned as-is, not wrapped in our CDN
      assert result == unsplash_url
    end

    test "handles nil URL even when CDN is enabled" do
      assert CDN.url(nil) == nil
    end

    test "handles empty string URL even when CDN is enabled" do
      assert CDN.url("") == ""
    end

    test "returns original URL for invalid URLs" do
      invalid_url = "not-a-valid-url"
      assert CDN.url(invalid_url) == invalid_url
    end

    test "returns original URL for URLs without scheme" do
      url_without_scheme = "example.com/image.jpg"
      assert CDN.url(url_without_scheme) == url_without_scheme
    end

    test "handles URLs with query parameters" do
      url = "https://example.com/image.jpg?size=large&v=2"
      result = CDN.url(url, width: 800)

      assert String.contains?(result, "width=800")
      assert String.ends_with?(result, "/https://example.com/image.jpg?size=large&v=2")
    end

    test "handles URLs with fragments" do
      url = "https://example.com/image.jpg#section"
      result = CDN.url(url, width: 800)

      assert String.contains?(result, "width=800")
      assert String.ends_with?(result, "/https://example.com/image.jpg#section")
    end
  end

  describe "url/2 with custom domain" do
    setup do
      Application.put_env(:eventasaurus, :cdn,
        enabled: true,
        domain: "custom-cdn.example.com"
      )

      :ok
    end

    test "uses custom domain from configuration" do
      url = "https://example.com/image.jpg"
      result = CDN.url(url, width: 800)

      assert String.starts_with?(result, "https://custom-cdn.example.com/cdn-cgi/image/")
    end

    test "detects custom domain URLs as already CDN URLs" do
      cdn_url =
        "https://custom-cdn.example.com/cdn-cgi/image/width=800/https://example.com/image.jpg"

      result = CDN.url(cdn_url)

      # Should not double-wrap
      assert result == cdn_url
    end
  end

  describe "real-world usage examples" do
    setup do
      Application.put_env(:eventasaurus, :cdn, enabled: true, domain: "cdn.wombie.com")
      :ok
    end

    test "event image with standard options" do
      url = "https://upload.wikimedia.org/wikipedia/commons/4/43/Bonnet_macaque.jpg"
      result = CDN.url(url, width: 800, quality: 90)

      assert String.starts_with?(result, "https://cdn.wombie.com/cdn-cgi/image/")
      assert String.ends_with?(result, "/#{url}")
      assert String.contains?(result, "width=800")
      assert String.contains?(result, "quality=90")
    end

    test "responsive image with multiple sizes" do
      url = "https://example.com/hero.jpg"

      # Thumbnail
      thumbnail = CDN.url(url, width: 400, height: 300, fit: "cover", quality: 85)
      assert String.contains?(thumbnail, "width=400")
      assert String.contains?(thumbnail, "height=300")

      # Desktop
      desktop = CDN.url(url, width: 1200, quality: 90)
      assert String.contains?(desktop, "width=1200")

      # Mobile retina
      mobile_retina = CDN.url(url, width: 800, dpr: 2, format: "webp")
      assert String.contains?(mobile_retina, "width=800")
      assert String.contains?(mobile_retina, "dpr=2")
      assert String.contains?(mobile_retina, "format=webp")
    end

    test "avatar image optimization" do
      url = "https://api.dicebear.com/9.x/dylan/svg?seed=user123"
      result = CDN.url(url, width: 200, format: "webp", quality: 85)

      assert String.contains?(result, "width=200")
      assert String.contains?(result, "format=webp")
      assert String.contains?(result, "quality=85")
    end
  end

  describe "edge cases" do
    setup do
      Application.put_env(:eventasaurus, :cdn, enabled: true, domain: "cdn.wombie.com")
      :ok
    end

    test "handles URL with special characters" do
      url = "https://example.com/image%20with%20spaces.jpg"
      result = CDN.url(url, width: 800)

      assert String.contains?(result, "width=800")
      assert String.ends_with?(result, "/#{url}")
    end

    test "handles very long URLs" do
      long_path = String.duplicate("very-long-path/", 50)
      url = "https://example.com/#{long_path}image.jpg"
      result = CDN.url(url, width: 800)

      assert String.contains?(result, "width=800")
      assert String.ends_with?(result, "/#{url}")
    end

    test "handles URL with port number" do
      url = "https://example.com:8080/image.jpg"
      result = CDN.url(url, width: 800)

      assert String.contains?(result, "width=800")
      assert String.ends_with?(result, "/#{url}")
    end

    test "handles URL with authentication" do
      url = "https://user:pass@example.com/image.jpg"
      result = CDN.url(url, width: 800)

      assert String.contains?(result, "width=800")
      assert String.ends_with?(result, "/#{url}")
    end

    test "handles data URIs" do
      data_uri = "data:image/png;base64,iVBORw0KGgoAAAANS"
      result = CDN.url(data_uri)

      # Data URIs should be returned as-is (invalid URL)
      assert result == data_uri
    end
  end
end
