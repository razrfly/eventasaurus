defmodule EventasaurusDiscovery.Sources.Kupbilecik.Extractors.EventExtractorTest do
  @moduledoc """
  Tests for the Kupbilecik EventExtractor module.

  Tests extraction of event data from server-side rendered HTML pages.
  Kupbilecik uses SSR, so all data is available in the initial HTML response.
  """
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Kupbilecik.Extractors.EventExtractor

  describe "extract/2" do
    test "extracts complete event data from valid HTML" do
      html = """
      <!DOCTYPE html>
      <html>
      <head>
        <meta property="og:title" content="Test Concert - Amazing Band">
        <meta property="og:description" content="An incredible night of music.">
        <meta property="og:image" content="https://www.kupbilecik.pl/images/event123.jpg">
      </head>
      <body>
        <h1>Test Concert - Amazing Band</h1>
        <div class="event-date">15 grudnia 2025 o godz. 20:00</div>
      </body>
      </html>
      """

      url = "https://www.kupbilecik.pl/imprezy/123456/test-concert/"

      assert {:ok, event_data} = EventExtractor.extract(html, url)
      assert event_data["title"] == "Test Concert - Amazing Band"
      assert event_data["date_string"] == "15 grudnia 2025 o godz. 20:00"
      assert event_data["url"] == url
    end

    test "returns error for HTML missing required title" do
      html = """
      <!DOCTYPE html>
      <html>
      <head></head>
      <body>
        <div class="event-date">15 grudnia 2025 o godz. 20:00</div>
      </body>
      </html>
      """

      url = "https://www.kupbilecik.pl/imprezy/123456/"

      assert {:error, :title_not_found} = EventExtractor.extract(html, url)
    end

    test "returns error for HTML missing required date" do
      html = """
      <!DOCTYPE html>
      <html>
      <head>
        <meta property="og:title" content="Test Event">
      </head>
      <body>
        <h1>Test Event</h1>
      </body>
      </html>
      """

      url = "https://www.kupbilecik.pl/imprezy/123456/"

      assert {:error, :date_not_found} = EventExtractor.extract(html, url)
    end
  end

  describe "extract_description/1" do
    test "extracts description from og:description meta tag" do
      html = """
      <html>
      <head>
        <meta property="og:description" content="This is a great event.">
      </head>
      <body></body>
      </html>
      """

      assert EventExtractor.extract_description(html) == "This is a great event."
    end

    test "falls back to meta description when og:description missing" do
      html = """
      <html>
      <head>
        <meta name="description" content="Fallback description.">
      </head>
      <body></body>
      </html>
      """

      assert EventExtractor.extract_description(html) == "Fallback description."
    end

    test "returns nil when no description found" do
      html = """
      <html>
      <head></head>
      <body><h1>Just a title</h1></body>
      </html>
      """

      assert EventExtractor.extract_description(html) == nil
    end
  end

  describe "extract_performers/1" do
    test "extracts performers from strong tags" do
      html = """
      <html>
      <body>
        <p><strong>Anna Kowalska</strong> - główna rola</p>
        <p><strong>Jan Nowak</strong> - drugoplanowa</p>
      </body>
      </html>
      """

      performers = EventExtractor.extract_performers(html)
      assert is_list(performers)
    end

    test "filters out non-name content from strong tags" do
      html = """
      <html>
      <body>
        <p><strong>Cena: 120 zł</strong></p>
        <p><strong>Godz. 20:00</strong></p>
        <p><strong>Adam Performer</strong></p>
      </body>
      </html>
      """

      performers = EventExtractor.extract_performers(html)
      assert is_list(performers)
      refute Enum.any?(performers, &String.contains?(&1, "zł"))
      refute Enum.any?(performers, &String.contains?(&1, "Godz"))
    end

    test "returns empty list when no performers found" do
      html = """
      <html>
      <body>
        <h1>Event without cast information</h1>
      </body>
      </html>
      """

      assert EventExtractor.extract_performers(html) == []
    end

    test "filters out production crew labels from strong tags" do
      html = """
      <html>
      <body>
        <p><strong>Scenariusz:</strong> Krzysztof Kowalski</p>
        <p><strong>Reżyseria:</strong> Jan Nowak</p>
        <p><strong>Producent:</strong> Adam Wiśniewski</p>
        <p><strong>Maria Performer</strong></p>
      </body>
      </html>
      """

      performers = EventExtractor.extract_performers(html)
      # Only the actual performer should be extracted, not crew labels
      refute Enum.any?(performers, &String.contains?(&1, "Scenariusz"))
      refute Enum.any?(performers, &String.contains?(&1, "Reżyseria"))
      refute Enum.any?(performers, &String.contains?(&1, "Producent"))
    end

    test "filters out names that are too long (over 100 chars)" do
      # Create a very long name that would exceed DB column limit
      long_name = String.duplicate("a", 150)

      html = """
      <html>
      <body>
        <p><strong>#{long_name}</strong></p>
        <p><strong>Valid Performer Name</strong></p>
      </body>
      </html>
      """

      performers = EventExtractor.extract_performers(html)
      # Long name should be filtered out
      refute Enum.any?(performers, &(String.length(&1) > 100))
    end
  end

  describe "extract_category/2" do
    test "extracts category from href path in breadcrumb" do
      html = """
      <html>
      <body>
        <nav class="breadcrumb">
          <a href="/">Home</a>
          <a href="/kabarety/">Występy kabaretowe</a>
        </nav>
      </body>
      </html>
      """

      url = "https://www.kupbilecik.pl/imprezy/123456/"

      category = EventExtractor.extract_category(html, url)
      assert category == "kabarety"
    end

    test "extracts concert category from href" do
      html = """
      <html>
      <body>
        <a href="/koncerty/">Koncerty</a>
      </body>
      </html>
      """

      url = "https://www.kupbilecik.pl/imprezy/123456/"

      category = EventExtractor.extract_category(html, url)
      assert category == "koncerty"
    end

    test "extracts theater category from href" do
      html = """
      <html>
      <body>
        <a href="/teatr/">Teatr</a>
      </body>
      </html>
      """

      url = "https://www.kupbilecik.pl/imprezy/123456/"

      category = EventExtractor.extract_category(html, url)
      assert category == "teatr"
    end

    test "extracts inne (other) category from href" do
      html = """
      <html>
      <body>
        <a href="/inne/">Inne rodzaje występów</a>
      </body>
      </html>
      """

      url = "https://www.kupbilecik.pl/imprezy/123456/"

      category = EventExtractor.extract_category(html, url)
      assert category == "inne"
    end

    test "returns nil when no category found" do
      html = """
      <html>
      <body>
        <h1>Generic Event</h1>
      </body>
      </html>
      """

      url = "https://www.kupbilecik.pl/imprezy/123456/"

      category = EventExtractor.extract_category(html, url)
      assert is_nil(category)
    end
  end

  describe "extract_title/1" do
    test "extracts title from og:title meta tag" do
      html = """
      <html>
      <head>
        <meta property="og:title" content="Amazing Concert 2025">
      </head>
      <body></body>
      </html>
      """

      assert {:ok, "Amazing Concert 2025"} = EventExtractor.extract_title(html)
    end

    test "extracts title from h1 tag when og:title missing" do
      html = """
      <html>
      <head></head>
      <body>
        <h1>Concert Title from H1</h1>
      </body>
      </html>
      """

      assert {:ok, "Concert Title from H1"} = EventExtractor.extract_title(html)
    end

    test "returns error when no title found" do
      html = """
      <html>
      <head></head>
      <body>
        <p>No title here</p>
      </body>
      </html>
      """

      assert {:error, :title_not_found} = EventExtractor.extract_title(html)
    end
  end

  describe "extract_date_string/1" do
    test "extracts Polish date string" do
      html = """
      <html>
      <body>
        <div class="event-date">20 stycznia 2025 o godz. 19:30</div>
      </body>
      </html>
      """

      assert {:ok, date_string} = EventExtractor.extract_date_string(html)
      assert String.contains?(date_string, "stycznia")
      assert String.contains?(date_string, "2025")
    end

    test "returns error when no date found" do
      html = """
      <html>
      <body>
        <p>No date information</p>
      </body>
      </html>
      """

      assert {:error, :date_not_found} = EventExtractor.extract_date_string(html)
    end
  end

  describe "extract_venue/1" do
    test "returns map for venue information" do
      html = """
      <html>
      <body>
        <div class="venue">
          <span class="name">Teatr Wielki</span>
        </div>
      </body>
      </html>
      """

      venue = EventExtractor.extract_venue(html)
      assert is_map(venue)
    end

    test "returns empty map when no venue found" do
      html = """
      <html>
      <body>
        <h1>Event Title</h1>
      </body>
      </html>
      """

      venue = EventExtractor.extract_venue(html)
      assert is_map(venue)
    end

    test "extracts venue name from /obiekty/ link with bold wrapper" do
      html = """
      <html>
      <body>
        <h3><a href="/obiekty/5453/Teatr+%C5%BBelazny/" title="Teatr Żelazny bilety"><b>Teatr Żelazny</b></a>, Ul. Gliwicka 148a</h3>
      </body>
      </html>
      """

      venue = EventExtractor.extract_venue(html)
      assert venue.name == "Teatr Żelazny"
    end

    test "extracts address from h3 with venue link" do
      html = """
      <html>
      <body>
        <h3><a href="/obiekty/5453/Test+Venue/"><b>Test Venue</b></a>, Ul. Gliwicka 148a</h3>
      </body>
      </html>
      """

      venue = EventExtractor.extract_venue(html)
      assert venue.address == "Ul. Gliwicka 148a"
    end

    test "extracts city from /miasta/ link" do
      html = """
      <html>
      <body>
        <h2><a href="/miasta/61/Katowice/" title="Katowice bilety"><b>Katowice</b></a></h2>
        <h3><a href="/obiekty/123/Test/"><b>Test</b></a>, Address</h3>
      </body>
      </html>
      """

      venue = EventExtractor.extract_venue(html)
      assert venue.city == "Katowice"
    end

    test "extracts city from URL when not found in HTML" do
      html = """
      <html>
      <body>
        <h3><a href="/obiekty/123/Test/"><b>Test</b></a>, Address</h3>
      </body>
      </html>
      """

      url = "https://www.kupbilecik.pl/imprezy/175576/Warszawa/Event-Slug/"
      venue = EventExtractor.extract_venue(html, url)
      assert venue.city == "Warszawa"
    end

    test "extracts all venue components from real Kupbilecik HTML structure" do
      html = """
      <html>
      <body>
        <h2><a href="/miasta/61/Katowice/" title="Katowice bilety"><b>Katowice</b></a></h2>
        <h3><a href="/obiekty/5453/Teatr+%C5%BBelazny/" title="Teatr Żelazny bilety"><b>Teatr Żelazny</b></a>, Ul. Gliwicka 148a</h3>
      </body>
      </html>
      """

      venue = EventExtractor.extract_venue(html)
      assert venue.name == "Teatr Żelazny"
      assert venue.address == "Ul. Gliwicka 148a"
      assert venue.city == "Katowice"
    end
  end

  describe "extract_image_url/1" do
    test "extracts image from og:image meta tag" do
      html = """
      <html>
      <head>
        <meta property="og:image" content="https://www.kupbilecik.pl/images/event.jpg">
      </head>
      <body></body>
      </html>
      """

      assert EventExtractor.extract_image_url(html) ==
               "https://www.kupbilecik.pl/images/event.jpg"
    end

    test "returns nil when no image found" do
      html = """
      <html>
      <head></head>
      <body></body>
      </html>
      """

      assert EventExtractor.extract_image_url(html) == nil
    end
  end

  describe "extract_price/1" do
    test "extracts single price from HTML" do
      html = """
      <html>
      <body>
        <span class="price">od 89 zł</span>
      </body>
      </html>
      """

      price = EventExtractor.extract_price(html)
      assert price == "od 89 zł"
    end

    test "extracts prices from bullet point list format" do
      html = """
      <html>
      <body>
        <p>Bilety:</p>
        <ul>
          <li>Dorośli (powyżej 18 r.ż.) - 55 zł</li>
          <li>Studenci - 40 zł</li>
          <li>Dzieci (do 9 r.ż.) - bezpłatnie</li>
        </ul>
      </body>
      </html>
      """

      price = EventExtractor.extract_price(html)
      # Should return price range for multiple prices
      assert price == "40-55 zł"
    end

    test "extracts single price from bullet point format" do
      html = """
      <html>
      <body>
        <p>* Bilety - 99 zł</p>
      </body>
      </html>
      """

      price = EventExtractor.extract_price(html)
      assert price == "od 99 zł"
    end

    test "returns nil when price not in HTML" do
      html = """
      <html>
      <body>
        <h1>Event without visible price</h1>
      </body>
      </html>
      """

      assert EventExtractor.extract_price(html) == nil
    end
  end
end
