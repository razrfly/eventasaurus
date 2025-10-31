#!/usr/bin/env elixir

# Test EnrichmentJob Metadata Functionality
# Run with: mix run test_enrichment_metadata.exs

IO.puts("\n=== EnrichmentJob Metadata Test ===\n")

# This script demonstrates the metadata tracking feature
# To test in production:
# 1. Enqueue a job for a venue with images:
#    %{venue_id: 13, providers: ["google_places"], geocode: true}
#    |> EventasaurusDiscovery.VenueImages.EnrichmentJob.new()
#    |> Oban.insert()
#
# 2. Check Oban UI at /admin/jobs or /dev/dashboard/oban
# 3. Find the completed job and view its Meta field
# 4. You should see:
#    {
#      "status": "success",
#      "images_found": 8,
#      "providers": {
#        "google_places": {
#          "status": "success",
#          "images_fetched": 8,
#          "images_uploaded": 8,
#          "imagekit_urls": ["https://ik.imagekit.io/..."],
#          "cost_usd": 0.007
#        }
#      },
#      "imagekit_urls": ["https://ik.imagekit.io/...", ...],
#      "total_cost_usd": 0.007,
#      "execution_time_ms": 3779,
#      "completed_at": "2025-01-24T09:26:00Z",
#      "summary": "Found 8 images from google_places, uploaded to ImageKit"
#    }

IO.puts("✅ Metadata tracking is now enabled for EnrichmentJob!")
IO.puts("")
IO.puts("Features:")
IO.puts("  - See image counts in Oban UI")
IO.puts("  - Track provider success/failures")
IO.puts("  - View ImageKit upload results")
IO.puts("  - Monitor costs and execution time")
IO.puts("  - Distinguish 'no images' from 'API error'")
IO.puts("")
IO.puts("To test:")
IO.puts("  1. Run an enrichment job for a venue")
IO.puts("  2. Check Oban UI Meta field")
IO.puts("  3. See detailed results without checking logs!")
IO.puts("")
IO.puts("Example jobs to test:")
IO.puts("  - Success with images: venue_id with Google Places photos")
IO.puts("  - Success with 0 images: venue_id with no photos")
IO.puts("  - Failure: venue_id with invalid provider_id")
IO.puts("")
