# Test script for cinema geocoding
# Run with: mix run scripts/test_cinema_geocoding.exs

alias EventasaurusDiscovery.Sources.KinoKrakow.Extractors.CinemaExtractor
alias EventasaurusWeb.Services.GooglePlaces.VenueGeocoder

IO.puts("\n🎬 Testing Cinema Geocoding Implementation\n")
IO.puts(String.duplicate("=", 60))

# Test 1: CinemaExtractor returns correct format
IO.puts("\n1️⃣ Testing CinemaExtractor.extract/2...")
cinema_data = CinemaExtractor.extract("", "kino-pod-baranami")

IO.puts("✅ CinemaExtractor output:")
IO.inspect(cinema_data, label: "Cinema Data")

# Verify expected fields
if cinema_data.name && cinema_data.city == "Kraków" && cinema_data.country == "Poland" do
  IO.puts("✅ All required fields present")
else
  IO.puts("❌ Missing required fields")
  System.halt(1)
end

# Test 2: VenueGeocoder can geocode the cinema
IO.puts("\n2️⃣ Testing VenueGeocoder.geocode_venue/1...")

geocoding_data = %{
  name: cinema_data.name,
  city_name: cinema_data.city,
  country_name: cinema_data.country
}

case VenueGeocoder.geocode_venue(geocoding_data) do
  {:ok, %{latitude: lat, longitude: lng} = result} ->
    IO.puts("✅ Successfully geocoded cinema!")
    IO.puts("   Name: #{cinema_data.name}")
    IO.puts("   Coordinates: #{lat}, #{lng}")
    IO.inspect(result, label: "Full Geocoding Result")

  {:error, reason} ->
    IO.puts("❌ Geocoding failed: #{inspect(reason)}")
    IO.puts("\nNote: This might fail if Google Maps API key is not configured")
    IO.puts("Check GOOGLE_MAPS_API_KEY environment variable")
end

# Test 3: Test multiple cinema names
IO.puts("\n3️⃣ Testing multiple cinema slug formats...")

test_slugs = [
  "kino-pod-baranami",
  "cinema-city-bonarka",
  "kino-kika",
  "multikino"
]

Enum.each(test_slugs, fn slug ->
  cinema = CinemaExtractor.extract("", slug)
  IO.puts("   #{slug} → #{cinema.name}")
end)

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("✨ Cinema geocoding test complete!\n")
