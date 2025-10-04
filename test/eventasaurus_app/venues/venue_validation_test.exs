defmodule EventasaurusApp.Venues.VenueValidationTest do
  use EventasaurusApp.DataCase
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusApp.Repo

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

    test "allows online venues without coordinates (application level)" do
      # Note: While this passes application validation, the database-level
      # NOT NULL constraint will prevent actual insertion without coordinates
      changeset =
        Venue.changeset(%Venue{}, %{
          name: "Online Venue",
          venue_type: "online",
          source: "user"
        })

      assert changeset.valid?
    end

    test "allows tbd venues without coordinates (application level)" do
      # Note: While this passes application validation, the database-level
      # NOT NULL constraint will prevent actual insertion without coordinates
      changeset =
        Venue.changeset(%Venue{}, %{
          name: "TBD Venue",
          venue_type: "tbd",
          source: "user"
        })

      assert changeset.valid?
    end

    test "accepts valid coordinates" do
      changeset =
        Venue.changeset(%Venue{}, %{
          name: "Test Venue",
          venue_type: "venue",
          source: "scraper",
          latitude: 50.0619,
          longitude: 19.9368
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
      {:ok, venue} =
        %Venue{}
        |> Venue.changeset(%{
          name: "Venue With Coordinates",
          venue_type: "venue",
          source: "scraper",
          latitude: 50.0619,
          longitude: 19.9368,
          address: "123 Main St"
        })
        |> Repo.insert()

      assert venue.latitude == 50.0619
      assert venue.longitude == 19.9368
    end
  end
end
