defmodule EventasaurusWeb.JsonLd.CitySchemaTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusWeb.JsonLd.CitySchema
  alias EventasaurusDiscovery.Locations.City

  describe "build_city_schema/2" do
    test "generates basic city schema without stats" do
      city = %City{
        id: 1,
        name: "Warsaw",
        slug: "warsaw",
        latitude: Decimal.new("52.2297"),
        longitude: Decimal.new("21.0122"),
        country: %{name: "Poland", code: "PL"}
      }

      schema = CitySchema.build_city_schema(city)

      assert schema["@context"] == "https://schema.org"
      assert schema["@type"] == "City"
      assert schema["name"] == "Warsaw"
      assert schema["url"] =~ "/c/warsaw"
      assert schema["description"] =~ "Warsaw"
      assert schema["description"] =~ "Poland"

      # Check geo coordinates
      assert schema["geo"]["@type"] == "GeoCoordinates"
      assert schema["geo"]["latitude"] == 52.2297
      assert schema["geo"]["longitude"] == 21.0122

      # Check country
      assert schema["containedInPlace"]["@type"] == "Country"
      assert schema["containedInPlace"]["name"] == "Poland"
    end

    test "generates city schema with stats" do
      city = %City{
        id: 1,
        name: "Warsaw",
        slug: "warsaw",
        latitude: Decimal.new("52.2297"),
        longitude: Decimal.new("21.0122"),
        country: %{name: "Poland", code: "PL"}
      }

      stats = %{
        events_count: 127,
        venues_count: 45,
        categories_count: 12
      }

      schema = CitySchema.build_city_schema(city, stats)

      # Check description includes event count
      assert schema["description"] =~ "127 upcoming events"

      # Check additional properties
      additional_props = schema["additionalProperty"]
      assert length(additional_props) == 3

      assert Enum.any?(additional_props, fn prop ->
        prop["name"] == "Upcoming Events" && prop["value"] == 127
      end)

      assert Enum.any?(additional_props, fn prop ->
        prop["name"] == "Event Venues" && prop["value"] == 45
      end)

      assert Enum.any?(additional_props, fn prop ->
        prop["name"] == "Event Categories" && prop["value"] == 12
      end)
    end

    test "handles city without coordinates" do
      city = %City{
        id: 1,
        name: "Test City",
        slug: "test-city",
        latitude: nil,
        longitude: nil,
        country: %{name: "Test Country", code: "TC"}
      }

      schema = CitySchema.build_city_schema(city)

      refute Map.has_key?(schema, "geo")
      assert schema["name"] == "Test City"
    end

    test "handles city without country" do
      city = %City{
        id: 1,
        name: "Test City",
        slug: "test-city",
        latitude: Decimal.new("52.2297"),
        longitude: Decimal.new("21.0122"),
        country: nil
      }

      schema = CitySchema.build_city_schema(city)

      refute Map.has_key?(schema, "containedInPlace")
      assert schema["description"] =~ "Test City"
      refute schema["description"] =~ ","
    end

    test "handles zero stats gracefully" do
      city = %City{
        id: 1,
        name: "Empty City",
        slug: "empty-city",
        country: %{name: "Test", code: "TS"}
      }

      stats = %{
        events_count: 0,
        venues_count: 0,
        categories_count: 0
      }

      schema = CitySchema.build_city_schema(city, stats)

      # Should not add additionalProperty if all stats are 0
      refute Map.has_key?(schema, "additionalProperty")
    end
  end

  describe "generate/2" do
    test "returns valid JSON-LD string" do
      city = %City{
        id: 1,
        name: "Warsaw",
        slug: "warsaw",
        latitude: Decimal.new("52.2297"),
        longitude: Decimal.new("21.0122"),
        country: %{name: "Poland", code: "PL"}
      }

      json_ld = CitySchema.generate(city)

      # Should be valid JSON
      assert {:ok, decoded} = Jason.decode(json_ld)

      # Check basic structure
      assert decoded["@context"] == "https://schema.org"
      assert decoded["@type"] == "City"
      assert decoded["name"] == "Warsaw"
    end

    test "returns valid JSON-LD with stats" do
      city = %City{
        id: 1,
        name: "Krakow",
        slug: "krakow",
        latitude: Decimal.new("50.0647"),
        longitude: Decimal.new("19.9450"),
        country: %{name: "Poland", code: "PL"}
      }

      stats = %{events_count: 85, venues_count: 30, categories_count: 8}

      json_ld = CitySchema.generate(city, stats)

      assert {:ok, decoded} = Jason.decode(json_ld)
      assert decoded["additionalProperty"]
      assert length(decoded["additionalProperty"]) == 3
    end
  end
end
