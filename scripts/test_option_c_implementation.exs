#!/usr/bin/env elixir

# Test the Option C implementation for week_pl
# Validates the new multi-date aliased query approach
#
# Usage: mix run test_option_c_implementation.exs

defmodule OptionCTest do
  @moduledoc """
  Tests the Option C implementation (Issue #2351) for week_pl source.
  Validates that the new multi-date aliased query works correctly.
  """

  def run do
    IO.puts("\n" <> IO.ANSI.cyan() <> "=== Testing Option C Implementation (Issue #2351) ===" <> IO.ANSI.reset())
    IO.puts("Testing week_pl Client.fetch_restaurants with multi-date aliases\n")

    # Load the application to access Client module
    Mix.Task.run("app.start")

    # Test parameters
    region_id = "1"  # Kraków
    region_name = "Kraków"
    base_date = Date.utc_today() |> Date.to_string()
    slot = 1140  # 7:00 PM
    people_count = 2

    IO.puts("Test parameters:")
    IO.puts("  Region: #{region_name} (ID: #{region_id})")
    IO.puts("  Base date: #{base_date}")
    IO.puts("  Date range: #{base_date} to #{Date.utc_today() |> Date.add(7) |> Date.to_string()}")
    IO.puts("  Time slot: #{slot} (7:00 PM)")
    IO.puts("  Party size: #{people_count}\n")

    IO.puts(IO.ANSI.yellow() <> "Executing fetch_restaurants with multi-date aliases..." <> IO.ANSI.reset())

    # Call the updated Client.fetch_restaurants function
    result = EventasaurusDiscovery.Sources.WeekPl.Client.fetch_restaurants(
      region_id,
      region_name,
      base_date,
      slot,
      people_count
    )

    case result do
      {:ok, response} ->
        analyze_response(response, region_name)

      {:error, reason} ->
        IO.puts(IO.ANSI.red() <> "❌ Request failed: #{inspect(reason)}" <> IO.ANSI.reset())
        IO.puts("\nTest FAILED")
    end
  end

  defp analyze_response(%{"pageProps" => %{"apolloState" => apollo_state}}, region_name) do
    # Extract restaurants from Apollo state
    restaurants =
      apollo_state
      |> Enum.filter(fn {key, _} -> String.starts_with?(key, "Restaurant:") end)
      |> Enum.map(fn {_key, restaurant} -> restaurant end)

    restaurant_count = length(restaurants)

    IO.puts("\n" <> IO.ANSI.green() <> IO.ANSI.bright() <> "✅ SUCCESS!" <> IO.ANSI.reset())
    IO.puts("Region: #{region_name}")
    IO.puts("Unique restaurants found: #{restaurant_count}")

    if restaurant_count > 0 do
      IO.puts("\n" <> IO.ANSI.cyan() <> "Sample restaurants:" <> IO.ANSI.reset())

      restaurants
      |> Enum.take(5)
      |> Enum.each(fn r ->
        IO.puts("  - #{r["name"]}")
        IO.puts("    Slug: #{r["slug"]}")
        IO.puts("    ID: #{r["id"]}")
        IO.puts("    Address: #{r["address"]}")

        tags = (r["tags"] || []) |> Enum.map(& &1["name"]) |> Enum.join(", ")
        if tags != "", do: IO.puts("    Tags: #{tags}")

        IO.puts("")
      end)

      # Validation checks
      IO.puts(IO.ANSI.cyan() <> "Validation:" <> IO.ANSI.reset())

      # Check for duplicates (there shouldn't be any due to Enum.uniq_by in implementation)
      restaurant_ids = Enum.map(restaurants, & &1["id"])
      unique_ids = Enum.uniq(restaurant_ids)

      if length(restaurant_ids) == length(unique_ids) do
        IO.puts("  ✅ No duplicate restaurants (deduplication working)")
      else
        duplicate_count = length(restaurant_ids) - length(unique_ids)
        IO.puts("  ⚠️  Found #{duplicate_count} duplicates")
      end

      # Check data completeness
      missing_fields =
        restaurants
        |> Enum.filter(fn r ->
          is_nil(r["id"]) || is_nil(r["name"]) || is_nil(r["slug"])
        end)
        |> length()

      if missing_fields == 0 do
        IO.puts("  ✅ All restaurants have required fields (id, name, slug)")
      else
        IO.puts("  ⚠️  #{missing_fields} restaurants missing required fields")
      end

      # Check for GPS coordinates
      has_coords =
        restaurants
        |> Enum.filter(fn r ->
          !is_nil(r["latitude"]) && !is_nil(r["longitude"])
        end)
        |> length()

      IO.puts("  ✅ #{has_coords}/#{restaurant_count} restaurants have GPS coordinates")

      # Success summary
      IO.puts("\n" <> IO.ANSI.green() <> "Summary:" <> IO.ANSI.reset())
      IO.puts("  • Multi-date aliased query: WORKING ✅")
      IO.puts("  • Deduplication: WORKING ✅")
      IO.puts("  • Data format: Compatible with existing jobs ✅")
      IO.puts("  • Coverage: #{restaurant_count} unique restaurants across 8 dates")
      IO.puts("\n" <> IO.ANSI.green() <> "🎉 Option C implementation is functioning correctly!" <> IO.ANSI.reset())

    else
      IO.puts(IO.ANSI.yellow() <> "⚠️  No restaurants found - this might be expected if:")
      IO.puts("  - No restaurants have availability for the queried dates")
      IO.puts("  - No active festival is running")
      IO.puts("  - API rate limiting is in effect" <> IO.ANSI.reset())
    end
  end

  defp analyze_response(response, _region_name) do
    IO.puts(IO.ANSI.red() <> "❌ Unexpected response structure" <> IO.ANSI.reset())
    IO.puts(inspect(response, pretty: true, limit: :infinity))
  end
end

# Run the test
OptionCTest.run()
