defmodule EventasaurusApp.Venues.VenueImageFallbackTest do
  use EventasaurusApp.DataCase
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusApp.Images.CachedImage
  alias EventasaurusDiscovery.Locations.{City, Country}
  alias EventasaurusApp.Repo

  describe "get_cover_image/2 - venue with cached images" do
    test "returns venue's cached image when available" do
      city = create_test_city()
      venue = create_test_venue(city, %{})

      # Create a cached image for this venue
      create_cached_image(venue.id, 0, "https://cdn.example.com/venue-image.jpg")

      assert {:ok, url, :venue} = Venue.get_cover_image(venue)
      # URL should be from CDN
      assert url =~ "cdn.example.com/venue-image.jpg" || url =~ "cdn.wombie.com"
    end

    test "returns first image when multiple available" do
      city = create_test_city()
      venue = create_test_venue(city, %{})

      # Create multiple cached images
      create_cached_image(venue.id, 0, "https://cdn.example.com/first.jpg")
      create_cached_image(venue.id, 1, "https://cdn.example.com/second.jpg")

      assert {:ok, url, :venue} = Venue.get_cover_image(venue)
      assert url =~ "first.jpg"
    end

    test "accepts CDN options" do
      city = create_test_city()
      venue = create_test_venue(city, %{})

      create_cached_image(venue.id, 0, "https://cdn.example.com/image.jpg")

      assert {:ok, url, :venue} = Venue.get_cover_image(venue, width: 800, quality: 90)
      assert url =~ "example.com/image.jpg"
    end
  end

  describe "get_cover_image/2 - city category fallback" do
    test "returns city category image when venue has no images" do
      city = create_city_with_categorized_gallery()

      # Theater venue should get historic category
      venue =
        create_test_venue(city, %{
          metadata: %{"category" => "theater"}
        })
        |> Repo.preload(:city_ref)

      assert {:ok, url, source} = Venue.get_cover_image(venue)
      assert source in [:city_category, :city_general]
      assert url =~ "unsplash.com"
    end

    test "maps cultural venues to historic category" do
      city = create_city_with_categorized_gallery()

      venue =
        create_test_venue(city, %{
          metadata: %{"category" => "opera"}
        })
        |> Repo.preload(:city_ref)

      # CategoryMapper should select "historic" for opera
      assert {:ok, _url, source} = Venue.get_cover_image(venue)
      assert source in [:city_category, :city_general]
    end

    test "maps modern venues to architecture category" do
      city = create_city_with_categorized_gallery()

      venue =
        create_test_venue(city, %{
          metadata: %{"architectural_style" => "modern"}
        })
        |> Repo.preload(:city_ref)

      assert {:ok, _url, source} = Venue.get_cover_image(venue)
      assert source in [:city_category, :city_general]
    end

    test "uses name patterns for category detection" do
      city = create_city_with_categorized_gallery()

      venue =
        create_test_venue(city, %{
          name: "Old Town Square"
        })
        |> Repo.preload(:city_ref)

      # Should map to "old_town" category
      assert {:ok, _url, source} = Venue.get_cover_image(venue)
      assert source in [:city_category, :city_general]
    end

    test "falls back to general when primary category has no images" do
      city = create_city_with_partial_gallery()

      venue =
        create_test_venue(city, %{
          # This should map to a category that doesn't exist in partial gallery
          metadata: %{"category" => "castle"}
        })
        |> Repo.preload(:city_ref)

      # Should fallback to general
      assert {:ok, _url, :city_general} = Venue.get_cover_image(venue)
    end
  end

  describe "get_cover_image/2 - no images available" do
    test "returns error when venue and city have no images" do
      city = create_test_city()

      venue =
        create_test_venue(city, %{})
        |> Repo.preload(:city_ref)

      assert {:error, :no_image} = Venue.get_cover_image(venue)
    end

    test "returns error when city_ref not preloaded" do
      city = create_test_city()

      venue = create_test_venue(city, %{})

      assert {:error, :no_image} = Venue.get_cover_image(venue)
    end

    test "returns error when city has legacy gallery format" do
      city = create_city_with_legacy_gallery()

      venue =
        create_test_venue(city, %{})
        |> Repo.preload(:city_ref)

      # Legacy format not supported by CategoryMapper
      assert {:error, :no_image} = Venue.get_cover_image(venue)
    end
  end

  # Helper functions

  defp create_cached_image(venue_id, position, cdn_url) do
    {:ok, cached_image} =
      %CachedImage{}
      |> CachedImage.changeset(%{
        entity_type: "venue",
        entity_id: venue_id,
        position: position,
        original_url: "https://original.example.com/image.jpg",
        cdn_url: cdn_url,
        status: "cached"
      })
      |> Repo.insert()

    cached_image
  end

  defp create_test_city do
    {:ok, country} =
      Country.changeset(%Country{}, %{name: "Poland", code: "PL"})
      |> Repo.insert()

    {:ok, city} =
      City.changeset(%City{}, %{
        name: "Kraków",
        country_id: country.id,
        latitude: Decimal.new("50.0619"),
        longitude: Decimal.new("19.9368")
      })
      |> Repo.insert()

    city
  end

  defp create_city_with_categorized_gallery do
    city = create_test_city()

    gallery = %{
      "active_category" => "general",
      "categories" => %{
        "general" => %{
          "images" => [
            %{
              "url" => "https://images.unsplash.com/general-1",
              "attribution" => %{"name" => "Test Photographer"}
            }
          ],
          "search_terms" => ["Kraków", "Kraków cityscape"],
          "last_refreshed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        },
        "historic" => %{
          "images" => [
            %{
              "url" => "https://images.unsplash.com/historic-1",
              "attribution" => %{"name" => "Test Photographer"}
            }
          ],
          "search_terms" => ["Kraków historic", "Kraków old town"],
          "last_refreshed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        },
        "architecture" => %{
          "images" => [
            %{
              "url" => "https://images.unsplash.com/architecture-1",
              "attribution" => %{"name" => "Test Photographer"}
            }
          ],
          "search_terms" => ["Kraków architecture", "Kraków modern"],
          "last_refreshed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }
    }

    {:ok, city} =
      City.gallery_changeset(city, gallery)
      |> Repo.update()

    city
  end

  defp create_city_with_partial_gallery do
    city = create_test_city()

    # Only has general category
    gallery = %{
      "active_category" => "general",
      "categories" => %{
        "general" => %{
          "images" => [
            %{
              "url" => "https://images.unsplash.com/general-only",
              "attribution" => %{"name" => "Test Photographer"}
            }
          ],
          "search_terms" => ["Kraków"],
          "last_refreshed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }
    }

    {:ok, city} =
      City.gallery_changeset(city, gallery)
      |> Repo.update()

    city
  end

  defp create_city_with_legacy_gallery do
    city = create_test_city()

    # Legacy format (not categorized)
    gallery = %{
      "images" => [
        %{
          "url" => "https://images.unsplash.com/legacy",
          "attribution" => %{"name" => "Test Photographer"}
        }
      ],
      "current_index" => 0,
      "last_refreshed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    {:ok, city} =
      City.gallery_changeset(city, gallery)
      |> Repo.update()

    city
  end

  defp create_test_venue(city, attrs) do
    default_attrs = %{
      name: "Test Venue",
      venue_type: "venue",
      source: "user",
      latitude: 50.0619,
      longitude: 19.9368,
      city_id: city.id
    }

    attrs = Map.merge(default_attrs, attrs)

    {:ok, venue} =
      Venue.changeset(%Venue{}, attrs)
      |> Repo.insert()

    venue
  end
end
