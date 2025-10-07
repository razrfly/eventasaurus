# Test if RA has an artist detail query endpoint
#
# Run with: mix run test/one_off_scripts/test_ra_artist_detail.exs

require Logger

# Known artist IDs from previous tests
test_artist_ids = [
  {"5742", "Anna Haleta"},
  {"123571", "Barbur 95"},
  {"4703", "Soussana"}
]

IO.puts("\n" <> IO.ANSI.cyan() <> "🔬 Testing RA Artist Detail Endpoint" <> IO.ANSI.reset())
IO.puts(String.duplicate("=", 80))

# Test various possible artist detail query patterns
test_queries = [
  %{
    name: "artist(id: ID!)",
    query: fn artist_id ->
      """
      query GET_ARTIST($artistId: ID!) {
        artist(id: $artistId) {
          id
          name
          image
          bio
          country {
            id
            name
            urlCode
          }
          contentUrl
        }
      }
      """
    end,
    variables: fn artist_id -> %{"artistId" => artist_id} end,
    operation: "GET_ARTIST"
  },
  %{
    name: "dj(id: ID!)",
    query: fn artist_id ->
      """
      query GET_DJ($djId: ID!) {
        dj(id: $djId) {
          id
          name
          image
          bio
          country {
            id
            name
            urlCode
          }
          contentUrl
        }
      }
      """
    end,
    variables: fn artist_id -> %{"djId" => artist_id} end,
    operation: "GET_DJ"
  },
  %{
    name: "artistDetail(id: ID!)",
    query: fn artist_id ->
      """
      query GET_ARTIST_DETAIL($artistId: ID!) {
        artistDetail(id: $artistId) {
          id
          name
          image
          bio
          country {
            id
            name
          }
        }
      }
      """
    end,
    variables: fn artist_id -> %{"artistId" => artist_id} end,
    operation: "GET_ARTIST_DETAIL"
  }
]

headers = [
  {"Content-Type", "application/json"},
  {"User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"},
  {"Referer", "https://ra.co/dj/annahaleta"}
]

# Test first artist with each query pattern
{artist_id, artist_name} = List.first(test_artist_ids)

Enum.each(test_queries, fn test ->
  IO.puts("\n" <> IO.ANSI.yellow() <> "Testing: #{test.name}" <> IO.ANSI.reset())
  IO.puts("  Artist: #{artist_name} (ID: #{artist_id})")

  query = test.query.(artist_id)
  variables = test.variables.(artist_id)

  body = Jason.encode!(%{
    "query" => query,
    "variables" => variables,
    "operationName" => test.operation
  })

  case HTTPoison.post("https://ra.co/graphql", body, headers, timeout: 10_000) do
    {:ok, %{status_code: 200, body: response_body}} ->
      case Jason.decode(response_body) do
        {:ok, %{"data" => data} = response} when not is_nil(data) ->
          if response["errors"] do
            IO.puts(IO.ANSI.red() <> "  ❌ GraphQL Errors:" <> IO.ANSI.reset())
            Enum.each(response["errors"], fn error ->
              IO.puts("    #{error["message"]}")
            end)
          else
            IO.puts(IO.ANSI.green() <> "  ✅ Query succeeded!" <> IO.ANSI.reset())
            IO.puts("  Response data: #{inspect(data, pretty: true, limit: :infinity)}")
          end

        {:ok, %{"errors" => errors}} ->
          IO.puts(IO.ANSI.red() <> "  ❌ GraphQL Errors:" <> IO.ANSI.reset())
          Enum.each(errors, fn error ->
            IO.puts("    #{error["message"]}")
          end)

        {:ok, other} ->
          IO.puts(IO.ANSI.red() <> "  ❌ Unexpected response: #{inspect(other)}" <> IO.ANSI.reset())

        {:error, reason} ->
          IO.puts(IO.ANSI.red() <> "  ❌ JSON decode failed: #{inspect(reason)}" <> IO.ANSI.reset())
      end

    {:ok, %{status_code: code, body: body}} ->
      IO.puts(IO.ANSI.red() <> "  ❌ HTTP #{code}: #{String.slice(body, 0, 100)}" <> IO.ANSI.reset())

    {:error, reason} ->
      IO.puts(IO.ANSI.red() <> "  ❌ Request failed: #{inspect(reason)}" <> IO.ANSI.reset())
  end

  Process.sleep(1000)
end)

IO.puts("\n" <> String.duplicate("=", 80))

# If none of the queries work, suggest scraping the artist page
IO.puts("\n" <> IO.ANSI.yellow() <> "Alternative: Artist Page Scraping" <> IO.ANSI.reset())
IO.puts("If no GraphQL endpoint exists, we can scrape artist pages:")
IO.puts("  Example URL: https://ra.co/dj/annahaleta")
IO.puts("  Available data: bio, social links, follower count, upcoming events")
IO.puts("")
