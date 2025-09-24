defmodule EventasaurusWeb.Live.Components.RichDataDisplayComponentTest do
  use ExUnit.Case, async: true
  alias EventasaurusWeb.Live.Components.RichDataDisplayComponent

  describe "tmdb_image_url/2" do
    test "returns nil for nil path" do
      assert nil == RichDataDisplayComponent.tmdb_image_url(nil, "w500")
    end

    test "returns nil for empty path" do
      assert nil == RichDataDisplayComponent.tmdb_image_url("", "w500")
    end

    test "builds correct URL for valid TMDB path" do
      expected = "https://image.tmdb.org/t/p/w500/abc123.jpg"
      assert expected == RichDataDisplayComponent.tmdb_image_url("/abc123.jpg", "w500")
    end

    test "builds correct URL for different sizes" do
      path = "/abc123.jpg"

      assert "https://image.tmdb.org/t/p/w300/abc123.jpg" ==
               RichDataDisplayComponent.tmdb_image_url(path, "w300")

      assert "https://image.tmdb.org/t/p/original/abc123.jpg" ==
               RichDataDisplayComponent.tmdb_image_url(path, "original")
    end

    test "defaults to w500 size when size not provided" do
      expected = "https://image.tmdb.org/t/p/w500/test.jpg"
      assert expected == RichDataDisplayComponent.tmdb_image_url("/test.jpg")
    end

    test "returns nil for invalid path format" do
      assert nil == RichDataDisplayComponent.tmdb_image_url("invalid-path", "w500")
      assert nil == RichDataDisplayComponent.tmdb_image_url("/invalid", "w500")
      assert nil == RichDataDisplayComponent.tmdb_image_url("/path-without-extension", "w500")
    end

    test "works with different valid file extensions" do
      assert "https://image.tmdb.org/t/p/w500/test.png" ==
               RichDataDisplayComponent.tmdb_image_url("/test.png", "w500")

      assert "https://image.tmdb.org/t/p/w500/test.webp" ==
               RichDataDisplayComponent.tmdb_image_url("/test.webp", "w500")

      assert "https://image.tmdb.org/t/p/w500/test.jpeg" ==
               RichDataDisplayComponent.tmdb_image_url("/test.jpeg", "w500")
    end

    test "handles paths with valid special characters" do
      assert "https://image.tmdb.org/t/p/w500/test_123-abc.jpg" ==
               RichDataDisplayComponent.tmdb_image_url("/test_123-abc.jpg", "w500")

      assert "https://image.tmdb.org/t/p/w500/test.name.jpg" ==
               RichDataDisplayComponent.tmdb_image_url("/test.name.jpg", "w500")
    end

    test "returns nil for non-string arguments" do
      assert nil == RichDataDisplayComponent.tmdb_image_url(123, "w500")
      assert nil == RichDataDisplayComponent.tmdb_image_url("/test.jpg", 500)
    end
  end
end
