defmodule Mix.Tasks.Quality.TestIrishVenues do
  use Mix.Task

  @shortdoc "Test venue country detection with known Irish coordinates"

  @moduledoc """
  Test venue country detection to debug why 0 mismatches are detected.

  This tests:
  1. Raw :geocoding.reverse/2 output for Irish coordinates
  2. CityResolver.resolve_city_and_country/2 for Irish coordinates
  3. The full check_venue_countries query with limit=5

  ## Usage

      mix quality.test_irish_venues
  """

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    alias EventasaurusDiscovery.Helpers.CityResolver
    alias EventasaurusDiscovery.Admin.DataQualityChecker

    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.bright() <> "=== Irish Venue Detection Test ===" <> IO.ANSI.reset())
    Mix.shell().info("")

    # Test 1: Raw geocoding for Dingle coordinates (known Irish venue)
    dingle_lat = 52.1408534
    dingle_lng = -10.2671142

    Mix.shell().info(
      IO.ANSI.bright() <>
        "1. Testing raw :geocoding.reverse for Dingle (#{dingle_lat}, #{dingle_lng})" <>
        IO.ANSI.reset()
    )

    raw_result = :geocoding.reverse(dingle_lat, dingle_lng)
    Mix.shell().info("   Raw result: #{inspect(raw_result)}")
    Mix.shell().info("")

    # Test 2: CityResolver for Dingle
    Mix.shell().info(
      IO.ANSI.bright() <> "2. Testing CityResolver.resolve_city_and_country" <> IO.ANSI.reset()
    )

    resolver_result = CityResolver.resolve_city_and_country(dingle_lat, dingle_lng)
    Mix.shell().info("   CityResolver result: #{inspect(resolver_result)}")
    Mix.shell().info("")

    # Test 3: Cork coordinates
    cork_lat = 51.8985
    cork_lng = -8.4756

    Mix.shell().info(
      IO.ANSI.bright() <>
        "3. Testing Cork coordinates (#{cork_lat}, #{cork_lng})" <> IO.ANSI.reset()
    )

    cork_raw = :geocoding.reverse(cork_lat, cork_lng)
    Mix.shell().info("   Raw result: #{inspect(cork_raw)}")

    cork_resolver = CityResolver.resolve_city_and_country(cork_lat, cork_lng)
    Mix.shell().info("   CityResolver result: #{inspect(cork_resolver)}")
    Mix.shell().info("")

    # Test 4: Dublin coordinates
    dublin_lat = 53.3498
    dublin_lng = -6.2603

    Mix.shell().info(
      IO.ANSI.bright() <>
        "4. Testing Dublin coordinates (#{dublin_lat}, #{dublin_lng})" <> IO.ANSI.reset()
    )

    dublin_raw = :geocoding.reverse(dublin_lat, dublin_lng)
    Mix.shell().info("   Raw result: #{inspect(dublin_raw)}")

    dublin_resolver = CityResolver.resolve_city_and_country(dublin_lat, dublin_lng)
    Mix.shell().info("   CityResolver result: #{inspect(dublin_resolver)}")
    Mix.shell().info("")

    # Test 5: Test Wicklow coordinates (venue 239 in local DB)
    wicklow_lat = 52.9829065
    wicklow_lng = -6.0420741

    Mix.shell().info(
      IO.ANSI.bright() <>
        "5. Testing Wicklow coordinates (#{wicklow_lat}, #{wicklow_lng})" <> IO.ANSI.reset()
    )

    wicklow_raw = :geocoding.reverse(wicklow_lat, wicklow_lng)
    Mix.shell().info("   Raw result: #{inspect(wicklow_raw)}")

    wicklow_resolver = CityResolver.resolve_city_and_country(wicklow_lat, wicklow_lng)
    Mix.shell().info("   CityResolver result: #{inspect(wicklow_resolver)}")
    Mix.shell().info("")

    # Test 6: Check venue countries with limit 50
    Mix.shell().info(
      IO.ANSI.bright() <>
        "6. Testing check_venue_countries(limit: 50, country: \"United Kingdom\")" <>
        IO.ANSI.reset()
    )

    result = DataQualityChecker.check_venue_countries(limit: 50, country: "United Kingdom")
    Mix.shell().info("   Total checked: #{result.total_checked}")
    Mix.shell().info("   Mismatches found: #{result.mismatch_count}")
    Mix.shell().info("   By confidence: #{inspect(result.by_confidence)}")
    Mix.shell().info("   By country pair: #{inspect(result.by_country_pair)}")
    Mix.shell().info("")

    # If we have results, show first 3
    if length(result.mismatches) > 0 do
      Mix.shell().info(IO.ANSI.bright() <> "   First 3 mismatches:" <> IO.ANSI.reset())

      result.mismatches
      |> Enum.take(3)
      |> Enum.each(fn m ->
        Mix.shell().info("   - #{m.venue_name} (#{m.current_country} -> #{m.expected_country})")
        Mix.shell().info("     coords: (#{m.latitude}, #{m.longitude})")
      end)
    else
      Mix.shell().info(IO.ANSI.yellow() <> "   No mismatches found!" <> IO.ANSI.reset())

      # Show mismatches from a fresh query for debugging
      Mix.shell().info("")
      Mix.shell().info("   Mismatches from fresh query (limit: 3):")
      all_results = DataQualityChecker.check_venue_countries(limit: 3, country: "United Kingdom")

      if Enum.empty?(all_results.mismatches) do
        Mix.shell().info("   No mismatches in sample - venues may already be correctly assigned")
      else
        Enum.each(all_results.mismatches, fn r ->
          Mix.shell().info(
            "   - #{r.venue_name}: current=#{r.current_country}, expected=#{r.expected_country}"
          )
        end)
      end
    end

    Mix.shell().info("")
  end
end
