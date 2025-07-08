defmodule EventasaurusWeb.Live.Components.VenueAccessibilityPerformanceTest do
  @moduledoc """
  Comprehensive test suite for venue component accessibility and performance features.

  Tests for Task 4.5: Accessibility compliance, performance optimizations,
  keyboard navigation, screen reader support, lazy loading, and error handling.
  """

  use EventasaurusWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias EventasaurusWeb.Live.Components.{
    VenueHeroComponent,
    VenueDetailsComponent,
    VenuePhotosComponent,
    VenueReviewsComponent,
    RichDataDisplayComponent
  }

  describe "VenueHeroComponent accessibility" do
    setup do
      venue_data = build_test_venue_data()
      %{venue_data: venue_data}
    end

    test "includes proper ARIA attributes and semantic HTML", %{venue_data: venue_data} do
      html = render_component(VenueHeroComponent, %{
        id: "test-hero",
        rich_data: venue_data,
        compact: false
      })

      # Main article structure
      assert html =~ ~s(role="main")
      assert html =~ ~s(aria-labelledby="venue-title")

      # Proper heading hierarchy
      assert html =~ ~s(<h1 id="venue-title")
      assert html =~ ~s(<header class=)

      # Address accessibility
      assert html =~ ~s(aria-label="Located at)
      assert html =~ ~s(<span class="sr-only">Located at: </span>)

      # Rating accessibility
      assert html =~ ~s(aria-label="Rating:)
      assert html =~ ~s(out of 5 stars")

      # List semantics for metadata
      assert html =~ ~s(role="list")
      assert html =~ ~s(role="listitem")
    end

    test "provides screen reader support", %{venue_data: venue_data} do
      html = render_component(VenueHeroComponent, %{
        id: "test-hero-sr",
        rich_data: venue_data,
        compact: false
      })

      # Screen reader only content
      assert html =~ ~s(class="sr-only")
      assert html =~ "Located at:"

      # ARIA labels for interactive elements
      assert html =~ ~s(aria-label=)
      assert html =~ ~s(aria-describedby=)

      # Proper image alt text
      assert html =~ ~s(alt="Hero image of)
      assert html =~ ~s(alt="Additional image of)
    end

    test "supports keyboard navigation", %{venue_data: venue_data} do
      html = render_component(VenueHeroComponent, %{
        id: "test-hero-keyboard",
        rich_data: venue_data,
        compact: false
      })

      # Focus management
      assert html =~ ~s(tabindex=)
      assert html =~ ~s(onkeydown=)

      # Keyboard accessible interactions
      assert html =~ "if(event.key === 'Enter' || event.key === ' ')"
    end

    test "handles missing data gracefully with accessibility", %{venue_data: _venue_data} do
      minimal_data = %{
        "name" => "Test Place",
        "place_id" => "test123"
      }

      html = render_component(VenueHeroComponent, %{
        id: "test-hero-minimal",
        rich_data: minimal_data,
        compact: false
      })

      # Still maintains semantic structure
      assert html =~ ~s(role="main")
      assert html =~ ~s(<h1 id="venue-title")
      assert html =~ "Test Place"

      # Handles missing images gracefully
      assert html =~ ~s(aria-label="Venue information card")
    end
  end

  describe "VenueDetailsComponent accessibility" do
    setup do
      venue_data = build_test_venue_data()
      %{venue_data: venue_data}
    end

    test "provides comprehensive ARIA support", %{venue_data: venue_data} do
      html = render_component(VenueDetailsComponent, %{
        id: "test-details",
        rich_data: venue_data,
        compact: false
      })

      # Main section semantics
      assert html =~ ~s(role="complementary")
      assert html =~ ~s(aria-labelledby="venue-details-title")

      # Grouped contact information
      assert html =~ ~s(role="group")
      assert html =~ ~s(aria-labelledby="contact-info")
      assert html =~ ~s(aria-labelledby="address-label")

      # Proper labeling for all fields
      assert html =~ ~s(aria-describedby="address-label")
      assert html =~ ~s(aria-describedby="phone-label")
      assert html =~ ~s(aria-describedby="website-label")
    end

    test "includes proper link accessibility", %{venue_data: venue_data} do
      html = render_component(VenueDetailsComponent, %{
        id: "test-details-links",
        rich_data: venue_data,
        compact: false
      })

      # External link indicators
      assert html =~ ~s((opens in new tab))
      assert html =~ ~s(target="_blank")
      assert html =~ ~s(rel="noopener noreferrer")

      # Phone link accessibility
      assert html =~ ~s(href="tel:)
      assert html =~ ~s(role="link")
    end

    test "handles status information accessibly", %{venue_data: venue_data} do
      html = render_component(VenueDetailsComponent, %{
        id: "test-details-status",
        rich_data: venue_data,
        compact: false
      })

      # Status communication
      assert html =~ ~s(aria-label="Based on)
      assert html =~ ~s(reviews")

      # Hours status
      assert html =~ ~s(aria-describedby="hours-label")
    end
  end

  describe "VenuePhotosComponent performance and accessibility" do
    setup do
      # Create venue data with many photos for performance testing
      venue_data = build_test_venue_data_with_many_photos(25)
      %{venue_data: venue_data}
    end

    test "implements lazy loading with accessibility", %{venue_data: venue_data} do
      html = render_component(VenuePhotosComponent, %{
        id: "test-photos",
        rich_data: venue_data,
        compact: false
      })

      # Lazy loading attributes
      assert html =~ ~s(loading="lazy")
      assert html =~ ~s(phx-hook="LazyImage")
      assert html =~ ~s(data-src=)

      # Accessibility for photo gallery
      assert html =~ ~s(role="region")
      assert html =~ ~s(aria-labelledby="photos-heading")
      assert html =~ ~s(role="list")
      assert html =~ ~s(role="listitem")
    end

    test "implements pagination for performance", %{venue_data: venue_data} do
      html = render_component(VenuePhotosComponent, %{
        id: "test-photos-pagination",
        rich_data: venue_data,
        compact: false
      })

      # Pagination controls
      assert html =~ "Page 1 of"
      assert html =~ ~s(aria-label="Go to previous page")
      assert html =~ ~s(aria-label="Go to next page")
      assert html =~ ~s(aria-live="polite")

      # Performance indicators
      assert html =~ "Showing 1-12 of 25"
    end

    test "provides keyboard navigation for photo viewer", %{venue_data: venue_data} do
      # Test photo viewer modal accessibility
      {:ok, view, _html} = live_isolated(VenuePhotosComponent, %{
        id: "test-photos-modal",
        rich_data: venue_data,
        compact: false
      })

      # Open photo viewer
      view |> element("[phx-click='show_photo'][phx-value-index='0']") |> render_click()

      html = render(view)

      # Modal accessibility
      assert html =~ ~s(role="dialog")
      assert html =~ ~s(aria-modal="true")
      assert html =~ ~s(aria-labelledby="photo-viewer-title")

      # Keyboard navigation
      assert html =~ ~s(phx-window-keydown="handle_keydown")
      assert html =~ ~s(phx-key="Escape")
    end

    test "handles image loading errors gracefully", %{venue_data: _venue_data} do
      # Test with broken image URLs
      broken_venue_data = %{
        "images" => [
          %{"url" => "https://broken-url.com/image1.jpg"},
          %{"url" => "https://broken-url.com/image2.jpg"}
        ]
      }

      html = render_component(VenuePhotosComponent, %{
        id: "test-photos-errors",
        rich_data: broken_venue_data,
        compact: false
      })

      # Error handling
      assert html =~ ~s(onerror=)
      assert html =~ "this.style.display='none'"
      assert html =~ "photo-error-state"
    end

    test "provides performance optimizations", %{venue_data: venue_data} do
      html = render_component(VenuePhotosComponent, %{
        id: "test-photos-performance",
        rich_data: venue_data,
        compact: false
      })

      # Thumbnail optimization
      assert html =~ "thumbnail_url"

      # Limited photo display for performance
      photo_count = html |> String.split(~s(phx-click="show_photo")) |> length() - 1
      assert photo_count <= 12  # Should limit photos per page

      # Loading states
      assert html =~ "animate-pulse"
    end
  end

  describe "VenueReviewsComponent accessibility" do
    setup do
      venue_data = build_test_venue_data_with_reviews()
      %{venue_data: venue_data}
    end

    test "provides accessible review structure", %{venue_data: venue_data} do
      html = render_component(VenueReviewsComponent, %{
        id: "test-reviews",
        rich_data: venue_data,
        compact: false
      })

      # Accessible review structure
      assert html =~ ~s(role="list")
      assert html =~ ~s(role="listitem")

      # Rating accessibility
      assert html =~ ~s(aria-label="Rating:)
      assert html =~ "out of 5 stars"

      # Review author information
      assert html =~ ~s(aria-label="Review by)
    end
  end

  describe "RichDataDisplayComponent integration testing" do
    setup do
      venue_data = build_comprehensive_venue_data()
      %{venue_data: venue_data}
    end

    test "maintains accessibility across all sections", %{venue_data: venue_data} do
      html = render_component(RichDataDisplayComponent, %{
        id: "test-integration",
        rich_data: venue_data,
        compact: false
      })

      # Overall accessibility structure
      assert html =~ ~s(role="main")
      assert html =~ ~s(role="complementary")
      assert html =~ ~s(role="region")

      # Proper heading hierarchy maintained across components
      assert html =~ ~s(<h1)
      assert html =~ ~s(<h3)

      # No duplicate IDs
      id_matches = Regex.scan(~r/id="([^"]+)"/, html)
      unique_ids = id_matches |> Enum.map(&List.last/1) |> Enum.uniq()
      assert length(id_matches) == length(unique_ids)
    end

    test "provides consistent keyboard navigation", %{venue_data: venue_data} do
      html = render_component(RichDataDisplayComponent, %{
        id: "test-integration-keyboard",
        rich_data: venue_data,
        compact: false
      })

      # Consistent tabindex usage
      assert html =~ ~s(tabindex="0")

      # Keyboard event handlers
      assert html =~ ~s(onkeydown=)
      assert html =~ "Enter"

      # Focus management
      assert html =~ "focus:"
    end

    test "handles performance at scale", %{venue_data: venue_data} do
      # Test with large amounts of data
      large_venue_data = Map.merge(venue_data, %{
        "images" => Enum.map(1..100, fn i ->
          %{"url" => "https://example.com/photo#{i}.jpg"}
        end),
        "reviews" => Enum.map(1..50, fn i ->
          %{
            "author_name" => "Reviewer #{i}",
            "rating" => 4,
            "text" => "Great place! Review #{i}"
          }
        end)
      })

      html = render_component(RichDataDisplayComponent, %{
        id: "test-integration-performance",
        rich_data: large_venue_data,
        compact: false
      })

      # Should handle large datasets without issues
      assert html =~ "Central Park"

      # Should implement pagination/limiting
      photo_count = html |> String.split("phx-click=\"show_photo\"") |> length() - 1
      assert photo_count <= 12  # Should limit photos

      review_count = html |> String.split("Review by") |> length() - 1
      assert review_count <= 5  # Should limit reviews
    end

    test "provides progressive enhancement", %{venue_data: venue_data} do
      html = render_component(RichDataDisplayComponent, %{
        id: "test-integration-progressive",
        rich_data: venue_data,
        compact: false
      })

      # Progressive image loading
      assert html =~ "thumbnail_url"
      assert html =~ "opacity-0"
      assert html =~ "hover:opacity-100"

      # Graceful degradation
      assert html =~ "onerror="
      assert html =~ "fallback"
    end
  end

  describe "Performance monitoring" do
    test "LazyImage hook integration" do
      # Test that LazyImage hook is properly attached
      venue_data = build_test_venue_data()

      html = render_component(VenueHeroComponent, %{
        id: "test-lazy-loading",
        rich_data: venue_data,
        compact: false
      })

      # LazyImage hook attributes
      assert html =~ ~s(phx-hook="LazyImage")
      assert html =~ ~s(data-src=)
      assert html =~ ~s(loading="lazy")

      # Performance optimization
      assert html =~ ~s(onload="this.style.opacity='1'")
      assert html =~ ~s(onerror=)
    end

    test "caching optimization indicators" do
      venue_data = build_test_venue_data()

      html = render_component(VenuePhotosComponent, %{
        id: "test-caching",
        rich_data: venue_data,
        compact: false
      })

      # Should include thumbnail URLs for caching
      assert html =~ "thumbnail_url"

      # Should show performance information in dev mode
      if Application.get_env(:eventasaurus, :env) == :dev do
        assert html =~ "Performance:"
        assert html =~ "Showing"
        assert html =~ "of"
      end
    end
  end

  # Helper functions

  defp build_test_venue_data do
    %{
      "place_id" => "ChIJtest123",
      "name" => "Central Park",
      "formatted_address" => "New York, NY, USA",
      "vicinity" => "New York, NY",
      "rating" => 4.6,
      "user_ratings_total" => 145289,
      "price_level" => 0,
      "business_status" => "OPERATIONAL",
      "types" => ["park", "tourist_attraction"],
      "formatted_phone_number" => "+1 212-310-6600",
      "website" => "https://www.centralparknyc.org/",
      "geometry" => %{
        "location" => %{"lat" => 40.7828687, "lng" => -73.9653551}
      },
      "photos" => [
        %{
          "photo_reference" => "test1",
          "height" => 400,
          "width" => 600
        },
        %{
          "photo_reference" => "test2",
          "height" => 400,
          "width" => 600
        }
      ]
    }
  end

  defp build_test_venue_data_with_many_photos(count) do
    base_data = build_test_venue_data()

    photos = Enum.map(1..count, fn i ->
      %{
        "url" => "https://example.com/photo#{i}.jpg",
        "thumbnail_url" => "https://example.com/thumb#{i}.jpg",
        "width" => 800,
        "height" => 600
      }
    end)

    Map.put(base_data, "images", photos)
  end

  defp build_test_venue_data_with_reviews do
    base_data = build_test_venue_data()

    reviews = [
      %{
        "author_name" => "John Doe",
        "rating" => 5,
        "text" => "Amazing place to visit!",
        "time" => 1640995200
      },
      %{
        "author_name" => "Jane Smith",
        "rating" => 4,
        "text" => "Great for families and very accessible.",
        "time" => 1640995100
      }
    ]

    Map.put(base_data, "reviews", reviews)
  end

  defp build_comprehensive_venue_data do
    build_test_venue_data()
    |> Map.merge(build_test_venue_data_with_many_photos(15))
    |> Map.merge(build_test_venue_data_with_reviews())
  end
end
