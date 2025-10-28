# Phase 2: ImageKit Migration - Comprehensive Specification

## Executive Summary

Phase 2 migrates venue images from Tigris S3 to ImageKit CDN with a dual-mode architecture:
- **Local Dev**: Populate Tigris URLs for UI testing (no ImageKit upload)
- **Production**: Upload to ImageKit with country-based phased rollout

**Status**: ✅ Approach validated and feasible
**Database Schema**: ✅ Full support for country/city filtering
**Rollback**: ✅ Per-country rollback capability

---

## Current State Analysis

### Local Development Database
- Phase 1 migration data not persisted (database reset between sessions)
- Only 10 venues have images (Google Places source, not trivia_advisor)
- Zero Tigris CDN URLs currently in database
- Venues table: 973 total venues in local dev

### Database Schema (Country Support)
```
venues.city_id → cities.id
cities.country_id → countries.id
countries.name / countries.code / countries.slug
```

**Query Pattern**:
```sql
SELECT v.*, c.name as city, co.name as country
FROM venues v
JOIN cities c ON v.city_id = c.id
JOIN countries co ON c.country_id = co.id
WHERE co.name = 'United Kingdom'
```

✅ **Country/city filtering fully supported** via JOIN queries

### Production Venue Distribution (Estimated from Phase 0)
- **Total**: 575 venues, ~2,838 images
- **United Kingdom**: ~412 venues (71.6%)
- **Poland**: ~89 venues (15.5%)
- **France**: ~45 venues (7.8%)
- **Germany**: ~29 venues (5.0%)

---

## Phase 2 Architecture: Dual-Mode Design

### Mode 1: Local Development (Default)

**Purpose**: Populate venue_images with Tigris URLs for UI testing

**Behavior**:
1. Connect to production trivia_advisor database (read-only)
2. Read venue images from trivia_advisor
3. Transform to eventasaurus format with Tigris S3 URLs
4. Update local dev database with `upload_status: "external"`
5. **NO ImageKit upload** (zero cost, instant execution)
6. Verify images display in local UI

**Commands**:
```bash
# Default mode - populate local dev with Tigris URLs
mix migration.phase2

# Dry-run mode - preview changes without database update
mix migration.phase2 --dry-run

# Test with small subset
mix migration.phase2 --limit=10

# Verification mode - check URL accessibility
mix migration.phase2 --verify
```

**Benefits**:
- ✅ Test image display without ImageKit costs ($0)
- ✅ Verify frontend handles external URLs correctly
- ✅ Fast iteration (no upload delays, ~1-2 minutes total)
- ✅ Tigris URLs are public and CORS-friendly
- ✅ Safe testing in local environment

**Expected Result**:
```json
{
  "url": "https://cdn.quizadvisor.com/uploads/venue_123.jpg",
  "upload_status": "external",
  "width": 800,
  "height": 600,
  "source": "trivia_advisor_migration",
  "migrated_at": "2025-10-26T16:00:00Z"
}
```

---

### Mode 2: Production with Phased Rollout

**Purpose**: Upload images to ImageKit CDN with country-based control

**Behavior**:
1. Connect to production eventasaurus database
2. Query venues by country with `upload_status: "external"`
3. For each venue:
   - Download images from Tigris S3
   - Upload to ImageKit with optimization
   - Update database with ImageKit URLs
   - Change `upload_status: "external"` → `"completed"`
   - Preserve original Tigris URL as fallback
4. Generate rollback data per country
5. Generate migration report

**Commands**:
```bash
# List country distribution first
mix migration.phase2 --list-countries

# By country (recommended approach)
mix migration.phase2 --production --country="United Kingdom"
mix migration.phase2 --production --country="Poland"
mix migration.phase2 --production --country="France"

# By city (even more granular)
mix migration.phase2 --production --city="London"
mix migration.phase2 --production --city="Kraków"

# Test with small batch first
mix migration.phase2 --production --country="United Kingdom" --limit=10

# Dry-run for production (no uploads, just preview)
mix migration.phase2 --production --country="United Kingdom" --dry-run
```

**Benefits**:
- ✅ Controlled rollout reduces risk (country-by-country)
- ✅ Monitor success rate before proceeding to next country
- ✅ Rollback capability per country
- ✅ Pause/resume if issues detected
- ✅ Detailed error reporting per country
- ✅ Progressive validation

