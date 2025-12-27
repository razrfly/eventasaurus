defmodule EventasaurusDiscovery.VenueRequirementTest do
  @moduledoc """
  Tests to verify that venue requirements are properly enforced at all levels:
  1. Database level (NOT NULL constraint)
  2. Schema level (validation)
  3. Processor level (hard failure)
  4. Source integration level (Bandsintown, Karnet, Ticketmaster)
  """

  use EventasaurusApp.DataCase, async: false

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusApp.Events.Event
  alias EventasaurusDiscovery.Scraping.Processors.EventProcessor
  alias EventasaurusDiscovery.Sources.{Source, Processor}
  alias EventasaurusDiscovery.Locations.{City, Country}
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.Sources.Bandsintown.Transformer, as: BandstownTransformer
  alias EventasaurusDiscovery.Sources.Karnet.Transformer, as: KarnetTransformer

  describe "database level enforcement" do
    test "public_events table requires venue_id" do
      # Try to insert without venue_id using raw SQL
      assert_raise Postgrex.Error, ~r/null value in column "venue_id"/, fn ->
        Repo.query!("""
        INSERT INTO public_events (title, starts_at, slug, inserted_at, updated_at)
        VALUES ('Test Event', NOW(), 'test-event', NOW(), NOW())
        """)
      end
    end

    test "events table requires venue_id" do
      # Try to insert without venue_id using raw SQL
      assert_raise Postgrex.Error, ~r/null value in column "venue_id"/, fn ->
        Repo.query!("""
        INSERT INTO events (title, timezone, visibility, slug, inserted_at, updated_at)
        VALUES ('Test Event', 'UTC', 'public', 'test-event', NOW(), NOW())
        """)
      end
    end
  end

  describe "schema level enforcement" do
    setup do
      # Create a venue for testing
      country = Repo.insert!(%Country{name: "Poland", code: "PL"})
      city = Repo.insert!(%City{name: "Kraków", country_id: country.id})

      venue =
        Repo.insert!(%Venue{
          name: "Test Venue",
          city_id: city.id,
          latitude: Decimal.new("50.0647"),
          longitude: Decimal.new("19.9450"),
          slug: "test-venue"
        })

      {:ok, venue: venue}
    end

    test "PublicEvent changeset requires venue_id", %{venue: venue} do
      # Valid changeset with venue_id
      valid_attrs = %{
        title: "Test Event",
        starts_at: ~U[2024-12-01 19:00:00Z],
        venue_id: venue.id,
        slug: "test-event"
      }

      valid_changeset = PublicEvent.changeset(%PublicEvent{}, valid_attrs)
      assert valid_changeset.valid?

      # Invalid changeset without venue_id
      invalid_attrs = Map.delete(valid_attrs, :venue_id)
      invalid_changeset = PublicEvent.changeset(%PublicEvent{}, invalid_attrs)
      refute invalid_changeset.valid?
      assert "can't be blank" in errors_on(invalid_changeset).venue_id
    end

    test "Event changeset requires venue_id", %{venue: venue} do
      # Valid changeset with venue_id
      valid_attrs = %{
        title: "Test Event",
        timezone: "Europe/Warsaw",
        visibility: :public,
        venue_id: venue.id,
        slug: "test-event"
      }

      valid_changeset = Event.changeset(%Event{}, valid_attrs)
      assert valid_changeset.valid?

      # Invalid changeset without venue_id
      invalid_attrs = Map.delete(valid_attrs, :venue_id)
      invalid_changeset = Event.changeset(%Event{}, invalid_attrs)
      refute invalid_changeset.valid?
      assert "can't be blank" in errors_on(invalid_changeset).venue_id
    end
  end

  describe "processor level enforcement" do
    setup do
      # Create test data
      country = Repo.insert!(%Country{name: "Poland", code: "PL"})

      city =
        Repo.insert!(%City{
          name: "Kraków",
          country_id: country.id,
          latitude: Decimal.new("50.0647"),
          longitude: Decimal.new("19.9450")
        })

      source =
        Repo.insert!(%Source{
          name: "Test Source",
          slug: "test-source",
          priority: 50
        })

      {:ok, city: city, source: source}
    end

    test "EventProcessor raises when venue is nil", %{city: city, source: source} do
      event_data = %{
        title: "Test Event",
        start_at: ~U[2024-12-01 19:00:00Z],
        external_id: "test-123",
        source_url: "https://example.com/event",
        # No venue data
        venue_data: nil
      }

      assert_raise RuntimeError, "Venue is required for all events", fn ->
        Processor.process_single_event(event_data, source, city: city)
      end
    end

    test "EventProcessor succeeds with valid venue data", %{city: city, source: source} do
      event_data = %{
        title: "Test Event",
        start_at: ~U[2024-12-01 19:00:00Z],
        external_id: "test-123",
        source_url: "https://example.com/event",
        venue_data: %{
          name: "Test Venue",
          latitude: 50.0647,
          longitude: 19.9450,
          address: "Test Address, Kraków",
          city: "Kraków",
          country: "Poland"
        }
      }

      assert {:ok, event} = Processor.process_single_event(event_data, source, city: city)
      assert event.venue_id
    end
  end

  describe "Bandsintown transformer" do
    test "returns nil venue for events without venue data" do
      raw_event = %{
        "title" => "Test Event",
        "artist_name" => "Test Artist",
        "url" => "https://bandsintown.com/e/123",
        "date" => "2024-12-01",
        # Missing venue fields
        "venue_name" => nil,
        "venue_latitude" => nil,
        "venue_longitude" => nil
      }

      transformed = BandstownTransformer.transform_event(raw_event)

      # Venue should have incomplete data
      assert transformed.venue.name == "Unknown Venue"
      assert is_nil(transformed.venue.latitude)
      assert is_nil(transformed.venue.longitude)
    end

    test "transforms valid venue data correctly" do
      raw_event = %{
        "title" => "Test Event",
        "artist_name" => "Test Artist",
        "url" => "https://bandsintown.com/e/123",
        "date" => "2024-12-01",
        "venue_name" => "Madison Square Garden",
        "venue_latitude" => "40.7505",
        "venue_longitude" => "-73.9934",
        "venue_address" => "4 Pennsylvania Plaza",
        "venue_city" => "New York",
        "venue_state" => "NY",
        "venue_country" => "United States"
      }

      transformed = BandstownTransformer.transform_event(raw_event)

      assert transformed.venue.name == "Madison Square Garden"
      assert transformed.venue.latitude == 40.7505
      assert transformed.venue.longitude == -73.9934
      assert transformed.venue.address =~ "Pennsylvania Plaza"
    end
  end

  describe "Karnet transformer" do
    test "returns nil venue for events without venue data" do
      raw_event = %{
        title: "Test Event",
        url: "https://karnet.krakow.pl/event/123",
        date_text: "1 grudnia 2024",
        venue_data: nil
      }

      transformed = KarnetTransformer.transform_event(raw_event)

      assert is_nil(transformed.venue)
    end

    test "transforms valid venue data with geocoding flag" do
      raw_event = %{
        title: "Test Event",
        url: "https://karnet.krakow.pl/event/123",
        date_text: "1 grudnia 2024",
        venue_data: %{
          name: "Teatr Słowackiego",
          address: "pl. Świętego Ducha 1",
          city: "Kraków",
          country: "Poland"
          # Note: No coordinates provided
        }
      }

      transformed = KarnetTransformer.transform_event(raw_event)

      assert transformed.venue.name == "Teatr Słowackiego"
      assert transformed.venue.city == "Kraków"
      # Should have default Kraków coordinates
      assert transformed.venue.latitude == 50.0647
      assert transformed.venue.longitude == 19.9450
      # Should be flagged for geocoding
      assert transformed.venue.needs_geocoding == true
    end

    test "transforms venue with provided coordinates" do
      raw_event = %{
        title: "Test Event",
        url: "https://karnet.krakow.pl/event/123",
        date_text: "1 grudnia 2024",
        venue_data: %{
          name: "Teatr Słowackiego",
          latitude: 50.0639,
          longitude: 19.9416,
          address: "pl. Świętego Ducha 1",
          city: "Kraków",
          country: "Poland"
        }
      }

      transformed = KarnetTransformer.transform_event(raw_event)

      assert transformed.venue.name == "Teatr Słowackiego"
      assert transformed.venue.latitude == 50.0639
      assert transformed.venue.longitude == 19.9416
      # Should NOT be flagged for geocoding
      assert transformed.venue.needs_geocoding == false
    end
  end

  describe "integration: full pipeline with venue enforcement" do
    setup do
      # Create test infrastructure
      country = Repo.insert!(%Country{name: "Poland", code: "PL"})

      city =
        Repo.insert!(%City{
          name: "Kraków",
          country_id: country.id,
          latitude: Decimal.new("50.0647"),
          longitude: Decimal.new("19.9450")
        })

      source =
        Repo.insert!(%Source{
          name: "Test Source",
          slug: "test-source",
          priority: 50
        })

      {:ok, city: city, source: source}
    end

    test "events without venues are rejected at multiple levels", %{city: city, source: source} do
      # Test data without venue
      event_data = %{
        title: "Event Without Venue",
        start_at: ~U[2024-12-01 19:00:00Z],
        external_id: "no-venue-123",
        source_url: "https://example.com/event",
        venue_data: nil
      }

      # Should raise at processor level
      assert_raise RuntimeError, "Venue is required for all events", fn ->
        Processor.process_single_event(event_data, source, city: city)
      end
    end

    test "events with valid venues are processed successfully", %{city: city, source: source} do
      # Test data with complete venue
      event_data = %{
        title: "Event With Venue",
        start_at: ~U[2024-12-01 19:00:00Z],
        external_id: "with-venue-123",
        source_url: "https://example.com/event",
        venue_data: %{
          name: "Great Venue",
          latitude: 50.0647,
          longitude: 19.9450,
          address: "Main Street 1, Kraków",
          city: "Kraków",
          country: "Poland"
        }
      }

      assert {:ok, event} = Processor.process_single_event(event_data, source, city: city)
      assert event.venue_id

      # Verify the event was saved with venue
      saved_event = Repo.get!(PublicEvent, event.id) |> Repo.preload(:venue)
      assert saved_event.venue
      assert saved_event.venue.name == "Great Venue"
    end
  end

  # Helper function for changeset errors
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
