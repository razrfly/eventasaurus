defmodule EventasaurusWeb.Services.PlacesDataServiceTest do
  use ExUnit.Case, async: true
  alias EventasaurusWeb.Services.PlacesDataService

  describe "prepare_place_option_data/1" do
    test "creates data in correct external_id/external_data pattern" do
      place_data = %{
        "place_id" => "ChIJGVtI4by3t4kRr51d_Qm_x58",
        "name" => "Central Park",
        "rating" => 4.6,
        "user_ratings_total" => 123_456,
        "types" => ["park", "tourist_attraction", "establishment", "point_of_interest"],
        "vicinity" => "New York, NY, USA",
        "formatted_address" => "New York, NY, USA",
        "photos" => [
          %{"url" => "https://example.com/photo1.jpg"},
          %{"url" => "https://example.com/photo2.jpg"}
        ]
      }

      result = PlacesDataService.prepare_place_option_data(place_data)

      # Verify it follows the external API pattern like movies
      assert result["external_id"] == "places:ChIJGVtI4by3t4kRr51d_Qm_x58"
      assert result["external_data"] == place_data
      assert result["image_url"] == "https://example.com/photo1.jpg"
      assert result["title"] == "Central Park"
      assert String.contains?(result["description"], "Rating: 4.6★")
      assert String.contains?(result["description"], "Park, Tourist attraction")
      assert String.contains?(result["description"], "New York, NY, USA")
    end

    test "handles place data without photos" do
      place_data = %{
        "place_id" => "ChIJtest123",
        "name" => "Test Restaurant",
        "rating" => 4.2,
        "types" => ["restaurant", "food"],
        "vicinity" => "Test City"
      }

      result = PlacesDataService.prepare_place_option_data(place_data)

      assert result["external_id"] == "places:ChIJtest123"
      assert result["external_data"] == place_data
      assert result["image_url"] == nil
      assert result["title"] == "Test Restaurant"
    end

    test "handles minimal place data" do
      place_data = %{
        "place_id" => "ChIJminimal",
        "name" => "Minimal Place"
      }

      result = PlacesDataService.prepare_place_option_data(place_data)

      assert result["external_id"] == "places:ChIJminimal"
      assert result["external_data"] == place_data
      assert result["image_url"] == nil
      assert result["title"] == "Minimal Place"
      assert result["description"] == ""
    end

    test "handles photos as URL strings (from frontend processing)" do
      place_data = %{
        "place_id" => "ChIJGVtI4by3t4kRr51d_Qm_x58",
        "name" => "Central Park",
        "rating" => 4.6,
        "types" => ["park", "tourist_attraction"],
        "vicinity" => "New York, NY, USA",
        "photos" => [
          "https://maps.googleapis.com/maps/api/place/js/PhotoService.GetPhoto?token=12345",
          "https://maps.googleapis.com/maps/api/place/js/PhotoService.GetPhoto?token=67890"
        ]
      }

      result = PlacesDataService.prepare_place_option_data(place_data)

      assert result["external_id"] == "places:ChIJGVtI4by3t4kRr51d_Qm_x58"

      assert result["image_url"] ==
               "https://maps.googleapis.com/maps/api/place/js/PhotoService.GetPhoto?token=12345"

      assert Map.has_key?(result, "external_data")
    end

    test "handles photos as map objects (from raw API)" do
      place_data = %{
        "place_id" => "ChIJGVtI4by3t4kRr51d_Qm_x58",
        "name" => "Central Park",
        "rating" => 4.6,
        "types" => ["park", "tourist_attraction"],
        "vicinity" => "New York, NY, USA",
        "photos" => [
          %{"url" => "https://example.com/photo1.jpg"},
          %{"url" => "https://example.com/photo2.jpg"}
        ]
      }

      result = PlacesDataService.prepare_place_option_data(place_data)

      assert result["external_id"] == "places:ChIJGVtI4by3t4kRr51d_Qm_x58"
      assert result["image_url"] == "https://example.com/photo1.jpg"
      assert Map.has_key?(result, "external_data")
    end
  end

  describe "get_place_categories/1" do
    test "filters and humanizes place types" do
      place_data = %{
        "types" => ["restaurant", "food", "establishment", "point_of_interest", "cafe"]
      }

      categories = PlacesDataService.get_place_categories(place_data)

      assert "Restaurant" in categories
      assert "Food" in categories
      assert "Cafe" in categories
      refute "establishment" in categories
      refute "point_of_interest" in categories
      # Limited to 3
      assert length(categories) <= 3
    end
  end

  describe "compatibility with poll_option schema" do
    test "data structure is compatible with external_id patterns" do
      place_data = %{
        "place_id" => "ChIJGVtI4by3t4kRr51d_Qm_x58",
        "name" => "Test Place"
      }

      result = PlacesDataService.prepare_place_option_data(place_data)

      # Verify external_id follows the established pattern
      assert String.starts_with?(result["external_id"], "places:")

      # Verify the pattern can be parsed by existing PollOption functions
      # (This tests compatibility with the external_service/1 function)
      assert String.contains?(result["external_id"], ":")
      [service, _id] = String.split(result["external_id"], ":", parts: 2)
      assert service == "places"
    end
  end

  describe "edge cases" do
    test "handles missing place_id gracefully" do
      place_data = %{
        "name" => "Unknown Place",
        "vicinity" => "Somewhere"
      }

      result = PlacesDataService.prepare_place_option_data(place_data)

      assert result["external_id"] == "places:"
      assert result["external_data"] == place_data
      assert result["image_url"] == nil
      # Vicinity is included in description
      assert result["description"] == "Somewhere"
    end

    test "handles empty photos array" do
      place_data = %{
        "place_id" => "ChIJGVtI4by3t4kRr51d_Qm_x58",
        "name" => "Test Place",
        "photos" => []
      }

      result = PlacesDataService.prepare_place_option_data(place_data)

      assert result["image_url"] == nil
    end
  end
end