**Expected Result**:
```json
{
  "url": "https://ik.imagekit.io/your_id/venues/white-hart-whitechapel/img_001.jpg",
  "upload_status": "completed",
  "imagekit_file_id": "abc123xyz",
  "width": 800,
  "height": 600,
  "source": "trivia_advisor_migration",
  "migrated_at": "2025-10-26T16:00:00Z",
  "imagekit_uploaded_at": "2025-10-26T16:30:00Z",
  "original_tigris_url": "https://cdn.quizadvisor.com/uploads/venue_123.jpg"
}
```

---

## Implementation Details

### File Structure
```
lib/mix/tasks/
├── migration_phase2.ex              # Main Phase 2 task
├── migration_phase2_rollback.ex     # Rollback task
└── migration_helpers/
    ├── imagekit_client.ex           # ImageKit API client
    ├── country_filter.ex            # Country/city filtering
    └── verification.ex              # URL verification utilities
```

### Core Query Pattern: Country-Based Filtering

```elixir
def load_venues_by_country(conn, country_name, opts \\ []) do
  limit = Keyword.get(opts, :limit)

  query = """
    SELECT
      v.id,
      v.slug,
      v.venue_images,
      c.name as city_name,
      c.slug as city_slug,
      co.name as country_name,
      co.code as country_code
    FROM venues v
    JOIN cities c ON v.city_id = c.id
    JOIN countries co ON c.country_id = co.id
    WHERE v.venue_images IS NOT NULL
      AND jsonb_typeof(v.venue_images) = 'array'
      AND jsonb_array_length(v.venue_images) > 0
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(v.venue_images) img
        WHERE img->>'upload_status' = 'external'
        AND img->>'source' = 'trivia_advisor_migration'
      )
      AND co.name = $1
    ORDER BY v.id
    #{if limit, do: "LIMIT #{limit}", else: ""}
  """

  {:ok, result} = Postgrex.query(conn, query, [country_name])
  parse_venue_results(result)
end
```

### Mode Determination Logic

```elixir
defmodule Mix.Tasks.Migration.Phase2 do
  @moduledoc """
  Phase 2: ImageKit CDN Migration with Dual-Mode Architecture

  LOCAL DEV MODE (default):
    mix migration.phase2                    # Populate Tigris URLs
    mix migration.phase2 --limit=10         # Test with subset
    mix migration.phase2 --verify           # Verify URL accessibility

  PRODUCTION MODE:
    mix migration.phase2 --list-countries   # Show distribution
    mix migration.phase2 --production --country="United Kingdom"
    mix migration.phase2 --production --city="London"

  ROLLBACK:
    mix migration.phase2.rollback --country="United Kingdom"
  """

  use Mix.Task
  require Logger

  @shortdoc "Run Phase 2 image migration (dev or production mode)"

  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args,
      switches: [
        production: :boolean,
        country: :string,
        city: :string,
        limit: :integer,
        dry_run: :boolean,
        verify: :boolean,
        list_countries: :boolean
      ],
      aliases: [
        p: :production,
        l: :limit,
        d: :dry_run
      ]
    )

    mode = determine_mode(opts)

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("TRIVIA ADVISOR → EVENTASAURUS IMAGE MIGRATION")
    IO.puts("Phase 2: #{mode_description(mode)}")
    if Keyword.get(opts, :dry_run), do: IO.puts("DRY RUN MODE - No changes will be committed")
    IO.puts(String.duplicate("=", 80) <> "\n")

    case mode do
      :list_countries -> list_country_distribution()
      :verify -> run_verification_only(opts)
      :local_dev -> run_local_populate(opts)
      :production -> run_production_upload(opts)
    end
  end

  defp determine_mode(opts) do
    cond do
      Keyword.get(opts, :list_countries) -> :list_countries
      Keyword.get(opts, :verify) -> :verify
      Keyword.get(opts, :production) -> :production
      true -> :local_dev  # Default
    end
  end

  defp mode_description(:list_countries), do: "Country Distribution Analysis"
  defp mode_description(:verify), do: "Verification Mode (URL Accessibility Check)"
  defp mode_description(:local_dev), do: "Local Development (Tigris URLs)"
  defp mode_description(:production), do: "Production Upload (ImageKit CDN)"
end
```

