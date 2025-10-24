defmodule EventasaurusDiscovery.Sources.Sortiraparis.Extractors.EventExtractorTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Sortiraparis.Extractors.EventExtractor

  describe "extract/2" do
    test "extracts complete event data from HTML" do
      html = """
      <html>
        <head>
          <title>Indochine Concert at Accor Arena | Sortiraparis.com</title>
          <meta property="og:title" content="Indochine Concert at Accor Arena">
          <meta property="og:image" content="https://www.sortiraparis.com/images/indochine.jpg">
        </head>
        <body>
          <article>
            <h1>Indochine Concert at Accor Arena</h1>
            <time>February 25, 2026</time>
            <p>Indochine returns to Paris for an exclusive concert.</p>
            <p>Tickets available from €45 to €85.</p>
          </article>
        </body>
      </html>
      """

      url = "https://www.sortiraparis.com/articles/123-indochine"

      assert {:ok, event_data} = EventExtractor.extract(html, url)
      assert event_data["title"] == "Indochine Concert at Accor Arena"
      assert event_data["url"] == url
      assert event_data["date_string"] == "February 25, 2026"
      assert event_data["description"] =~ "Indochine returns to Paris"
      assert event_data["image_url"] == "https://www.sortiraparis.com/images/indochine.jpg"
      assert event_data["currency"] == "EUR"
    end

    test "returns error when title is missing" do
      html = "<html><body><article><p>No title here</p></article></body></html>"
      url = "https://example.com/test"

      assert {:error, :title_not_found} = EventExtractor.extract(html, url)
    end

    test "returns error when date is missing" do
      html = "<html><body><article><h1>Event Title</h1></article></body></html>"
      url = "https://example.com/test"

      assert {:error, :date_not_found} = EventExtractor.extract(html, url)
    end

    test "returns error for invalid input" do
      assert {:error, :invalid_input} = EventExtractor.extract(nil, "url")
      assert {:error, :invalid_input} = EventExtractor.extract("html", nil)
    end
  end

  describe "extract_title/1" do
    test "extracts title from h1 tag" do
      html = "<h1>Concert at Venue</h1>"
      assert {:ok, "Concert at Venue"} = EventExtractor.extract_title(html)
    end

    test "extracts title from og:title meta tag" do
      html = ~s(<meta property="og:title" content="Exhibition Opening">)
      assert {:ok, "Exhibition Opening"} = EventExtractor.extract_title(html)
    end

    test "extracts title from page title tag" do
      html = "<title>Theater Show | Sortiraparis.com</title>"
      assert {:ok, "Theater Show"} = EventExtractor.extract_title(html)
    end

    test "returns error when no title found" do
      html = "<div>No title here</div>"
      assert {:error, :title_not_found} = EventExtractor.extract_title(html)
    end
  end

  describe "extract_date_string/1" do
    test "extracts date from time element" do
      html = "<time>October 31, 2025</time>"
      assert {:ok, "October 31, 2025"} = EventExtractor.extract_date_string(html)
    end

    test "extracts date from text with multi-date pattern" do
      html = "<article>Event dates: February 25, 27, 28, 2026</article>"
      assert {:ok, date_string} = EventExtractor.extract_date_string(html)
      assert date_string =~ "February 25, 27, 28, 2026"
    end

    test "extracts date range from text" do
      html = "<p>From October 15, 2025 to January 19, 2026</p>"
      assert {:ok, date_string} = EventExtractor.extract_date_string(html)
      assert date_string =~ "October 15, 2025 to January 19, 2026"
    end

    test "returns error when no date found" do
      html = "<div>No date information</div>"
      assert {:error, :date_not_found} = EventExtractor.extract_date_string(html)
    end
  end

  describe "extract_description/1" do
    test "extracts description from article paragraphs" do
      html = """
      <article>
        <h1>Title</h1>
        <p>First paragraph with event details.</p>
        <p>Second paragraph with more information.</p>
        <p>Third paragraph that won't be included.</p>
      </article>
      """

      assert {:ok, description} = EventExtractor.extract_description(html)
      assert description =~ "First paragraph"
      assert description =~ "Second paragraph"
      refute description =~ "Third paragraph"
    end

    test "falls back to meta description" do
      html = ~s(<meta name="description" content="Event description from meta tag">)
      assert {:ok, "Event description from meta tag"} = EventExtractor.extract_description(html)
    end

    test "returns error when no description found" do
      html = "<div>No description</div>"
      assert {:error, :description_not_found} = EventExtractor.extract_description(html)
    end
  end

  describe "extract_image_url/1" do
    test "extracts image from og:image meta tag" do
      html = ~s(<meta property="og:image" content="https://example.com/image.jpg">)
      assert {:ok, "https://example.com/image.jpg"} = EventExtractor.extract_image_url(html)
    end

    test "extracts image from figure element" do
      html = ~s(<figure><img src="https://example.com/fig.jpg"></figure>)
      assert {:ok, "https://example.com/fig.jpg"} = EventExtractor.extract_image_url(html)
    end

    test "extracts first image from article" do
      html =
        ~s(<article><img src="https://example.com/first.jpg"><img src="https://example.com/second.jpg"></article>)

      assert {:ok, "https://example.com/first.jpg"} = EventExtractor.extract_image_url(html)
    end

    test "returns ok with nil when no image found" do
      html = "<div>No images</div>"
      assert {:ok, nil} = EventExtractor.extract_image_url(html)
    end
  end

  describe "extract_pricing/1" do
    test "extracts price range with euro symbol" do
      html = "<p>Tickets from €15 to €35</p>"

      pricing = EventExtractor.extract_pricing(html)

      assert pricing[:is_ticketed] == true
      assert pricing[:is_free] == false
      assert pricing[:currency] == "EUR"
      assert Decimal.equal?(pricing[:min_price], Decimal.new("15"))
      assert Decimal.equal?(pricing[:max_price], Decimal.new("35"))
    end

    test "detects free events" do
      html = "<p>Free admission for all visitors</p>"

      pricing = EventExtractor.extract_pricing(html)

      assert pricing[:is_free] == true
      assert pricing[:is_ticketed] == false
      assert pricing[:min_price] == nil
      assert pricing[:max_price] == nil
    end

    test "ignores prices when event is free (database constraint compliance)" do
      # Real-world case: free event description mentions prices in context
      html = "<p>Free admission. Regular exhibitions cost €15.</p>"

      pricing = EventExtractor.extract_pricing(html)

      # Must be free with no prices (database constraint)
      assert pricing[:is_free] == true
      assert pricing[:is_ticketed] == false
      assert pricing[:min_price] == nil
      assert pricing[:max_price] == nil
    end

    test "extracts prices in various formats" do
      html = "<p>Prices: 20€, €25, 30 euros</p>"

      pricing = EventExtractor.extract_pricing(html)

      assert pricing[:is_ticketed] == true
      assert Decimal.equal?(pricing[:min_price], Decimal.new("20"))
      assert Decimal.equal?(pricing[:max_price], Decimal.new("30"))
    end

    test "returns no pricing when none found" do
      html = "<p>Event details without pricing</p>"

      pricing = EventExtractor.extract_pricing(html)

      assert pricing[:is_free] == false
      assert pricing[:is_ticketed] == false
      assert pricing[:min_price] == nil
    end
  end

  describe "extract_performers/1" do
    test "returns empty list" do
      html = "<article>Concert with performers</article>"
      assert [] = EventExtractor.extract_performers(html)
    end
  end
end
