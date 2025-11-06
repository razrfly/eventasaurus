defmodule EventasaurusDiscovery.Admin.CityManagerInvalidCitiesTest do
  use EventasaurusApp.DataCase

  alias EventasaurusDiscovery.Admin.CityManager
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusApp.Venues.Venue

  describe "find_invalid_cities/0" do
    setup do
      gb = insert(:country, name: "United Kingdom", code: "GB")
      au = insert(:country, name: "Australia", code: "AU")
      us = insert(:country, name: "United States", code: "US")

      # Valid cities
      london = insert(:city, name: "London", country: gb)
      sydney = insert(:city, name: "Sydney", country: au)
      new_york = insert(:city, name: "New York City", country: us)

      # Invalid cities (street addresses)
      botchergate = insert(:city, name: "10-16 Botchergate", country: gb)
      burwood = insert(:city, name: "425 Burwood Hwy", country: au)

      {:ok,
       gb: gb,
       au: au,
       us: us,
       london: london,
       sydney: sydney,
       new_york: new_york,
       botchergate: botchergate,
       burwood: burwood}
    end

    test "returns only invalid cities" do
      invalid_cities = CityManager.find_invalid_cities()

      # Should return 2 invalid cities
      assert length(invalid_cities) == 2

      invalid_names = Enum.map(invalid_cities, & &1.name)
      assert "10-16 Botchergate" in invalid_names
      assert "425 Burwood Hwy" in invalid_names

      # Should NOT include valid cities
      refute "London" in invalid_names
      refute "Sydney" in invalid_names
      refute "New York City" in invalid_names
    end

    test "returns empty list when all cities are valid", %{
      botchergate: botchergate,
      burwood: burwood
    } do
      # Delete invalid cities
      Repo.delete!(botchergate)
      Repo.delete!(burwood)

      invalid_cities = CityManager.find_invalid_cities()
      assert invalid_cities == []
    end

    test "preloads country association" do
      invalid_cities = CityManager.find_invalid_cities()

      Enum.each(invalid_cities, fn city ->
        assert %Ecto.Association.NotLoaded{} != city.country
        assert city.country.code in ["GB", "AU", "US"]
      end)
    end
  end

  describe "extract_city_from_address/2" do
    test "extracts city from UK address format (Street, City, Postcode)" do
      assert {:ok, "Carlisle"} =
               CityManager.extract_city_from_address("10-16 Botchergate, Carlisle, CA1 1PE", "GB")

      assert {:ok, "Leeds"} =
               CityManager.extract_city_from_address("168 Lower Briggate, Leeds, LS1 3HY", "GB")

      assert {:ok, "Plymouth"} =
               CityManager.extract_city_from_address(
                 "12 Derrys Cross, Plymouth, PL1 2SW",
                 "GB"
               )
    end

    test "extracts city from UK address format (Street, City)" do
      assert {:ok, "Manchester"} =
               CityManager.extract_city_from_address("123 Oxford Road, Manchester", "GB")
    end

    test "extracts city from AU address format (Street, City State Postcode)" do
      assert {:ok, "Wantirna South"} =
               CityManager.extract_city_from_address(
                 "425 Burwood Hwy, Wantirna South VIC 3152",
                 "AU"
               )

      assert {:ok, "Collie"} =
               CityManager.extract_city_from_address("46-54 Collie St, Collie WA 6225", "AU")
    end

    test "extracts city from US address format (Street, City, State ZIP)" do
      assert {:ok, "Beverly Hills"} =
               CityManager.extract_city_from_address("9100 Wilshire Blvd, Beverly Hills, CA 90210", "US")

      assert {:ok, "New York"} =
               CityManager.extract_city_from_address("123 Broadway, New York, NY 10001", "US")
    end

    test "handles addresses with extra commas" do
      assert {:ok, "London"} =
               CityManager.extract_city_from_address(
                 "The Rose Crown, 123 Main St, London, SW18 2SS",
                 "GB"
               )
    end

    test "returns error for single-part address (no city)" do
      assert {:error, :no_city_found} =
               CityManager.extract_city_from_address("Just A Street Name", "GB")
    end

    test "returns error for nil address" do
      assert {:error, :no_city_found} = CityManager.extract_city_from_address(nil, "GB")
    end

    test "returns error when city part is too short" do
      assert {:error, :no_city_found} =
               CityManager.extract_city_from_address("123 Street, AB, 12345", "US")
    end
  end

  describe "suggest_replacement_city/1" do
    setup do
      gb = insert(:country, name: "United Kingdom", code: "GB")
      au = insert(:country, name: "Australia", code: "AU")

      # Create Carlisle as a valid city
      carlisle = insert(:city, name: "Carlisle", country: gb)

      # Create invalid city (street address)
      botchergate = insert(:city, name: "10-16 Botchergate", country: gb)

      # Helper function to create venue through changeset (ensures slug generation)
      # Using unique coordinates to avoid duplicate detection
      create_venue = fn city_id, address, name, lat, lng ->
        %Venue{}
        |> Venue.changeset(%{
          name: name,
          city_id: city_id,
          address: address,
          latitude: lat,
          longitude: lng,
          venue_type: "venue"
        })
        |> Repo.insert!()
      end

      # Create venues with addresses containing "Carlisle" (UK coordinates - far apart to avoid duplicate detection)
      create_venue.(botchergate.id, "10-16 Botchergate, Carlisle, CA1 1PE", "Botchergate Venue", 54.8951, -2.9382)
      create_venue.(botchergate.id, "Some Street, Carlisle, Cumbria", "City Centre Venue", 54.8960, -2.9350)
      create_venue.(botchergate.id, "Another Address, Carlisle, CA2 5XX", "North Carlisle Venue", 54.8940, -2.9400)

      # Create invalid AU city
      burwood = insert(:city, name: "425 Burwood Hwy", country: au)

      # Create venues with addresses containing "Wantirna South" (AU coordinates)
      create_venue.(burwood.id, "425 Burwood Hwy, Wantirna South VIC 3152", "Venue 4", -37.8631, 145.2270)

      {:ok,
       gb: gb,
       au: au,
       carlisle: carlisle,
       botchergate: botchergate,
       burwood: burwood}
    end

    test "suggests most common city from venue addresses", %{
      botchergate: botchergate,
      carlisle: carlisle
    } do
      # Preload country for the test
      botchergate = Repo.preload(botchergate, :country)

      assert {:ok, suggested_city} = CityManager.suggest_replacement_city(botchergate)
      assert suggested_city.name == "Carlisle"
      assert suggested_city.id == carlisle.id
    end

    test "creates new city if suggested city doesn't exist", %{burwood: burwood, au: au} do
      # Preload country
      burwood = Repo.preload(burwood, :country)

      # Wantirna South doesn't exist yet
      refute Repo.get_by(City, name: "Wantirna South", country_id: au.id)

      assert {:ok, suggested_city} = CityManager.suggest_replacement_city(burwood)
      assert suggested_city.name == "Wantirna South"
      assert suggested_city.country_id == au.id

      # Verify city was created in database
      assert Repo.get_by(City, name: "Wantirna South", country_id: au.id)
    end

    test "returns error when invalid city has no venues", %{gb: gb} do
      # Create invalid city with no venues
      no_venues = insert(:city, name: "Invalid City", country: gb)
      no_venues = Repo.preload(no_venues, :country)

      assert {:error, :no_replacement_found} = CityManager.suggest_replacement_city(no_venues)
    end

    test "returns error when venues have no addresses", %{gb: gb} do
      invalid_city = insert(:city, name: "No Address City", country: gb)

      # Create venues without addresses (using changeset with unique coordinates and names)
      %Venue{}
      |> Venue.changeset(%{
        name: "The Red Lion Pub",
        city_id: invalid_city.id,
        address: nil,
        latitude: 51.5074,
        longitude: -0.1278,
        venue_type: "venue"
      })
      |> Repo.insert!()

      %Venue{}
      |> Venue.changeset(%{
        name: "Blue Moon Theatre",
        city_id: invalid_city.id,
        address: nil,
        latitude: 51.5100,
        longitude: -0.1250,
        venue_type: "venue"
      })
      |> Repo.insert!()

      invalid_city = Repo.preload(invalid_city, :country)

      assert {:error, :no_replacement_found} = CityManager.suggest_replacement_city(invalid_city)
    end

    test "returns error when addresses don't contain valid cities", %{gb: gb} do
      invalid_city = insert(:city, name: "Unparseable", country: gb)

      # Create venues with unparseable addresses (using changeset with unique coordinates and names)
      %Venue{}
      |> Venue.changeset(%{
        name: "Queens Arms Hotel",
        city_id: invalid_city.id,
        address: "Just A Street",
        latitude: 52.4862,
        longitude: -1.8904,
        venue_type: "venue"
      })
      |> Repo.insert!()

      %Venue{}
      |> Venue.changeset(%{
        name: "Central Library",
        city_id: invalid_city.id,
        address: "No Commas Here",
        latitude: 52.4900,
        longitude: -1.8850,
        venue_type: "venue"
      })
      |> Repo.insert!()

      invalid_city = Repo.preload(invalid_city, :country)

      assert {:error, :no_replacement_found} = CityManager.suggest_replacement_city(invalid_city)
    end

    test "handles mixed valid and invalid addresses", %{gb: gb} do
      invalid_city = insert(:city, name: "Mixed Addresses", country: gb)
      manchester = insert(:city, name: "Manchester", country: gb)

      # Mix of parseable and unparseable addresses (using changeset with unique Manchester coordinates and names)
      %Venue{}
      |> Venue.changeset(%{
        name: "Oxford Road Club",
        city_id: invalid_city.id,
        address: "123 Oxford Road, Manchester",
        latitude: 53.4808,
        longitude: -2.2426,
        venue_type: "venue"
      })
      |> Repo.insert!()

      %Venue{}
      |> Venue.changeset(%{
        name: "Deansgate Theatre",
        city_id: invalid_city.id,
        address: "456 Deansgate, Manchester, M3 2XX",
        latitude: 53.4830,
        longitude: -2.2450,
        venue_type: "venue"
      })
      |> Repo.insert!()

      %Venue{}
      |> Venue.changeset(%{
        name: "Northern Quarter Bar",
        city_id: invalid_city.id,
        address: "Unparseable",
        latitude: 53.4850,
        longitude: -2.2380,
        venue_type: "venue"
      })
      |> Repo.insert!()

      invalid_city = Repo.preload(invalid_city, :country)

      assert {:ok, suggested_city} = CityManager.suggest_replacement_city(invalid_city)
      assert suggested_city.id == manchester.id
    end

    test "suggests most frequent city when venues have multiple cities", %{gb: gb} do
      invalid_city = insert(:city, name: "Multiple Cities", country: gb)
      london = insert(:city, name: "London", country: gb)
      manchester = insert(:city, name: "Manchester", country: gb)

      # 3 venues in London, 1 in Manchester (using changeset with unique coordinates)
      %Venue{}
      |> Venue.changeset(%{
        name: "Test Venue 1",
        city_id: invalid_city.id,
        address: "123 Baker St, London, SW1A 1AA",
        latitude: 51.5074,
        longitude: -0.1278,
        venue_type: "venue"
      })
      |> Repo.insert!()

      %Venue{}
      |> Venue.changeset(%{
        name: "Test Venue 2",
        city_id: invalid_city.id,
        address: "456 Oxford St, London, W1D 1BS",
        latitude: 51.5150,
        longitude: -0.1415,
        venue_type: "venue"
      })
      |> Repo.insert!()

      %Venue{}
      |> Venue.changeset(%{
        name: "Test Venue 3",
        city_id: invalid_city.id,
        address: "789 Regent St, London, W1B 5AH",
        latitude: 51.5101,
        longitude: -0.1344,
        venue_type: "venue"
      })
      |> Repo.insert!()

      %Venue{}
      |> Venue.changeset(%{
        name: "Test Venue 4",
        city_id: invalid_city.id,
        address: "123 Oxford Rd, Manchester, M1 5AN",
        latitude: 53.4808,
        longitude: -2.2426,
        venue_type: "venue"
      })
      |> Repo.insert!()

      invalid_city = Repo.preload(invalid_city, :country)

      assert {:ok, suggested_city} = CityManager.suggest_replacement_city(invalid_city)
      # Should suggest London (most frequent)
      assert suggested_city.id == london.id
    end
  end

  describe "merge_cities/2" do
    setup do
      gb = insert(:country, name: "United Kingdom", code: "GB")

      # Create valid replacement city
      carlisle = insert(:city, name: "Carlisle", country: gb)

      # Create invalid city (street address)
      botchergate = insert(:city, name: "10-16 Botchergate", country: gb)

      # Create venues associated with invalid city (using changeset for slug generation)
      %Venue{}
      |> Venue.changeset(%{
        name: "Botchergate Venue",
        city_id: botchergate.id,
        address: "10-16 Botchergate, Carlisle, CA1 1PE",
        latitude: 54.8951,
        longitude: -2.9382,
        venue_type: "venue"
      })
      |> Repo.insert!()

      %Venue{}
      |> Venue.changeset(%{
        name: "City Centre Venue",
        city_id: botchergate.id,
        address: "Some Street, Carlisle, Cumbria",
        latitude: 54.8960,
        longitude: -2.9350,
        venue_type: "venue"
      })
      |> Repo.insert!()

      {:ok, gb: gb, carlisle: carlisle, botchergate: botchergate}
    end

    test "merges single invalid city into replacement city", %{
      carlisle: carlisle,
      botchergate: botchergate
    } do
      # Verify venues start in botchergate
      assert Repo.one(
               from v in Venue,
                 where: v.city_id == ^botchergate.id,
                 select: count(v.id)
             ) == 2

      # Merge cities using single integer overload
      assert {:ok, result} = CityManager.merge_cities(carlisle.id, botchergate.id)

      # Verify result
      assert result.venues_moved == 2
      assert result.cities_deleted == 1
      assert result.target_city.id == carlisle.id

      # Verify venues moved to carlisle
      assert Repo.one(
               from v in Venue,
                 where: v.city_id == ^carlisle.id,
                 select: count(v.id)
             ) == 2

      # Verify botchergate was deleted
      refute Repo.get(City, botchergate.id)
    end

    test "adds invalid city name as alternate name", %{
      carlisle: carlisle,
      botchergate: botchergate
    } do
      assert {:ok, result} = CityManager.merge_cities(carlisle.id, botchergate.id)

      # Reload carlisle to get updated alternate names
      updated_carlisle = Repo.get!(City, carlisle.id)
      assert "10-16 Botchergate" in (updated_carlisle.alternate_names || [])
    end

    test "returns error when invalid city not found", %{carlisle: carlisle} do
      assert {:error, :source_city_not_found} =
               CityManager.merge_cities(carlisle.id, 999_999)
    end

    test "returns error when replacement city not found", %{botchergate: botchergate} do
      assert_raise Ecto.NoResultsError, fn ->
        CityManager.merge_cities(999_999, botchergate.id)
      end
    end
  end
end