### Local Dev Mode Implementation

```elixir
defp run_local_populate(opts) do
  IO.puts("📊 Mode: Local Development")
  IO.puts("Action: Populate with Tigris S3 URLs (no ImageKit upload)")
  IO.puts("Cost: $0 | Speed: Fast (~1-2 minutes)\n")

  # Connect to both databases
  ta_conn = connect_trivia_advisor()
  ea_conn = connect_eventasaurus_dev()

  # Load matched venues from Phase 0 results
  IO.puts("📊 Step 1: Loading Matched Venues")
  IO.puts(String.duplicate("-", 80))

  matches = load_matches("temp/migration_recon/matching_report.csv", opts[:limit])
  IO.puts("✓ Loaded #{length(matches)} matched venues\n")

  # Process each venue
  IO.puts("📊 Step 2: Populating Images (Tigris URLs)")
  IO.puts(String.duplicate("-", 80))

  results = Enum.map(matches, fn match ->
    populate_venue_images_dev(ta_conn, ea_conn, match, opts[:dry_run])
  end)

  # Generate report
  generate_report(results, :local_dev, opts[:dry_run])

  GenServer.stop(ta_conn)
  GenServer.stop(ea_conn)
end

defp populate_venue_images_dev(ta_conn, ea_conn, match, dry_run) do
  IO.puts("\nVenue: #{match.ta_name} → #{match.ea_name}")

  # Fetch from trivia_advisor
  {:ok, ta_result} = Postgrex.query(ta_conn, """
    SELECT google_place_images FROM venues WHERE id = $1
  """, [match.ta_id])

  ta_images = extract_images(ta_result)

  if ta_images != [] && length(ta_images) > 0 do
    IO.puts("  Found #{length(ta_images)} images from trivia_advisor")

    # Get current images
    {:ok, ea_result} = Postgrex.query(ea_conn, """
      SELECT venue_images FROM venues WHERE id = $1
    """, [match.ea_id])

    original_images = extract_images(ea_result)
    IO.puts("  Current eventasaurus images: #{length(original_images)}")

    # Transform to Tigris URLs
    tigris_images = Enum.map(ta_images, &transform_to_tigris_url/1)

    # Merge with existing
    merged_images = merge_images(original_images, tigris_images)
    added_count = max(length(merged_images) - length(original_images), 0)

    IO.puts("  After merge: #{length(merged_images)} total images (+#{added_count} new)")

    if !dry_run do
      update_venue_images(ea_conn, match.ea_id, merged_images)
    else
      IO.puts("  [DRY RUN] Would update with #{added_count} new images")
    end

    %{
      success: true,
      ea_id: match.ea_id,
      images_added: added_count
    }
  else
    IO.puts("  ⚠️  No images found in trivia_advisor")
    %{success: false, ea_id: match.ea_id, images_added: 0}
  end
end

defp transform_to_tigris_url(ta_image) do
  local_path = ta_image["local_path"]
  tigris_url = "https://cdn.quizadvisor.com#{local_path}"

  %{
    "url" => tigris_url,
    "upload_status" => "external",
    "width" => ta_image["width"],
    "height" => ta_image["height"],
    "source" => "trivia_advisor_migration",
    "migrated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
  }
end
```

### Production Mode with ImageKit Upload

