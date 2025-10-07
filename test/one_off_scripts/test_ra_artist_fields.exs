# Test script to discover available artist fields from RA GraphQL
#
# Run with: mix run test/one_off_scripts/test_ra_artist_fields.exs
#
# This script tests various artist fields to see which ones are available
# in RA's GraphQL API for event listings

require Logger

# Test different artist field combinations
test_queries = [
  %{
    name: "Basic fields (current)",
    fields: """
    artists {
      id
      name
    }
    """
  },
  %{
    name: "With image",
    fields: """
    artists {
      id
      name
      image
    }
    """
  },
  %{
    name: "With country",
    fields: """
    artists {
      id
      name
      country
    }
    """
  },
  %{
    name: "With bio",
    fields: """
    artists {
      id
      name
      bio
    }
    """
  },
  %{
    name: "With genres",
    fields: """
    artists {
      id
      name
      genres
    }
    """
  },
  %{
    name: "With contentUrl",
    fields: """
    artists {
      id
      name
      contentUrl
    }
    """
  },
  %{
    name: "With multiple fields",
    fields: """
    artists {
      id
      name
      image
      country
      contentUrl
      bio
    }
    """
  }
]

IO.puts("\n" <> IO.ANSI.cyan() <> "🔬 Testing RA Artist Field Availability" <> IO.ANSI.reset())
IO.puts(String.duplicate("=", 80))

# Known working area ID (Kraków from existing code)
area_id = 42  # Kraków area ID
date_from = Date.utc_today() |> Date.to_string()
date_to = Date.utc_today() |> Date.add(7) |> Date.to_string()

Enum.each(test_queries, fn test ->
  IO.puts("\n" <> IO.ANSI.yellow() <> "Testing: #{test.name}" <> IO.ANSI.reset())

  query = """
  query GET_EVENT_LISTINGS(
    $filters: FilterInputDtoInput,
    $filterOptions: FilterOptionsInputDtoInput,
    $page: Int,
    $pageSize: Int
  ) {
    eventListings(
      filters: $filters,
      filterOptions: $filterOptions,
      pageSize: $pageSize,
      page: $page
    ) {
      data {
        id
        event {
          id
          title
          #{test.fields}
        }
      }
    }
  }
  """

  variables = %{
    "filters" => %{
      "areas" => %{"eq" => area_id},
      "listingDate" => %{
        "gte" => date_from,
        "lte" => date_to
      }
    },
    "filterOptions" => %{"genre" => true},
    "page" => 1,
    "pageSize" => 1  # Only need 1 event to test
  }

  body = Jason.encode!(%{
    "query" => query,
    "variables" => variables,
    "operationName" => "GET_EVENT_LISTINGS"
  })

  headers = [
    {"Content-Type", "application/json"},
    {"User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"},
    {"Referer", "https://ra.co/events/pl/krakow"}
  ]

  case HTTPoison.post("https://ra.co/graphql", body, headers, timeout: 10_000) do
    {:ok, %{status_code: 200, body: response_body}} ->
      case Jason.decode(response_body) do
        {:ok, %{"data" => %{"eventListings" => %{"data" => events}}} = response} ->
          if length(events) > 0 do
            event = List.first(events)
            artists = get_in(event, ["event", "artists"]) || []

            if length(artists) > 0 do
              first_artist = List.first(artists)
              available_fields = Map.keys(first_artist) |> Enum.sort()

              IO.puts(IO.ANSI.green() <> "   ✅ Query succeeded!" <> IO.ANSI.reset())
              IO.puts("   Available fields: #{inspect(available_fields)}")

              # Show sample data
              Enum.each(available_fields, fn field ->
                value = Map.get(first_artist, field)
                display_value = case value do
                  nil -> "nil"
                  v when is_binary(v) and byte_size(v) > 50 -> String.slice(v, 0, 47) <> "..."
                  v -> inspect(v)
                end
                IO.puts("     #{field}: #{display_value}")
              end)
            else
              IO.puts(IO.ANSI.yellow() <> "   ⚠️  No artists in event" <> IO.ANSI.reset())
            end
          else
            IO.puts(IO.ANSI.yellow() <> "   ⚠️  No events found" <> IO.ANSI.reset())
          end

        {:ok, %{"errors" => errors}} ->
          IO.puts(IO.ANSI.red() <> "   ❌ GraphQL Error:" <> IO.ANSI.reset())
          Enum.each(errors, fn error ->
            message = error["message"]
            IO.puts("     #{message}")
          end)

        {:ok, other} ->
          IO.puts(IO.ANSI.red() <> "   ❌ Unexpected response: #{inspect(other)}" <> IO.ANSI.reset())

        {:error, reason} ->
          IO.puts(IO.ANSI.red() <> "   ❌ JSON decode failed: #{inspect(reason)}" <> IO.ANSI.reset())
      end

    {:ok, %{status_code: code, body: body}} ->
      IO.puts(IO.ANSI.red() <> "   ❌ HTTP #{code}: #{String.slice(body, 0, 100)}" <> IO.ANSI.reset())

    {:error, reason} ->
      IO.puts(IO.ANSI.red() <> "   ❌ Request failed: #{inspect(reason)}" <> IO.ANSI.reset())
  end

  # Be nice to RA's servers
  Process.sleep(1000)
end)

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts(IO.ANSI.cyan() <> "✅ Field discovery complete!" <> IO.ANSI.reset() <> "\n")
