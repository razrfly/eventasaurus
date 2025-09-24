defmodule EventasaurusWeb.Services.GooglePlaces.VenueGeocoderTest do
  use ExUnit.Case
  alias EventasaurusWeb.Services.GooglePlaces.VenueGeocoder

  describe "build_geocoding_query/1" do
    test "builds query with all components" do
      venue_data = %{
        name: "The Blue Note",
        address: "123 Main St",
        city_name: "New York",
        state: "NY",
        country_name: "USA"
      }

      query = VenueGeocoder.build_geocoding_query(venue_data)
      assert query == "The Blue Note, 123 Main St, New York, NY, USA"
    end

    test "builds query without street address" do
      venue_data = %{
        name: "Central Park",
        city_name: "New York",
        state: "NY",
        country_name: "USA"
      }

      query = VenueGeocoder.build_geocoding_query(venue_data)
      assert query == "Central Park, New York, NY, USA"
    end

    test "builds query with minimal data" do
      venue_data = %{
        name: "Venue Name",
        city_name: "Kraków",
        country_name: "Poland"
      }

      query = VenueGeocoder.build_geocoding_query(venue_data)
      assert query == "Venue Name, Kraków, Poland"
    end

    test "handles empty or nil values gracefully" do
      venue_data = %{
        name: "Test Venue",
        address: "",
        city_name: "Berlin",
        state: nil,
        country_name: "Germany"
      }

      query = VenueGeocoder.build_geocoding_query(venue_data)
      assert query == "Test Venue, Berlin, Germany"
    end
  end

  describe "valid_coordinates?/2" do
    test "returns true for valid coordinates" do
      assert VenueGeocoder.valid_coordinates?(40.7128, -74.0060) == true
      assert VenueGeocoder.valid_coordinates?(0, 0) == true
      assert VenueGeocoder.valid_coordinates?(-90, 180) == true
      assert VenueGeocoder.valid_coordinates?(90, -180) == true
    end

    test "returns false for invalid coordinates" do
      assert VenueGeocoder.valid_coordinates?(nil, nil) == false
      assert VenueGeocoder.valid_coordinates?(91, 0) == false
      assert VenueGeocoder.valid_coordinates?(0, 181) == false
      assert VenueGeocoder.valid_coordinates?(-91, 0) == false
      assert VenueGeocoder.valid_coordinates?(0, -181) == false
      assert VenueGeocoder.valid_coordinates?("40", "50") == false
    end
  end

  @tag :integration
  describe "geocode_venue/1" do
    test "returns error when API key is not configured" do
      # This test will only run if GOOGLE_MAPS_API_KEY is not set
      if is_nil(System.get_env("GOOGLE_MAPS_API_KEY")) do
        venue_data = %{
          name: "Test Venue",
          city_name: "New York",
          country_name: "USA"
        }

        assert {:error, "No API key configured"} = VenueGeocoder.geocode_venue(venue_data)
      end
    end

    test "returns error for insufficient address data" do
      venue_data = %{}

      assert {:error, "Insufficient address data for geocoding"} =
               VenueGeocoder.geocode_venue(venue_data)
    end
  end
end
