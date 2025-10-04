defmodule EventasaurusApp.Venues.VenueValidationTest do
  use EventasaurusApp.DataCase
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusApp.Repo

  # Helper to create a test city for tests that need city_id
  defp create_test_city do
    {:ok, country} =
      EventasaurusDiscovery.Locations.Country.changeset(
        %EventasaurusDiscovery.Locations.Country{},
        %{name: "Poland", code: "PL"}
      )
      |> Repo.insert()

    {:ok, city} =
      EventasaurusDiscovery.Locations.City.changeset(
        %EventasaurusDiscovery.Locations.City{},
        %{name: "Kraków", slug: "krakow", country_id: country.id}
      )
      |> Repo.insert()

    city
  end

  describe "GPS coordinate validation" do
    test "requires both latitude and longitude for physical venues" do
      changeset =
        Venue.changeset(%Venue{}, %{
          name: "Test Venue",
          venue_type: "venue",
          source: "scraper"
        })

      refute changeset.valid?
      assert {:latitude, {"GPS coordinates are required for physical venues", []}} in changeset.errors
      assert {:longitude, {"GPS coordinates are required for physical venues", []}} in changeset.errors
    end

    test "accepts valid coordinates" do
      city = create_test_city()

      changeset =
        Venue.changeset(%Venue{}, %{
          name: "Test Venue",
          venue_type: "venue",
          source: "scraper",
          latitude: 50.0619,
          longitude: 19.9368,
          city_id: city.id
        })

      assert changeset.valid?
    end

    test "rejects latitude outside valid range" do
      changeset =
        Venue.changeset(%Venue{}, %{
          name: "Test Venue",
          venue_type: "venue",
          source: "scraper",
          # Invalid - > 90
          latitude: 91.0,
          longitude: 19.9368
        })

      refute changeset.valid?
      assert {:latitude, {"must be between -90 and 90 degrees", []}} in changeset.errors
    end

    test "rejects longitude outside valid range" do
      changeset =
        Venue.changeset(%Venue{}, %{
          name: "Test Venue",
          venue_type: "venue",
          source: "scraper",
          latitude: 50.0619,
          # Invalid - > 180
          longitude: 181.0
        })

      refute changeset.valid?
      assert {:longitude, {"must be between -180 and 180 degrees", []}} in changeset.errors
    end

    test "requires both coordinates together" do
      # Only latitude provided
      changeset1 =
        Venue.changeset(%Venue{}, %{
          name: "Test Venue",
          venue_type: "venue",
          source: "scraper",
          latitude: 50.0619
        })

      refute changeset1.valid?
      assert {:longitude, {"is required when latitude is provided", []}} in changeset1.errors

      # Only longitude provided
      changeset2 =
        Venue.changeset(%Venue{}, %{
          name: "Test Venue",
          venue_type: "venue",
          source: "scraper",
          longitude: 19.9368
        })

      refute changeset2.valid?
      assert {:latitude, {"is required when longitude is provided", []}} in changeset2.errors
    end

    test "prevents insertion of physical venue without coordinates" do
      {:error, changeset} =
        %Venue{}
        |> Venue.changeset(%{
          name: "Venue Without Coordinates",
          venue_type: "venue",
          source: "scraper",
          address: "123 Main St"
        })
        |> Repo.insert()

      refute changeset.valid?
      assert {:latitude, {"GPS coordinates are required for physical venues", []}} in changeset.errors
      assert {:longitude, {"GPS coordinates are required for physical venues", []}} in changeset.errors
    end

    test "allows insertion of venue with valid coordinates" do
      city = create_test_city()

      {:ok, venue} =
        %Venue{}
        |> Venue.changeset(%{
          name: "Venue With Coordinates",
          venue_type: "venue",
          source: "scraper",
          latitude: 50.0619,
          longitude: 19.9368,
          address: "123 Main St",
          city_id: city.id
        })
        |> Repo.insert()

      assert venue.latitude == 50.0619
      assert venue.longitude == 19.9368
    end

    test "city venues require coordinates" do
      changeset =
        Venue.changeset(%Venue{}, %{
          name: "San Francisco",
          venue_type: "city",
          source: "user"
        })

      refute changeset.valid?
      assert {:latitude, {"GPS coordinates are required for physical venues", []}} in changeset.errors
      assert {:longitude, {"GPS coordinates are required for physical venues", []}} in changeset.errors
    end

    test "region venues require coordinates" do
      changeset =
        Venue.changeset(%Venue{}, %{
          name: "Bay Area",
          venue_type: "region",
          source: "user"
        })

      refute changeset.valid?
      assert {:latitude, {"GPS coordinates are required for physical venues", []}} in changeset.errors
      assert {:longitude, {"GPS coordinates are required for physical venues", []}} in changeset.errors
    end

    test "city venues accept valid coordinates" do
      city = create_test_city()

      {:ok, venue} =
        %Venue{}
        |> Venue.changeset(%{
          name: "San Francisco",
          venue_type: "city",
          source: "user",
          latitude: 37.7749,
          longitude: -122.4194,
          city_id: city.id
        })
        |> Repo.insert()

      assert venue.venue_type == "city"
      assert venue.latitude == 37.7749
      assert venue.longitude == -122.4194
    end

    test "region venues accept valid coordinates" do
      {:ok, venue} =
        %Venue{}
        |> Venue.changeset(%{
          name: "Bay Area",
          venue_type: "region",
          source: "user",
          latitude: 37.8,
          longitude: -122.4
        })
        |> Repo.insert()

      assert venue.venue_type == "region"
      assert venue.latitude == 37.8
      assert venue.longitude == -122.4
    end

    test "venue type requires city_id" do
      changeset =
        Venue.changeset(%Venue{}, %{
          name: "Test Theater",
          venue_type: "venue",
          source: "user",
          latitude: 37.7749,
          longitude: -122.4194
        })

      refute changeset.valid?
      assert {:city_id, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "city type requires city_id" do
      changeset =
        Venue.changeset(%Venue{}, %{
          name: "San Francisco",
          venue_type: "city",
          source: "user",
          latitude: 37.7749,
          longitude: -122.4194
        })

      refute changeset.valid?
      assert {:city_id, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "region type allows NULL city_id" do
      changeset =
        Venue.changeset(%Venue{}, %{
          name: "Bay Area",
          venue_type: "region",
          source: "user",
          latitude: 37.8,
          longitude: -122.4
        })

      assert changeset.valid?
    end

    test "region type with city_id is valid" do
      # Create a test city
      {:ok, country} =
        EventasaurusDiscovery.Locations.Country.changeset(
          %EventasaurusDiscovery.Locations.Country{},
          %{name: "United States", code: "US"}
        )
        |> Repo.insert()

      {:ok, city} =
        EventasaurusDiscovery.Locations.City.changeset(
          %EventasaurusDiscovery.Locations.City{},
          %{name: "San Francisco", slug: "san-francisco", country_id: country.id}
        )
        |> Repo.insert()

      changeset =
        Venue.changeset(%Venue{}, %{
          name: "Bay Area",
          venue_type: "region",
          source: "user",
          latitude: 37.8,
          longitude: -122.4,
          city_id: city.id
        })

      assert changeset.valid?
    end

    test "venue with city_id passes validation and db constraint" do
      # Create a test city
      {:ok, country} =
        EventasaurusDiscovery.Locations.Country.changeset(
          %EventasaurusDiscovery.Locations.Country{},
          %{name: "Poland", code: "PL"}
        )
        |> Repo.insert()

      {:ok, city} =
        EventasaurusDiscovery.Locations.City.changeset(
          %EventasaurusDiscovery.Locations.City{},
          %{name: "Kraków", slug: "krakow", country_id: country.id}
        )
        |> Repo.insert()

      {:ok, venue} =
        %Venue{}
        |> Venue.changeset(%{
          name: "Kino Pod Baranami",
          venue_type: "venue",
          source: "user",
          latitude: 50.0619,
          longitude: 19.9368,
          city_id: city.id
        })
        |> Repo.insert()

      assert venue.city_id == city.id
      assert venue.venue_type == "venue"
    end
  end
end
