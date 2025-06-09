defmodule EventasaurusWeb.SocialCardViewTest do
  use ExUnit.Case, async: true

  alias EventasaurusWeb.SocialCardView

  describe "format_title/3" do
        test "splits long title into multiple lines" do
      title = "This is a very long event title that should be split across multiple lines"

      line_0 = SocialCardView.format_title(title, 0, 25)
      line_1 = SocialCardView.format_title(title, 1, 25)
      line_2 = SocialCardView.format_title(title, 2, 25)

      assert line_0 == "This is a very long event"
      assert line_1 == "title that should be"
      assert line_2 == "split across multiple"
    end

    test "handles short titles" do
      title = "Short Title"

      line_0 = SocialCardView.format_title(title, 0)
      line_1 = SocialCardView.format_title(title, 1)
      line_2 = SocialCardView.format_title(title, 2)

      assert line_0 == "Short Title"
      assert line_1 == ""
      assert line_2 == ""
    end

    test "limits to 3 lines maximum" do
      title = "This is an extremely long event title that would normally span many lines but should be limited to only three lines maximum"

      line_0 = SocialCardView.format_title(title, 0, 20)
      line_1 = SocialCardView.format_title(title, 1, 20)
      line_2 = SocialCardView.format_title(title, 2, 20)
      line_3 = SocialCardView.format_title(title, 3, 20)

      assert line_0 != ""
      assert line_1 != ""
      assert line_2 != ""
      assert line_3 == ""
    end

    test "handles single long word" do
      title = "Supercalifragilisticexpialidocious"

      line_0 = SocialCardView.format_title(title, 0, 10)
      line_1 = SocialCardView.format_title(title, 1, 10)

      assert line_0 == "Supercalifragilisticexpialidocious"
      assert line_1 == ""
    end

        test "escapes special characters" do
      title = "Event with <script> & \"quotes\""

      line_0 = SocialCardView.format_title(title, 0)

      assert line_0 == "Event with &lt;script&gt; &amp;"
    end

    test "handles nil and non-string inputs" do
      assert SocialCardView.format_title(nil, 0) == ""
      assert SocialCardView.format_title(123, 0) == ""
      assert SocialCardView.format_title(%{}, 0) == ""
    end
  end

  describe "svg_escape/1" do
    test "escapes HTML/XML special characters" do
      text = "Test & <script>alert('xss')</script> \"quotes\" 'apostrophes'"
      expected = "Test &amp; &lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt; &quot;quotes&quot; &#39;apostrophes&#39;"

      assert SocialCardView.svg_escape(text) == expected
    end

    test "handles nil input" do
      assert SocialCardView.svg_escape(nil) == ""
    end

    test "handles empty string" do
      assert SocialCardView.svg_escape("") == ""
    end
  end

  describe "format_color/1" do
    test "adds # prefix to hex colors without it" do
      assert SocialCardView.format_color("ff0000") == "#ff0000"
      assert SocialCardView.format_color("123abc") == "#123abc"
    end

    test "preserves # prefix when already present" do
      assert SocialCardView.format_color("#ff0000") == "#ff0000"
      assert SocialCardView.format_color("#123abc") == "#123abc"
    end

    test "handles invalid inputs" do
      assert SocialCardView.format_color(nil) == "#000000"
      assert SocialCardView.format_color(123) == "#000000"
      assert SocialCardView.format_color(%{}) == "#000000"
    end
  end

  describe "calculate_font_size/1" do
    test "returns larger font size for short titles" do
      assert SocialCardView.calculate_font_size("Short") == "48"
    end

    test "returns medium font size for medium titles" do
      assert SocialCardView.calculate_font_size("This is a medium length title") == "42"
    end

    test "returns smaller font size for long titles" do
      assert SocialCardView.calculate_font_size("This is a very long title that should use smaller font") == "36"
    end

    test "returns smallest font size for very long titles" do
      long_title = "This is an extremely long title that definitely exceeds sixty characters and should use the smallest font size"
      assert SocialCardView.calculate_font_size(long_title) == "32"
    end

    test "handles nil and non-string inputs" do
      assert SocialCardView.calculate_font_size(nil) == "42"
      assert SocialCardView.calculate_font_size(123) == "42"
    end
  end

  describe "has_image?/1" do
    test "returns true for valid image URL" do
      event = %{image_url: "https://example.com/image.jpg"}
      assert SocialCardView.has_image?(event) == true
    end

    test "returns false for empty image URL" do
      event = %{image_url: ""}
      assert SocialCardView.has_image?(event) == false
    end

    test "returns false for nil image URL" do
      event = %{image_url: nil}
      assert SocialCardView.has_image?(event) == false
    end

    test "returns false for missing image_url field" do
      event = %{title: "Event without image"}
      assert SocialCardView.has_image?(event) == false
    end
  end

  describe "safe_image_url/1" do
    test "returns escaped URL for valid image" do
      event = %{image_url: "https://example.com/image.jpg?param=value&other=test"}
      expected = "https://example.com/image.jpg?param=value&amp;other=test"
      assert SocialCardView.safe_image_url(event) == expected
    end

    test "returns nil for empty image URL" do
      event = %{image_url: ""}
      assert SocialCardView.safe_image_url(event) == nil
    end

    test "returns nil for nil image URL" do
      event = %{image_url: nil}
      assert SocialCardView.safe_image_url(event) == nil
    end

    test "returns nil for missing image_url field" do
      event = %{title: "Event without image"}
      assert SocialCardView.safe_image_url(event) == nil
    end
  end
end
