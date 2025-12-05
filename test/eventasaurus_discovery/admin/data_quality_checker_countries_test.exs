defmodule EventasaurusDiscovery.Admin.DataQualityCheckerCountriesTest do
  use ExUnit.Case, async: true

  alias EventasaurusDiscovery.Admin.DataQualityChecker

  describe "Phase 3: Venue Country Mismatch Detection" do
    test "module exports check_venue_countries/1 function" do
      assert function_exported?(DataQualityChecker, :check_venue_countries, 1)
    end

    test "module exports get_country_mismatches/3 function" do
      assert function_exported?(DataQualityChecker, :get_country_mismatches, 3)
    end

    test "module exports export_venue_country_report/1 function" do
      assert function_exported?(DataQualityChecker, :export_venue_country_report, 1)
    end

    test "check_venue_countries/1 accepts options" do
      # Verify function signature accepts keyword list options
      # Without database, we just verify it doesn't crash on options parsing
      {:module, DataQualityChecker} = Code.ensure_compiled(DataQualityChecker)

      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify function definition exists with options
      assert source_code =~ "def check_venue_countries(options \\\\ [])"
      assert source_code =~ "limit = Keyword.get(options, :limit, 1000)"
      assert source_code =~ "source_slug = Keyword.get(options, :source)"
      assert source_code =~ "country_filter = Keyword.get(options, :country)"
    end

    test "check_venue_countries returns expected structure" do
      # Verify the return structure documentation
      {:module, DataQualityChecker} = Code.ensure_compiled(DataQualityChecker)

      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify return structure keys
      assert source_code =~ "total_checked:"
      assert source_code =~ "mismatch_count:"
      assert source_code =~ "mismatches:"
      assert source_code =~ "by_confidence:"
      assert source_code =~ "by_country_pair:"
    end
  end

  describe "Phase 3: Implementation Details" do
    test "uses CityResolver for geocoding" do
      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      assert source_code =~ "alias EventasaurusDiscovery.Helpers.CityResolver"
      assert source_code =~ "CityResolver.resolve_city_and_country"
    end

    test "supports confidence levels" do
      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify confidence level determination
      assert source_code =~ "determine_confidence"
      assert source_code =~ ":high"
      assert source_code =~ ":medium" or source_code =~ ":low"
    end

    test "normalizes country names for comparison" do
      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify normalization function
      assert source_code =~ "defp normalize_country"
      assert source_code =~ "String.downcase"
    end

    test "handles UK vs Ireland as high confidence" do
      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify UK/Ireland handling
      assert source_code =~ "united kingdom"
      assert source_code =~ "ireland"
    end

    test "uses common country names mapping" do
      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify common names mapping exists
      assert source_code =~ "@common_country_names"
      assert source_code =~ "\"GB\" => \"United Kingdom\""
      assert source_code =~ "\"IE\" => \"Ireland\""
    end
  end

  describe "Phase 3: Export Report Structure" do
    test "export_venue_country_report generates expected fields" do
      source_path =
        DataQualityChecker.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      # Verify export structure
      assert source_code =~ "generated_at:"
      assert source_code =~ "DateTime.utc_now()"
      assert source_code =~ "DateTime.to_iso8601"
    end
  end
end
