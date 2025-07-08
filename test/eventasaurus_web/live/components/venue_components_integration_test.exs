defmodule EventasaurusWeb.Live.Components.VenueComponentsIntegrationTest do
  use EventasaurusWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias EventasaurusWeb.Live.Components.RichDataDisplayComponent
  alias EventasaurusWeb.Live.Components.Adapters.GooglePlacesDataAdapter

  describe "Google Places venue components integration" do
    setup do
      # Google Places venue data (raw format from Google Places API)
      venue_data = %{
        "place_id" => "ChIJGVtI4by3t4kRr51d_Qm_x58",
        "name" => "Central Park",
        "vicinity" => "New York, NY, USA",
        "formatted_address" => "New York, NY, USA",
        "formatted_phone_number" => "+1 212-310-6600",
        "website" => "https://www.centralparknyc.org/",
        "rating" => 4.6,
        "user_ratings_total" => 145289,
        "price_level" => 0,
        "business_status" => "OPERATIONAL",
        "types" => ["park", "tourist_attraction", "establishment", "point_of_interest"],
        "geometry" => %{
          "location" => %{"lat" => 40.7828687, "lng" => -73.9653551}
        },
        "photos" => [
          %{"photo_reference" => "test1", "height" => 300, "width" => 400},
          %{"photo_reference" => "test2", "height" => 300, "width" => 400}
        ],
        "reviews" => []
      }

      %{venue_data: venue_data}
    end

    test "adapter detection and transformation", %{venue_data: venue_data} do
      # Test that GooglePlacesDataAdapter correctly identifies this data
      assert GooglePlacesDataAdapter.handles?(venue_data) == true

      # Test that it transforms correctly
      adapted = GooglePlacesDataAdapter.adapt(venue_data)
      assert adapted.title == "Central Park"
      assert adapted.type == :activity
      assert adapted.rating.value == 4.6
      assert adapted.rating.count == 145289
    end

    test "RichDataDisplayComponent with Google Places data", %{venue_data: venue_data} do
      html = render_component(RichDataDisplayComponent, %{
        id: "test-venue",
        rich_data: venue_data,
        compact: false
      })

      # Should render the venue name
      assert html =~ "Central Park"
      # Should render the rating
      assert html =~ "4.6"
      # Should render review count
      assert html =~ "145,289+ reviews"
      # Should render price level
      assert html =~ "Free"
      # Should render categories
      assert html =~ "Park"
      assert html =~ "Tourist Attraction"
      # Should render address
      assert html =~ "New York, NY, USA"
    end

    test "compact mode rendering", %{venue_data: venue_data} do
      html = render_component(RichDataDisplayComponent, %{
        id: "test-venue-compact",
        rich_data: venue_data,
        compact: true
      })

      # Should still render essential info in compact mode
      assert html =~ "Central Park"
      assert html =~ "4.6"
    end

    test "handles minimal venue data" do
      minimal_data = %{
        "place_id" => "ChIJtest_minimal",
        "name" => "Test Venue",
        "vicinity" => "Test Location",
        "geometry" => %{
          "location" => %{"lat" => 40.0, "lng" => -74.0}
        }
      }

      html = render_component(RichDataDisplayComponent, %{
        id: "test-minimal-venue",
        rich_data: minimal_data,
        compact: false
      })

      # Should render without errors even with minimal data
      assert html =~ "Test Venue"
      assert html =~ "Test Location"
    end

    test "handles unsupported data gracefully" do
      unsupported_data = %{
        "unknown_field" => "test",
        "other_field" => "value"
      }

      html = render_component(RichDataDisplayComponent, %{
        id: "test-unsupported",
        rich_data: unsupported_data,
        compact: false
      })

      assert html =~ "No compatible adapter found for data"
    end
  end
end
