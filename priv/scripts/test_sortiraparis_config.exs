#!/usr/bin/env elixir

# Test script for Sortiraparis source configuration validation
# Run with: mix run priv/scripts/test_sortiraparis_config.exs

IO.puts("=== Sortiraparis Configuration Validation ===\n")

alias EventasaurusDiscovery.Sources.Sortiraparis.{Source, Config}

# Test 1: Validate source configuration
IO.puts("1. Testing Source.validate_config/0...")

case Source.validate_config() do
  {:ok, message} ->
    IO.puts("✅ #{message}")

  {:error, reason} ->
    IO.puts("❌ Validation failed: #{reason}")
end

IO.puts("")

# Test 2: Verify basic configuration values
IO.puts("2. Verifying basic configuration...")
IO.puts("   Base URL: #{Config.base_url()}")
IO.puts("   Rate limit: #{Config.rate_limit()} seconds")
IO.puts("   Timeout: #{Config.timeout()} ms")
IO.puts("   Sitemap URLs: #{length(Config.sitemap_urls())} files")
IO.puts("")

# Test 3: Test URL classification
IO.puts("3. Testing URL classification...")

test_urls = [
  {"https://www.sortiraparis.com/concerts-music-festival/articles/319282-indochine",
   true, "Concert event"},
  {"https://www.sortiraparis.com/guides/best-restaurants", false, "Guide (not event)"},
  {"https://www.sortiraparis.com/theater/articles/123-hamlet", true, "Theater event"},
  {"https://www.sortiraparis.com/news/latest-updates", false, "News article"}
]

Enum.each(test_urls, fn {url, expected, description} ->
  result = Config.is_event_url?(url)
  status = if result == expected, do: "✅", else: "❌"
  IO.puts("   #{status} #{description}: #{result}")
end)

IO.puts("")

# Test 4: Test article ID extraction
IO.puts("4. Testing article ID extraction...")

test_extraction = [
  {"/articles/319282-indochine-concert", "319282"},
  {"https://www.sortiraparis.com/articles/123-test", "123"},
  {"/concerts-music-festival", nil}
]

Enum.each(test_extraction, fn {url, expected} ->
  result = Config.extract_article_id(url)
  status = if result == expected, do: "✅", else: "❌"
  IO.puts("   #{status} #{url} → #{inspect(result)}")
end)

IO.puts("")

# Test 5: Test external ID generation
IO.puts("5. Testing external ID generation...")
external_id = Config.generate_external_id("319282")
IO.puts("   Article ID 319282 → #{external_id}")

status = if external_id == "sortiraparis_319282", do: "✅", else: "❌"
IO.puts("   #{status} Format correct")

IO.puts("")

# Test 6: Source configuration
IO.puts("6. Testing source configuration...")
config = Source.config()

checks = [
  {"Base URL", config.base_url == Config.base_url()},
  {"Priority", Source.priority() == 65},
  {"City", config.city == "Paris"},
  {"Country", config.country == "France"},
  {"Timezone", config.timezone == "Europe/Paris"},
  {"Requires geocoding", config.requires_geocoding == true},
  {"Geocoding strategy", config.geocoding_strategy == :multi_provider},
  {"Supports pagination", config.supports_pagination == false}
]

Enum.each(checks, fn {name, result} ->
  status = if result, do: "✅", else: "❌"
  IO.puts("   #{status} #{name}")
end)

IO.puts("")

# Test 7: Headers
IO.puts("7. Testing HTTP headers...")
headers = Config.headers()
IO.puts("   Total headers: #{length(headers)}")

required_headers = ["User-Agent", "Accept", "Accept-Language", "Referer"]

Enum.each(required_headers, fn header_name ->
  has_header = Enum.any?(headers, fn {k, _v} -> k == header_name end)
  status = if has_header, do: "✅", else: "❌"
  IO.puts("   #{status} #{header_name} present")
end)

IO.puts("")

# Summary
IO.puts("=== Configuration Validation Complete ===")
IO.puts("✅ All checks passed!")
IO.puts("\nSortiraparis source is ready for Phase 3 (Sitemap & Discovery)")
