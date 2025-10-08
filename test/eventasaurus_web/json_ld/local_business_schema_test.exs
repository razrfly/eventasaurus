defmodule EventasaurusWeb.JsonLd.LocalBusinessSchemaTest do
  use ExUnit.Case, async: true

  alias EventasaurusWeb.JsonLd.LocalBusinessSchema

  describe "generate/1" do
    test "generates valid LocalBusiness JSON-LD for a venue with full details" do
      venue = %{
        name: "Tauron Arena Kraków",
        slug: "tauron-arena-krakow",
        address: "ul. Lema 7",
        latitude: 50.068512,
        longitude: 19.998699,
        venue_type: "venue",
        place_id: "ChIJa_8MdK5bFkcRwLIIIJIH5O0",
        city_ref: %{
          name: "Kraków",
          slug: "krakow",
          country: %{
            code: "PL"
          }
        }
      }

      json = LocalBusinessSchema.generate(venue)
      schema = Jason.decode!(json)

      assert schema["@context"] == "https://schema.org"
      assert schema["@type"] == "EntertainmentBusiness"
      assert schema["name"] == "Tauron Arena Kraków"
      assert schema["address"]["@type"] == "PostalAddress"
      assert schema["address"]["streetAddress"] == "ul. Lema 7"
      assert schema["address"]["addressLocality"] == "Kraków"
      assert schema["address"]["addressCountry"] == "PL"
      assert schema["geo"]["@type"] == "GeoCoordinates"
      assert schema["geo"]["latitude"] == 50.068512
      assert schema["geo"]["longitude"] == 19.998699
      assert schema["hasMap"] == "https://www.google.com/maps/place/?q=place_id:ChIJa_8MdK5bFkcRwLIIIJIH5O0"
      assert String.contains?(schema["url"], "/venues/tauron-arena-krakow")
    end

    test "handles venue without address" do
      venue = %{
        name: "Virtual Venue",
        slug: "virtual-venue",
        address: nil,
        latitude: 50.0,
        longitude: 19.0,
        venue_type: "venue",
        place_id: nil,
        city_ref: %{
          name: "Kraków",
          slug: "krakow",
          country: %{code: "PL"}
        }
      }

      json = LocalBusinessSchema.generate(venue)
      schema = Jason.decode!(json)

      assert schema["address"]["@type"] == "PostalAddress"
      refute Map.has_key?(schema["address"], "streetAddress")
      assert schema["address"]["addressLocality"] == "Kraków"
    end

    test "handles city-type venue" do
      venue = %{
        name: "Kraków",
        slug: "krakow",
        address: nil,
        latitude: 50.0614,
        longitude: 19.9383,
        venue_type: "city",
        place_id: nil,
        city_ref: %{
          name: "Kraków",
          slug: "krakow",
          country: %{code: "PL"}
        }
      }

      json = LocalBusinessSchema.generate(venue)
      schema = Jason.decode!(json)

      assert schema["@type"] == "Place"
    end

    test "handles region-type venue" do
      venue = %{
        name: "Małopolska Region",
        slug: "malopolska",
        address: nil,
        latitude: 50.0,
        longitude: 19.0,
        venue_type: "region",
        place_id: nil,
        city_ref: nil
      }

      json = LocalBusinessSchema.generate(venue)
      schema = Jason.decode!(json)

      assert schema["@type"] == "Place"
      assert schema["name"] == "Małopolska Region"
    end

    test "handles venue without place_id" do
      venue = %{
        name: "Local Club",
        slug: "local-club",
        address: "Test Street 1",
        latitude: 50.0,
        longitude: 19.0,
        venue_type: "venue",
        place_id: nil,
        city_ref: %{
          name: "Kraków",
          slug: "krakow",
          country: %{code: "PL"}
        }
      }

      json = LocalBusinessSchema.generate(venue)
      schema = Jason.decode!(json)

      refute Map.has_key?(schema, "hasMap")
    end

    test "handles venue without country in city" do
      venue = %{
        name: "Local Venue",
        slug: "local-venue",
        address: "Main St 1",
        latitude: 50.0,
        longitude: 19.0,
        venue_type: "venue",
        place_id: nil,
        city_ref: %{
          name: "Test City",
          slug: "test-city",
          country: nil
        }
      }

      json = LocalBusinessSchema.generate(venue)
      schema = Jason.decode!(json)

      assert schema["address"]["addressLocality"] == "Test City"
      refute Map.has_key?(schema["address"], "addressCountry")
    end

    test "build_business_schema/1 returns map structure" do
      venue = %{
        name: "Test Venue",
        slug: "test-venue",
        address: "Test St",
        latitude: 50.0,
        longitude: 19.0,
        venue_type: "venue",
        place_id: "test123",
        city_ref: %{
          name: "Test City",
          slug: "test",
          country: %{code: "US"}
        }
      }

      schema = LocalBusinessSchema.build_business_schema(venue)

      assert is_map(schema)
      assert schema["@context"] == "https://schema.org"
      assert schema["@type"] == "EntertainmentBusiness"
    end
  end
end
