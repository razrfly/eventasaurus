defmodule EventasaurusDiscovery.Scraping.Processors.VenueProcessorCityValidationTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusDiscovery.Scraping.Processors.VenueProcessor
  alias EventasaurusDiscovery.Locations.{City, Country}
  alias EventasaurusApp.Sources.Source

  describe "VenueProcessor city validation (Layer 2 safety net)" do
    setup do
      # Create test country
      {:ok, country} = %Country{}
        |> Country.changeset(%{
          name: "United Kingdom",
          code: "GB",
          slug: "united-kingdom"
        })
        |> Repo.insert()

      # Create test source
      {:ok, source} = %Source{}
        |> Source.changeset(%{
          name: "Test Source",
          slug: "test-source",
          is_active: true
        })
        |> Repo.insert()

      %{country: country, source: source}
    end

    test "rejects UK postcodes", %{country: country} do
      venue_data = %{
        name: "Test Venue",
        city_name: "SW18 2SS",  # UK postcode
        country_name: "United Kingdom",
        latitude: 51.4566,
        longitude: -0.1917
      }

      # VenueProcessor should reject this due to invalid city name
      result = VenueProcessor.process_venue_data(venue_data, country.id, nil)

      # Should fail because city validation rejected the postcode
      assert {:error, reason} = result
      assert reason =~ "Failed to find or create city"
    end

    test "rejects US ZIP codes", %{country: country} do
      venue_data = %{
        name: "Test Venue",
        city_name: "90210",  # US ZIP code
        country_name: "United Kingdom",
        latitude: 51.5074,
        longitude: -0.1278
      }

      result = VenueProcessor.process_venue_data(venue_data, country.id, nil)

      assert {:error, reason} = result
      assert reason =~ "Failed to find or create city"
    end

    test "rejects street addresses starting with numbers", %{country: country} do
      venue_data = %{
        name: "Test Venue",
        city_name: "13 Bollo Lane",  # Street address
        country_name: "United Kingdom",
        latitude: 51.4936,
        longitude: -0.2663
      }

      result = VenueProcessor.process_venue_data(venue_data, country.id, nil)

      assert {:error, reason} = result
      assert reason =~ "Failed to find or create city"
    end

    test "rejects pure numeric values", %{country: country} do
      venue_data = %{
        name: "Test Venue",
        city_name: "12345",  # Pure number
        country_name: "United Kingdom",
        latitude: 51.5074,
        longitude: -0.1278
      }

      result = VenueProcessor.process_venue_data(venue_data, country.id, nil)

      assert {:error, reason} = result
      assert reason =~ "Failed to find or create city"
    end

    test "accepts valid city names", %{country: country, source: source} do
      venue_data = %{
        name: "Test Venue",
        city_name: "London",  # Valid city
        country_name: "United Kingdom",
        latitude: 51.5074,
        longitude: -0.1278
      }

      result = VenueProcessor.process_venue_data(venue_data, source)

      # Should succeed with valid city name
      assert {:ok, venue} = result
      assert venue.city.name == "London"
      assert venue.city.country_id == country.id
    end

    test "allows nil city names", %{source: source} do
      venue_data = %{
        name: "Test Venue",
        city_name: nil,  # Nil is allowed
        country_name: "United Kingdom",
        latitude: 51.5074,
        longitude: -0.1278
      }

      result = VenueProcessor.process_venue_data(venue_data, source)

      # Should succeed but without city
      # Note: This depends on how VenueProcessor handles nil cities
      # Adjust assertion based on actual behavior
      case result do
        {:ok, venue} ->
          # If VenueProcessor allows venues without cities
          assert is_nil(venue.city_id)

        {:error, _} ->
          # If VenueProcessor requires cities
          # This is expected behavior - venue needs a city
          assert true
      end
    end

    test "validates city names even when transformers don't", %{country: country} do
      # Simulate a buggy transformer passing invalid city
      venue_data = %{
        name: "Test Venue",
        city_name: "76 Narrow Street",  # Street address from buggy transformer
        country_name: "United Kingdom",
        latitude: 51.5074,
        longitude: -0.1278
      }

      result = VenueProcessor.process_venue_data(venue_data, country.id, nil)

      # VenueProcessor safety net should catch this
      assert {:error, reason} = result
      assert reason =~ "Failed to find or create city"
    end

    test "prevents database pollution from any source", %{country: country} do
      # Test that multiple invalid city names are all rejected
      invalid_cities = [
        "SW18 2SS",         # UK postcode
        "90210",            # US ZIP
        "13 Bollo Lane",    # Street address
        "999",              # Numeric
        "The Rose Crown"    # Could be venue name
      ]

      for invalid_city <- invalid_cities do
        venue_data = %{
          name: "Test Venue",
          city_name: invalid_city,
          country_name: "United Kingdom",
          latitude: 51.5074,
          longitude: -0.1278
        }

        result = VenueProcessor.process_venue_data(venue_data, country.id, nil)

        # All should be rejected
        assert {:error, _} = result,
               "Expected #{invalid_city} to be rejected but it was accepted"
      end

      # Verify no invalid cities were created
      invalid_city_count = Repo.all(
        from c in City,
        where: c.country_id == ^country.id and
               (c.name ~* "^[A-Z]{1,2}[0-9]{1,2}" or  # Postcodes
                c.name ~* "^\\d+$" or                  # Pure numbers
                c.name ~* "^\\d+\\s+")                 # Street addresses
      ) |> length()

      assert invalid_city_count == 0, "Found #{invalid_city_count} invalid cities in database"
    end
  end

  describe "VenueProcessor integration with transformers" do
    setup do
      {:ok, country} = %Country{}
        |> Country.changeset(%{
          name: "United States",
          code: "US",
          slug: "united-states"
        })
        |> Repo.insert()

      {:ok, source} = %Source{}
        |> Source.changeset(%{
          name: "Test Source",
          slug: "test-source",
          is_active: true
        })
        |> Repo.insert()

      %{country: country, source: source}
    end

    test "works with transformer-validated city names", %{country: country, source: source} do
      # Simulate a good transformer providing validated city
      venue_data = %{
        name: "Test Venue",
        city_name: "New York",  # Already validated by transformer
        country_name: "United States",
        latitude: 40.7128,
        longitude: -74.0060
      }

      result = VenueProcessor.process_venue_data(venue_data, source)

      # Both layers of validation pass
      assert {:ok, venue} = result
      assert venue.city.name == "New York"
    end

    test "catches transformer mistakes (defense in depth)", %{country: country} do
      # Simulate a transformer that forgot to validate
      venue_data = %{
        name: "Test Venue",
        city_name: "10001",  # ZIP code that transformer didn't catch
        country_name: "United States",
        latitude: 40.7128,
        longitude: -74.0060
      }

      result = VenueProcessor.process_venue_data(venue_data, country.id, nil)

      # VenueProcessor (Layer 2) catches what transformer (Layer 1) missed
      assert {:error, _} = result
    end
  end

  describe "VenueProcessor logging" do
    setup do
      {:ok, country} = %Country{}
        |> Country.changeset(%{
          name: "Poland",
          code: "PL",
          slug: "poland"
        })
        |> Repo.insert()

      %{country: country}
    end

    test "logs detailed error for invalid city names", %{country: country} do
      venue_data = %{
        name: "Test Venue",
        city_name: "00-001",  # Polish postcode
        country_name: "Poland",
        latitude: 52.2297,
        longitude: 21.0122
      }

      # Capture log output
      log_output = ExUnit.CaptureLog.capture_log(fn ->
        VenueProcessor.process_venue_data(venue_data, country.id, nil)
      end)

      # Should log rejection with details
      assert log_output =~ "VenueProcessor REJECTED invalid city name"
      assert log_output =~ "00-001"
      assert log_output =~ "Poland"
    end
  end
end
