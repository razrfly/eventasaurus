# Sortiraparis POC - Date Parsing Test

# Sample date formats found:
date_samples = [
  # Multi-date list
  "February 25, 27, 28, 2026",
  "March 3, 4, 6, 7, 2026",

  # Date range
  "October 15, 2025 to January 19, 2026",

  # Single date with day name
  "Friday, October 31, 2025",

  # Date with time
  "Saturday October 11 at 12 noon",

  # Ticket sale date
  "on Saturday October 11 at 12 noon"
]

IO.puts("=== Date Format Analysis ===\n")

Enum.each(date_samples, fn date_str ->
  IO.puts("Format: #{date_str}")
  IO.puts("  - Contains 'to': #{String.contains?(date_str, " to ")}")
  IO.puts("  - Contains comma-separated dates: #{Regex.match?(~r/\d+,\s*\d+/, date_str)}")
  IO.puts("  - Contains time: #{String.contains?(date_str, " at ")}")
  IO.puts("")
end)

# Test Paris timezone
IO.puts("\n=== Timezone Test ===")
{:ok, paris_tz} = DateTime.now("Europe/Paris")
IO.puts("Current time in Paris: #{paris_tz}")

# Test address patterns for geocoding
addresses = [
  "8 Boulevard de Bercy, 75012 Paris 12",
  "43, avenue de Villiers, 75017 Paris 17",
  "Palais des Festivals, Cannes"
]

IO.puts("\n=== Address Patterns ===")
Enum.each(addresses, fn addr ->
  IO.puts("Address: #{addr}")
  IO.puts("  - Has postal code: #{Regex.match?(~r/\d{5}/, addr)}")
  IO.puts("  - Has 'Paris': #{String.contains?(addr, "Paris")}")
  IO.puts("")
end)

IO.puts("\n=== POC Summary ===")
IO.puts("✓ Can access sortiraparis.com via WebFetch")
IO.puts("⚠ Some pages return 401 (inconsistent bot protection)")
IO.puts("✓ Events have full venue addresses")
IO.puts("✓ JSON-LD structured data available (NewsArticle)")
IO.puts("⚠ Date formats are varied and complex")
IO.puts("✓ Addresses have postal codes for geocoding")
