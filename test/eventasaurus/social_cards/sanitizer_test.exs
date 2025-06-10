defmodule Eventasaurus.SocialCards.SanitizerTest do
  use ExUnit.Case, async: true

  alias Eventasaurus.SocialCards.Sanitizer

  describe "sanitize_event_data/1" do
    test "sanitizes and validates all event fields" do
      event = %{
        id: 123,
        title: "<script>alert('xss')</script>My Event",
        description: "<svg><rect/></svg>Event description & more",
        cover_image_url: "https://example.com/image.jpg",
        updated_at: ~N[2023-01-01 12:00:00]
      }

      result = Sanitizer.sanitize_event_data(event)

      assert result.id == 123
      assert result.title == "My Event"
      assert result.description == "Event description &amp; more"
      assert result.cover_image_url == "https://example.com/image.jpg"
      assert result.updated_at == ~N[2023-01-01 12:00:00]
    end

    test "handles missing fields gracefully" do
      event = %{id: 456}

      result = Sanitizer.sanitize_event_data(event)

      assert result.id == 456
      assert result.title == ""
      assert result.description == ""
      assert result.cover_image_url == nil
      assert result.updated_at == nil
    end

    test "sanitizes malicious image URLs" do
      event = %{
        id: 789,
        title: "Test Event",
        cover_image_url: "javascript:alert('xss')"
      }

      result = Sanitizer.sanitize_event_data(event)
      assert result.cover_image_url == nil
    end
  end

  describe "sanitize_theme_data/1" do
    test "validates and sanitizes color values" do
      theme = %{
        color1: "#ff0000",
        color2: "invalid-color"
      }

      result = Sanitizer.sanitize_theme_data(theme)

      assert result.color1 == "#ff0000"
      assert result.color2 == "#6E56CF"  # Default color
    end

    test "handles missing color fields" do
      theme = %{}

      result = Sanitizer.sanitize_theme_data(theme)

      assert result.color1 == "#6E56CF"
      assert result.color2 == "#6E56CF"
    end
  end

  describe "sanitize_text/1" do
    test "removes HTML/XML tags" do
      assert Sanitizer.sanitize_text("<script>alert('xss')</script>Hello") == "Hello"
      assert Sanitizer.sanitize_text("<svg><rect/></svg>My Event") == "My Event"
      assert Sanitizer.sanitize_text("<b>Bold</b> and <i>italic</i>") == "Bold and italic"
    end

    test "removes HTML entities" do
      assert Sanitizer.sanitize_text("Hello &nbsp; World &amp; More") == "Hello  World  More"
      assert Sanitizer.sanitize_text("Test &#x3C;script&#x3E;") == "Test script"
    end

    test "escapes XML special characters" do
      assert Sanitizer.sanitize_text("Hello & World") == "Hello &amp; World"
      assert Sanitizer.sanitize_text("Title with \"quotes\" and 'apostrophes'") == "Title with &quot;quotes&quot; and &apos;apostrophes&apos;"
      assert Sanitizer.sanitize_text("Test < and > symbols") == "Test &lt; and &gt; symbols"
    end

    test "removes control characters" do
      text_with_control_chars = "Hello\x00\x01\x7FWorld"
      assert Sanitizer.sanitize_text(text_with_control_chars) == "HelloWorld"
    end

    test "truncates extremely long text" do
      long_text = String.duplicate("A", 250)
      result = Sanitizer.sanitize_text(long_text)

      assert String.length(result) == 203  # 200 chars + "..."
      assert String.ends_with?(result, "...")
    end

    test "handles edge cases" do
      assert Sanitizer.sanitize_text("") == ""
      assert Sanitizer.sanitize_text("   ") == ""
      assert Sanitizer.sanitize_text(nil) == ""
      assert Sanitizer.sanitize_text(123) == ""
      assert Sanitizer.sanitize_text(%{}) == ""
    end

    test "preserves valid text" do
      assert Sanitizer.sanitize_text("Hello World") == "Hello World"
      assert Sanitizer.sanitize_text("Event 2023") == "Event 2023"
      assert Sanitizer.sanitize_text("My-Event_Name") == "My-Event_Name"
    end

    test "complex SVG injection attempts" do
      malicious_svg = """
      <svg onload="alert('XSS')">
        <script>malicious code</script>
        <image href="javascript:alert('XSS')"/>
        <text>Innocent text</text>
      </svg>
      """

      result = Sanitizer.sanitize_text(malicious_svg)
      assert result == "Innocent text"
      refute String.contains?(result, "script")
      refute String.contains?(result, "onload")
      refute String.contains?(result, "javascript:")
    end
  end

  describe "validate_image_url/1" do
    test "accepts valid HTTP/HTTPS URLs" do
      valid_urls = [
        "https://example.com/image.jpg",
        "http://example.com/image.png",
        "https://cdn.example.com/path/to/image.gif",
        "https://example.com/image.jpg?size=large&format=webp"
      ]

      for url <- valid_urls do
        assert Sanitizer.validate_image_url(url) == url
      end
    end

    test "rejects malicious URLs" do
      malicious_urls = [
        "javascript:alert('xss')",
        "data:text/html,<script>alert('xss')</script>",
        "vbscript:msgbox('xss')",
        "https://example.com/image.jpg<script>alert('xss')</script>",
        "https://example.com/image.jpg>malicious",
        "ftp://example.com/image.jpg",
        "file:///etc/passwd"
      ]

      for url <- malicious_urls do
        assert Sanitizer.validate_image_url(url) == nil
      end
    end

    test "rejects invalid URL formats" do
      invalid_urls = [
        "not-a-url",
        "://missing-protocol",
        "https://",
        "https:// space-in-url.com",
        "https://example.com image.jpg",  # Space in URL
        ""
      ]

      for url <- invalid_urls do
        assert Sanitizer.validate_image_url(url) == nil
      end
    end

    test "handles edge cases" do
      assert Sanitizer.validate_image_url(nil) == nil
      assert Sanitizer.validate_image_url(123) == nil
      assert Sanitizer.validate_image_url(%{}) == nil
      assert Sanitizer.validate_image_url([]) == nil
    end
  end

  describe "validate_color/1" do
    test "accepts valid hex colors" do
      valid_colors = [
        "#000",           # 3-digit hex
        "#fff",           # 3-digit hex
        "#ff0000",        # 6-digit hex
        "#00FF00",        # 6-digit hex (uppercase)
        "#0000ffaa"       # 8-digit hex with alpha
      ]

      for color <- valid_colors do
        result = Sanitizer.validate_color(color)
        assert String.downcase(result) == String.downcase(color)
      end
    end

    test "normalizes hex colors to lowercase" do
      assert Sanitizer.validate_color("#FF0000") == "#ff0000"
      assert Sanitizer.validate_color("#ABC") == "#abc"
    end

    test "rejects invalid color formats" do
      invalid_colors = [
        "red",
        "rgb(255, 0, 0)",
        "hsl(0, 100%, 50%)",
        "#gg0000",        # Invalid hex characters
        "#12345",         # Invalid length
        "#1234567",       # Invalid length
        "123456",         # Missing #
        "",
        "#"
      ]

      for color <- invalid_colors do
        assert Sanitizer.validate_color(color) == "#6E56CF"
      end
    end

    test "handles edge cases" do
      assert Sanitizer.validate_color(nil) == "#6E56CF"
      assert Sanitizer.validate_color(123) == "#6E56CF"
      assert Sanitizer.validate_color(%{}) == "#6E56CF"
      assert Sanitizer.validate_color([]) == "#6E56CF"
    end
  end
end