```elixir
defp run_production_upload(opts) do
  country = Keyword.get(opts, :country)
  city = Keyword.get(opts, :city)

  unless country or city do
    IO.puts("❌ ERROR: Must specify --country or --city for production mode")
    IO.puts("\nExamples:")
    IO.puts("  mix migration.phase2 --production --country=\"United Kingdom\"")
    IO.puts("  mix migration.phase2 --production --city=\"London\"")
    System.halt(1)
  end

  # Safety confirmation
  confirm_production_migration(country || city, opts)

  # Connect to production database
  ea_conn = connect_eventasaurus_production()

  # Load venues by country/city
  IO.puts("📊 Step 1: Loading Venues")
  IO.puts(String.duplicate("-", 80))

  venues = if country do
    load_venues_by_country(ea_conn, country, opts)
  else
    load_venues_by_city(ea_conn, city, opts)
  end

  total_images = count_external_images(venues)

  IO.puts("✓ Found #{length(venues)} venues in #{country || city}")
  IO.puts("✓ Total images to upload: #{total_images}\n")

  # Process with ImageKit upload
  IO.puts("📊 Step 2: Uploading to ImageKit")
  IO.puts(String.duplicate("-", 80))

  results = Enum.map(venues, fn venue ->
    upload_venue_to_imagekit(ea_conn, venue, opts[:dry_run])
  end)

  # Generate reports
  generate_report(results, :production, country || city, opts[:dry_run])

  if !opts[:dry_run] do
    generate_rollback_data(results, country || city)
  end

  GenServer.stop(ea_conn)
end

defp upload_venue_to_imagekit(conn, venue, dry_run) do
  IO.puts("\nVenue: #{venue.slug} (#{venue.city_name}, #{venue.country_name})")

  external_images = Enum.filter(venue.venue_images, fn img ->
    img["upload_status"] == "external" &&
    img["source"] == "trivia_advisor_migration"
  end)

  IO.puts("  Found #{length(external_images)} external images to upload")

  if dry_run do
    IO.puts("  [DRY RUN] Would upload to ImageKit and update database")
    %{success: true, venue_id: venue.id, images_uploaded: length(external_images)}
  else
    # Upload each image
    updated_images = Enum.map(venue.venue_images, fn img ->
      if img["upload_status"] == "external" && img["source"] == "trivia_advisor_migration" do
        upload_single_image_to_imagekit(venue, img)
      else
        img  # Keep as-is
      end
    end)

    # Update database
    update_venue_images(conn, venue.id, updated_images)

    uploaded_count = Enum.count(updated_images, fn img ->
      img["upload_status"] == "completed"
    end)

    IO.puts("  ✓ Uploaded #{uploaded_count} images to ImageKit")

    %{success: true, venue_id: venue.id, images_uploaded: uploaded_count}
  end
end

defp upload_single_image_to_imagekit(venue, img) do
  try do
    # Download from Tigris
    {:ok, image_binary} = download_image(img["url"])

    # Generate unique filename
    filename = "#{venue.slug}_#{:crypto.hash(:md5, img["url"]) |> Base.encode16(case: :lower)}.jpg"

    # Upload to ImageKit
    case ImageKit.upload(image_binary,
      folder: "/venues/#{venue.slug}",
      fileName: filename,
      useUniqueFileName: false
    ) do
      {:ok, ik_response} ->
        %{
          "url" => ik_response.url,
          "upload_status" => "completed",
          "imagekit_file_id" => ik_response.fileId,
          "width" => img["width"],
          "height" => img["height"],
          "source" => img["source"],
          "migrated_at" => img["migrated_at"],
          "imagekit_uploaded_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "original_tigris_url" => img["url"]
        }

      {:error, reason} ->
        IO.puts("    ✗ Upload failed: #{inspect(reason)}")
        img  # Keep original on failure
    end
  rescue
    e ->
      IO.puts("    ✗ Error: #{inspect(e)}")
      img  # Keep original on error
  end
end
```

---

## Country Distribution Query

```elixir
defp list_country_distribution do
  ea_conn = connect_eventasaurus_production()

  {:ok, result} = Postgrex.query(ea_conn, """
    SELECT
      co.name as country,
      co.code,
      COUNT(DISTINCT v.id) as venue_count,
      COUNT(DISTINCT c.id) as city_count,
      SUM(jsonb_array_length(v.venue_images)) as total_images
    FROM venues v
    JOIN cities c ON v.city_id = c.id
    JOIN countries co ON c.country_id = co.id
    WHERE v.venue_images IS NOT NULL
      AND jsonb_array_length(v.venue_images) > 0
      AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(v.venue_images) img
        WHERE img->>'upload_status' = 'external'
        AND img->>'source' = 'trivia_advisor_migration'
      )
    GROUP BY co.name, co.code
    ORDER BY venue_count DESC
  """, [])

  IO.puts("Country Distribution for Phase 2 Migration:")
  IO.puts(String.duplicate("=", 80))
  IO.puts("")

  total_venues = 0
  total_images = 0

  Enum.each(result.rows, fn [country, code, venues, cities, images] ->
    IO.puts("#{String.pad_trailing(country, 20)} #{String.pad_leading("#{venues}", 4)} venues  " <>
            "#{String.pad_leading("#{images}", 5)} images  " <>
            "#{String.pad_leading("#{cities}", 3)} cities")
    total_venues = total_venues + venues
    total_images = total_images + images
  end)

  IO.puts("")
  IO.puts(String.duplicate("-", 80))
  IO.puts("Total: #{total_venues} venues, #{total_images} images\n")

  GenServer.stop(ea_conn)
end
```

