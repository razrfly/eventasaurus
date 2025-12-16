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

      assert schema["description"] ==
               "Moin performing music event at Łaźnia Nowa Theatre in Kraków."
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

      assert schema["description"] ==
               "Moin and Abdullah Miniawy performing music event at Łaźnia Nowa Theatre in Kraków."
    end

    test "generates fallback with three performers using comma and 'and'", %{
      venue: venue,
      category: category
    } do
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

      assert schema["description"] ==
               "Moin, Abdullah Miniawy, and Artur Rumiński performing music event at Łaźnia Nowa Theatre in Kraków."
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

    test "uses fallback when source description is empty string", %{
      venue: venue,
      category: category
    } do
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

      assert schema["description"] ==
               "Test Artist performing music event at Łaźnia Nowa Theatre in Kraków."
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

      assert schema["description"] ==
               "Test Artist performing music event at Łaźnia Nowa Theatre in Kraków."
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

  # Phase 1: Enhanced JSON-LD Structured Data for ScreeningEvent
  describe "Phase 1: Enhanced ScreeningEvent structured data" do
    setup do
      country = %Country{id: 1, name: "Poland", code: "PL", slug: "poland"}
      city = %City{id: 1, name: "Kraków", slug: "krakow", country_id: 1, country: country}

      venue = %Venue{
        id: 1,
        name: "Cinema City Bonarka",
        address: "Kamieńskiego 11",
        latitude: 50.0234,
        longitude: 19.9567,
        city_id: 1,
        city_ref: city
      }

      category = %Category{
        id: 1,
        name: "Movies",
        slug: "movies",
        schema_type: "ScreeningEvent"
      }

      {:ok, venue: venue, category: category}
    end

    test "uses MovieTheater instead of Place for ScreeningEvent", %{
      venue: venue,
      category: category
    } do
      movie = %Movie{id: 1, title: "Test Movie", tmdb_id: 12345}

      event = %PublicEvent{
        id: 1,
        title: "Movie Screening",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: [],
        movies: [movie],
        sources: []
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["@type"] == "ScreeningEvent"
      assert schema["location"]["@type"] == "MovieTheater"
      assert schema["location"]["name"] == "Cinema City Bonarka"
    end

    test "uses Place for non-ScreeningEvent even with cinema venue", %{venue: venue} do
      category = %Category{id: 2, name: "Concerts", slug: "concerts", schema_type: "MusicEvent"}

      event = %PublicEvent{
        id: 1,
        title: "Concert at Cinema",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: [],
        movies: [],
        sources: []
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["@type"] == "MusicEvent"
      assert schema["location"]["@type"] == "Place"
    end

    test "includes full movie metadata in workPresented from TMDb", %{
      venue: venue,
      category: category
    } do
      movie = %Movie{
        id: 1,
        title: "Dune: Part Two",
        tmdb_id: 693_134,
        tmdb_metadata: %{
          "release_date" => "2024-02-27",
          "runtime" => 166,
          "vote_average" => 8.3,
          "vote_count" => 5432,
          "genres" => [
            %{"id" => 878, "name" => "Science Fiction"},
            %{"id" => 12, "name" => "Adventure"}
          ],
          "credits" => %{
            "crew" => [
              %{"job" => "Director", "name" => "Denis Villeneuve"},
              %{"job" => "Producer", "name" => "Mary Parent"}
            ],
            "cast" => [
              %{"name" => "Timothée Chalamet"},
              %{"name" => "Zendaya"},
              %{"name" => "Rebecca Ferguson"}
            ]
          }
        },
        metadata: %{
          "imdbID" => "tt15239678"
        }
      }

      event = %PublicEvent{
        id: 1,
        title: "Dune: Part Two Screening",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: [],
        movies: [movie],
        sources: []
      }

      schema = PublicEventSchema.build_event_schema(event)

      work = schema["workPresented"]

      assert work["@type"] == "Movie"
      assert work["name"] == "Dune: Part Two"
      assert work["datePublished"] == "2024-02-27"
      assert work["duration"] == "PT2H46M"
      assert work["genre"] == ["Science Fiction", "Adventure"]

      # Director
      assert work["director"]["@type"] == "Person"
      assert work["director"]["name"] == "Denis Villeneuve"

      # Actors
      assert is_list(work["actor"])
      assert length(work["actor"]) == 3
      assert Enum.at(work["actor"], 0)["name"] == "Timothée Chalamet"

      # Rating
      assert work["aggregateRating"]["@type"] == "AggregateRating"
      assert work["aggregateRating"]["ratingValue"] == 8.3
      assert work["aggregateRating"]["ratingCount"] == 5432
    end

    test "includes movie image from poster_url", %{venue: venue, category: category} do
      movie = %Movie{
        id: 1,
        title: "Test Movie",
        slug: "test-movie",
        tmdb_id: 12345,
        poster_url: "https://image.tmdb.org/t/p/w500/poster.jpg"
      }

      event = %PublicEvent{
        id: 1,
        title: "Movie Screening",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: [],
        movies: [movie],
        sources: []
      }

      schema = PublicEventSchema.build_event_schema(event)

      work = schema["workPresented"]

      assert work["image"] != nil
      assert String.contains?(work["image"], "poster.jpg")
    end

    test "includes sameAs URLs for cinegraph.org and IMDb", %{venue: venue, category: category} do
      movie = %Movie{
        id: 1,
        title: "Test Movie",
        slug: "test-movie",
        tmdb_id: 12345,
        metadata: %{
          "imdbID" => "tt1234567"
        }
      }

      event = %PublicEvent{
        id: 1,
        title: "Movie Screening",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: [],
        movies: [movie],
        sources: []
      }

      schema = PublicEventSchema.build_event_schema(event)

      work = schema["workPresented"]

      assert is_list(work["sameAs"])
      assert "https://cinegraph.org/movies/test-movie" in work["sameAs"]
      assert "https://www.imdb.com/title/tt1234567/" in work["sameAs"]
    end

    test "includes only cinegraph.org URL when IMDb ID not available", %{
      venue: venue,
      category: category
    } do
      movie = %Movie{
        id: 1,
        title: "Test Movie",
        slug: "test-movie",
        tmdb_id: 12345,
        metadata: nil
      }

      event = %PublicEvent{
        id: 1,
        title: "Movie Screening",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: [],
        movies: [movie],
        sources: []
      }

      schema = PublicEventSchema.build_event_schema(event)

      work = schema["workPresented"]

      assert work["sameAs"] == ["https://cinegraph.org/movies/test-movie"]
    end

    test "includes videoFormat from source metadata", %{venue: venue, category: category} do
      movie = %Movie{id: 1, title: "Avatar", tmdb_id: 76600}

      source_record = %Source{id: 1, name: "Cinema City"}

      source = %PublicEventSource{
        id: 1,
        source_id: 1,
        source: source_record,
        metadata: %{
          "format_info" => %{
            "is_3d" => true,
            "is_imax" => true,
            "is_4dx" => false
          }
        }
      }

      event = %PublicEvent{
        id: 1,
        title: "Avatar: The Way of Water 3D IMAX",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: [],
        movies: [movie],
        sources: [source]
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert is_list(schema["videoFormat"])
      assert "3D" in schema["videoFormat"]
      assert "IMAX" in schema["videoFormat"]
      refute "4DX" in schema["videoFormat"]
    end

    test "includes single videoFormat when only one format", %{venue: venue, category: category} do
      movie = %Movie{id: 1, title: "Test Movie", tmdb_id: 12345}

      source_record = %Source{id: 1, name: "Cinema City"}

      source = %PublicEventSource{
        id: 1,
        source_id: 1,
        source: source_record,
        metadata: %{
          "format_info" => %{
            "is_3d" => false,
            "is_imax" => true,
            "is_4dx" => false
          }
        }
      }

      event = %PublicEvent{
        id: 1,
        title: "Movie IMAX",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: [],
        movies: [movie],
        sources: [source]
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["videoFormat"] == "IMAX"
    end

    test "includes inLanguage from source metadata", %{venue: venue, category: category} do
      movie = %Movie{id: 1, title: "Test Movie", tmdb_id: 12345}

      source_record = %Source{id: 1, name: "Cinema City"}

      source = %PublicEventSource{
        id: 1,
        source_id: 1,
        source: source_record,
        metadata: %{
          "language_info" => %{
            "original_language" => "EN",
            "is_dubbed" => false,
            "is_subbed" => true
          }
        }
      }

      event = %PublicEvent{
        id: 1,
        title: "Movie with Subtitles",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: [],
        movies: [movie],
        sources: [source]
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["inLanguage"] == "EN"
    end

    test "uses dubbed_language when original_language not available", %{
      venue: venue,
      category: category
    } do
      movie = %Movie{id: 1, title: "Test Movie", tmdb_id: 12345}

      source_record = %Source{id: 1, name: "Cinema City"}

      source = %PublicEventSource{
        id: 1,
        source_id: 1,
        source: source_record,
        metadata: %{
          "language_info" => %{
            "is_dubbed" => true,
            "dubbed_language" => "PL"
          }
        }
      }

      event = %PublicEvent{
        id: 1,
        title: "Dubbed Movie",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: [],
        movies: [movie],
        sources: [source]
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert schema["inLanguage"] == "PL"
    end

    test "falls back to OMDb metadata when TMDb not available", %{
      venue: venue,
      category: category
    } do
      movie = %Movie{
        id: 1,
        title: "The Matrix",
        tmdb_id: 603,
        tmdb_metadata: nil,
        metadata: %{
          "imdbID" => "tt0133093",
          "imdbRating" => "8.7",
          "imdbVotes" => "2,000,000",
          "Released" => "1999-03-31",
          "Genre" => "Action, Sci-Fi",
          "Director" => "Lana Wachowski, Lilly Wachowski",
          "Actors" => "Keanu Reeves, Laurence Fishburne, Carrie-Anne Moss",
          "Runtime" => "136 min"
        }
      }

      event = %PublicEvent{
        id: 1,
        title: "The Matrix Screening",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: [],
        movies: [movie],
        sources: []
      }

      schema = PublicEventSchema.build_event_schema(event)

      work = schema["workPresented"]

      assert work["@type"] == "Movie"
      assert work["name"] == "The Matrix"
      assert work["datePublished"] == "1999-03-31"
      assert work["duration"] == "PT2H16M"
      assert work["genre"] == ["Action", "Sci-Fi"]

      # Director from OMDb
      assert work["director"]["@type"] == "Person"
      assert work["director"]["name"] == "Lana Wachowski, Lilly Wachowski"

      # Actors from OMDb
      assert is_list(work["actor"])
      assert length(work["actor"]) == 3

      # Rating from OMDb
      assert work["aggregateRating"]["@type"] == "AggregateRating"
      assert work["aggregateRating"]["ratingValue"] == 8.7
      assert work["aggregateRating"]["ratingCount"] == 2_000_000
    end

    test "does not include videoFormat or inLanguage when not in metadata", %{
      venue: venue,
      category: category
    } do
      movie = %Movie{id: 1, title: "Test Movie", tmdb_id: 12345}

      event = %PublicEvent{
        id: 1,
        title: "Movie Screening",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: [],
        movies: [movie],
        sources: []
      }

      schema = PublicEventSchema.build_event_schema(event)

      refute Map.has_key?(schema, "videoFormat")
      refute Map.has_key?(schema, "inLanguage")
    end

    test "handles format_info with atom keys", %{venue: venue, category: category} do
      movie = %Movie{id: 1, title: "Test Movie", tmdb_id: 12345}

      source_record = %Source{id: 1, name: "Cinema City"}

      # Note: using atom keys like the transformer creates
      source = %PublicEventSource{
        id: 1,
        source_id: 1,
        source: source_record,
        metadata: %{
          "format_info" => %{
            is_3d: true,
            is_imax: false,
            is_4dx: true
          }
        }
      }

      event = %PublicEvent{
        id: 1,
        title: "Movie 3D 4DX",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [category],
        performers: [],
        movies: [movie],
        sources: [source]
      }

      schema = PublicEventSchema.build_event_schema(event)

      assert is_list(schema["videoFormat"])
      assert "3D" in schema["videoFormat"]
      assert "4DX" in schema["videoFormat"]
    end
  end

  describe "generate_with_occurrences/2" do
    setup do
      country = %Country{id: 1, name: "Poland", code: "PL", slug: "poland"}
      city = %City{id: 1, name: "Kraków", slug: "krakow", country_id: 1, country: country}

      venue = %Venue{
        id: 1,
        name: "Cinema City",
        address: "Test Street 123",
        latitude: 50.0647,
        longitude: 19.9450,
        city_id: 1,
        city_ref: city,
        venue_type: "cinema"
      }

      category = %Category{
        id: 1,
        name: "Movies",
        slug: "movies",
        schema_type: "ScreeningEvent"
      }

      movie = %Movie{
        id: 1,
        title: "Avatar: Fire and Ash",
        slug: "avatar-fire-and-ash",
        metadata: %{
          "Poster" => "https://example.com/poster.jpg"
        }
      }

      event = %PublicEvent{
        id: 1,
        title: "Avatar: Fire and Ash at Cinema City",
        slug: "avatar-fire-and-ash-at-cinema-city",
        starts_at: ~U[2024-12-15 19:00:00Z],
        ends_at: ~U[2024-12-15 22:00:00Z],
        venue_id: 1,
        venue: venue,
        categories: [category],
        performers: [],
        movies: [movie],
        sources: []
      }

      {:ok, event: event, venue: venue, movie: movie}
    end

    test "returns single schema when occurrences is nil", %{event: event} do
      json = PublicEventSchema.generate_with_occurrences(event, nil)
      schema = Jason.decode!(json)

      # Should return single object, not array
      assert is_map(schema)
      assert schema["@type"] == "ScreeningEvent"
    end

    test "returns single schema when occurrences is empty list", %{event: event} do
      json = PublicEventSchema.generate_with_occurrences(event, [])
      schema = Jason.decode!(json)

      assert is_map(schema)
      assert schema["@type"] == "ScreeningEvent"
    end

    test "returns single schema for one occurrence", %{event: event} do
      occurrences = [
        %{
          datetime: ~U[2024-12-15 19:00:00Z],
          date: ~D[2024-12-15],
          time: ~T[19:00:00],
          label: "2D",
          external_id: "cinema_city_123"
        }
      ]

      json = PublicEventSchema.generate_with_occurrences(event, occurrences)
      schema = Jason.decode!(json)

      # Single occurrence returns single object
      assert is_map(schema)
      assert schema["@type"] == "ScreeningEvent"
      assert schema["startDate"] == "2024-12-15T19:00:00Z"
    end

    test "returns array of schemas for multiple occurrences", %{event: event} do
      occurrences = [
        %{
          datetime: ~U[2024-12-15 15:00:00Z],
          date: ~D[2024-12-15],
          time: ~T[15:00:00],
          label: "2D",
          external_id: "cinema_city_123_1500"
        },
        %{
          datetime: ~U[2024-12-15 18:00:00Z],
          date: ~D[2024-12-15],
          time: ~T[18:00:00],
          label: "3D",
          external_id: "cinema_city_123_1800"
        },
        %{
          datetime: ~U[2024-12-15 21:00:00Z],
          date: ~D[2024-12-15],
          time: ~T[21:00:00],
          label: "IMAX",
          external_id: "cinema_city_123_2100"
        }
      ]

      json = PublicEventSchema.generate_with_occurrences(event, occurrences)
      schemas = Jason.decode!(json)

      # Multiple occurrences return array
      assert is_list(schemas)
      assert length(schemas) == 3

      # Each schema is a ScreeningEvent
      Enum.each(schemas, fn schema ->
        assert schema["@type"] == "ScreeningEvent"
        assert schema["@context"] == "https://schema.org"
      end)

      # Check start times are correct
      start_dates = Enum.map(schemas, & &1["startDate"])
      assert "2024-12-15T15:00:00Z" in start_dates
      assert "2024-12-15T18:00:00Z" in start_dates
      assert "2024-12-15T21:00:00Z" in start_dates
    end

    test "extracts videoFormat from occurrence label", %{event: event} do
      occurrences = [
        %{
          datetime: ~U[2024-12-15 15:00:00Z],
          date: ~D[2024-12-15],
          time: ~T[15:00:00],
          label: "3D",
          external_id: "cinema_city_123_3d"
        },
        %{
          datetime: ~U[2024-12-15 18:00:00Z],
          date: ~D[2024-12-15],
          time: ~T[18:00:00],
          label: "IMAX 3D",
          external_id: "cinema_city_123_imax3d"
        }
      ]

      json = PublicEventSchema.generate_with_occurrences(event, occurrences)
      schemas = Jason.decode!(json)

      # First showtime should have 3D format
      first_schema = Enum.find(schemas, &(&1["startDate"] == "2024-12-15T15:00:00Z"))
      assert first_schema["videoFormat"] == "3D"

      # Second showtime should have both IMAX and 3D
      second_schema = Enum.find(schemas, &(&1["startDate"] == "2024-12-15T18:00:00Z"))
      assert is_list(second_schema["videoFormat"])
      assert "3D" in second_schema["videoFormat"]
      assert "IMAX" in second_schema["videoFormat"]
    end

    test "includes workPresented movie in each occurrence", %{event: event} do
      occurrences = [
        %{
          datetime: ~U[2024-12-15 19:00:00Z],
          date: ~D[2024-12-15],
          time: ~T[19:00:00],
          label: "2D",
          external_id: "cinema_city_123"
        }
      ]

      json = PublicEventSchema.generate_with_occurrences(event, occurrences)
      schema = Jason.decode!(json)

      assert schema["workPresented"]
      assert schema["workPresented"]["@type"] == "Movie"
      assert schema["workPresented"]["name"] == "Avatar: Fire and Ash"
    end

    test "uses MovieTheater location for cinema venues", %{event: event} do
      occurrences = [
        %{
          datetime: ~U[2024-12-15 19:00:00Z],
          date: ~D[2024-12-15],
          time: ~T[19:00:00],
          label: "2D",
          external_id: "cinema_city_123"
        }
      ]

      json = PublicEventSchema.generate_with_occurrences(event, occurrences)
      schema = Jason.decode!(json)

      assert schema["location"]
      assert schema["location"]["@type"] == "MovieTheater"
      assert schema["location"]["name"] == "Cinema City"
    end

    test "falls back to regular generate for non-movie events", %{venue: venue} do
      # Create a music event (not a movie)
      music_category = %Category{
        id: 2,
        name: "Concerts",
        slug: "concerts",
        schema_type: "MusicEvent"
      }

      music_event = %PublicEvent{
        id: 2,
        title: "Rock Concert",
        slug: "rock-concert",
        starts_at: ~U[2024-12-15 20:00:00Z],
        venue: venue,
        categories: [music_category],
        performers: [],
        movies: [],
        sources: []
      }

      occurrences = [
        %{
          datetime: ~U[2024-12-15 20:00:00Z],
          date: ~D[2024-12-15],
          time: ~T[20:00:00],
          label: nil,
          external_id: "concert_123"
        }
      ]

      json = PublicEventSchema.generate_with_occurrences(music_event, occurrences)
      schema = Jason.decode!(json)

      # Non-movie events should use regular generate (single schema)
      assert is_map(schema)
      assert schema["@type"] == "MusicEvent"
    end
  end
end
