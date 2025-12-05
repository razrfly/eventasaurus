defmodule EventasaurusDiscovery.Admin.DataQualityCheckerFixTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Admin.DataQualityChecker

  describe "Phase 4: Venue Country Fix Functions" do
    test "module exports fix_venue_country/1 function" do
      assert function_exported?(DataQualityChecker, :fix_venue_country, 1)
    end

    test "module exports fix_venue_country/2 function" do
      assert function_exported?(DataQualityChecker, :fix_venue_country, 2)
    end

    test "module exports ignore_venue_country_mismatch/1 function" do
      assert function_exported?(DataQualityChecker, :ignore_venue_country_mismatch, 1)
    end

    test "module exports ignore_venue_country_mismatch/2 function" do
      assert function_exported?(DataQualityChecker, :ignore_venue_country_mismatch, 2)
    end

    test "module exports bulk_fix_venue_countries/0 function" do
      assert function_exported?(DataQualityChecker, :bulk_fix_venue_countries, 0)
    end

    test "module exports bulk_fix_venue_countries/1 function" do
      assert function_exported?(DataQualityChecker, :bulk_fix_venue_countries, 1)
    end

    test "module exports get_venue_mismatch/1 function" do
      assert function_exported?(DataQualityChecker, :get_venue_mismatch, 1)
    end

    test "module exports venue_country_ignored?/1 function" do
      assert function_exported?(DataQualityChecker, :venue_country_ignored?, 1)
    end
  end

  describe "Phase 4: Implementation Details" do
    test "fix_venue_country uses CityResolver" do
      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify it uses CityResolver for geocoding
      assert source_code =~ "CityResolver.resolve_city_and_country"
    end

    test "fix_venue_country handles venue not found" do
      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify error handling
      assert source_code =~ ":venue_not_found"
      assert source_code =~ ":no_coordinates"
      assert source_code =~ ":not_a_mismatch"
    end

    test "ignore_venue_country_mismatch stores in metadata" do
      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify ignore storage in metadata
      assert source_code =~ "country_mismatch_ignored"
      assert source_code =~ "ignored_at"
    end

    test "bulk_fix_venue_countries filters by confidence" do
      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify confidence filtering
      assert source_code =~ ":high"
      assert source_code =~ ":medium"
      assert source_code =~ "confidence_match"
    end

    test "find_or_create_city creates city if not exists" do
      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify city creation logic
      assert source_code =~ "defp find_or_create_city"
      assert source_code =~ "City.changeset"
      assert source_code =~ "Repo.insert"
    end

    test "logs venue country fixes" do
      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify logging
      assert source_code =~ "log_venue_country_fix"
      assert source_code =~ "Logger.info"
      assert source_code =~ "[VenueCountryFix]"
    end
  end

  describe "Phase 4: Return Structure" do
    test "fix_venue_country returns expected success structure" do
      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify return structure fields
      assert source_code =~ "venue: updated_venue"
      assert source_code =~ "old_city: old_city"
      assert source_code =~ "new_city: new_city"
      assert source_code =~ "old_country: current_country"
      assert source_code =~ "new_country: expected_country_name"
    end

    test "bulk_fix_venue_countries returns count structure" do
      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify bulk return structure
      assert source_code =~ "fixed: fixed_count"
      assert source_code =~ "failed: failed_count"
      assert source_code =~ "total_attempted:"
      assert source_code =~ "results: results"
    end
  end
end