**Example Output**:
```
Country Distribution for Phase 2 Migration:
================================================================================

United Kingdom        412 venues   2060 images   87 cities
Poland                 89 venues    445 images   12 cities
France                 45 venues    225 images    8 cities
Germany                29 venues    145 images    5 cities

--------------------------------------------------------------------------------
Total: 575 venues, 2875 images
```

---

## Rollback Strategy

### Rollback Data Structure

```json
{
  "country": "United Kingdom",
  "migration_timestamp": "2025-10-26T16:00:00Z",
  "total_venues": 412,
  "total_images": 2060,
  "venues": [
    {
      "venue_id": 457,
      "venue_slug": "white-hart-whitechapel",
      "city": "London",
      "images_before_phase2": [
        {
          "url": "https://cdn.quizadvisor.com/uploads/venue_457_1.jpg",
          "upload_status": "external",
          "width": 800,
          "height": 600
        }
      ],
      "images_after_phase2": [
        {
          "url": "https://ik.imagekit.io/your_id/venues/white-hart-whitechapel/img_001.jpg",
          "upload_status": "completed",
          "imagekit_file_id": "abc123",
          "original_tigris_url": "https://cdn.quizadvisor.com/uploads/venue_457_1.jpg"
        }
      ]
    }
  ]
}
```

### Rollback Task

```elixir
defmodule Mix.Tasks.Migration.Phase2.Rollback do
  @moduledoc """
  Rollback Phase 2 migration for a specific country or city

  Usage:
    mix migration.phase2.rollback --country="United Kingdom"
    mix migration.phase2.rollback --city="London"
    mix migration.phase2.rollback --venue-id=457
  """

  use Mix.Task

  def run(args) do
    {opts, _, _} = OptionParser.parse(args,
      switches: [country: :string, city: :string, venue_id: :integer]
    )

    # Load appropriate rollback file
    rollback_data = load_rollback_data(opts)

    # Confirmation
    IO.puts("⚠️  WARNING: Rolling back Phase 2 migration")
    IO.puts("Scope: #{opts[:country] || opts[:city] || "Single venue"}")
    IO.puts("Venues affected: #{length(rollback_data.venues)}")
    IO.puts("\nType 'ROLLBACK' to confirm:")

    response = IO.gets("> ") |> String.trim()

    unless response == "ROLLBACK" do
      IO.puts("❌ Rollback aborted")
      System.halt(0)
    end

    # Execute rollback
    ea_conn = connect_eventasaurus_production()

    results = Enum.map(rollback_data.venues, fn venue_data ->
      rollback_venue(ea_conn, venue_data)
    end)

    # Report
    successful = Enum.count(results, & &1.success)
    IO.puts("\n✓ Rollback complete: #{successful}/#{length(results)} venues restored")

    GenServer.stop(ea_conn)
  end

  defp rollback_venue(conn, venue_data) do
    IO.puts("Rolling back venue #{venue_data.venue_slug}...")

    # Restore images_before_phase2
    case Postgrex.query(conn, """
      UPDATE venues
      SET venue_images = $1,
          updated_at = NOW()
      WHERE id = $2
    """, [venue_data.images_before_phase2, venue_data.venue_id]) do
      {:ok, %{num_rows: 1}} ->
        IO.puts("  ✓ Restored")
        %{success: true, venue_id: venue_data.venue_id}

      {:error, reason} ->
        IO.puts("  ✗ Failed: #{inspect(reason)}")
        %{success: false, venue_id: venue_data.venue_id}
    end
  end
end
```

---

## Production Workflow

### Recommended Approach: Phased Country Rollout

#### Week 1: United Kingdom (Test + Full)

**Day 1-2: Test Batch**
```bash
# Test with 10 venues
mix migration.phase2 --production --country="United Kingdom" --limit=10

# Verify in production UI
# Check ImageKit dashboard
# Monitor error logs
```

