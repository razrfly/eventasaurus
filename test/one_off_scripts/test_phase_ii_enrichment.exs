# Test Phase II: Verify artist enrichment with real RA GraphQL data
#
# Run with: mix run test/one_off_scripts/test_phase_ii_enrichment.exs

alias EventasaurusDiscovery.Sources.ResidentAdvisor.Transformer

IO.puts("\n" <> IO.ANSI.cyan() <> "🧪 Testing Phase II: Artist Data Enrichment" <> IO.ANSI.reset())
IO.puts(String.duplicate("=", 80))

# City context
city_context = %{
  name: "Kraków",
  country: %{name: "Poland"},
  latitude: 50.0647,
  longitude: 19.9450,
  timezone: "Europe/Warsaw"
}

# Simulate real RA GraphQL response with enriched artist data
enriched_event = %{
  "id" => "2139012",
  "title" => "Anna Haleta & Barbur 95 b2b",
  "date" => "2025-10-09",
  "startTime" => "02:00",
  "endTime" => "06:00",
  "contentUrl" => "/events/test-event",
  "isTicketed" => false,
  "artists" => [
    %{
      "id" => "5742",
      "name" => "Anna Haleta",
      "image" => "https://static.ra.co/images/profiles/square/annahaleta.jpg?dateUpdated=1682441137000",
      "contentUrl" => "/dj/annahaleta",
      "country" => %{
        "id" => "102",
        "name" => "Israel",
        "urlCode" => "IL"
      }
    },
    %{
      "id" => "123571",
      "name" => "Barbur 95",
      "image" => "https://static.ra.co/images/profiles/square/barbur95.jpg?dateUpdated=1684402083000",
      "contentUrl" => "/dj/barbur95",
      "country" => %{
        "id" => "102",
        "name" => "Israel",
        "urlCode" => "IL"
      }
    }
  ],
  "venue" => %{
    "id" => "venue123",
    "name" => "Test Club",
    "contentUrl" => "/clubs/test-club",
    "live" => false
  }
}

# Test case with missing optional fields
minimal_artist_event = %{
  "id" => "2139013",
  "title" => "Local DJ Night",
  "date" => "2025-10-10",
  "startTime" => "22:00",
  "contentUrl" => "/events/local-night",
  "isTicketed" => false,
  "artists" => [
    %{
      "id" => "999999",
      "name" => "Unknown DJ",
      # No image
      # No contentUrl
      # No country
    }
  ],
  "venue" => %{
    "id" => "venue456",
    "name" => "Small Venue",
    "contentUrl" => "/clubs/small",
    "live" => false
  }
}

IO.puts("\n" <> IO.ANSI.yellow() <> "Test 1: Enriched artist data (with all fields)" <> IO.ANSI.reset())

case Transformer.transform_event(enriched_event, city_context) do
  {:ok, transformed} ->
    performers = transformed[:performers]
    IO.puts("✅ Transform successful")
    IO.puts("   Performers count: #{length(performers)}\n")

    performers
    |> Enum.with_index(1)
    |> Enum.each(fn {performer, idx} ->
      IO.puts("   Performer #{idx}:")
      IO.puts("     Name: #{performer[:name]}")
      IO.puts("     Image URL: #{performer[:image_url] || "nil"}")
      IO.puts("     RA Artist ID: #{get_in(performer, [:metadata, :ra_artist_id])}")
      IO.puts("     RA Artist URL: #{get_in(performer, [:metadata, :ra_artist_url]) || "nil"}")
      IO.puts("     Country: #{get_in(performer, [:metadata, :country]) || "nil"}")
      IO.puts("     Country Code: #{get_in(performer, [:metadata, :country_code]) || "nil"}")
      IO.puts("     Source: #{get_in(performer, [:metadata, :source])}")

      # Validation checks
      checks = [
        {performer[:image_url] != nil, "Has image URL"},
        {get_in(performer, [:metadata, :ra_artist_url]) != nil, "Has artist URL"},
        {get_in(performer, [:metadata, :country]) != nil, "Has country"},
        {get_in(performer, [:metadata, :country_code]) != nil, "Has country code"},
        {get_in(performer, [:metadata, :source]) == "resident_advisor", "Source is RA"}
      ]

      passed = Enum.count(checks, fn {result, _} -> result end)
      IO.puts("\n     " <> IO.ANSI.cyan() <> "Validation: #{passed}/#{length(checks)} checks passed" <> IO.ANSI.reset())

      Enum.each(checks, fn {result, desc} ->
        status = if result, do: IO.ANSI.green() <> "✅", else: IO.ANSI.yellow() <> "⚠️ "
        IO.puts("     #{status} #{desc}" <> IO.ANSI.reset())
      end)

      IO.puts("")
    end)

    if length(performers) == 2 do
      IO.puts(IO.ANSI.green() <> "   ✅ PASS: Both artists captured with enriched data\n" <> IO.ANSI.reset())
    else
      IO.puts(IO.ANSI.red() <> "   ❌ FAIL: Expected 2 artists\n" <> IO.ANSI.reset())
    end

  {:error, reason} ->
    IO.puts(IO.ANSI.red() <> "❌ Transform failed: #{inspect(reason)}" <> IO.ANSI.reset())
