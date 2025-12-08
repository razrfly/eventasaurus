defmodule EventasaurusWeb.JsonLd.ItemListSchemaTest do
  use ExUnit.Case, async: true

  alias EventasaurusWeb.JsonLd.ItemListSchema
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Categories.Category
  alias EventasaurusDiscovery.Locations.{City, Country}

  describe "build_item_list_schema/5" do
    setup do
      # Create country, city
      country = %Country{id: 1, name: "Poland", code: "PL", slug: "poland"}
      city = %City{id: 1, name: "Kraków", slug: "krakow", country_id: 1, country: country}

      # Create venue
      venue = %Venue{
        id: 1,
        name: "Test Venue",
        address: "Test Street 123",
        slug: "test-venue",
        latitude: 50.0647,
        longitude: 19.9450,
        city_id: 1,
        city_ref: city
      }

      # Create category
      category = %Category{
        id: 1,
        name: "Trivia Nights",
        slug: "trivia-nights",
        schema_type: "SocialEvent"
      }

      # Create events
      events = [
        %PublicEvent{
          id: 1,
          title: "Monday Trivia",
          slug: "monday-trivia",
          starts_at: ~U[2024-12-15 19:00:00Z],
          ends_at: ~U[2024-12-15 22:00:00Z],
          venue_id: 1,
          venue: venue,
          categories: [category],
          performers: [],
          movies: [],
          sources: []
        },
        %PublicEvent{
          id: 2,
          title: "Tuesday Quiz Night",
          slug: "tuesday-quiz",
          starts_at: ~U[2024-12-16 19:00:00Z],
          ends_at: ~U[2024-12-16 22:00:00Z],
          venue_id: 1,
          venue: venue,
          categories: [category],
          performers: [],
          movies: [],
          sources: []
        }
      ]

      {:ok, events: events, city: city, category: category}
    end

    test "generates basic ItemList schema", %{events: events, city: city} do
      schema = ItemListSchema.build_item_list_schema(events, "SocialEvent", "trivia-nights", city)

      assert schema["@context"] == "https://schema.org"
      assert schema["@type"] == "ItemList"
      assert schema["numberOfItems"] == 2
    end

    test "generates list name with identifier and city", %{events: events, city: city} do
      schema = ItemListSchema.build_item_list_schema(events, "SocialEvent", "trivia-nights", city)

      assert schema["name"] == "Trivia Nights - social events in Kraków"
    end

    test "generates description with event count", %{events: events, city: city} do
      schema = ItemListSchema.build_item_list_schema(events, "SocialEvent", "trivia-nights", city)

      assert schema["description"] ==
               "Discover trivia nights and other social events in Kraków. 2 events available."
    end

    test "uses singular 'event' for single event", %{events: events, city: city} do
      single_event = [List.first(events)]

      schema =
        ItemListSchema.build_item_list_schema(single_event, "SocialEvent", "trivia-nights", city)

      assert String.contains?(schema["description"], "1 event available")
    end

    test "generates canonical URL", %{events: events, city: city} do
      schema = ItemListSchema.build_item_list_schema(events, "SocialEvent", "trivia-nights", city)

      # Note: Uses EventasaurusDiscovery.AggregationTypeSlug mapping (SocialEvent -> "social")
      assert String.contains?(schema["url"], "/c/krakow/social/trivia-nights")
    end

    test "generates JSON-LD string", %{events: events, city: city} do
      json_ld = ItemListSchema.generate(events, "SocialEvent", "trivia-nights", city)

      assert is_binary(json_ld)
      assert String.contains?(json_ld, "\"@context\":\"https://schema.org\"")
      assert String.contains?(json_ld, "\"@type\":\"ItemList\"")
    end
  end

  describe "itemListElement" do
    setup do
      country = %Country{id: 1, name: "Poland", code: "PL", slug: "poland"}
      city = %City{id: 1, name: "Kraków", slug: "krakow", country_id: 1, country: country}

      venue = %Venue{
        id: 1,
        name: "Test Venue",
        slug: "test-venue",
        city_ref: city
      }

      category = %Category{
        id: 1,
        name: "Music Events",
        slug: "music",
        schema_type: "MusicEvent"
      }

      events = [
        %PublicEvent{
          id: 1,
          title: "Concert A",
          slug: "concert-a",
          starts_at: ~U[2024-12-15 19:00:00Z],
          venue: venue,
          categories: [category],
          performers: [],
          movies: [],
          sources: []
        },
        %PublicEvent{
          id: 2,
          title: "Concert B",
          slug: "concert-b",
          starts_at: ~U[2024-12-16 19:00:00Z],
          venue: venue,
          categories: [category],
          performers: [],
          movies: [],
          sources: []
        }
      ]

      {:ok, events: events, city: city}
    end

    test "includes ListItem for each event with position", %{events: events, city: city} do
      schema = ItemListSchema.build_item_list_schema(events, "MusicEvent", "concerts", city)

      items = schema["itemListElement"]
      assert length(items) == 2

      first_item = Enum.at(items, 0)
      assert first_item["@type"] == "ListItem"
      assert first_item["position"] == 1

      second_item = Enum.at(items, 1)
      assert second_item["@type"] == "ListItem"
      assert second_item["position"] == 2
    end

    test "includes full event schema in each ListItem", %{events: events, city: city} do
      schema = ItemListSchema.build_item_list_schema(events, "MusicEvent", "concerts", city)

      first_item = Enum.at(schema["itemListElement"], 0)
      event_schema = first_item["item"]

      assert event_schema["@type"] == "MusicEvent"
      assert event_schema["name"] == "Concert A"
      assert event_schema["startDate"] == "2024-12-15T19:00:00Z"
    end
  end

  describe "max_items option" do
    setup do
      country = %Country{id: 1, name: "Poland", code: "PL", slug: "poland"}
      city = %City{id: 1, name: "Kraków", slug: "krakow", country_id: 1, country: country}

      venue = %Venue{id: 1, name: "Test Venue", slug: "test-venue", city_ref: city}
      category = %Category{id: 1, name: "Events", slug: "events", schema_type: "Event"}

      # Create 25 events
      events =
        Enum.map(1..25, fn i ->
          %PublicEvent{
            id: i,
            title: "Event #{i}",
            slug: "event-#{i}",
            starts_at: ~U[2024-12-15 19:00:00Z],
            venue: venue,
            categories: [category],
            performers: [],
            movies: [],
            sources: []
          }
        end)

      {:ok, events: events, city: city}
    end

    test "defaults to 20 items", %{events: events, city: city} do
      schema = ItemListSchema.build_item_list_schema(events, "Event", "all-events", city)

      assert schema["numberOfItems"] == 20
      assert length(schema["itemListElement"]) == 20
    end

    test "respects max_items option", %{events: events, city: city} do
      schema =
        ItemListSchema.build_item_list_schema(events, "Event", "all-events", city, max_items: 10)

      assert schema["numberOfItems"] == 10
      assert length(schema["itemListElement"]) == 10
    end

    test "description shows total count even when limited", %{events: events, city: city} do
      schema =
        ItemListSchema.build_item_list_schema(events, "Event", "all-events", city, max_items: 10)

      # Description should show total count (25), not limited count (10)
      assert String.contains?(schema["description"], "25 events available")
    end
  end

  describe "schema type friendly names" do
    setup do
      country = %Country{id: 1, name: "USA", code: "US", slug: "usa"}
      city = %City{id: 1, name: "New York", slug: "new-york", country_id: 1, country: country}

      venue = %Venue{id: 1, name: "Test Venue", slug: "test-venue", city_ref: city}

      event = %PublicEvent{
        id: 1,
        title: "Test Event",
        slug: "test-event",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [],
        performers: [],
        movies: [],
        sources: []
      }

      {:ok, event: event, city: city}
    end

    test "converts SocialEvent to 'social events'", %{event: event, city: city} do
      schema = ItemListSchema.build_item_list_schema([event], "SocialEvent", "trivia", city)

      assert String.contains?(schema["name"], "social events")
      assert String.contains?(schema["description"], "social events")
    end

    test "converts FoodEvent to 'food events'", %{event: event, city: city} do
      schema = ItemListSchema.build_item_list_schema([event], "FoodEvent", "tastings", city)

      assert String.contains?(schema["name"], "food events")
      assert String.contains?(schema["description"], "food events")
    end

    test "converts MusicEvent to 'music events'", %{event: event, city: city} do
      schema = ItemListSchema.build_item_list_schema([event], "MusicEvent", "concerts", city)

      assert String.contains?(schema["name"], "music events")
      assert String.contains?(schema["description"], "music events")
    end

    test "converts ComedyEvent to 'comedy shows'", %{event: event, city: city} do
      schema = ItemListSchema.build_item_list_schema([event], "ComedyEvent", "standup", city)

      assert String.contains?(schema["name"], "comedy shows")
      assert String.contains?(schema["description"], "comedy shows")
    end

    test "converts DanceEvent to 'dance performances'", %{event: event, city: city} do
      schema = ItemListSchema.build_item_list_schema([event], "DanceEvent", "ballet", city)

      assert String.contains?(schema["name"], "dance performances")
      assert String.contains?(schema["description"], "dance performances")
    end

    test "converts EducationEvent to 'classes and workshops'", %{event: event, city: city} do
      schema = ItemListSchema.build_item_list_schema([event], "EducationEvent", "workshops", city)

      assert String.contains?(schema["name"], "classes and workshops")
      assert String.contains?(schema["description"], "classes and workshops")
    end

    test "converts SportsEvent to 'sports events'", %{event: event, city: city} do
      schema = ItemListSchema.build_item_list_schema([event], "SportsEvent", "games", city)

      assert String.contains?(schema["name"], "sports events")
      assert String.contains?(schema["description"], "sports events")
    end

    test "converts TheaterEvent to 'theater performances'", %{event: event, city: city} do
      schema = ItemListSchema.build_item_list_schema([event], "TheaterEvent", "plays", city)

      assert String.contains?(schema["name"], "theater performances")
      assert String.contains?(schema["description"], "theater performances")
    end

    test "converts Festival to 'festivals'", %{event: event, city: city} do
      schema = ItemListSchema.build_item_list_schema([event], "Festival", "summer-fest", city)

      assert String.contains?(schema["name"], "festivals")
      assert String.contains?(schema["description"], "festivals")
    end

    test "converts ScreeningEvent to 'movie screenings'", %{event: event, city: city} do
      schema = ItemListSchema.build_item_list_schema([event], "ScreeningEvent", "films", city)

      assert String.contains?(schema["name"], "movie screenings")
      assert String.contains?(schema["description"], "movie screenings")
    end

    test "defaults unknown types to 'events'", %{event: event, city: city} do
      schema = ItemListSchema.build_item_list_schema([event], "UnknownEvent", "misc", city)

      assert String.contains?(schema["name"], "events")
      assert String.contains?(schema["description"], "events")
    end
  end

  describe "identifier formatting" do
    setup do
      country = %Country{id: 1, name: "USA", code: "US", slug: "usa"}
      city = %City{id: 1, name: "New York", slug: "new-york", country_id: 1, country: country}

      venue = %Venue{id: 1, name: "Test Venue", slug: "test-venue", city_ref: city}

      event = %PublicEvent{
        id: 1,
        title: "Test Event",
        slug: "test-event",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [],
        performers: [],
        movies: [],
        sources: []
      }

      {:ok, event: event, city: city}
    end

    test "converts hyphens to spaces in title", %{event: event, city: city} do
      schema =
        ItemListSchema.build_item_list_schema([event], "SocialEvent", "trivia-nights", city)

      assert String.contains?(schema["name"], "Trivia Nights")
    end

    test "capitalizes each word in title", %{event: event, city: city} do
      schema =
        ItemListSchema.build_item_list_schema([event], "SocialEvent", "open-mic-comedy", city)

      assert String.contains?(schema["name"], "Open Mic Comedy")
    end

    test "keeps hyphens in description", %{event: event, city: city} do
      schema =
        ItemListSchema.build_item_list_schema([event], "SocialEvent", "trivia-nights", city)

      assert String.contains?(schema["description"], "trivia nights")
    end
  end

  describe "empty event list" do
    test "handles empty event list gracefully" do
      country = %Country{id: 1, name: "USA", code: "US", slug: "usa"}
      city = %City{id: 1, name: "New York", slug: "new-york", country_id: 1, country: country}

      schema = ItemListSchema.build_item_list_schema([], "SocialEvent", "trivia", city)

      assert schema["numberOfItems"] == 0
      assert schema["itemListElement"] == []
      assert String.contains?(schema["description"], "0 events available")
    end
  end

  describe "canonical URL construction" do
    test "constructs correct URL for different schema types" do
      country = %Country{id: 1, name: "USA", code: "US", slug: "usa"}
      city = %City{id: 1, name: "New York", slug: "new-york", country_id: 1, country: country}

      venue = %Venue{id: 1, name: "Test Venue", slug: "test-venue", city_ref: city}

      event = %PublicEvent{
        id: 1,
        title: "Test Event",
        slug: "test-event",
        starts_at: ~U[2024-12-15 19:00:00Z],
        venue: venue,
        categories: [],
        performers: [],
        movies: [],
        sources: []
      }

      # Note: Uses EventasaurusDiscovery.AggregationTypeSlug mapping
      # Test SocialEvent -> social
      schema = ItemListSchema.build_item_list_schema([event], "SocialEvent", "trivia", city)
      assert String.contains?(schema["url"], "/c/new-york/social/trivia")

      # Test MusicEvent -> music
      schema = ItemListSchema.build_item_list_schema([event], "MusicEvent", "concerts", city)
      assert String.contains?(schema["url"], "/c/new-york/music/concerts")

      # Test FoodEvent -> food
      schema = ItemListSchema.build_item_list_schema([event], "FoodEvent", "tastings", city)
      assert String.contains?(schema["url"], "/c/new-york/food/tastings")

      # Test ScreeningEvent -> movies
      schema =
        ItemListSchema.build_item_list_schema([event], "ScreeningEvent", "indie-films", city)

      assert String.contains?(schema["url"], "/c/new-york/movies/indie-films")
    end
  end
end
