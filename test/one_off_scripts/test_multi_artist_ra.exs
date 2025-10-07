# Test script to verify Resident Advisor multi-artist handling
#
# Run with: mix run test/one_off_scripts/test_multi_artist_ra.exs

alias EventasaurusDiscovery.Sources.ResidentAdvisor.Transformer

# Mock city context (matches the structure from RA client)
city_context = %{
  name: "Kraków",
  country: %{name: "Poland"},
  latitude: 50.0647,
  longitude: 19.9450,
  timezone: "Europe/Warsaw"
}

# Test case 1: Event with multiple artists (back-to-back set)
multi_artist_event = %{
  "id" => "12345",
  "title" => "Carl Cox b2b Adam Beyer",
  "date" => "2025-01-15",
  "startTime" => "23:00",
  "endTime" => "06:00",
  "contentUrl" => "/events/test-event",
  "isTicketed" => true,
  "artists" => [
    %{"id" => "carlcox", "name" => "Carl Cox"},
    %{"id" => "adambeyer", "name" => "Adam Beyer"}
  ],
  "venue" => %{
    "id" => "venue123",
    "name" => "Test Club",
    "contentUrl" => "/clubs/test-club",
    "live" => false
  }
}

# Test case 2: Event with single artist
single_artist_event = %{
  "id" => "67890",
  "title" => "Nina Kraviz",
  "date" => "2025-01-20",
  "startTime" => "22:00",
  "contentUrl" => "/events/nina-event",
  "isTicketed" => true,
  "artists" => [
    %{"id" => "ninakraviz", "name" => "Nina Kraviz"}
  ],
  "venue" => %{
    "id" => "venue456",
    "name" => "Another Club",
    "contentUrl" => "/clubs/another-club",
    "live" => false
  }
}

# Test case 3: Event with no artists
no_artist_event = %{
  "id" => "11111",
  "title" => "Open Decks Night",
  "date" => "2025-01-25",
  "startTime" => "20:00",
  "contentUrl" => "/events/open-decks",
  "isTicketed" => false,
  "artists" => [],
  "venue" => %{
    "id" => "venue789",
    "name" => "Community Space",
    "contentUrl" => "/clubs/community",
    "live" => false
  }
}

IO.puts("\n" <> IO.ANSI.cyan() <> "🧪 Testing Multi-Artist Handling" <> IO.ANSI.reset())
IO.puts(String.duplicate("=", 80))

# Test 1: Multi-artist event
IO.puts("\n" <> IO.ANSI.yellow() <> "Test 1: Multi-artist event (Carl Cox b2b Adam Beyer)" <> IO.ANSI.reset())
case Transformer.transform_event(multi_artist_event, city_context) do
  {:ok, transformed} ->
    performers = transformed[:performers] || transformed["performers"]
    IO.puts("✅ Transform successful")
    IO.puts("   Performers count: #{length(performers)}")

    Enum.each(performers, fn performer ->
      IO.puts("   - #{performer[:name] || performer["name"]} (RA ID: #{get_in(performer, [:metadata, :ra_artist_id]) || get_in(performer, ["metadata", "ra_artist_id"])})")
    end)

    if length(performers) == 2 do
      IO.puts(IO.ANSI.green() <> "   ✅ PASS: Both artists captured" <> IO.ANSI.reset())
    else
      IO.puts(IO.ANSI.red() <> "   ❌ FAIL: Expected 2 artists, got #{length(performers)}" <> IO.ANSI.reset())
    end

  {:error, reason} ->
    IO.puts(IO.ANSI.red() <> "❌ Transform failed: #{inspect(reason)}" <> IO.ANSI.reset())
end

# Test 2: Single-artist event
IO.puts("\n" <> IO.ANSI.yellow() <> "Test 2: Single-artist event (Nina Kraviz)" <> IO.ANSI.reset())
case Transformer.transform_event(single_artist_event, city_context) do
  {:ok, transformed} ->
    performers = transformed[:performers] || transformed["performers"]
    IO.puts("✅ Transform successful")
    IO.puts("   Performers count: #{length(performers)}")

    Enum.each(performers, fn performer ->
      IO.puts("   - #{performer[:name] || performer["name"]} (RA ID: #{get_in(performer, [:metadata, :ra_artist_id]) || get_in(performer, ["metadata", "ra_artist_id"])})")
    end)

    if length(performers) == 1 do
      IO.puts(IO.ANSI.green() <> "   ✅ PASS: Single artist captured correctly" <> IO.ANSI.reset())
    else
      IO.puts(IO.ANSI.red() <> "   ❌ FAIL: Expected 1 artist, got #{length(performers)}" <> IO.ANSI.reset())
    end

  {:error, reason} ->
    IO.puts(IO.ANSI.red() <> "❌ Transform failed: #{inspect(reason)}" <> IO.ANSI.reset())
end

# Test 3: No artists
IO.puts("\n" <> IO.ANSI.yellow() <> "Test 3: Event with no artists (Open Decks)" <> IO.ANSI.reset())
case Transformer.transform_event(no_artist_event, city_context) do
  {:ok, transformed} ->
    performers = transformed[:performers] || transformed["performers"]
    IO.puts("✅ Transform successful")
    IO.puts("   Performers count: #{length(performers)}")

    if length(performers) == 0 do
      IO.puts(IO.ANSI.green() <> "   ✅ PASS: Empty list returned for no artists" <> IO.ANSI.reset())
    else
      IO.puts(IO.ANSI.red() <> "   ❌ FAIL: Expected 0 artists, got #{length(performers)}" <> IO.ANSI.reset())
    end

  {:error, reason} ->
    IO.puts(IO.ANSI.red() <> "❌ Transform failed: #{inspect(reason)}" <> IO.ANSI.reset())
end

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts(IO.ANSI.cyan() <> "✅ Testing complete!" <> IO.ANSI.reset() <> "\n")