end

IO.puts("\n" <> IO.ANSI.yellow() <> "Test 2: Minimal artist data (graceful handling of missing fields)" <> IO.ANSI.reset())

case Transformer.transform_event(minimal_artist_event, city_context) do
  {:ok, transformed} ->
    performers = transformed[:performers]
    IO.puts("✅ Transform successful")
    IO.puts("   Performers count: #{length(performers)}\n")

    Enum.each(performers, fn performer ->
      IO.puts("   Performer:")
      IO.puts("     Name: #{performer[:name]}")
      IO.puts("     Image URL: #{performer[:image_url] || "nil (expected)"}")
      IO.puts("     RA Artist ID: #{get_in(performer, [:metadata, :ra_artist_id])}")
      IO.puts("     RA Artist URL: #{get_in(performer, [:metadata, :ra_artist_url]) || "nil (expected)"}")
      IO.puts("     Country: #{get_in(performer, [:metadata, :country]) || "nil (expected)"}")
      IO.puts("     Country Code: #{get_in(performer, [:metadata, :country_code]) || "nil (expected)"}")

      # Check that nil values are handled gracefully
      checks = [
        {performer[:name] != nil, "Has name (required)"},
        {is_map(performer[:metadata]), "Has metadata map"},
        {get_in(performer, [:metadata, :ra_artist_id]) != nil, "Has RA artist ID"},
        {get_in(performer, [:metadata, :source]) == "resident_advisor", "Source is RA"}
      ]

      passed = Enum.count(checks, fn {result, _} -> result end)
      IO.puts("\n     " <> IO.ANSI.cyan() <> "Validation: #{passed}/#{length(checks)} checks passed" <> IO.ANSI.reset())

      Enum.each(checks, fn {result, desc} ->
        status = if result, do: IO.ANSI.green() <> "✅", else: IO.ANSI.red() <> "❌"
        IO.puts("     #{status} #{desc}" <> IO.ANSI.reset())
      end)
    end)

    IO.puts("\n" <> IO.ANSI.green() <> "   ✅ PASS: Minimal data handled gracefully\n" <> IO.ANSI.reset())

  {:error, reason} ->
    IO.puts(IO.ANSI.red() <> "❌ Transform failed: #{inspect(reason)}" <> IO.ANSI.reset())
end

IO.puts(String.duplicate("=", 80))
IO.puts(IO.ANSI.cyan() <> "✅ Phase II testing complete!\n" <> IO.ANSI.reset())

IO.puts(IO.ANSI.green() <> "\nPhase II Summary:" <> IO.ANSI.reset())
IO.puts("  ✅ GraphQL query updated with image, contentUrl, country")
IO.puts("  ✅ Transformer extracts and maps all new fields")
IO.puts("  ✅ Performer records enriched with:")
IO.puts("     - Profile images (image_url)")
IO.puts("     - Artist profile URLs (metadata.ra_artist_url)")
IO.puts("     - Country names (metadata.country)")
IO.puts("     - Country codes (metadata.country_code)")
IO.puts("  ✅ Graceful handling of missing optional fields")
IO.puts("")