**Day 3-5: Full UK Migration**
```bash
# Full migration (~412 venues)
mix migration.phase2 --production --country="United Kingdom"

# Monitor for 48 hours
# Check performance metrics
# Verify image loading speeds
```

#### Week 2: Poland
```bash
# Poland migration (~89 venues)
mix migration.phase2 --production --country="Poland"

# Monitor for 24 hours
```

#### Week 3: Remaining Countries
```bash
# France (~45 venues)
mix migration.phase2 --production --country="France"

# Germany (~29 venues)
mix migration.phase2 --production --country="Germany"
```

### Alternative Approach: City-by-City

For even more granular control:

```bash
# Major cities first
mix migration.phase2 --production --city="London"
mix migration.phase2 --production --city="Manchester"
mix migration.phase2 --production --city="Kraków"
mix migration.phase2 --production --city="Warsaw"
mix migration.phase2 --production --city="Paris"
```

---

## Error Handling

### ImageKit Upload Errors

**Common Errors**:
1. **Rate Limit Exceeded**: Automatic retry with exponential backoff
2. **File Size Too Large**: Skip image, log error, continue
3. **Network Timeout**: Retry up to 3 times, then skip
4. **Invalid Image Format**: Skip, log error
5. **ImageKit API Error**: Log detailed error, continue

**Error Report Structure**:
```json
{
  "venue_id": 457,
  "venue_slug": "white-hart-whitechapel",
  "image_url": "https://cdn.quizadvisor.com/...",
  "error_type": "timeout",
  "error_message": "Connection timed out after 30s",
  "retry_count": 3,
  "timestamp": "2025-10-26T16:30:00Z"
}
```

### Recovery Strategies

1. **Partial Failure**: Continue with remaining venues, generate error report
2. **Network Issues**: Checkpoint system allows resume from last successful venue
3. **Database Errors**: Rollback current venue, continue with next
4. **ImageKit Outage**: Pause migration, resume when service restored

---

## Configuration Requirements

### Environment Variables

**Local Dev**:
```bash
TRVIA_ADVISOR_DATABASE_URL=postgresql://...  # Production TA database (read-only)
# Local eventasaurus uses default config (127.0.0.1:54322)
```

**Production**:
```bash
PRODUCTION_DATABASE_URL=postgresql://...     # Production EA database
TRVIA_ADVISOR_DATABASE_URL=postgresql://...  # Production TA database
IMAGEKIT_PUBLIC_KEY=...
IMAGEKIT_PRIVATE_KEY=...
IMAGEKIT_URL_ENDPOINT=https://ik.imagekit.io/your_id
```

### ImageKit Setup

1. Create ImageKit account (free tier: 20GB storage, 20GB bandwidth/month)
2. Get API credentials from dashboard
3. Configure folder structure: `/venues/{slug}/`
4. Enable automatic optimization
5. Set up webhook for upload notifications (optional)

---

## Testing Plan

### Local Dev Testing

1. **Phase 2 Dev Mode**:
   ```bash
   mix migration.phase2 --limit=10
   ```

2. **Verify Local UI**:
   - Navigate to venue pages
   - Check image display
   - Verify CORS works
   - Test responsive images

3. **Verification Mode**:
   ```bash
   mix migration.phase2 --verify
   ```
   - Checks all URLs return HTTP 200
   - Validates image dimensions
   - Reports broken links

### Production Testing

1. **Dry Run**:
   ```bash
   mix migration.phase2 --production --country="United Kingdom" --dry-run
   ```

2. **Small Batch**:
   ```bash
   mix migration.phase2 --production --country="United Kingdom" --limit=10
   ```

3. **Verify Production UI**:
   - Check 10 test venues
   - Verify ImageKit URLs work
   - Test image transformations
   - Monitor performance

4. **Full Migration**:
   ```bash
   mix migration.phase2 --production --country="United Kingdom"
   ```

5. **Monitor**:
   - ImageKit dashboard (bandwidth, requests)
   - Application logs (errors)
   - Performance metrics (page load times)
   - User feedback

---

## Performance Estimates

### Local Dev Mode
- **Speed**: ~1-2 minutes for 575 venues
- **Cost**: $0 (no uploads)
- **Network**: Read-only queries to TA database
- **Database Load**: Minimal (simple UPDATE queries)

### Production Mode (per country)

