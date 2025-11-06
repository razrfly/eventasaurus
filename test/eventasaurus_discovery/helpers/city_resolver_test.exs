defmodule EventasaurusDiscovery.Helpers.CityResolverTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Helpers.CityResolver

  describe "resolve_city/2" do
    test "resolves New York from coordinates" do
      # New York City coordinates
      assert {:ok, city} = CityResolver.resolve_city(40.7128, -74.0060)
      assert is_binary(city)
      assert String.length(city) > 0
      # Should be "New York" or similar valid city
      assert {:ok, _} = CityResolver.validate_city_name(city)
    end

    test "resolves London from coordinates" do
      # London coordinates
      assert {:ok, city} = CityResolver.resolve_city(51.5074, -0.1278)
      assert is_binary(city)
      assert String.length(city) > 0
      assert {:ok, _} = CityResolver.validate_city_name(city)
    end

    test "resolves Tokyo from coordinates" do
      # Tokyo coordinates
      assert {:ok, city} = CityResolver.resolve_city(35.6762, 139.6503)
      assert is_binary(city)
      assert String.length(city) > 0
      assert {:ok, _} = CityResolver.validate_city_name(city)
    end

    test "resolves Paris from coordinates" do
      # Paris coordinates
      assert {:ok, city} = CityResolver.resolve_city(48.8566, 2.3522)
      assert is_binary(city)
      assert String.length(city) > 0
      assert {:ok, _} = CityResolver.validate_city_name(city)
    end

    test "resolves Sydney from coordinates" do
      # Sydney coordinates
      assert {:ok, city} = CityResolver.resolve_city(-33.8688, 151.2093)
      assert is_binary(city)
      assert String.length(city) > 0
      assert {:ok, _} = CityResolver.validate_city_name(city)
    end

    test "handles missing latitude" do
      assert {:error, :missing_coordinates} = CityResolver.resolve_city(nil, -74.0060)
    end

    test "handles missing longitude" do
      assert {:error, :missing_coordinates} = CityResolver.resolve_city(40.7128, nil)
    end

    test "handles both missing coordinates" do
      assert {:error, :missing_coordinates} = CityResolver.resolve_city(nil, nil)
    end

    test "handles coordinate in remote ocean" do
      # Middle of Pacific Ocean (far from any land)
      result = CityResolver.resolve_city(0.0, -160.0)

      # The geocoding library may find a distant city, which is acceptable
      case result do
        {:ok, city} ->
          # If found, should be valid
          assert is_binary(city)
          assert {:ok, _} = CityResolver.validate_city_name(city)

        {:error, reason} ->
          # Not found is also acceptable
          assert reason in [:not_found, :invalid_city_name]
      end
    end

    test "handles coordinates at North Pole" do
      # North Pole coordinates - may find nearest city (Longyearbyen, Svalbard)
      result = CityResolver.resolve_city(90.0, 0.0)

      # The geocoding library may find the nearest city even at extreme latitudes
      case result do
        {:ok, city} ->
          # If found, should be valid
          assert is_binary(city)
          assert {:ok, _} = CityResolver.validate_city_name(city)

        {:error, reason} ->
          # Not found is also acceptable
          assert reason in [:not_found, :invalid_city_name]
      end
    end

    test "handles invalid latitude type" do
      assert {:error, :invalid_coordinates} = CityResolver.resolve_city("40.7128", -74.0060)
    end

    test "handles invalid longitude type" do
      assert {:error, :invalid_coordinates} = CityResolver.resolve_city(40.7128, "-74.0060")
    end
  end

  describe "validate_city_name/2 - GeoNames lookup (NEW)" do
    test "accepts real UK cities" do
      assert {:ok, "London"} = CityResolver.validate_city_name("London", "GB")
      assert {:ok, "Manchester"} = CityResolver.validate_city_name("Manchester", "GB")
      assert {:ok, "Leeds"} = CityResolver.validate_city_name("Leeds", "GB")
      assert {:ok, "Birmingham"} = CityResolver.validate_city_name("Birmingham", "GB")
      assert {:ok, "Liverpool"} = CityResolver.validate_city_name("Liverpool", "GB")
      assert {:ok, "Glasgow"} = CityResolver.validate_city_name("Glasgow", "GB")
    end

    test "accepts real Australian cities" do
      assert {:ok, "Sydney"} = CityResolver.validate_city_name("Sydney", "AU")
      assert {:ok, "Melbourne"} = CityResolver.validate_city_name("Melbourne", "AU")
      assert {:ok, "Perth"} = CityResolver.validate_city_name("Perth", "AU")
      assert {:ok, "Brisbane"} = CityResolver.validate_city_name("Brisbane", "AU")
      assert {:ok, "Adelaide"} = CityResolver.validate_city_name("Adelaide", "AU")
    end

    test "accepts real US cities" do
      assert {:ok, "New York City"} = CityResolver.validate_city_name("New York City", "US")
      assert {:ok, "Los Angeles"} = CityResolver.validate_city_name("Los Angeles", "US")
      assert {:ok, "Chicago"} = CityResolver.validate_city_name("Chicago", "US")
      assert {:ok, "Houston"} = CityResolver.validate_city_name("Houston", "US")
      assert {:ok, "Phoenix"} = CityResolver.validate_city_name("Phoenix", "US")
    end

    test "rejects UK street addresses from the data leak - CRITICAL FIX" do
      # These are the actual invalid cities from the bug report
      uk_addresses = [
        "10-16 Botchergate",      # Carlisle address
        "12 Derrys Cross",         # Plymouth address
        "168 Lower Briggate",      # Leeds address
        "48 Chapeltown",           # Sheffield address
        "98 Highgate",             # Birmingham address
        "40 Bondgate"              # Darlington address
      ]

      for address <- uk_addresses do
        assert {:error, :not_a_valid_city} = CityResolver.validate_city_name(address, "GB"),
               "Expected '#{address}' to be rejected (not in GeoNames)"
      end
    end

    test "rejects Australian street addresses from the data leak - CRITICAL FIX" do
      # These are the actual invalid cities from the bug report
      assert {:error, :not_a_valid_city} =
               CityResolver.validate_city_name("425 Burwood Hwy", "AU")

      assert {:error, :not_a_valid_city} =
               CityResolver.validate_city_name("46-54 Collie St", "AU")
    end

    test "rejects US ZIP codes (not in GeoNames)" do
      assert {:error, :not_a_valid_city} = CityResolver.validate_city_name("90210", "US")
      assert {:error, :not_a_valid_city} = CityResolver.validate_city_name("10001", "US")
      assert {:error, :not_a_valid_city} = CityResolver.validate_city_name("12345", "US")
    end

    test "rejects UK postcodes (not in GeoNames)" do
      assert {:error, :not_a_valid_city} = CityResolver.validate_city_name("SW18 2SS", "GB")
      assert {:error, :not_a_valid_city} = CityResolver.validate_city_name("E5 8NN", "GB")
      assert {:error, :not_a_valid_city} = CityResolver.validate_city_name("W1F 8PU", "GB")
      assert {:error, :not_a_valid_city} = CityResolver.validate_city_name("M1 1AE", "GB")
    end

    test "rejects city names with embedded postcodes (not in GeoNames)" do
      assert {:error, :not_a_valid_city} =
               CityResolver.validate_city_name("England E5 8NN", "GB")

      assert {:error, :not_a_valid_city} =
               CityResolver.validate_city_name("London England W1F 8PU", "GB")

      assert {:error, :not_a_valid_city} =
               CityResolver.validate_city_name("Cambridge England CB2 3AR", "GB")
    end

    test "rejects venue names (not in GeoNames)" do
      assert {:error, :not_a_valid_city} =
               CityResolver.validate_city_name("The Rose and Crown Pub", "GB")

      assert {:error, :not_a_valid_city} =
               CityResolver.validate_city_name("Sports Bar at Stadium", "US")

      assert {:error, :not_a_valid_city} =
               CityResolver.validate_city_name("Green Dragon Inn", "GB")
    end

    test "case insensitive matching" do
      assert {:ok, "london"} = CityResolver.validate_city_name("london", "GB")
      assert {:ok, "LONDON"} = CityResolver.validate_city_name("LONDON", "GB")
      assert {:ok, "LoNdOn"} = CityResolver.validate_city_name("LoNdOn", "GB")
    end

    test "trims whitespace" do
      assert {:ok, "Paris"} = CityResolver.validate_city_name("  Paris  ", "FR")
      assert {:ok, "Tokyo"} = CityResolver.validate_city_name("\tTokyo\n", "JP")
    end

    test "rejects empty strings" do
      assert {:error, :empty_name} = CityResolver.validate_city_name("", "GB")
      assert {:error, :empty_name} = CityResolver.validate_city_name("   ", "GB")
      assert {:error, :empty_name} = CityResolver.validate_city_name("\t\n", "GB")
    end

    test "rejects nil" do
      assert {:error, :empty_name} = CityResolver.validate_city_name(nil)
    end

    test "rejects single character names" do
      assert {:error, :too_short} = CityResolver.validate_city_name("A", "GB")
      assert {:error, :too_short} = CityResolver.validate_city_name("X", "US")
      assert {:error, :too_short} = CityResolver.validate_city_name("1", "AU")
    end

    test "handles non-string input" do
      assert {:error, :invalid_type} = CityResolver.validate_city_name(12345)
      assert {:error, :invalid_type} = CityResolver.validate_city_name([:not, :a, :string])
      assert {:error, :invalid_type} = CityResolver.validate_city_name(%{city: "Paris"})
    end
  end

  describe "validate_city_name/1 - DEPRECATED (backward compatibility)" do
    test "returns error when country code not provided" do
      # All callers should be updated to use validate_city_name/2
      assert {:error, :country_required} = CityResolver.validate_city_name("New York")
      assert {:error, :country_required} = CityResolver.validate_city_name("London")
      assert {:error, :country_required} = CityResolver.validate_city_name("Los Angeles")
    end

    test "rejects empty strings" do
      assert {:error, :empty_name} = CityResolver.validate_city_name("")
      assert {:error, :empty_name} = CityResolver.validate_city_name("   ")
      assert {:error, :empty_name} = CityResolver.validate_city_name("\t\n")
    end

    test "rejects nil" do
      assert {:error, :empty_name} = CityResolver.validate_city_name(nil)
    end

    test "rejects single character names" do
      assert {:error, :country_required} = CityResolver.validate_city_name("A")
      assert {:error, :country_required} = CityResolver.validate_city_name("X")
      assert {:error, :country_required} = CityResolver.validate_city_name("1")
    end

    test "handles non-string input" do
      assert {:error, :invalid_type} = CityResolver.validate_city_name(12345)
      assert {:error, :invalid_type} = CityResolver.validate_city_name([:not, :a, :string])
      assert {:error, :invalid_type} = CityResolver.validate_city_name(%{city: "Paris"})
    end
  end

  describe "integration tests - GeoNames validation" do
    test "end-to-end resolution validates cities with GeoNames" do
      # New York coordinates → should get valid city from GeoNames
      result = CityResolver.resolve_city(40.7128, -74.0060)

      case result do
        {:ok, city} ->
          # If we get a city, it should be validated against GeoNames
          assert is_binary(city)
          assert String.length(city) > 1
          # The validation happens internally in resolve_city now

        {:error, reason} ->
          # Errors are acceptable for coordinates
          assert reason in [
                   :not_found,
                   :invalid_city_name,
                   :missing_coordinates,
                   :geocoding_error
                 ]
      end
    end

    test "full workflow with valid coordinates uses GeoNames validation" do
      # London coordinates → should get valid city from GeoNames
      result = CityResolver.resolve_city(51.5074, -0.1278)

      case result do
        {:ok, city} ->
          assert is_binary(city)
          assert String.length(city) > 1

        {:error, reason} ->
          assert reason in [:not_found, :invalid_city_name]
      end
    end

    test "validates real cities exist in GeoNames across countries" do
      # Test that major cities are validated correctly
      assert {:ok, _} = CityResolver.validate_city_name("Paris", "FR")
      assert {:ok, _} = CityResolver.validate_city_name("Tokyo", "JP")
      assert {:ok, _} = CityResolver.validate_city_name("Berlin", "DE")
      assert {:ok, _} = CityResolver.validate_city_name("Rome", "IT")
      assert {:ok, _} = CityResolver.validate_city_name("Madrid", "ES")
    end
  end
end
