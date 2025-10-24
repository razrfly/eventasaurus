defmodule EventasaurusDiscovery.Sources.Sortiraparis.Extractors.VenueExtractorTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Sortiraparis.Extractors.VenueExtractor

  describe "extract/1" do
    test "extracts complete venue data from _mapHandler.init (primary strategy)" do
      html = """
      <html>
        <body>
          <article>
            <address>28 Rue du Sommerard, 75005 Paris</address>
          </article>
          <div id="map-canvas" class="fake-map"></div>
          <script>_mapHandler.init({"markers":[{"l":48.850483,"L":2.344081,"t":"Musée du Moyen-Age - Musée de Cluny"}]});</script>
        </body>
      </html>
      """

      assert {:ok, venue_data} = VenueExtractor.extract(html)
      assert venue_data["name"] == "Musée du Moyen-Age - Musée de Cluny"
      assert venue_data["address"] == "28 Rue du Sommerard, 75005 Paris"
      assert venue_data["city"] == "Paris"
      assert venue_data["postal_code"] == "75005"
      assert venue_data["country"] == "France"
      assert venue_data["latitude"] == 48.850483
      assert venue_data["longitude"] == 2.344081
    end

    test "extracts complete venue data from HTML" do
      html = """
      <html>
        <body>
          <article>
            <div class="venue">Accor Arena</div>
            <address>8 Boulevard de Bercy, 75012 Paris</address>
          </article>
        </body>
      </html>
      """

      assert {:ok, venue_data} = VenueExtractor.extract(html)
      assert venue_data["name"] == "Accor Arena"
      assert venue_data["address"] == "8 Boulevard de Bercy, 75012 Paris"
      assert venue_data["city"] == "Paris"
      assert venue_data["postal_code"] == "75012"
      assert venue_data["country"] == "France"
    end

    test "extracts venue with GPS coordinates" do
      html = """
      <html>
        <body>
          <div class="venue">Le Zénith</div>
          <address>211 Avenue Jean Jaurès, 75019 Paris</address>
          <div data-lat="48.8938" data-lng="2.3876"></div>
        </body>
      </html>
      """

      assert {:ok, venue_data} = VenueExtractor.extract(html)
      assert venue_data["name"] == "Le Zénith"
      assert venue_data["latitude"] == 48.8938
      assert venue_data["longitude"] == 2.3876
    end

    test "extracts venue from JSON-LD structured data" do
      html = """
      <html>
        <head>
          <script type="application/ld+json">
          {
            "@type": "Event",
            "location": {
              "name": "Palais des Sports",
              "address": {
                "streetAddress": "34 Boulevard Victor",
                "addressLocality": "Paris",
                "postalCode": "75015"
              },
              "geo": {
                "latitude": 48.8355,
                "longitude": 2.2735
              }
            }
          }
          </script>
        </head>
      </html>
      """

      assert {:ok, venue_data} = VenueExtractor.extract(html)
      assert venue_data["name"] == "Palais des Sports"
      assert venue_data["address"] == "34 Boulevard Victor, 75015 Paris"
      assert venue_data["city"] == "Paris"
      assert venue_data["postal_code"] == "75015"
      assert venue_data["latitude"] == 48.8355
      assert venue_data["longitude"] == 2.2735
    end

    test "returns error when venue name not found" do
      html = "<html><body><div>No venue here</div></body></html>"
      assert {:error, :venue_name_not_found} = VenueExtractor.extract(html)
    end

    test "returns error when address not found" do
      html = """
      <html>
        <body>
          <div class="venue">Test Venue</div>
        </body>
      </html>
      """

      assert {:error, :address_not_found} = VenueExtractor.extract(html)
    end

    test "returns error for invalid input" do
      assert {:error, :invalid_input} = VenueExtractor.extract(nil)
      assert {:error, :invalid_input} = VenueExtractor.extract(123)
    end
  end

  describe "extract_venue_name/1" do
    test "extracts venue from _mapHandler.init (primary strategy)" do
      html = """
      <html>
        <body>
          <script>_mapHandler.init({"markers":[{"l":48.850483,"L":2.344081,"t":"Musée du Moyen-Age - Musée de Cluny"}]});</script>
        </body>
      </html>
      """

      assert {:ok, "Musée du Moyen-Age - Musée de Cluny"} =
               VenueExtractor.extract_venue_name(html)
    end

    test "extracts venue from _mapHandler.init with multiple markers (uses first)" do
      html = """
      <html>
        <body>
          <script>_mapHandler.init({"markers":[{"l":48.838604,"L":2.37847,"t":"Accor Arena"},{"l":48.8566,"L":2.3522,"t":"Other Venue"}]});</script>
        </body>
      </html>
      """

      assert {:ok, "Accor Arena"} = VenueExtractor.extract_venue_name(html)
    end

    test "extracts venue from dedicated element" do
      html = ~s(<div class="venue">Olympia Bruno Coquatrix</div>)
      assert {:ok, "Olympia Bruno Coquatrix"} = VenueExtractor.extract_venue_name(html)
    end

    test "extracts venue from span with location class" do
      html = ~s(<span class="event-location">La Cigale</span>)
      assert {:ok, "La Cigale"} = VenueExtractor.extract_venue_name(html)
    end

    test "extracts venue from h2 heading" do
      html = ~s(<h2 class="venue-name">Théâtre du Châtelet</h2>)
      assert {:ok, "Théâtre du Châtelet"} = VenueExtractor.extract_venue_name(html)
    end

    test "extracts venue from JSON-LD" do
      html = """
      <script type="application/ld+json">
      {
        "location": {
          "name": "Grand Rex"
        }
      }
      </script>
      """

      assert {:ok, "Grand Rex"} = VenueExtractor.extract_venue_name(html)
    end

    test "extracts venue from text patterns" do
      html = "<p>Where: Moulin Rouge</p>"
      assert {:ok, "Moulin Rouge"} = VenueExtractor.extract_venue_name(html)
    end

    test "extracts venue from title with 'The' prefix" do
      html =
        "<title>The Musée de Cluny at night: discover the Middle Ages - Sortiraparis.com</title>"

      assert {:ok, "Musée de Cluny"} = VenueExtractor.extract_venue_name(html)
    end

    test "extracts venue from title with 'at' pattern" do
      html = "<title>Concert at Accor Arena | Sortiraparis.com</title>"
      assert {:ok, "Accor Arena"} = VenueExtractor.extract_venue_name(html)
    end

    test "extracts venue from title with 'in' pattern" do
      html = "<title>Exhibition in Grand Palais - Sortiraparis.com</title>"
      assert {:ok, "Grand Palais"} = VenueExtractor.extract_venue_name(html)
    end

    test "returns error when no venue name found" do
      html = "<div>No venue information</div>"
      assert {:error, :venue_name_not_found} = VenueExtractor.extract_venue_name(html)
    end
  end

  describe "extract_address_data/1" do
    test "extracts address from Schema.org structured data with itemprop (primary strategy)" do
      html = """
      <p itemprop="location" itemscope itemtype="http://schema.org/Place">
        <strong>Location</strong><br/>
        <a itemprop="url" href="#"><span itemprop="name">L'École des Arts Joailliers</span></a>
        <br/>
        <span itemprop="address" itemscope itemtype="http://schema.org/PostalAddress">
          <span itemprop="streetAddress">16 Bis Boulevard Montmartre</span><br/>
          <span itemprop="postalCode">75009</span> <span itemprop="addressLocality">Paris 9</span>
        </span>
      </p>
      """

      assert {:ok, address_data} = VenueExtractor.extract_address_data(html)
      assert address_data[:full_address] == "16 Bis Boulevard Montmartre, 75009 Paris 9"
      assert address_data[:city] == "Paris 9"
      assert address_data[:postal_code] == "75009"
    end

    test "extracts address from dedicated address block" do
      html = "<address>15 Rue des Martyrs, 75009 Paris</address>"

      assert {:ok, address_data} = VenueExtractor.extract_address_data(html)
      assert address_data[:full_address] == "15 Rue des Martyrs, 75009 Paris"
      assert address_data[:city] == "Paris"
      assert address_data[:postal_code] == "75009"
    end

    test "extracts address from div with address class" do
      html = ~s(<div class="address-info">120 Boulevard Rochechouart, 75018 Paris</div>)

      assert {:ok, address_data} = VenueExtractor.extract_address_data(html)
      assert address_data[:full_address] == "120 Boulevard Rochechouart, 75018 Paris"
      assert address_data[:postal_code] == "75018"
    end

    test "extracts address from JSON-LD" do
      html = """
      <script type="application/ld+json">
      {
        "location": {
          "address": {
            "streetAddress": "1 Place du Trocadéro",
            "addressLocality": "Paris",
            "postalCode": "75116"
          }
        }
      }
      </script>
      """

      assert {:ok, address_data} = VenueExtractor.extract_address_data(html)
      assert address_data[:full_address] == "1 Place du Trocadéro, 75116 Paris"
      assert address_data[:city] == "Paris"
      assert address_data[:postal_code] == "75116"
    end

    test "extracts address from text with Paris pattern" do
      html = "<p>Visit us at 28 Boulevard des Capucines, 75009 Paris 9</p>"

      assert {:ok, address_data} = VenueExtractor.extract_address_data(html)
      assert address_data[:full_address] == "28 Boulevard des Capucines, 75009 Paris 9"
      assert address_data[:city] == "Paris 9"
      assert address_data[:postal_code] == "75009"
    end

    test "handles address without arrondissement" do
      html = "<address>50 Avenue des Champs-Élysées, 75008 Paris</address>"

      assert {:ok, address_data} = VenueExtractor.extract_address_data(html)
      assert address_data[:city] == "Paris"
      assert address_data[:postal_code] == "75008"
    end

    test "returns error when no address found" do
      html = "<div>No address here</div>"
      assert {:error, :address_not_found} = VenueExtractor.extract_address_data(html)
    end
  end

  describe "extract_gps_coordinates/1" do
    test "extracts coordinates from _mapHandler.init with single marker" do
      html = """
      <html>
        <body>
          <div id="map-canvas" class="fake-map"><a href="#"><span><span>Load the map</span></span></a></div>
          <script>_mapHandler.init({"keyword":"default","id":"map-canvas","type":"google","height":"#practical-info","zoom":11,"markers":[{"l":48.850483,"L":2.344081,"t":"Musée du Moyen-Age - Musée de Cluny"}]});</script>
        </body>
      </html>
      """

      coords = VenueExtractor.extract_gps_coordinates(html)
      assert coords[:latitude] == 48.850483
      assert coords[:longitude] == 2.344081
    end

    test "extracts coordinates from _mapHandler.init with multiple markers (uses first)" do
      html = """
      <html>
        <body>
          <div id="map-canvas"></div>
          <script>_mapHandler.init({"markers":[{"l":48.838604,"L":2.37847,"t":"Accor Arena"},{"l":48.8566,"L":2.3522,"t":"Hotel Nearby"}]});</script>
        </body>
      </html>
      """

      coords = VenueExtractor.extract_gps_coordinates(html)
      assert coords[:latitude] == 48.838604
      assert coords[:longitude] == 2.37847
    end

    test "extracts coordinates from JSON-LD" do
      html = """
      <script type="application/ld+json">
      {
        "location": {
          "geo": {
            "latitude": 48.8566,
            "longitude": 2.3522
          }
        }
      }
      </script>
      """

      coords = VenueExtractor.extract_gps_coordinates(html)
      assert coords[:latitude] == 48.8566
      assert coords[:longitude] == 2.3522
    end

    test "extracts coordinates from meta tags" do
      html = ~s(<meta name="geo.position" content="48.8738,2.2950">)

      coords = VenueExtractor.extract_gps_coordinates(html)
      assert coords[:latitude] == 48.8738
      assert coords[:longitude] == 2.2950
    end

    test "extracts coordinates from embedded map data" do
      html = ~s(<div class="map" data-lat="48.8429" data-lng="2.3213"></div>)

      coords = VenueExtractor.extract_gps_coordinates(html)
      assert coords[:latitude] == 48.8429
      assert coords[:longitude] == 2.3213
    end

    test "handles coordinates as strings" do
      html = ~s(<div data-lat="48.8584" data-lng="2.2945"></div>)

      coords = VenueExtractor.extract_gps_coordinates(html)
      assert coords[:latitude] == 48.8584
      assert coords[:longitude] == 2.2945
    end

    test "handles coordinates as numbers in JSON-LD" do
      html = """
      <script type="application/ld+json">
      {
        "location": {
          "geo": {
            "latitude": 48.8920,
            "longitude": 2.2370
          }
        }
      }
      </script>
      """

      coords = VenueExtractor.extract_gps_coordinates(html)
      assert coords[:latitude] == 48.8920
      assert coords[:longitude] == 2.2370
    end

    test "returns nil values when coordinates not found" do
      html = "<div>No GPS data</div>"

      coords = VenueExtractor.extract_gps_coordinates(html)
      assert coords[:latitude] == nil
      assert coords[:longitude] == nil
    end

    test "returns nil values when coordinates are invalid" do
      html = ~s(<div data-lat="invalid" data-lng="data"></div>)

      coords = VenueExtractor.extract_gps_coordinates(html)
      assert coords[:latitude] == nil
      assert coords[:longitude] == nil
    end

    test "returns nil when only one coordinate present" do
      html = ~s(<div data-lat="48.8566"></div>)

      coords = VenueExtractor.extract_gps_coordinates(html)
      assert coords[:latitude] == nil
      assert coords[:longitude] == nil
    end
  end
end
