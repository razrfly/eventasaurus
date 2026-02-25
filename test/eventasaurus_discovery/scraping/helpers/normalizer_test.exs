defmodule EventasaurusDiscovery.Scraping.Helpers.NormalizerTest do
  use ExUnit.Case, async: true
  alias EventasaurusDiscovery.Scraping.Helpers.Normalizer

  describe "clean_html/1" do
    test "handles nil input" do
      assert Normalizer.clean_html(nil) == nil
    end

    test "removes HTML tags" do
      assert Normalizer.clean_html("<p>Hello <b>world</b></p>") == "Hello world"
      assert Normalizer.clean_html("<div><span>Test</span></div>") == "Test"

      assert Normalizer.clean_html("<article><h1>Title</h1><p>Content</p></article>") ==
               "Title Content"
    end

    test "normalizes whitespace" do
      assert Normalizer.clean_html("Multiple   spaces") == "Multiple spaces"
      assert Normalizer.clean_html("Line\n\nbreaks") == "Line breaks"
      assert Normalizer.clean_html("  Leading and trailing  ") == "Leading and trailing"
      assert Normalizer.clean_html("Mixed\t\ttabs   and    spaces") == "Mixed tabs and spaces"
    end

    test "decodes numeric apostrophe entities (&#039; - the original bug)" do
      # This was the specific bug in city names
      assert Normalizer.clean_html("L&#039;Aeroport") == "L'Aeroport"
      assert Normalizer.clean_html("d&#039;Orly") == "d'Orly"
      assert Normalizer.clean_html("Hay les Roses (L&#039;)") == "Hay les Roses (L')"
    end

    test "decodes short numeric apostrophe entities (&#39;)" do
      assert Normalizer.clean_html("L&#39;Aeroport") == "L'Aeroport"
      assert Normalizer.clean_html("d&#39;Orly") == "d'Orly"
    end

    test "decodes common HTML entities" do
      assert Normalizer.clean_html("rock&amp;roll") == "rock&roll"
      # &nbsp; decodes to non-breaking space (\u00A0), not regular space
      assert Normalizer.clean_html("Hello&nbsp;World") == "Hello\u00A0World"
      assert Normalizer.clean_html("&lt;tag&gt;") == "<tag>"
      assert Normalizer.clean_html("Say &quot;hello&quot;") == "Say \"hello\""
    end

    test "decodes French accented characters" do
      assert Normalizer.clean_html("caf&eacute;") == "café"
      assert Normalizer.clean_html("&agrave; Paris") == "à Paris"
      assert Normalizer.clean_html("&egrave;ve") == "ève"
      assert Normalizer.clean_html("&ecirc;tre") == "être"
      assert Normalizer.clean_html("ga&ccedil;on") == "gaçon"
    end

    test "decodes other European accented characters" do
      assert Normalizer.clean_html("ma&ntilde;ana") == "mañana"
      assert Normalizer.clean_html("&uuml;ber") == "über"
      assert Normalizer.clean_html("na&iuml;ve") == "naïve"
    end

    test "handles mixed entities in real-world content" do
      # From the original bug report - event description
      input =
        "rock&#039;n&#039;roll &amp; metal band will be presenting &quot;God Of Angels Trust&quot;"

      expected = "rock'n'roll & metal band will be presenting \"God Of Angels Trust\""
      assert Normalizer.clean_html(input) == expected
    end

    test "handles entities within HTML tags" do
      input = "<p>L&#039;exposition &agrave; Paris</p>"
      expected = "L'exposition à Paris"
      assert Normalizer.clean_html(input) == expected
    end

    test "handles complex real-world HTML with entities" do
      input = """
      <div class="description">
        <p>Visitez le mus&eacute;e d&#039;Orsay pour d&eacute;couvrir l&#039;art fran&ccedil;ais.</p>
        <p>Entr&eacute;e libre &amp; gratuite!</p>
      </div>
      """

      expected =
        "Visitez le musée d'Orsay pour découvrir l'art français. Entrée libre & gratuite!"

      assert Normalizer.clean_html(input) == expected
    end

    test "handles empty strings" do
      assert Normalizer.clean_html("") == ""
    end

    test "handles strings with only whitespace" do
      assert Normalizer.clean_html("   ") == ""
      assert Normalizer.clean_html("\n\n\n") == ""
    end

    test "handles strings with only HTML tags" do
      assert Normalizer.clean_html("<div></div>") == ""
      assert Normalizer.clean_html("<p><span></span></p>") == ""
    end

    test "preserves text content order" do
      input = "<article><h1>First</h1><p>Second</p><p>Third</p></article>"
      expected = "First Second Third"
      assert Normalizer.clean_html(input) == expected
    end

    test "handles numeric entities for other characters" do
      assert Normalizer.clean_html("&#169;") == "©"
      assert Normalizer.clean_html("&#8364;") == "€"
      assert Normalizer.clean_html("&#8211;") == "–"
      assert Normalizer.clean_html("&#8212;") == "—"
    end

    test "handles hex numeric entities" do
      assert Normalizer.clean_html("&#x27;") == "'"
      assert Normalizer.clean_html("&#xA9;") == "©"
      assert Normalizer.clean_html("&#xE9;") == "é"
    end
  end

  describe "normalize_text/1" do
    test "handles nil input" do
      assert Normalizer.normalize_text(nil) == nil
    end

    test "trims whitespace" do
      assert Normalizer.normalize_text("  hello  ") == "hello"
    end

    test "normalizes multiple spaces" do
      assert Normalizer.normalize_text("hello    world") == "hello world"
    end

    test "removes control characters" do
      assert Normalizer.normalize_text("hello\x00world") == "helloworld"
      assert Normalizer.normalize_text("test\x01\x02\x03") == "test"
    end

    test "preserves mathematical bold Unicode characters" do
      # RA promoters use mathematical bold Unicode (U+1D5D7 etc.)
      # These are multi-byte UTF-8 sequences that must not be corrupted
      assert Normalizer.normalize_text("𝗗𝗔𝗥𝗜𝗔 𝗞𝗢𝗟𝗢𝗦𝗢𝗩𝗔") == "𝗗𝗔𝗥𝗜𝗔 𝗞𝗢𝗟𝗢𝗦𝗢𝗩𝗔"
    end

    test "preserves other multi-byte UTF-8 characters" do
      assert Normalizer.normalize_text("café résumé") == "café résumé"
      assert Normalizer.normalize_text("日本語テスト") == "日本語テスト"
      assert Normalizer.normalize_text("Łódź Kraków") == "Łódź Kraków"
    end
  end

  describe "create_slug/1" do
    test "handles nil input" do
      assert Normalizer.create_slug(nil) == nil
    end

    test "converts to lowercase" do
      assert Normalizer.create_slug("Hello World") == "hello-world"
    end

    test "replaces spaces with hyphens" do
      assert Normalizer.create_slug("my test slug") == "my-test-slug"
    end

    test "removes special characters" do
      assert Normalizer.create_slug("hello!@#$%world") == "helloworld"
    end

    test "collapses multiple hyphens" do
      assert Normalizer.create_slug("hello---world") == "hello-world"
    end

    test "trims leading and trailing hyphens" do
      assert Normalizer.create_slug("-hello-world-") == "hello-world"
    end
  end

  describe "title_case/1" do
    test "handles nil input" do
      assert Normalizer.title_case(nil) == nil
    end

    test "capitalizes each word" do
      assert Normalizer.title_case("hello world") == "Hello World"
    end

    test "converts uppercase to title case" do
      assert Normalizer.title_case("HELLO WORLD") == "Hello World"
    end

    test "handles mixed case" do
      assert Normalizer.title_case("hELLo WoRLd") == "Hello World"
    end
  end
end
