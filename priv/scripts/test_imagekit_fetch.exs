#!/usr/bin/env elixir

# Test ImageKit Fetch Functionality
# Run with: mix run test_imagekit_fetch.exs

require Logger

IO.puts("\n=== ImageKit Fetch Test ===\n")

# Test 1: Check configuration
IO.puts("1. Testing ImageKit Configuration...")
alias Eventasaurus.ImageKit.Config

private_key = Config.private_key()
url_endpoint = Config.url_endpoint()

IO.puts("  Private Key: [REDACTED]")
IO.puts("  URL Endpoint: #{url_endpoint}")

# Test 2: Test fetching images for a venue slug
IO.puts("\n2. Testing Image Fetch for Venue...")
alias Eventasaurus.ImageKit.Fetcher

# Use a test venue slug that might exist in production
# If you have uploaded images to /venues/test-venue-slug/ you can test with that
test_slug = "test-venue-slug"

IO.puts("  Fetching images for venue: #{test_slug}")
IO.puts("  API Query: path: \"/venues/#{test_slug}/\"")

case Fetcher.list_venue_images(test_slug) do
  {:ok, images} when is_list(images) and images != [] ->
    IO.puts("\n✅ SUCCESS! Found #{length(images)} images")

    Enum.each(Enum.take(images, 3), fn img ->
      IO.puts("  - URL: #{img["url"]}")
      IO.puts("    Provider: #{img["provider"]}")
      IO.puts("    Size: #{img["width"]}x#{img["height"]}")
      IO.puts("")
    end)

    if length(images) > 3 do
      IO.puts("  ... and #{length(images) - 3} more images")
    end

    IO.puts("\n=== Fetch Test PASSED ===\n")

  {:ok, []} ->
    IO.puts("\n⚠️  No images found for venue: #{test_slug}")
    IO.puts("  This is normal if no images have been uploaded to /venues/#{test_slug}/")
    IO.puts("  Try with a different venue slug that exists in production ImageKit")
    IO.puts("\n=== Fetch Test COMPLETED (No Images) ===\n")

  {:error, reason} ->
    IO.puts("\n❌ FAILED!")
    IO.puts("  Error: #{inspect(reason, pretty: true)}")
    IO.puts("\n=== Fetch Test FAILED ===\n")
end

# Test 3: Test with likely non-existent venue
IO.puts("\n3. Testing with non-existent venue...")
test_slug_2 = "definitely-does-not-exist-#{:rand.uniform(999999)}"
IO.puts("  Testing: #{test_slug_2}")

case Fetcher.list_venue_images(test_slug_2) do
  {:ok, []} ->
    IO.puts("  ✅ Correctly returned empty list for non-existent venue")

  {:ok, images} ->
    IO.puts("  ⚠️  Unexpectedly found #{length(images)} images")

  {:error, reason} ->
    IO.puts("  ⚠️  Got error (acceptable): #{inspect(reason)}")
end

IO.puts("\n=== All Tests Complete ===\n")
