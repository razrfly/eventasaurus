defmodule EventasaurusDiscovery.Helpers.CityResolverValidationTest do
  use EventasaurusApp.DataCase

  alias EventasaurusDiscovery.Helpers.CityResolver

  describe "validate_city_name/2 - street address detection" do
    test "rejects addresses starting with number-dash-number" do
      assert {:error, :street_address} = CityResolver.validate_city_name("10-16 Botchergate", "GB")
      assert {:error, :street_address} = CityResolver.validate_city_name("7-9", "GB")
      assert {:error, :street_address} = CityResolver.validate_city_name("23-26 High Street", "GB")
      assert {:error, :street_address} = CityResolver.validate_city_name("3-4 Northumberland Place", "GB")
    end

    test "rejects addresses starting with hash symbol" do
      assert {:error, :street_address} = CityResolver.validate_city_name("#59", "AU")
      assert {:error, :street_address} = CityResolver.validate_city_name("#23A", "US")
    end

    test "rejects addresses with number followed by letter" do
      assert {:error, :street_address} = CityResolver.validate_city_name("17A Wallgate", "GB")
      assert {:error, :street_address} = CityResolver.validate_city_name("6C Christchurch Road", "GB")
      assert {:error, :street_address} = CityResolver.validate_city_name("7a Cotton Road", "GB")
    end

    test "rejects addresses starting with number and containing street keywords" do
      assert {:error, :street_address} = CityResolver.validate_city_name("425 Burwood Hwy", "AU")
      assert {:error, :street_address} = CityResolver.validate_city_name("168 Lower Briggate Street", "GB")
      assert {:error, :street_address} = CityResolver.validate_city_name("12 Derrys Cross Road", "GB")
      assert {:error, :street_address} = CityResolver.validate_city_name("100 Main Street", "US")
    end

    test "rejects addresses with street keywords and numbers" do
      assert {:error, :street_address} = CityResolver.validate_city_name("8-9 Catalan Square", "GB")
      assert {:error, :street_address} = CityResolver.validate_city_name("46-54 Collie St", "AU")
      assert {:error, :street_address} = CityResolver.validate_city_name("54-56 Whitegate Drive", "GB")
    end

    test "rejects various street keyword variations" do
      assert {:error, :street_address} = CityResolver.validate_city_name("123 Main Street", "US")
      assert {:error, :street_address} = CityResolver.validate_city_name("456 Oak Road", "GB")
      assert {:error, :street_address} = CityResolver.validate_city_name("789 Highway 101", "US")
      assert {:error, :street_address} = CityResolver.validate_city_name("10 Park Avenue", "US")
      assert {:error, :street_address} = CityResolver.validate_city_name("5 Elm Lane", "GB")
      assert {:error, :street_address} = CityResolver.validate_city_name("25-27 Mount Pleasant Road", "GB")
    end
  end

  describe "validate_city_name/2 - real place names acceptance" do
    test "accepts real place names not in GeoNames" do
      # These are real administrative areas/neighborhoods in London
      assert {:ok, "Tower Hamlets"} = CityResolver.validate_city_name("Tower Hamlets", "GB")
      assert {:ok, "Westminster"} = CityResolver.validate_city_name("Westminster", "GB")
      assert {:ok, "Southwark"} = CityResolver.validate_city_name("Southwark", "GB")
    end

    test "accepts real neighborhoods" do
      # Real Dublin neighborhoods
      assert {:ok, "Dollymount"} = CityResolver.validate_city_name("Dollymount", "IE")
      assert {:ok, "Terenure"} = CityResolver.validate_city_name("Terenure", "IE")
      assert {:ok, "Rialto"} = CityResolver.validate_city_name("Rialto", "IE")
    end

    test "accepts place names with country codes in parentheses" do
      # May not be in GeoNames with this exact format
      assert {:ok, "Dublin (GB)"} = CityResolver.validate_city_name("Dublin (GB)", "GB")
    end

    test "accepts multi-word place names" do
      assert {:ok, "New Forest"} = CityResolver.validate_city_name("New Forest", "GB")
      assert {:ok, "Peak District"} = CityResolver.validate_city_name("Peak District", "GB")
    end

    test "accepts place names with hyphens" do
      assert {:ok, "Stratford-upon-Avon"} = CityResolver.validate_city_name("Stratford-upon-Avon", "GB")
      assert {:ok, "Kingston-upon-Thames"} = CityResolver.validate_city_name("Kingston-upon-Thames", "GB")
    end

    test "accepts place names with apostrophes" do
      assert {:ok, "St. Mary's"} = CityResolver.validate_city_name("St. Mary's", "GB")
      assert {:ok, "King's Lynn"} = CityResolver.validate_city_name("King's Lynn", "GB")
    end

    test "accepts international city names with Unicode characters" do
      # Slovak cities with diacritics (á, š, č, Ý, Ď)
      assert {:ok, "Liptovský Mikuláš"} = CityResolver.validate_city_name("Liptovský Mikuláš", "SK")
      assert {:ok, "Mýto pod Ďumbierom"} = CityResolver.validate_city_name("Mýto pod Ďumbierom", "SK")
      assert {:ok, "Kavečany"} = CityResolver.validate_city_name("Kavečany", "SK")

      # Cypriot city with Greek characters
      assert {:ok, "Pissoúri"} = CityResolver.validate_city_name("Pissoúri", "CY")

      # German cities with umlauts
      assert {:ok, "München"} = CityResolver.validate_city_name("München", "DE")
      assert {:ok, "Köln"} = CityResolver.validate_city_name("Köln", "DE")

      # Nordic cities
      assert {:ok, "Malmö"} = CityResolver.validate_city_name("Malmö", "SE")
      assert {:ok, "Århus"} = CityResolver.validate_city_name("Århus", "DK")

      # Spanish cities
      assert {:ok, "Córdoba"} = CityResolver.validate_city_name("Córdoba", "ES")
      assert {:ok, "Cádiz"} = CityResolver.validate_city_name("Cádiz", "ES")

      # Polish cities
      assert {:ok, "Kraków"} = CityResolver.validate_city_name("Kraków", "PL")
      assert {:ok, "Łódź"} = CityResolver.validate_city_name("Łódź", "PL")
    end
  end

  describe "validate_city_name/2 - edge cases" do
    test "rejects empty or too short names" do
      assert {:error, :empty_name} = CityResolver.validate_city_name("", "GB")
      assert {:error, :empty_name} = CityResolver.validate_city_name("  ", "GB")
      assert {:error, :too_short} = CityResolver.validate_city_name("A", "GB")
    end

    test "rejects names ending with numbers (likely postcodes)" do
      assert {:error, :not_a_valid_city} = CityResolver.validate_city_name("SW1A 1AA", "GB")
      assert {:error, :not_a_valid_city} = CityResolver.validate_city_name("M1 5AN", "GB")
    end

    test "rejects all-uppercase abbreviations" do
      assert {:error, :not_a_valid_city} = CityResolver.validate_city_name("SOHO", "GB")
      assert {:error, :not_a_valid_city} = CityResolver.validate_city_name("TRIBECA", "US")
    end

    test "allows short place names that start with letters" do
      # "Rye", "Ely" are real UK cities
      assert {:ok, "Rye"} = CityResolver.validate_city_name("Rye", "GB")
      assert {:ok, "Ely"} = CityResolver.validate_city_name("Ely", "GB")
    end
  end

  describe "validate_city_name/2 - GeoNames integration" do
    test "accepts cities in GeoNames database" do
      # Major cities that should definitely be in GeoNames
      assert {:ok, "London"} = CityResolver.validate_city_name("London", "GB")
      assert {:ok, "New York"} = CityResolver.validate_city_name("New York", "US")
      assert {:ok, "Sydney"} = CityResolver.validate_city_name("Sydney", "AU")
    end

    test "is case-insensitive for GeoNames lookup" do
      # GeoNames lookup should work regardless of case
      assert {:ok, "london"} = CityResolver.validate_city_name("london", "GB")
      assert {:ok, "LONDON"} = CityResolver.validate_city_name("LONDON", "GB")
      assert {:ok, "LoNdOn"} = CityResolver.validate_city_name("LoNdOn", "GB")
    end
  end

  describe "validate_city_name/2 - false positive prevention" do
    test "does not flag legitimate place names as street addresses" do
      # These contain words that COULD be street keywords but are real places
      # "Close" is a street keyword but also part of place names
      # Should pass heuristic validation since they don't have numbers
      assert {:ok, result} = CityResolver.validate_city_name("The Close", "GB")
      assert is_binary(result)
    end

    test "does not flag numbered landmarks as street addresses if no street keywords" do
      # "Tower 42" is a London landmark - has number but no street keyword
      # Should be rejected by heuristic (ends with number) not street address detection
      assert {:error, :not_a_valid_city} = CityResolver.validate_city_name("Tower 42", "GB")
    end
  end
end
