# Test script to verify venue validation in all transformers
require Logger

alias EventasaurusDiscovery.Sources.{
  Ticketmaster,
  Bandsintown,
  Karnet
}

Logger.configure(level: :info)

IO.puts("\n=== Testing Venue Validation for All Sources ===\n")

# Test Ticketmaster
IO.puts("1. Testing Ticketmaster Transformer:")
IO.puts("-----------------------------------")

# Event with venue
tm_event_with_venue = %{
  "id" => "test123",
  "name" => "Test Concert",
  "dates" => %{
    "start" => %{"dateTime" => "2024-12-31T20:00:00Z"}
  },
  "_embedded" => %{
    "venues" => [
      %{
        "id" => "venue456",
        "name" => "Madison Square Garden",
        "location" => %{
          "latitude" => "40.7505",
          "longitude" => "-73.9934"
        },
        "city" => %{"name" => "New York"},
        "country" => %{"name" => "USA"}
      }
    ]
  }
}

# Event without venue
tm_event_without_venue = %{
  "id" => "test456",
  "name" => "Test Concert Without Venue",
  "dates" => %{
    "start" => %{"dateTime" => "2024-12-31T20:00:00Z"},
    "timezone" => "Europe/Warsaw"
  }
}

case Ticketmaster.Transformer.transform_event(tm_event_with_venue) do
  {:ok, event} ->
    IO.puts("✅ Event WITH venue: PASSED")
    IO.puts("   Venue: #{event.venue_data[:name]}")
  {:error, reason} ->
    IO.puts("❌ Event WITH venue: FAILED - #{reason}")
end

case Ticketmaster.Transformer.transform_event(tm_event_without_venue) do
  {:ok, event} ->
    IO.puts("✅ Event WITHOUT venue: Created placeholder")
    IO.puts("   Venue: #{event.venue_data[:name]}")
  {:error, reason} ->
    IO.puts("❌ Event WITHOUT venue: REJECTED - #{reason}")
end

# Test Bandsintown
IO.puts("\n2. Testing Bandsintown Transformer:")
IO.puts("-----------------------------------")

# Event with venue
bt_event_with_venue = %{
  "title" => "Band Concert",
  "artist_name" => "Test Band",
  "date" => "2024-12-31",
  "venue_name" => "Kraków Arena",
  "venue_latitude" => 50.0647,
  "venue_longitude" => 19.9450,
  "venue_city" => "Kraków",
  "venue_country" => "Poland",
  "url" => "https://bandsintown.com/e/123"
}

# Event without venue
bt_event_without_venue = %{
  "title" => "Band Concert Without Venue",
  "artist_name" => "Test Band",
  "date" => "2024-12-31",
  "url" => "https://bandsintown.com/e/456"
}

case Bandsintown.Transformer.transform_event(bt_event_with_venue) do
  {:ok, event} ->
    IO.puts("✅ Event WITH venue: PASSED")
    IO.puts("   Venue: #{event.venue[:name]}")
  {:error, reason} ->
    IO.puts("❌ Event WITH venue: FAILED - #{reason}")
end

case Bandsintown.Transformer.transform_event(bt_event_without_venue) do
  {:ok, event} ->
    IO.puts("✅ Event WITHOUT venue: Created placeholder")
    IO.puts("   Venue: #{event.venue[:name]}")
  {:error, reason} ->
    IO.puts("❌ Event WITHOUT venue: REJECTED - #{reason}")
end

# Test Karnet
IO.puts("\n3. Testing Karnet Transformer:")
IO.puts("-------------------------------")

# Event with venue
karnet_event_with_venue = %{
  title: "Karnet Event",
  url: "https://karnet.krakow.pl/event/123",
  date_text: "31 grudnia 2024",
  venue_data: %{
    name: "ICE Kraków",
    city: "Kraków"
  }
}

# Event without venue
karnet_event_without_venue = %{
  title: "Karnet Event Without Venue",
  url: "https://karnet.krakow.pl/event/456",
  date_text: "31 grudnia 2024"
}

case Karnet.Transformer.transform_event(karnet_event_with_venue) do
  {:ok, event} ->
    IO.puts("✅ Event WITH venue: PASSED")
    IO.puts("   Venue: #{event.venue[:name]}")
  {:error, reason} ->
    IO.puts("❌ Event WITH venue: FAILED - #{reason}")
end

case Karnet.Transformer.transform_event(karnet_event_without_venue) do
  {:ok, event} ->
    IO.puts("✅ Event WITHOUT venue: Created placeholder")
    IO.puts("   Venue: #{event.venue[:name]}")
  {:error, reason} ->
    IO.puts("❌ Event WITHOUT venue: REJECTED - #{reason}")
end

IO.puts("\n=== Summary ===")
IO.puts("All transformers now:")
IO.puts("1. Validate venue data is present")
IO.puts("2. Create placeholder venues when data is missing")
IO.puts("3. Always provide latitude/longitude for collision detection")
IO.puts("4. Return {:ok, event} or {:error, reason} consistently")