#### United Kingdom (~412 venues, ~2,060 images)
- **Upload Time**: ~30-45 minutes
  - Download: ~5s per venue
  - ImageKit upload: ~2s per image
  - Database update: ~1s per venue
  - Rate limiting delays: ~10-15 minutes total
- **Cost**: Free tier sufficient (2GB storage, well within limits)
- **Network**: ~1-2GB download from Tigris, ~1-2GB upload to ImageKit

#### Poland (~89 venues, ~445 images)
- **Upload Time**: ~8-10 minutes
- **Cost**: Free tier
- **Network**: ~300-400MB

#### France + Germany (~74 venues, ~370 images)
- **Upload Time**: ~6-8 minutes per country
- **Cost**: Free tier
- **Network**: ~250-300MB per country

**Total Production Migration Time**: ~50-70 minutes for all 575 venues

---

## Success Criteria

### Local Dev
- ✅ All 575 venues populated with Tigris URLs
- ✅ `upload_status: "external"` set correctly
- ✅ Images display in local UI
- ✅ No CORS errors
- ✅ Responsive images work

### Production
- ✅ All venues successfully uploaded to ImageKit
- ✅ `upload_status: "completed"` for all images
- ✅ Original Tigris URLs preserved as fallback
- ✅ Rollback data generated per country
- ✅ Zero data loss
- ✅ Images display correctly in production UI
- ✅ Page load times improved (CDN benefits)
- ✅ ImageKit transformations working

---

## Monitoring & Alerting

### Metrics to Track

1. **Upload Success Rate**: Target >95% per country
2. **Average Upload Time**: <5s per image
3. **Error Rate**: <5% per country
4. **Page Load Times**: Should improve by 20-30%
5. **ImageKit Bandwidth**: Monitor monthly limits
6. **Database Performance**: Query times should remain stable

### Alerts

1. **High Error Rate**: >10% failures in a country → pause migration
2. **ImageKit API Errors**: Service outage → pause and queue for retry
3. **Database Connection Loss**: → checkpoint and resume when restored
4. **Rate Limit Exceeded**: → automatic backoff, resume when limit resets

---

## Rollback Plan

### When to Rollback

1. **High Error Rate**: >20% upload failures in a country
2. **ImageKit Issues**: Persistent API errors or outages
3. **Performance Degradation**: Page load times increase instead of decrease
4. **User Reports**: Significant image loading issues
5. **Data Integrity**: Any signs of data corruption

### Rollback Process

1. **Immediate**:
   ```bash
   mix migration.phase2.rollback --country="United Kingdom"
   ```

2. **Verify Rollback**:
   - Check venues restored to Tigris URLs
   - Verify `upload_status: "external"`
   - Test image display

3. **Investigate Issues**: Review error logs, identify root cause

4. **Fix and Retry**: Once issues resolved, re-run migration for that country

---

## Next Steps

1. ✅ **Specification Complete** (this document)
2. ⏳ **Implement Phase 2 Task**: `lib/mix/tasks/migration_phase2.ex`
3. ⏳ **Implement ImageKit Client**: `lib/eventasaurus/imagekit/client.ex`
4. ⏳ **Local Dev Testing**: Test with small subset
5. ⏳ **Frontend Verification**: Ensure UI displays external URLs
6. ⏳ **Production Dry Run**: Test with UK sample
7. ⏳ **Full Production Rollout**: Country by country

---

## Summary

Phase 2 provides a **flexible, safe, and cost-effective** approach to migrating venue images from Tigris S3 to ImageKit CDN:

### Key Features
- ✅ **Dual-Mode Architecture**: Dev testing without costs, production with full control
- ✅ **Phased Rollout**: Country/city-based deployment reduces risk
- ✅ **Full Rollback**: Per-country rollback capability with preserved data
- ✅ **Zero Data Loss**: Original URLs preserved as fallback
- ✅ **Performance Benefits**: CDN delivery, automatic optimization, transformations

### Risk Mitigation
- ✅ Test in local dev first (zero cost)
- ✅ Production dry-run mode
- ✅ Small batch testing (10 venues)
- ✅ Country-by-country rollout
- ✅ Comprehensive error handling
- ✅ Checkpoint/resume capability
- ✅ Rollback per country

**Ready for Implementation** ✅
