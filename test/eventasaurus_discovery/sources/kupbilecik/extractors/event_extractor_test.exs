defmodule EventasaurusDiscovery.Sources.Kupbilecik.Extractors.EventExtractorTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Kupbilecik.Extractors.EventExtractor

  @sample_html """
  <!DOCTYPE html>
  <html>
  <head>
    <title>Koncert Rockowy - kupbilecik.pl</title>
    <meta property="og:title" content="Koncert Rockowy - SUPERBAND 2025"/>
    <meta property="og:image" content="https://cdn.kupbilecik.pl/images/event123.jpg"/>
    <meta name="description" content="Niesamowity koncert rockowy w Warszawie"/>
  </head>
  <body>
    <h1 class="event-title">Koncert Rockowy - SUPERBAND 2025</h1>
    <div class="date-time">7 grudnia 2025 o godz. 20:00</div>
    <div class="event-description">
      Największy koncert roku! Nie przegap tej niesamowitej okazji.
    </div>
    <div class="venue-name">Hala Sportowa</div>
    <div class="address">ul. Sportowa 1, 00-001 Warszawa</div>
    <div class="city">Warszawa</div>
    <div class="price">od 99 zł</div>
    <div class="category">Koncerty</div>
  </body>
  </html>
  """

  @minimal_html """
  <!DOCTYPE html>
  <html>
  <head>
    <title>Test Event - kupbilecik.pl</title>
  </head>
  <body>
    <h1>Test Event Title</h1>
    <time>1 stycznia 2025 o godz. 19:00</time>
  </body>
  </html>
  """

  describe "extract/2" do
    test "extracts event data from complete HTML" do
      url = "https://www.kupbilecik.pl/imprezy/123456/koncert-rockowy"

      assert {:ok, event_data} = EventExtractor.extract(@sample_html, url)

      assert event_data["url"] == url
      assert event_data["title"] == "Koncert Rockowy - SUPERBAND 2025"
      assert event_data["date_string"] == "7 grudnia 2025 o godz. 20:00"
      assert event_data["image_url"] == "https://cdn.kupbilecik.pl/images/event123.jpg"
      assert event_data["venue_name"] == "Hala Sportowa"
      assert event_data["city"] == "Warszawa"
      assert event_data["price"] =~ "99 zł"
    end

    test "extracts from minimal HTML" do
      url = "https://www.kupbilecik.pl/imprezy/999/test"

      assert {:ok, event_data} = EventExtractor.extract(@minimal_html, url)

      assert event_data["title"] == "Test Event Title"
      assert event_data["date_string"] == "1 stycznia 2025 o godz. 19:00"
    end

    test "returns error for invalid input" do
      assert {:error, :invalid_input} = EventExtractor.extract(nil, "url")
      assert {:error, :invalid_input} = EventExtractor.extract("html", nil)
      assert {:error, :invalid_input} = EventExtractor.extract(123, "url")
    end

    test "returns error when title not found" do
      html_without_title = """
      <!DOCTYPE html>
      <html><body><p>No title here</p></body></html>
      """

      assert {:error, :title_not_found} =
               EventExtractor.extract(html_without_title, "https://example.com")
    end

    test "returns error when date not found" do
      html_without_date = """
      <!DOCTYPE html>
      <html><body><h1>Title Present</h1></body></html>
      """

      assert {:error, :date_not_found} =
               EventExtractor.extract(html_without_date, "https://example.com")
    end
  end

  describe "extract_title/1" do
    test "extracts title from h1 with event class" do
      html = ~s(<h1 class="event-title">Event Title</h1>)
      assert {:ok, "Event Title"} = EventExtractor.extract_title(html)
    end

    test "extracts title from og:title meta tag" do
      html = ~s(<meta property="og:title" content="OG Title - kupbilecik"/>)
      assert {:ok, "OG Title"} = EventExtractor.extract_title(html)
    end

    test "extracts title from page title tag" do
      html = ~s(<title>Page Title - kupbilecik.pl</title>)
      assert {:ok, "Page Title"} = EventExtractor.extract_title(html)
    end

    test "strips kupbilecik suffix from title" do
      html = ~s(<title>Event Name - kupbilecik.pl</title>)
      assert {:ok, title} = EventExtractor.extract_title(html)
      refute title =~ "kupbilecik"
    end

    test "returns error when no title found" do
      html = ~s(<div>No title</div>)
      assert {:error, :title_not_found} = EventExtractor.extract_title(html)
    end
  end

  describe "extract_date_string/1" do
    test "extracts date from time element" do
      html = ~s(<time>7 grudnia 2025 o godz. 20:00</time>)
      assert {:ok, date_string} = EventExtractor.extract_date_string(html)
      assert date_string =~ "7 grudnia 2025"
    end

    test "extracts date from date class element" do
      html = ~s(<div class="date-info">15 maja 2025, 19:30</div>)
      assert {:ok, date_string} = EventExtractor.extract_date_string(html)
      assert date_string =~ "15 maja 2025"
    end

    test "extracts date from text with Polish pattern" do
      html = ~s(<div>Wydarzenie odbędzie się 1 stycznia 2025 o godz. 18:00</div>)
      assert {:ok, date_string} = EventExtractor.extract_date_string(html)
      assert date_string =~ "1 stycznia 2025"
    end

    test "returns error when no date found" do
      html = ~s(<div>No date here</div>)
      assert {:error, :date_not_found} = EventExtractor.extract_date_string(html)
    end
  end

  describe "extract_description/1" do
    test "extracts description from description class" do
      html = ~s(<div class="event-description">This is the event description.</div>)
      description = EventExtractor.extract_description(html)
      assert description =~ "event description"
    end

    test "extracts description from meta tag" do
      html = ~s(<meta name="description" content="Meta description text"/>)
      description = EventExtractor.extract_description(html)
      assert description == "Meta description text"
    end

    test "returns nil when no description found" do
      html = ~s(<div>No description</div>)
      assert EventExtractor.extract_description(html) == nil
    end
  end

  describe "extract_image_url/1" do
    test "extracts image from og:image meta tag" do
      html = ~s(<meta property="og:image" content="https://example.com/image.jpg"/>)
      image_url = EventExtractor.extract_image_url(html)
      assert image_url == "https://example.com/image.jpg"
    end

    test "returns nil when no image found" do
      html = ~s(<div>No image</div>)
      assert EventExtractor.extract_image_url(html) == nil
    end
  end

  describe "extract_venue/1" do
    test "extracts venue information" do
      html = """
      <div class="venue-name">Concert Hall</div>
      <div class="address">ul. Main Street 123</div>
      <div class="city">Kraków</div>
      """

      venue = EventExtractor.extract_venue(html)

      assert venue.name == "Concert Hall"
      assert venue.address == "ul. Main Street 123"
      assert venue.city == "Kraków"
    end

    test "returns nil fields when venue not found" do
      html = ~s(<div>No venue info</div>)
      venue = EventExtractor.extract_venue(html)

      assert venue.name == nil
      assert venue.address == nil
    end
  end

  describe "extract_price/1" do
    test "extracts price in Polish format (zł)" do
      html = ~s(<span>od 99 zł</span>)
      price = EventExtractor.extract_price(html)
      assert price =~ "99 zł"
    end

    test "extracts price with decimal" do
      html = ~s(<span>49,99 zł</span>)
      price = EventExtractor.extract_price(html)
      assert price =~ "49,99 zł"
    end

    test "returns nil when no price found" do
      html = ~s(<div>No price</div>)
      assert EventExtractor.extract_price(html) == nil
    end
  end

  describe "extract_category/2" do
    test "extracts category from category element" do
      html = ~s(<div class="category">Koncerty</div>)
      category = EventExtractor.extract_category(html, "https://example.com")
      assert category == "Koncerty"
    end

    test "extracts category from URL path" do
      html = ~s(<div>No category element</div>)
      url = "https://www.kupbilecik.pl/koncerty/123/event-name"
      category = EventExtractor.extract_category(html, url)
      assert category == "koncerty"
    end

    test "returns nil when no category found" do
      html = ~s(<div>No category</div>)
      url = "https://www.kupbilecik.pl/imprezy/123/"
      category = EventExtractor.extract_category(html, url)
      assert category == nil
    end
  end
end
