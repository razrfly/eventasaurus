#!/usr/bin/env elixir

# Test ImageKit Upload Functionality
# Run with: mix run test_imagekit_upload.exs

require Logger

IO.puts("\n=== ImageKit Upload Test ===\n")

# Test 1: Check configuration
IO.puts("1. Testing ImageKit Configuration...")
alias Eventasaurus.ImageKit.Config

private_key = Config.private_key()
public_key = Config.public_key()
upload_endpoint = Config.upload_endpoint()
url_endpoint = Config.url_endpoint()

IO.puts("  Private Key: #{String.slice(private_key, 0..20)}...")
IO.puts("  Public Key: #{String.slice(public_key, 0..20)}...")
IO.puts("  Upload Endpoint: #{upload_endpoint}")
IO.puts("  URL Endpoint: #{url_endpoint}")

# Test 2: Test filename generation
IO.puts("\n2. Testing Filename Generation...")
alias Eventasaurus.ImageKit.Filename

test_url = "https://maps.googleapis.com/maps/api/place/photo?maxwidth=3000&photo_reference=ABC123"
provider = "google_places"

filename = Filename.generate(test_url, provider)
folder = Filename.build_folder_path("test-venue-slug")
full_path = Filename.build_full_path("test-venue-slug", filename)

IO.puts("  Provider: #{provider}")
IO.puts("  Provider Code: #{Filename.get_provider_code(provider)}")
IO.puts("  Hash: #{Filename.generate_hash(test_url)}")
IO.puts("  Generated Filename: #{filename}")
IO.puts("  Folder: #{folder}")
IO.puts("  Full Path: #{full_path}")

# Test 3: Test actual upload with real Google Places URL from database
IO.puts("\n3. Testing Actual Upload...")
alias Eventasaurus.ImageKit.Uploader

# Use a real URL from venue 207
real_url = "https://maps.googleapis.com/maps/api/place/photo?maxwidth=3000&photo_reference=AWn5SU7A75mZA4SAjsoqWVwUro8VOO5YifFh0Bh72IuXpWnrMl-DCC0b4_dcpyK3vKEHIT1Fq-NOm-Lbk-D_BkJRv2n-D80_rDypuwUv4tbUZIh5YyyOxJ7q7gm1PF3ZZVG81gYg8kfCWRoEkSzUUc1YfVqUcMQl_G1ZcqftvuXnYhburGTelm9IKDwS0KWEBD0ZRivPxcUhRis8JvaFxw02zshhzh0Q_V_feRJL3tX9pVsB3V1rwNGuKIdSe_-J7PScM3KBoua67JsLWpidJuwjiynda7ESFzniPSkigHrqu9rK_Nevx79seJ6j_VVcQpf7BXISfAlIU4iU00ooj45023p8qCutTIzKcTJ3IQ-kvOciPVuSzZkj3n87ZKjQRrrBcCVUCHTmPPgGrWsKMr-gIBuR7jAXShesK3K0L4fKHt4&key=AIzaSyBoPANJz0w_AFxX_Lw3O08g6OSXJrif5uI"

test_filename = Filename.generate(real_url, "google_places")
test_folder = "/test"

IO.puts("  Uploading to: #{test_folder}/#{test_filename}")
IO.puts("  From URL: #{String.slice(real_url, 0..80)}...")

case Uploader.upload_from_url(real_url,
       folder: test_folder,
       filename: test_filename,
       tags: ["test", "google_places"]
     ) do
  {:ok, imagekit_url} ->
    IO.puts("\n✅ SUCCESS!")
    IO.puts("  ImageKit URL: #{imagekit_url}")
    IO.puts("\n=== Upload Test PASSED ===\n")

  {:error, reason} ->
    IO.puts("\n❌ FAILED!")
    IO.puts("  Error: #{inspect(reason, pretty: true)}")
    IO.puts("\n=== Upload Test FAILED ===\n")
end
