defmodule EventasaurusWeb.JsonLd.PublicEventSchemaTest do
  use ExUnit.Case, async: true

  alias EventasaurusWeb.JsonLd.PublicEventSchema
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Categories.Category
  alias EventasaurusDiscovery.Performers.Performer
  alias EventasaurusDiscovery.Movies.Movie
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Locations.{City, Country}

  describe "domain_to_schema_type/1" do
    test "maps music domain to MusicEvent" do
      assert PublicEventSchema.domain_to_schema_type("music") == "MusicEvent"
      assert PublicEventSchema.domain_to_schema_type("concert") == "MusicEvent"
    end

    test "maps screening domains to ScreeningEvent" do
      assert PublicEventSchema.domain_to_schema_type("screening") == "ScreeningEvent"
      assert PublicEventSchema.domain_to_schema_type("movies") == "ScreeningEvent"
      assert PublicEventSchema.domain_to_schema_type("cinema") == "ScreeningEvent"
    end

    test "maps theater domain to TheaterEvent" do
      assert PublicEventSchema.domain_to_schema_type("theater") == "TheaterEvent"
    end

    test "maps sports domain to SportsEvent" do
      assert PublicEventSchema.domain_to_schema_type("sports") == "SportsEvent"
    end

    test "maps comedy domain to ComedyEvent" do
      assert PublicEventSchema.domain_to_schema_type("comedy") == "ComedyEvent"
    end

    test "maps food domain to FoodEvent" do
      assert PublicEventSchema.domain_to_schema_type("food") == "FoodEvent"
    end

    test "maps festival domain to Festival" do
      assert PublicEventSchema.domain_to_schema_type("festival") == "Festival"
    end

    test "maps social and trivia domains to SocialEvent" do
      assert PublicEventSchema.domain_to_schema_type("social") == "SocialEvent"
      assert PublicEventSchema.domain_to_schema_type("trivia") == "SocialEvent"
    end

    test "defaults unknown domains to Event" do
      assert PublicEventSchema.domain_to_schema_type("unknown") == "Event"
      assert PublicEventSchema.domain_to_schema_type("general") == "Event"
      assert PublicEventSchema.domain_to_schema_type(nil) == "Event"
    end
  end

  describe "build_event_schema/1" do
    setup do
      # Create country, city, and venue
      country = %Country{id: 1, name: "Poland", code: "PL", slug: "poland"}
      city = %City{id: 1, name: "Kraków", slug: "krakow", country_id: 1, country: country}

      venue = %Venue{
        id: 1,
        name: "Test Venue",
        address: "Test Street 123",
        latitude: 50.0647,
        longitude: 19.9450,
        city_id: 1,
        city_ref: city
      }

      # Create category
      category = %Category{
        id: 1,
        name: "Concerts",
        slug: "concerts",
        schema_type: "MusicEvent"
      }

      # Create minimal event
      event = %PublicEvent{
        id: 1,
        title: "Test Concert",
        slug: "test-concert",
        starts_at: ~U[2024-12-15 19:00:00Z],
        ends_at: ~U[2024-12-15 22:00:00Z],
        venue_id: 1,
        venue: venue,
        categories: [category],
        performers: [],
        movies: [],
        sources: []
      }

      {:ok, event: event, venue: venue, category: category}
    end

    test "generates basic event schema", %{event: event} do
      schema = PublicEventSchema.build_event_schema(event)

      assert schema["@context"] == "https://schema.org"
      assert schema["@type"] == "MusicEvent"
      assert schema["name"] == "Test Concert"
      assert schema["startDate"] == "2024-12-15T19:00:00Z"
      assert schema["endDate"] == "2024-12-15T22:00:00Z"
      assert schema["eventAttendanceMode"] == "https://schema.org/OfflineEventAttendanceMode"
      assert schema["eventStatus"] == "https://schema.org/EventScheduled"
    end

    test "includes location with address", %{event: event} do
      schema = PublicEventSchema.build_event_schema(event)

      assert schema["location"]["@type"] == "Place"
      assert schema["location"]["name"] == "Test Venue"
      assert schema["location"]["address"]["@type"] == "PostalAddress"
      assert schema["location"]["address"]["streetAddress"] == "Test Street 123"
      assert schema["location"]["address"]["addressLocality"] == "Kraków"
      assert schema["location"]["address"]["addressCountry"] == "PL"
    end

    test "includes geo coordinates when available", %{event: event} do
      schema = PublicEventSchema.build_event_schema(event)

      assert schema["location"]["geo"]["@type"] == "GeoCoordinates"
      assert schema["location"]["geo"]["latitude"] == 50.0647
      assert schema["location"]["geo"]["longitude"] == 19.9450
    end

    test "generates JSON-LD string", %{event: event} do
      json_ld = PublicEventSchema.generate(event)

      assert is_binary(json_ld)
      assert String.contains?(json_ld, "\"@context\":\"https://schema.org\"")
      assert String.contains?(json_ld, "\"@type\":\"MusicEvent\"")
    end
  end

  describe "event type determination" do
    test "uses category schema_type when available" do
      category = %Category{id: 1, schema_type: "TheaterEvent"}

      event = %PublicEvent{
        id: 1,
        title: "Test Event",
        starts_at: ~U[2024-12-15 19:00:00Z],
        categories: [category],
        performers: [],
        movies: [],
        sources: [],
        venue: nil
      }

      schema = PublicEventSchema.build_event_schema(event)
      assert schema["@type"] == "TheaterEvent"
    end

    test "falls back to source domain when no category" do
      source_record = %Source{id: 1, name: "Test Source", domains: ["sports"]}

      source = %PublicEventSource{
        id: 1,
        source_id: 1,
        source: source_record
      }

      event = %PublicEvent{
        id: 1,
        title: "Test Event",
        starts_at: ~U[2024-12-15 19:00:00Z],
        categories: [],
        performers: [],
        movies: [],
        sources: [source],
        venue: nil
      }

      schema = PublicEventSchema.build_event_schema(event)
      assert schema["@type"] == "SportsEvent"
    end

    test "defaults to Event when no type information" do
      event = %PublicEvent{
        id: 1,
        title: "Test Event",
        starts_at: ~U[2024-12-15 19:00:00Z],
        categories: [],
        performers: [],
        movies: [],
        sources: [],
        venue: nil
      }

      schema = PublicEventSchema.build_event_schema(event)
      assert schema["@type"] == "Event"
    end
  end

  describe "pricing and offers" do
    test "includes free event offer" do
      source_record = %Source{id: 1, name: "Test Source", website_url: "https://example.com"}

      source = %PublicEventSource{
        id: 1,
        source_id: 1,
        source: source_record,
        is_free: true,
        currency: "PLN",
        source_url: "https://example.com/tickets"
      }

      event = %PublicEvent{
        id: 1,
        title: "Free Event",
        starts_at: ~U[2024-12-15 19:00:00Z],
        categories: [],
        performers: [],
        movies: [],
        sources: [source],
        venue: nil
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["offers"]["@type"] == "Offer"
      assert schema["offers"]["price"] == 0
      assert schema["offers"]["priceCurrency"] == "PLN"
      assert schema["offers"]["url"] == "https://example.com/tickets"
    end

    test "includes paid event offer with price" do
      source_record = %Source{id: 1, name: "Test Source"}

      source = %PublicEventSource{
        id: 1,
        source_id: 1,
        source: source_record,
        min_price: Decimal.new("50.00"),
        max_price: Decimal.new("100.00"),
        currency: "USD",
        source_url: "https://example.com/tickets"
      }

      event = %PublicEvent{
        id: 1,
        title: "Paid Event",
        starts_at: ~U[2024-12-15 19:00:00Z],
        categories: [],
        performers: [],
        movies: [],
        sources: [source],
        venue: nil
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["offers"]["@type"] == "Offer"
      assert schema["offers"]["price"] == 50.0
      assert schema["offers"]["priceCurrency"] == "USD"
      assert schema["offers"]["priceSpecification"]["minPrice"] == 50.0
      assert schema["offers"]["priceSpecification"]["maxPrice"] == 100.0
    end
  end

  describe "performers" do
    test "includes single performer" do
      performer = %Performer{id: 1, name: "Test Artist"}

      event = %PublicEvent{
        id: 1,
        title: "Concert",
        starts_at: ~U[2024-12-15 19:00:00Z],
        categories: [],
        performers: [performer],
        movies: [],
        sources: [],
        venue: nil
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["performer"]["@type"] == "PerformingGroup"
      assert schema["performer"]["name"] == "Test Artist"
    end

    test "includes multiple performers as array" do
      performers = [
        %Performer{id: 1, name: "Artist 1"},
        %Performer{id: 2, name: "Artist 2"}
      ]

      event = %PublicEvent{
        id: 1,
        title: "Concert",
        starts_at: ~U[2024-12-15 19:00:00Z],
        categories: [],
        performers: performers,
        movies: [],
        sources: [],
        venue: nil
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert is_list(schema["performer"])
      assert length(schema["performer"]) == 2
      assert Enum.at(schema["performer"], 0)["name"] == "Artist 1"
      assert Enum.at(schema["performer"], 1)["name"] == "Artist 2"
    end
  end

  describe "ScreeningEvent with movies" do
    test "includes workPresented for movie screening" do
      category = %Category{id: 1, schema_type: "ScreeningEvent"}
      movie = %Movie{id: 1, title: "Test Movie"}

      event = %PublicEvent{
        id: 1,
        title: "Movie Screening",
        starts_at: ~U[2024-12-15 19:00:00Z],
        categories: [category],
        performers: [],
        movies: [movie],
        sources: [],
        venue: nil
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["@type"] == "ScreeningEvent"
      assert schema["workPresented"]["@type"] == "Movie"
      assert schema["workPresented"]["name"] == "Test Movie"
    end

    test "does not include workPresented for non-screening events" do
      category = %Category{id: 1, schema_type: "MusicEvent"}
      movie = %Movie{id: 1, title: "Test Movie"}

      event = %PublicEvent{
        id: 1,
        title: "Concert",
        starts_at: ~U[2024-12-15 19:00:00Z],
        categories: [category],
        performers: [],
        movies: [movie],
        sources: [],
        venue: nil
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["@type"] == "MusicEvent"
      refute Map.has_key?(schema, "workPresented")
    end
  end

  describe "organizer" do
    test "includes organizer from source" do
      source_record = %Source{
        id: 1,
        name: "Ticketmaster",
        website_url: "https://ticketmaster.com"
      }

      source = %PublicEventSource{
        id: 1,
        source_id: 1,
        source: source_record
      }

      event = %PublicEvent{
        id: 1,
        title: "Event",
        starts_at: ~U[2024-12-15 19:00:00Z],
        categories: [],
        performers: [],
        movies: [],
        sources: [source],
        venue: nil
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["organizer"]["@type"] == "Organization"
      assert schema["organizer"]["name"] == "Ticketmaster"
      assert schema["organizer"]["url"] == "https://ticketmaster.com"
    end
  end

  describe "images" do
    test "includes image from source image_url field" do
      source_record = %Source{id: 1, name: "Test Source"}

      source = %PublicEventSource{
        id: 1,
        source_id: 1,
        source: source_record,
        image_url: "https://example.com/event-image.jpg"
      }

      event = %PublicEvent{
        id: 1,
        title: "Event with Image",
        starts_at: ~U[2024-12-15 19:00:00Z],
        categories: [],
        performers: [],
        movies: [],
        sources: [source],
        venue: nil
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert is_list(schema["image"])
      assert "https://example.com/event-image.jpg" in schema["image"]
    end

    test "extracts image from Resident Advisor metadata" do
      source_record = %Source{id: 1, name: "Resident Advisor"}

      source = %PublicEventSource{
        id: 1,
        source_id: 1,
        source: source_record,
        metadata: %{
          "raw_data" => %{
            "event" => %{
              "flyerFront" => "https://ra.co/images/event-flyer.jpg"
            }
          }
        }
      }

      event = %PublicEvent{
        id: 1,
        title: "RA Event",
        starts_at: ~U[2024-12-15 19:00:00Z],
        categories: [],
        performers: [],
        movies: [],
        sources: [source],
        venue: nil
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert is_list(schema["image"])
      assert "https://ra.co/images/event-flyer.jpg" in schema["image"]
    end

    test "uses placeholder when no images available" do
      event = %PublicEvent{
        id: 1,
        title: "Event without Image",
        starts_at: ~U[2024-12-15 19:00:00Z],
        categories: [],
        performers: [],
        movies: [],
        sources: [],
        venue: nil
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert is_list(schema["image"])
      assert length(schema["image"]) == 1
      assert String.starts_with?(List.first(schema["image"]), "https://placehold.co/")
    end

    test "prioritizes source image_url over metadata" do
      source_record = %Source{id: 1, name: "Test Source"}

      source = %PublicEventSource{
        id: 1,
        source_id: 1,
        source: source_record,
        image_url: "https://example.com/direct-image.jpg",
        metadata: %{
          "raw_data" => %{
            "event" => %{
              "flyerFront" => "https://example.com/metadata-image.jpg"
            }
          }
        }
      }

      event = %PublicEvent{
        id: 1,
        title: "Event",
        starts_at: ~U[2024-12-15 19:00:00Z],
        categories: [],
        performers: [],
        movies: [],
        sources: [source],
        venue: nil
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert is_list(schema["image"])
      # Direct image_url should come first
      assert List.first(schema["image"]) == "https://example.com/direct-image.jpg"
    end
  end

  describe "description" do
    test "includes description from event source" do
      source_record = %Source{id: 1, name: "Test Source"}

      source = %PublicEventSource{
        id: 1,
        source_id: 1,
        source: source_record,
        description_translations: %{"en" => "This is a test event description"}
      }

      event = %PublicEvent{
        id: 1,
        title: "Event",
        starts_at: ~U[2024-12-15 19:00:00Z],
        categories: [],
        performers: [],
        movies: [],
        sources: [source],
        venue: nil
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["description"] == "This is a test event description"
    end

    test "truncates long descriptions to 5000 characters" do
      long_description = String.duplicate("A", 6000)

      source_record = %Source{id: 1, name: "Test Source"}

      source = %PublicEventSource{
        id: 1,
        source_id: 1,
        source: source_record,
        description_translations: %{"en" => long_description}
      }

      event = %PublicEvent{
        id: 1,
        title: "Event",
        starts_at: ~U[2024-12-15 19:00:00Z],
        categories: [],
        performers: [],
        movies: [],
        sources: [source],
        venue: nil
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert String.length(schema["description"]) == 5000
    end
  end

  describe "fallback description generation" do
    setup do
      country = %Country{id: 1, name: "Poland", code: "PL", slug: "poland"}
      city = %City{id: 1, name: "Kraków", slug: "krakow", country_id: 1, country: country}

      venue = %Venue{
        id: 1,
        name: "Łaźnia Nowa Theatre",
        address: "Test Street 123",
        city_id: 1,
        city_ref: city
      }

      category = %Category{
        id: 1,
        name: "music event",
        slug: "music",
        schema_type: "MusicEvent"
      }

      {:ok, venue: venue, category: category}
    end

    test "generates fallback with single performer", %{venue: venue, category: category} do
      performers = [%Performer{id: 1, name: "Moin"}]

      event = %PublicEvent{
        id: 1,
        title: "Test Concert",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: performers,
        movies: [],
        sources: []
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["description"] == "Moin performing music event at Łaźnia Nowa Theatre in Kraków."
    end

    test "generates fallback with two performers using 'and'", %{venue: venue, category: category} do
      performers = [
        %Performer{id: 1, name: "Moin"},
        %Performer{id: 2, name: "Abdullah Miniawy"}
      ]

      event = %PublicEvent{
        id: 1,
        title: "Test Concert",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: performers,
        movies: [],
        sources: []
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["description"] == "Moin and Abdullah Miniawy performing music event at Łaźnia Nowa Theatre in Kraków."
    end

    test "generates fallback with three performers using comma and 'and'", %{venue: venue, category: category} do
      performers = [
        %Performer{id: 1, name: "Moin"},
        %Performer{id: 2, name: "Abdullah Miniawy"},
        %Performer{id: 3, name: "Artur Rumiński"}
      ]

      event = %PublicEvent{
        id: 1,
        title: "Test Concert",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: performers,
        movies: [],
        sources: []
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["description"] == "Moin, Abdullah Miniawy, and Artur Rumiński performing music event at Łaźnia Nowa Theatre in Kraków."
    end

    test "generates fallback without performers", %{venue: venue, category: category} do
      event = %PublicEvent{
        id: 1,
        title: "Test Event",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: [],
        movies: [],
        sources: []
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["description"] == "Music event at Łaźnia Nowa Theatre in Kraków."
    end

    test "generates fallback without venue name", %{category: category} do
      country = %Country{id: 1, name: "Poland", code: "PL"}
      city = %City{id: 1, name: "Kraków", slug: "krakow", country: country}

      venue_without_name = %Venue{
        id: 1,
        name: nil,
        city_ref: city
      }

      event = %PublicEvent{
        id: 1,
        title: "Test Event",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue_without_name,
        categories: [category],
        performers: [],
        movies: [],
        sources: []
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["description"] == "Music event in Kraków."
    end

    test "generates fallback without city", %{category: category} do
      venue_without_city = %Venue{
        id: 1,
        name: "Test Venue",
        city_ref: nil
      }

      event = %PublicEvent{
        id: 1,
        title: "Test Event",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue_without_city,
        categories: [category],
        performers: [],
        movies: [],
        sources: []
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["description"] == "Music event at Test Venue."
    end

    test "uses fallback when source description is empty string", %{venue: venue, category: category} do
      source_record = %Source{id: 1, name: "Test Source"}

      source = %PublicEventSource{
        id: 1,
        source_id: 1,
        source: source_record,
        description_translations: %{"en" => ""}
      }

      performers = [%Performer{id: 1, name: "Test Artist"}]

      event = %PublicEvent{
        id: 1,
        title: "Test Concert",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: performers,
        movies: [],
        sources: [source]
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["description"] == "Test Artist performing music event at Łaźnia Nowa Theatre in Kraków."
    end

    test "uses fallback when source description is nil", %{venue: venue, category: category} do
      source_record = %Source{id: 1, name: "Test Source"}

      source = %PublicEventSource{
        id: 1,
        source_id: 1,
        source: source_record,
        description_translations: nil
      }

      performers = [%Performer{id: 1, name: "Test Artist"}]

      event = %PublicEvent{
        id: 1,
        title: "Test Concert",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: performers,
        movies: [],
        sources: [source]
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["description"] == "Test Artist performing music event at Łaźnia Nowa Theatre in Kraków."
    end

    test "source description takes precedence over fallback", %{venue: venue, category: category} do
      source_record = %Source{id: 1, name: "Test Source"}

      source = %PublicEventSource{
        id: 1,
        source_id: 1,
        source: source_record,
        description_translations: %{"en" => "Official event description"}
      }

      performers = [%Performer{id: 1, name: "Test Artist"}]

      event = %PublicEvent{
        id: 1,
        title: "Test Concert",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: performers,
        movies: [],
        sources: [source]
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["description"] == "Official event description"
    end

    test "fallback generates minimal description when minimal data available" do
      # Event with no venue, no performers, no category
      event = %PublicEvent{
        id: 1,
        title: "Test Event",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: nil,
        categories: [],
        performers: [],
        movies: [],
        sources: []
      }

      schema = PublicEventSchema.build_event_schema(event)

      # Even with minimal data, we can generate "Event."
      assert schema["description"] == "Event."
    end

    test "fallback with only event type (no venue or performers)" do
      category = %Category{
        id: 1,
        name: "concert",
        slug: "concerts",
        schema_type: "MusicEvent"
      }

      event = %PublicEvent{
        id: 1,
        title: "Test Event",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: nil,
        categories: [category],
        performers: [],
        movies: [],
        sources: []
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["description"] == "Concert."
    end

    test "fallback truncates long descriptions to 5000 characters" do
      # Create performers with very long names to exceed 5000 chars
      long_name = String.duplicate("A", 2000)
      performers = [
        %Performer{id: 1, name: long_name},
        %Performer{id: 2, name: long_name},
        %Performer{id: 3, name: long_name}
      ]

      country = %Country{id: 1, name: "Poland", code: "PL"}
      city = %City{id: 1, name: "Kraków", slug: "krakow", country: country}

      venue = %Venue{
        id: 1,
        name: "Test Venue",
        city_ref: city
      }

      category = %Category{
        id: 1,
        name: "music event",
        slug: "music",
        schema_type: "MusicEvent"
      }

      event = %PublicEvent{
        id: 1,
        title: "Test Concert",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: performers,
        movies: [],
        sources: []
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert String.length(schema["description"]) == 5000
    end
  end
end
