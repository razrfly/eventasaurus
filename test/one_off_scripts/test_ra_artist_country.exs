# Test country field with subfields
require Logger

area_id = 42
date_from = Date.utc_today() |> Date.to_string()
date_to = Date.utc_today() |> Date.add(7) |> Date.to_string()

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
      event {
        id
        title
        artists {
          id
          name
          image
          contentUrl
          country {
            id
            name
            urlCode
          }
        }
      }
    }
  }
}
"""

variables = %{
  "filters" => %{
    "areas" => %{"eq" => area_id},
    "listingDate" => %{"gte" => date_from, "lte" => date_to}
  },
  "page" => 1,
  "pageSize" => 3
}

body = Jason.encode!(%{
  "query" => query,
  "variables" => variables,
  "operationName" => "GET_EVENT_LISTINGS"
})

headers = [
  {"Content-Type", "application/json"},
  {"User-Agent", "Mozilla/5.0"},
  {"Referer", "https://ra.co/events/pl/krakow"}
]

IO.puts("\n🔬 Testing artist country field with subfields\n")

case HTTPoison.post("https://ra.co/graphql", body, headers, timeout: 10_000) do
  {:ok, %{status_code: 200, body: response_body}} ->
    case Jason.decode(response_body) do
      {:ok, %{"data" => %{"eventListings" => %{"data" => events}}}} ->
        IO.puts("✅ Query succeeded!\n")

        Enum.each(events, fn event_data ->
          event = event_data["event"]
          artists = event["artists"] || []

          IO.puts("Event: #{event["title"]}")
          IO.puts("Artists:")

          Enum.each(artists, fn artist ->
            IO.puts("  - #{artist["name"]}")
            IO.puts("    ID: #{artist["id"]}")
            IO.puts("    Image: #{artist["image"]}")
            IO.puts("    Content URL: #{artist["contentUrl"]}")

            if artist["country"] do
              country = artist["country"]
              IO.puts("    Country: #{country["name"]} (#{country["urlCode"]})")
            else
              IO.puts("    Country: nil")
            end

            IO.puts("")
          end)
        end)

      {:ok, %{"errors" => errors}} ->
        IO.puts("❌ GraphQL Errors:")
        Enum.each(errors, &IO.puts("  #{&1["message"]}"))

      other ->
        IO.puts("❌ Unexpected: #{inspect(other)}")
    end

  {:error, reason} ->
    IO.puts("❌ Request failed: #{inspect(reason)}")
end
