defmodule EventasaurusDiscovery.Admin.CityManagerTest do
  use EventasaurusApp.DataCase

  alias EventasaurusDiscovery.Admin.CityManager
  alias EventasaurusDiscovery.Locations.{City, Country}

  describe "create_city/1" do
    setup do
      country = insert(:country, name: "Australia", code: "AU")
      {:ok, country: country}
    end

    test "creates a city with valid attributes", %{country: country} do
      attrs = %{
        name: "Sydney",
        country_id: country.id,
        latitude: Decimal.new("-33.8688"),
        longitude: Decimal.new("151.2093"),
        discovery_enabled: true
      }

      assert {:ok, %City{} = city} = CityManager.create_city(attrs)
      assert city.name == "Sydney"
      assert city.country_id == country.id
      assert Decimal.eq?(city.latitude, Decimal.new("-33.8688"))
      assert Decimal.eq?(city.longitude, Decimal.new("151.2093"))
      assert city.discovery_enabled == true
      assert city.slug == "sydney"
    end

    test "creates a city without coordinates", %{country: country} do
      attrs = %{
        name: "Melbourne",
        country_id: country.id
      }

      assert {:ok, %City{} = city} = CityManager.create_city(attrs)
      assert city.name == "Melbourne"
      assert city.latitude == nil
      assert city.longitude == nil
    end

    test "returns error for invalid country_id" do
      attrs = %{
        name: "Invalid City",
        country_id: 999_999
      }

      assert {:error, changeset} = CityManager.create_city(attrs)
      assert "does not exist" in errors_on(changeset).country_id
    end

    test "returns error for missing name", %{country: country} do
      attrs = %{
        country_id: country.id
      }

      assert {:error, changeset} = CityManager.create_city(attrs)
      assert "can't be blank" in errors_on(changeset).name
    end

    test "returns error for missing country_id" do
      attrs = %{
        name: "No Country City"
      }

      assert {:error, changeset} = CityManager.create_city(attrs)
      assert "can't be blank" in errors_on(changeset).country_id
    end
  end

  describe "update_city/2" do
    setup do
      country = insert(:country, name: "Australia", code: "AU")
      city = insert(:city, name: "Sydney", country: country)
      {:ok, country: country, city: city}
    end

    test "updates city with valid attributes", %{city: city} do
      attrs = %{
        latitude: Decimal.new("-33.8688"),
        longitude: Decimal.new("151.2093"),
        discovery_enabled: true
      }

      assert {:ok, %City{} = updated_city} = CityManager.update_city(city, attrs)
      assert Decimal.eq?(updated_city.latitude, Decimal.new("-33.8688"))
      assert Decimal.eq?(updated_city.longitude, Decimal.new("151.2093"))
      assert updated_city.discovery_enabled == true
    end

    test "updates city name", %{city: city} do
      attrs = %{name: "Greater Sydney"}

      assert {:ok, %City{} = updated_city} = CityManager.update_city(city, attrs)
      assert updated_city.name == "Greater Sydney"
      # Slug may or may not update depending on autoslug configuration
    end

    test "returns error for invalid attributes", %{city: city} do
      attrs = %{name: nil}

      assert {:error, changeset} = CityManager.update_city(city, attrs)
      assert "can't be blank" in errors_on(changeset).name
    end
  end

  describe "delete_city/1" do
    setup do
      country = insert(:country, name: "Australia", code: "AU")
      city = insert(:city, name: "Sydney", country: country)
      {:ok, country: country, city: city}
    end

    test "deletes city with no venues", %{city: city} do
      assert {:ok, %City{}} = CityManager.delete_city(city.id)
      assert Repo.get(City, city.id) == nil
    end

    test "returns error when city has venues", %{city: city} do
      # Create a venue associated with this city
      insert(:venue, city_id: city.id)

      assert {:error, :has_venues} = CityManager.delete_city(city.id)
      assert Repo.get(City, city.id) != nil
    end

    test "returns error for non-existent city" do
      assert {:error, :not_found} = CityManager.delete_city(999_999)
    end
  end

  describe "get_city/1" do
    setup do
      country = insert(:country, name: "Australia", code: "AU")
      city = insert(:city, name: "Sydney", country: country)
      {:ok, country: country, city: city}
    end

    test "returns city with preloaded country", %{city: city, country: country} do
      result = CityManager.get_city(city.id)

      assert result.id == city.id
      assert result.name == "Sydney"
      assert result.country.id == country.id
      assert result.country.name == "Australia"
    end

    test "returns nil for non-existent city" do
      assert CityManager.get_city(999_999) == nil
    end
  end

  describe "list_cities/1" do
    setup do
      au = insert(:country, name: "Australia", code: "AU")
      us = insert(:country, name: "United States", code: "US")

      sydney = insert(:city, name: "Sydney", country: au, discovery_enabled: true)
      melbourne = insert(:city, name: "Melbourne", country: au, discovery_enabled: false)
      new_york = insert(:city, name: "New York", country: us, discovery_enabled: true)

      {:ok, australia: au, us: us, sydney: sydney, melbourne: melbourne, new_york: new_york}
    end

    test "returns all cities ordered by name" do
      cities = CityManager.list_cities()

      assert length(cities) == 3
      assert Enum.map(cities, & &1.name) == ["Melbourne", "New York", "Sydney"]
    end

    test "filters cities by search term", %{sydney: sydney} do
      cities = CityManager.list_cities(%{search: "syd"})

      assert length(cities) == 1
      assert hd(cities).id == sydney.id
    end

    test "search is case-insensitive", %{sydney: sydney} do
      cities = CityManager.list_cities(%{search: "SYDNEY"})

      assert length(cities) == 1
      assert hd(cities).id == sydney.id
    end

    test "filters cities by country_id", %{australia: au, sydney: sydney, melbourne: melbourne} do
      cities = CityManager.list_cities(%{country_id: au.id})

      assert length(cities) == 2
      city_ids = Enum.map(cities, & &1.id)
      assert sydney.id in city_ids
      assert melbourne.id in city_ids
    end

    test "filters cities by country_id string", %{australia: au} do
      cities = CityManager.list_cities(%{country_id: Integer.to_string(au.id)})

      assert length(cities) == 2
    end

    test "filters cities by discovery_enabled true", %{sydney: sydney, new_york: new_york} do
      cities = CityManager.list_cities(%{discovery_enabled: true})

      assert length(cities) == 2
      city_ids = Enum.map(cities, & &1.id)
      assert sydney.id in city_ids
      assert new_york.id in city_ids
    end

    test "filters cities by discovery_enabled false", %{melbourne: melbourne} do
      cities = CityManager.list_cities(%{discovery_enabled: false})

      assert length(cities) == 1
      assert hd(cities).id == melbourne.id
    end

    test "filters cities by discovery_enabled string 'true'", %{
      sydney: sydney,
      new_york: new_york
    } do
      cities = CityManager.list_cities(%{discovery_enabled: "true"})

      assert length(cities) == 2
      city_ids = Enum.map(cities, & &1.id)
      assert sydney.id in city_ids
      assert new_york.id in city_ids
    end

    test "filters cities by discovery_enabled string 'false'", %{melbourne: melbourne} do
      cities = CityManager.list_cities(%{discovery_enabled: "false"})

      assert length(cities) == 1
      assert hd(cities).id == melbourne.id
    end

    test "combines multiple filters", %{sydney: sydney, australia: au} do
      cities =
        CityManager.list_cities(%{
          search: "syd",
          country_id: au.id,
          discovery_enabled: true
        })

      assert length(cities) == 1
      assert hd(cities).id == sydney.id
    end
  end

  describe "list_cities_with_venue_counts/1" do
    setup do
      country = insert(:country, name: "Australia", code: "AU")
      sydney = insert(:city, name: "Sydney", country: country)
      melbourne = insert(:city, name: "Melbourne", country: country)

      # Add venues to Sydney
      insert(:venue, city_id: sydney.id, name: "Opera House")
      insert(:venue, city_id: sydney.id, name: "Harbour Bridge")

      # Melbourne has no venues

      {:ok, country: country, sydney: sydney, melbourne: melbourne}
    end

    test "returns cities with venue counts", %{sydney: sydney, melbourne: melbourne} do
      cities = CityManager.list_cities_with_venue_counts()

      # Find the cities we created in this test
      sydney_result = Enum.find(cities, &(&1.id == sydney.id))
      melbourne_result = Enum.find(cities, &(&1.id == melbourne.id))

      # Verify our cities have the correct venue counts
      assert sydney_result != nil
      assert melbourne_result != nil
      assert sydney_result.venue_count == 2
      assert melbourne_result.venue_count == 0
    end

    test "filters work with venue counts", %{sydney: sydney} do
      cities = CityManager.list_cities_with_venue_counts(%{search: "sydney"})

      assert length(cities) == 1
      assert hd(cities).id == sydney.id
      assert hd(cities).venue_count == 2
    end
  end

  describe "create_city/1 with GeoNames validation (Phase 2)" do
    setup do
      gb = insert(:country, name: "United Kingdom", code: "GB")
      au = insert(:country, name: "Australia", code: "AU")
      us = insert(:country, name: "United States", code: "US")
      {:ok, gb: gb, au: au, us: us}
    end

    test "accepts valid UK city from GeoNames", %{gb: gb} do
      attrs = %{
        name: "London",
        country_id: gb.id,
        latitude: Decimal.new("51.5074"),
        longitude: Decimal.new("-0.1278")
      }

      assert {:ok, %City{} = city} = CityManager.create_city(attrs)
      assert city.name == "London"
      assert city.country_id == gb.id
    end

    test "accepts valid AU city from GeoNames", %{au: au} do
      attrs = %{
        name: "Sydney",
        country_id: au.id,
        latitude: Decimal.new("-33.8688"),
        longitude: Decimal.new("151.2093")
      }

      assert {:ok, %City{} = city} = CityManager.create_city(attrs)
      assert city.name == "Sydney"
      assert city.country_id == au.id
    end

    test "accepts valid US city from GeoNames", %{us: us} do
      attrs = %{
        name: "New York City",
        country_id: us.id,
        latitude: Decimal.new("40.7128"),
        longitude: Decimal.new("-74.0060")
      }

      assert {:ok, %City{} = city} = CityManager.create_city(attrs)
      assert city.name == "New York City"
      assert city.country_id == us.id
    end

    test "rejects UK street address from bug report (10-16 Botchergate)", %{gb: gb} do
      attrs = %{
        name: "10-16 Botchergate",
        country_id: gb.id,
        latitude: Decimal.new("54.8911"),
        longitude: Decimal.new("-2.9319")
      }

      assert {:error, changeset} = CityManager.create_city(attrs)
      assert "is not a valid city in United Kingdom" in errors_on(changeset).name
    end

    test "rejects UK street address (168 Lower Briggate)", %{gb: gb} do
      attrs = %{
        name: "168 Lower Briggate",
        country_id: gb.id
      }

      assert {:error, changeset} = CityManager.create_city(attrs)
      assert "is not a valid city in United Kingdom" in errors_on(changeset).name
    end

    test "rejects AU street address from bug report (425 Burwood Hwy)", %{au: au} do
      attrs = %{
        name: "425 Burwood Hwy",
        country_id: au.id,
        latitude: Decimal.new("-37.8692"),
        longitude: Decimal.new("145.2442")
      }

      assert {:error, changeset} = CityManager.create_city(attrs)
      assert "is not a valid city in Australia" in errors_on(changeset).name
    end

    test "rejects AU street address (46-54 Collie St)", %{au: au} do
      attrs = %{
        name: "46-54 Collie St",
        country_id: au.id
      }

      assert {:error, changeset} = CityManager.create_city(attrs)
      assert "is not a valid city in Australia" in errors_on(changeset).name
    end

    test "rejects UK postcode (SW18 2SS)", %{gb: gb} do
      attrs = %{
        name: "SW18 2SS",
        country_id: gb.id
      }

      assert {:error, changeset} = CityManager.create_city(attrs)
      assert "is not a valid city in United Kingdom" in errors_on(changeset).name
    end

    test "rejects US ZIP code (90210)", %{us: us} do
      attrs = %{
        name: "90210",
        country_id: us.id
      }

      assert {:error, changeset} = CityManager.create_city(attrs)
      assert "is not a valid city in United States" in errors_on(changeset).name
    end

    test "returns error when country is missing" do
      attrs = %{
        name: "London"
      }

      assert {:error, changeset} = CityManager.create_city(attrs)
      assert "is required for validation" in errors_on(changeset).country_id
    end

    test "returns error when country_id is invalid" do
      attrs = %{
        name: "London",
        country_id: 999_999
      }

      assert {:error, changeset} = CityManager.create_city(attrs)
      assert "is required for validation" in errors_on(changeset).country_id
    end
  end
end
