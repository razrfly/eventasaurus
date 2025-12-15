#!/usr/bin/env elixir

# Test script to validate if week.pl GraphQL API supports query aliases
# This tests Option C from issue #2351
#
# Usage: elixir test_week_pl_aliases.exs

Mix.install([
  {:httpoison, "~> 2.0"},
  {:jason, "~> 1.4"}
])

defmodule WeekPlAliasTest do
  @moduledoc """
  Tests whether week.pl GraphQL API supports aliased queries for multiple dates.
  """

  @graphql_url "https://api.week.pl/graphql"
  @headers [
    {"Content-Type", "application/json"},
    {"Accept", "application/json"},
    {"Accept-Language", "pl,en;q=0.9"},
    {"User-Agent", "Mozilla/5.0 (compatible; EventasaurusBot/1.0)"}
  ]

  def run do
    IO.puts("\n" <> IO.ANSI.cyan() <> "=== Testing week.pl GraphQL API Alias Support ===" <> IO.ANSI.reset())
    IO.puts("Issue: #2351 - Option C validation\n")

    # Calculate test dates
    today = Date.utc_today()
    tomorrow = Date.add(today, 1)
    week_out = Date.add(today, 7)

    today_str = Date.to_string(today)
    tomorrow_str = Date.to_string(tomorrow)
    week_out_str = Date.to_string(week_out)

    IO.puts("Test dates:")
    IO.puts("  - Today: #{today_str}")
    IO.puts("  - Tomorrow: #{tomorrow_str}")
    IO.puts("  - Week out: #{week_out_str}\n")

    # Test 1: Single date query (baseline - should work)
    IO.puts(IO.ANSI.yellow() <> "Test 1: Single date query (baseline)" <> IO.ANSI.reset())
    test_single_date("1", "Kraków", tomorrow_str)

    IO.puts("\n" <> String.duplicate("-", 80) <> "\n")

    # Test 2: Aliased multi-date query (the key test)
    IO.puts(IO.ANSI.yellow() <> "Test 2: Aliased multi-date query" <> IO.ANSI.reset())
    test_aliased_query("1", "Kraków", today_str, tomorrow_str, week_out_str)

    IO.puts("\n" <> IO.ANSI.cyan() <> "=== Test Complete ===" <> IO.ANSI.reset() <> "\n")
  end

  defp test_single_date(region_id, region_name, date) do
    query = """
    query GetRestaurants($regionId: ID!, $filters: ReservationFilter) {
      restaurants(region_id: $regionId, reservation_filters: $filters, first: 5) {
        nodes {
          id
          name
          slug
        }
      }
    }
    """

    variables = %{
      "regionId" => region_id,
      "filters" => %{
        "startsOn" => date,
        "endsOn" => date,
        "hours" => [1140],  # 7:00 PM
        "peopleCount" => 2
      }
    }

    case execute_query(query, variables) do
      {:ok, response} ->
        analyze_single_response(response, region_name, date)

      {:error, reason} ->
        IO.puts(IO.ANSI.red() <> "❌ Request failed: #{inspect(reason)}" <> IO.ANSI.reset())
    end
  end

  defp test_aliased_query(region_id, region_name, date_today, date_tomorrow, date_week) do
    # This is the critical test - can we use aliases to query multiple dates?
    query = """
    query GetRestaurantsMultipleDates($regionId: ID!, $filtersToday: ReservationFilter, $filtersTomorrow: ReservationFilter, $filtersWeek: ReservationFilter) {
      today: restaurants(region_id: $regionId, reservation_filters: $filtersToday, first: 5) {
        nodes {
          id
          name
          slug
        }
      }
      tomorrow: restaurants(region_id: $regionId, reservation_filters: $filtersTomorrow, first: 5) {
        nodes {
          id
          name
          slug
        }
      }
      week_out: restaurants(region_id: $regionId, reservation_filters: $filtersWeek, first: 5) {
        nodes {
          id
          name
          slug
        }
      }
    }
    """

    variables = %{
      "regionId" => region_id,
      "filtersToday" => %{
        "startsOn" => date_today,
        "endsOn" => date_today,
        "hours" => [1140],
        "peopleCount" => 2
      },
      "filtersTomorrow" => %{
        "startsOn" => date_tomorrow,
        "endsOn" => date_tomorrow,
        "hours" => [1140],
        "peopleCount" => 2
      },
      "filtersWeek" => %{
        "startsOn" => date_week,
        "endsOn" => date_week,
        "hours" => [1140],
        "peopleCount" => 2
      }
    }

    case execute_query(query, variables) do
      {:ok, response} ->
        analyze_aliased_response(response, region_name)

      {:error, reason} ->
        IO.puts(IO.ANSI.red() <> "❌ Request failed: #{inspect(reason)}" <> IO.ANSI.reset())
    end
  end

  defp execute_query(query, variables) do
    body = Jason.encode!(%{
      "query" => query,
      "variables" => variables
    })

    IO.puts("Sending request to #{@graphql_url}...")

    case HTTPoison.post(@graphql_url, body, @headers, timeout: 15_000, recv_timeout: 15_000) do
      {:ok, %{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, json} -> {:ok, json}
          {:error, reason} -> {:error, {:json_decode_error, reason}}
        end

      {:ok, %{status_code: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, %{reason: reason}} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp analyze_single_response(response, region_name, date) do
    case response do
      %{"data" => %{"restaurants" => %{"nodes" => restaurants}}} ->
        count = length(restaurants)
        IO.puts(IO.ANSI.green() <> "✅ Success!" <> IO.ANSI.reset())
        IO.puts("Region: #{region_name}")
        IO.puts("Date: #{date}")
        IO.puts("Restaurants found: #{count}")

        if count > 0 do
          IO.puts("\nSample restaurants:")
          restaurants
          |> Enum.take(3)
          |> Enum.each(fn r ->
            IO.puts("  - #{r["name"]} (#{r["slug"]}, ID: #{r["id"]})")
          end)
        end

      %{"errors" => errors} ->
        IO.puts(IO.ANSI.red() <> "❌ GraphQL errors:" <> IO.ANSI.reset())
        errors |> Enum.each(fn err -> IO.puts("  #{inspect(err)}") end)

      _ ->
        IO.puts(IO.ANSI.red() <> "❌ Unexpected response structure" <> IO.ANSI.reset())
        IO.puts(inspect(response, pretty: true))
    end
  end

  defp analyze_aliased_response(response, region_name) do
    case response do
      %{"data" => data} when is_map(data) ->
        # Check if we got all three aliased fields
        has_today = Map.has_key?(data, "today")
        has_tomorrow = Map.has_key?(data, "tomorrow")
        has_week_out = Map.has_key?(data, "week_out")

        if has_today and has_tomorrow and has_week_out do
          IO.puts(IO.ANSI.green() <> IO.ANSI.bright() <> "✅ SUCCESS! API supports query aliases!" <> IO.ANSI.reset())
          IO.puts("Region: #{region_name}\n")

          # Analyze each date's results
          %{
            "today" => today_data,
            "tomorrow" => tomorrow_data,
            "week_out" => week_data
          } = data

          analyze_date_results("Today", today_data)
          analyze_date_results("Tomorrow", tomorrow_data)
          analyze_date_results("Week out", week_data)

          # Summary
          today_count = get_restaurant_count(today_data)
          tomorrow_count = get_restaurant_count(tomorrow_data)
          week_count = get_restaurant_count(week_data)
          total_count = today_count + tomorrow_count + week_count

          IO.puts("\n" <> IO.ANSI.cyan() <> "Summary:" <> IO.ANSI.reset())
          IO.puts("Total restaurants across all dates: #{total_count}")
          IO.puts("  - Today: #{today_count}")
          IO.puts("  - Tomorrow: #{tomorrow_count}")
          IO.puts("  - Week out: #{week_count}")

          IO.puts("\n" <> IO.ANSI.green() <> "🎉 Recommendation: Implement Option C (Query Aliases)" <> IO.ANSI.reset())
          IO.puts("This approach provides better coverage with NO increase in API calls!")

        else
          IO.puts(IO.ANSI.red() <> "❌ API does not support all aliases" <> IO.ANSI.reset())
          IO.puts("Present fields: #{inspect(Map.keys(data))}")
          IO.puts("\n" <> IO.ANSI.yellow() <> "⚠️  Recommendation: Implement Option A (Sequential queries)" <> IO.ANSI.reset())
        end

      %{"errors" => errors} ->
        IO.puts(IO.ANSI.red() <> "❌ GraphQL errors - API likely doesn't support aliases:" <> IO.ANSI.reset())
        errors |> Enum.each(fn err ->
          IO.puts("  #{inspect(err, pretty: true)}")
        end)
        IO.puts("\n" <> IO.ANSI.yellow() <> "⚠️  Recommendation: Implement Option A (Sequential queries)" <> IO.ANSI.reset())

      _ ->
        IO.puts(IO.ANSI.red() <> "❌ Unexpected response structure" <> IO.ANSI.reset())
        IO.puts(inspect(response, pretty: true, limit: :infinity))
    end
  end

  defp analyze_date_results(label, %{"nodes" => restaurants}) when is_list(restaurants) do
    count = length(restaurants)
    IO.puts("#{label}: #{count} restaurants")

    if count > 0 do
      IO.puts("  Sample: #{Enum.at(restaurants, 0)["name"]} (#{Enum.at(restaurants, 0)["slug"]})")
    end
  end

  defp analyze_date_results(label, data) do
    IO.puts("#{label}: Unexpected structure - #{inspect(data)}")
  end

  defp get_restaurant_count(%{"nodes" => restaurants}) when is_list(restaurants), do: length(restaurants)
  defp get_restaurant_count(_), do: 0
end

# Run the tests
WeekPlAliasTest.run()
