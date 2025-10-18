# Test geocoding for Paris venues

venues = [
  %{name: "Accor Arena", address: "8 Boulevard de Bercy, 75012 Paris 12"},
  %{name: "Jean-Jacques Henner Museum", address: "43, avenue de Villiers, 75017 Paris 17"},
  %{name: "Zénith de Paris - La Villette", address: "211 Avenue Jean Jaurès, 75019 Paris"},
  %{name: "Palais des Festivals", address: "Palais des Festivals, Cannes"},
  %{name: "Ground Control", address: "81 Rue du Charolais, 75012 Paris"}
]

IO.puts("=== Geocoding Test for Paris Venues ===\n")

# Check if Google Maps API key is configured
api_key = System.get_env("GOOGLE_MAPS_API_KEY")

if api_key do
  IO.puts("✓ Google Maps API key found")

  alias EventasaurusWeb.Services.GooglePlaces.Geocoding

  success_count = 0
  total_count = length(venues)

  Enum.reduce(venues, 0, fn venue, acc ->
    IO.puts("\nVenue: #{venue.name}")
    IO.puts("Address: #{venue.address}")

    case Geocoding.search(venue.address) do
      {:ok, [result | _]} ->
        geometry = get_in(result, ["geometry", "location"])
        place_id = Map.get(result, "place_id")
        formatted = Map.get(result, "formatted_address")

        IO.puts("  ✓ Geocoded successfully")
        IO.puts("  - Latitude: #{geometry["lat"]}")
        IO.puts("  - Longitude: #{geometry["lng"]}")
        IO.puts("  - Place ID: #{place_id}")
        IO.puts("  - Formatted: #{formatted}")
        acc + 1

      {:ok, []} ->
        IO.puts("  ✗ No results found")
        acc

      {:error, reason} ->
        IO.puts("  ✗ Geocoding failed: #{inspect(reason)}")
        acc
    end

    # Rate limit
    Process.sleep(200)
  end)
  |> then(fn success_count ->
    IO.puts("\n=== Geocoding Results ===")
    IO.puts("Success rate: #{success_count}/#{total_count} (#{Float.round(success_count / total_count * 100, 1)}%)")
  end)
else
  IO.puts("✗ No Google Maps API key found")
  IO.puts("  Set GOOGLE_MAPS_API_KEY environment variable to test geocoding")
end
