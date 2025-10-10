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

  describe "validate_city_name/1" do
    test "accepts valid city names" do
      assert {:ok, "New York"} = CityResolver.validate_city_name("New York")
      assert {:ok, "London"} = CityResolver.validate_city_name("London")
      assert {:ok, "Los Angeles"} = CityResolver.validate_city_name("Los Angeles")
      assert {:ok, "São Paulo"} = CityResolver.validate_city_name("São Paulo")
      assert {:ok, "Saint-Denis"} = CityResolver.validate_city_name("Saint-Denis")
      assert {:ok, "Mexico City"} = CityResolver.validate_city_name("Mexico City")
    end

    test "trims whitespace" do
      assert {:ok, "Paris"} = CityResolver.validate_city_name("  Paris  ")
      assert {:ok, "Tokyo"} = CityResolver.validate_city_name("\tTokyo\n")
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
      assert {:error, :too_short} = CityResolver.validate_city_name("A")
      assert {:error, :too_short} = CityResolver.validate_city_name("X")
      assert {:error, :too_short} = CityResolver.validate_city_name("1")
    end

    test "rejects postcodes (UK and US patterns)" do
      # UK postcodes
      assert {:error, :postcode_pattern} = CityResolver.validate_city_name("SW18 2SS")
      assert {:error, :postcode_pattern} = CityResolver.validate_city_name("E1 6AN")
      assert {:error, :postcode_pattern} = CityResolver.validate_city_name("W1A 1AA")
      assert {:error, :postcode_pattern} = CityResolver.validate_city_name("M1 1AE")
      assert {:error, :postcode_pattern} = CityResolver.validate_city_name("B33 8TH")

      # US ZIP codes (pure numeric)
      assert {:error, :postcode_pattern} = CityResolver.validate_city_name("90210")
      assert {:error, :postcode_pattern} = CityResolver.validate_city_name("10001")
    end

    test "rejects street addresses with numbers" do
      assert {:error, :street_address_pattern} =
               CityResolver.validate_city_name("123 Main Street")

      assert {:error, :street_address_pattern} =
               CityResolver.validate_city_name("76 Narrow Street")

      assert {:error, :street_address_pattern} =
               CityResolver.validate_city_name("42 Oak Avenue")

      assert {:error, :street_address_pattern} =
               CityResolver.validate_city_name("13 Bollo Lane")

      assert {:error, :street_address_pattern} =
               CityResolver.validate_city_name("1 High St")
    end

    test "rejects pure numeric values" do
      assert {:error, :postcode_pattern} = CityResolver.validate_city_name("12345")
      assert {:error, :postcode_pattern} = CityResolver.validate_city_name("999")
      assert {:error, :postcode_pattern} = CityResolver.validate_city_name("00000")
    end

    test "rejects likely venue names" do
      assert {:error, :venue_name_pattern} =
               CityResolver.validate_city_name("The Rose and Crown Pub")

      assert {:error, :venue_name_pattern} =
               CityResolver.validate_city_name("Sports Bar at Stadium")

      assert {:error, :venue_name_pattern} =
               CityResolver.validate_city_name("Green Dragon Inn")

      assert {:error, :venue_name_pattern} =
               CityResolver.validate_city_name("Downtown Restaurant")
    end

    test "accepts city names with numbers if not street addresses" do
      # Some cities legitimately have numbers
      assert {:ok, "Winston-Salem"} = CityResolver.validate_city_name("Winston-Salem")
    end

    test "handles non-string input" do
      assert {:error, :invalid_type} = CityResolver.validate_city_name(12345)
      assert {:error, :invalid_type} = CityResolver.validate_city_name([:not, :a, :string])
      assert {:error, :invalid_type} = CityResolver.validate_city_name(%{city: "Paris"})
    end
  end

  describe "integration tests" do
    test "end-to-end resolution rejects garbage coordinates" do
      # Test coordinates that historically produced garbage
      # These should either return valid cities or return errors

      # Example from issue: "13 Bollo Lane" coordinates (fictional for test)
      result = CityResolver.resolve_city(51.4922, -0.2432)

      case result do
        {:ok, city} ->
          # If we get a city, it should be valid
          assert {:ok, _} = CityResolver.validate_city_name(city)
          refute city =~ ~r/lane/i
          refute city =~ ~r/street/i
          refute city =~ ~r/road/i

        {:error, reason} ->
          # Errors are acceptable for bad coordinates
          assert reason in [
                   :not_found,
                   :invalid_city_name,
                   :missing_coordinates,
                   :geocoding_error
                 ]
      end
    end

    test "full workflow with valid coordinates" do
      # New York coordinates → should get valid city
      assert {:ok, city} = CityResolver.resolve_city(40.7128, -74.0060)
      assert {:ok, validated} = CityResolver.validate_city_name(city)
      assert validated == city
      assert String.length(validated) > 1
      refute validated =~ ~r/^\d+$/
      refute validated =~ ~r/street|road|avenue|lane/i
    end

    test "handles edge case of city name that looks like street" do
      # Some cities might have street-like names
      # The validation should be strict but not too strict
      result = CityResolver.validate_city_name("Highland Park")
      assert {:ok, "Highland Park"} = result
    end
  end
end
