defmodule EventasaurusDiscovery.Sources.Quizmeisters.Extractors.VenueExtractorTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Sources.Quizmeisters.Extractors.VenueExtractor

  @fixtures_dir Path.join([__DIR__, "..", "fixtures"])

  describe "extract_venue_data/1" do
    setup do
      # Load fixture data
      fixture_path = Path.join(@fixtures_dir, "api_response.json")
      {:ok, fixture_content} = File.read(fixture_path)
      {:ok, %{"results" => %{"locations" => locations}}} = Jason.decode(fixture_content)

      {:ok, locations: locations}
    end

    test "extracts all fields from complete venue data", %{locations: [location | _]} do
      assert {:ok, venue_data} = VenueExtractor.extract_venue_data(location)

      assert venue_data.venue_id == "library-bar"
      assert venue_data.name == "The Library Bar"
      assert venue_data.address == "123 Main St, Brooklyn, NY 11201"
      assert venue_data.latitude == 40.7128
      assert venue_data.longitude == -74.006
      assert venue_data.phone == "555-123-4567"
      assert venue_data.postcode == "11201"
      assert venue_data.url == "https://quizmeisters.com/venues/library-bar"
      assert venue_data.time_text == "Wednesdays at 7pm"
      assert venue_data.source_url == "https://quizmeisters.com/venues/library-bar"
    end

    test "extracts venue ID from URL slug", %{locations: [location | _]} do
      assert {:ok, venue_data} = VenueExtractor.extract_venue_data(location)
      assert venue_data.venue_id == "library-bar"
    end

    test "handles Survey Says field type", %{locations: [_, location | _]} do
      assert {:ok, venue_data} = VenueExtractor.extract_venue_data(location)
      assert venue_data.time_text == "Thursdays at 8:00 PM"
    end

    test "handles missing phone number", %{locations: [_, _, location | _]} do
      assert {:ok, venue_data} = VenueExtractor.extract_venue_data(location)
      assert is_nil(venue_data.phone)
      # Should still succeed since phone is optional
      assert venue_data.name == "Downtown Pub"
    end

    test "prefers Trivia field over other fields", %{locations: [_, _, location | _]} do
      # This location has both "Trivia" and "Other" fields
      assert {:ok, venue_data} = VenueExtractor.extract_venue_data(location)
      assert venue_data.time_text == "Tuesdays at 7:30pm"
    end

    test "parses GPS coordinates as floats" do
      location = %{
        "name" => "Test Venue",
        "address" => "123 Test St",
        "lat" => 40.7128,
        "lng" => -74.006,
        "url" => "https://quizmeisters.com/venues/test",
        "fields" => [%{"name" => "Trivia", "pivot_field_value" => "Mondays at 7pm"}]
      }

      assert {:ok, venue_data} = VenueExtractor.extract_venue_data(location)
      assert is_float(venue_data.latitude)
      assert is_float(venue_data.longitude)
      assert venue_data.latitude == 40.7128
      assert venue_data.longitude == -74.006
    end

    test "converts string coordinates to floats" do
      location = %{
        "name" => "Test Venue",
        "address" => "123 Test St",
        "lat" => "40.7128",
        "lng" => "-74.006",
        "url" => "https://quizmeisters.com/venues/test",
        "fields" => [%{"name" => "Trivia", "pivot_field_value" => "Mondays at 7pm"}]
      }

      assert {:ok, venue_data} = VenueExtractor.extract_venue_data(location)
      assert is_float(venue_data.latitude)
      assert is_float(venue_data.longitude)
      assert venue_data.latitude == 40.7128
      assert venue_data.longitude == -74.006
    end

    test "converts integer coordinates to floats" do
      location = %{
        "name" => "Test Venue",
        "address" => "123 Test St",
        "lat" => 40,
        "lng" => -74,
        "url" => "https://quizmeisters.com/venues/test",
        "fields" => [%{"name" => "Trivia", "pivot_field_value" => "Mondays at 7pm"}]
      }

      assert {:ok, venue_data} = VenueExtractor.extract_venue_data(location)
      assert is_float(venue_data.latitude)
      assert is_float(venue_data.longitude)
      assert venue_data.latitude == 40.0
      assert venue_data.longitude == -74.0
    end

    test "returns error when URL is missing" do
      # URL is required for source_url field
      location = %{
        "name" => "The Test Bar & Grill",
        "address" => "123 Test St",
        "lat" => 40.7128,
        "lng" => -74.006,
        "url" => nil,
        "fields" => [%{"name" => "Trivia", "pivot_field_value" => "Mondays at 7pm"}]
      }

      assert {:error, :missing_required_field} = VenueExtractor.extract_venue_data(location)
    end

    test "returns error when required field is missing" do
      location = %{
        "name" => "Test Venue",
        "address" => "123 Test St"
        # Missing lat, lng, url, fields
      }

      assert {:error, :missing_required_field} = VenueExtractor.extract_venue_data(location)
    end

    test "returns error when name is missing" do
      location = %{
        "address" => "123 Test St",
        "lat" => 40.7128,
        "lng" => -74.006,
        "url" => "https://quizmeisters.com/venues/test",
        "fields" => [%{"name" => "Trivia", "pivot_field_value" => "Mondays at 7pm"}]
      }

      assert {:error, :missing_required_field} = VenueExtractor.extract_venue_data(location)
    end

    test "returns error when GPS coordinates are missing" do
      location = %{
        "name" => "Test Venue",
        "address" => "123 Test St",
        "url" => "https://quizmeisters.com/venues/test",
        "fields" => [%{"name" => "Trivia", "pivot_field_value" => "Mondays at 7pm"}]
      }

      assert {:error, :missing_required_field} = VenueExtractor.extract_venue_data(location)
    end

    test "returns error when time_text cannot be extracted" do
      location = %{
        "name" => "Test Venue",
        "address" => "123 Test St",
        "lat" => 40.7128,
        "lng" => -74.006,
        "url" => "https://quizmeisters.com/venues/test",
        "fields" => []
      }

      assert {:error, :missing_required_field} = VenueExtractor.extract_venue_data(location)
    end

    test "handles empty fields array" do
      location = %{
        "name" => "Test Venue",
        "address" => "123 Test St",
        "lat" => 40.7128,
        "lng" => -74.006,
        "url" => "https://quizmeisters.com/venues/test",
        "fields" => []
      }

      assert {:error, :missing_required_field} = VenueExtractor.extract_venue_data(location)
    end

    test "handles nil fields" do
      location = %{
        "name" => "Test Venue",
        "address" => "123 Test St",
        "lat" => 40.7128,
        "lng" => -74.006,
        "url" => "https://quizmeisters.com/venues/test",
        "fields" => nil
      }

      assert {:error, :missing_required_field} = VenueExtractor.extract_venue_data(location)
    end
  end
end
