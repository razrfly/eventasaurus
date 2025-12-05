defmodule EventasaurusWeb.Admin.VenueCountryMismatchesLiveTest do
  use ExUnit.Case, async: true

  alias EventasaurusWeb.Admin.VenueCountryMismatchesLive

  describe "Phase 4: LiveView Module" do
    test "module exists" do
      assert Code.ensure_compiled?(VenueCountryMismatchesLive)
    end

    test "implements mount/3 callback" do
      assert function_exported?(VenueCountryMismatchesLive, :mount, 3)
    end

    test "implements handle_event/3 callback" do
      assert function_exported?(VenueCountryMismatchesLive, :handle_event, 3)
    end

    test "implements handle_params/3 callback" do
      assert function_exported?(VenueCountryMismatchesLive, :handle_params, 3)
    end
  end

  describe "Phase 4: Helper Functions" do
    test "confidence_color returns correct class for high" do
      assert VenueCountryMismatchesLive.confidence_color(:high) =~ "green"
    end

    test "confidence_color returns correct class for medium" do
      assert VenueCountryMismatchesLive.confidence_color(:medium) =~ "yellow"
    end

    test "confidence_color returns correct class for low" do
      assert VenueCountryMismatchesLive.confidence_color(:low) =~ "red"
    end

    test "confidence_label returns uppercase label" do
      assert VenueCountryMismatchesLive.confidence_label(:high) == "HIGH"
      assert VenueCountryMismatchesLive.confidence_label(:medium) == "MEDIUM"
      assert VenueCountryMismatchesLive.confidence_label(:low) == "LOW"
    end

    test "format_coords formats coordinates" do
      result = VenueCountryMismatchesLive.format_coords(51.5074, -0.1278)
      assert result =~ "51.5074"
      assert result =~ "-0.1278"
    end

    test "format_coords handles nil" do
      assert VenueCountryMismatchesLive.format_coords(nil, nil) == "N/A"
    end

    test "truncate shortens long strings" do
      long_string = "This is a very long venue name that should be truncated"
      result = VenueCountryMismatchesLive.truncate(long_string, 20)
      assert String.length(result) <= 20
      assert String.ends_with?(result, "...")
    end

    test "truncate preserves short strings" do
      short_string = "Short"
      result = VenueCountryMismatchesLive.truncate(short_string, 20)
      assert result == short_string
    end
  end

  describe "Phase 4: Event Handlers" do
    test "supports refresh event" do
      source_path =
        VenueCountryMismatchesLive.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      assert source_code =~ ~s(handle_event("refresh")
    end

    test "supports filter event" do
      source_path =
        VenueCountryMismatchesLive.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      assert source_code =~ ~s(handle_event("filter")
    end

    test "supports fix_venue event" do
      source_path =
        VenueCountryMismatchesLive.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      assert source_code =~ ~s(handle_event("fix_venue")
    end

    test "supports ignore_venue event" do
      source_path =
        VenueCountryMismatchesLive.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      assert source_code =~ ~s(handle_event("ignore_venue")
    end

    test "supports bulk_fix event" do
      source_path =
        VenueCountryMismatchesLive.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      assert source_code =~ ~s(handle_event("bulk_fix")
    end

    test "supports switch_tab event" do
      source_path =
        VenueCountryMismatchesLive.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      assert source_code =~ ~s(handle_event("switch_tab")
    end

    test "supports export_json event" do
      source_path =
        VenueCountryMismatchesLive.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      assert source_code =~ ~s(handle_event("export_json")
    end
  end

  describe "Phase 4: Uses DataQualityChecker" do
    test "calls check_venue_countries" do
      source_path =
        VenueCountryMismatchesLive.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      assert source_code =~ "DataQualityChecker.check_venue_countries"
    end

    test "calls fix_venue_country" do
      source_path =
        VenueCountryMismatchesLive.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      assert source_code =~ "DataQualityChecker.fix_venue_country"
    end

    test "calls ignore_venue_country_mismatch" do
      source_path =
        VenueCountryMismatchesLive.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      assert source_code =~ "DataQualityChecker.ignore_venue_country_mismatch"
    end

    test "calls bulk_fix_venue_countries" do
      source_path =
        VenueCountryMismatchesLive.module_info(:compile)[:source]
        |> to_string()

      {:ok, source_code} = File.read(source_path)

      assert source_code =~ "DataQualityChecker.bulk_fix_venue_countries"
    end
  end
end
