# Local Development: Using Production Venue Images

## Overview

Local development can now display production venue images from ImageKit without requiring production database access or making Google Places API calls.

## How It Works

### 1. **Slug-Based Folder Structure**

Venue images are now stored in ImageKit using the venue slug instead of ID:

- **Old**: `/venues/123/gp-a8f3d2.jpg`
- **New**: `/venues/blue-note-jazz-club/gp-a8f3d2.jpg`

Since slugs are identical across environments, local dev can construct the same paths as production.

### 2. **Automatic Image Fetching in Dev**

When a venue page loads in development:

1. **Check database**: Does `venue.venue_images` have images?
   - **Yes** → Use them (same as production)
   - **No** → Continue to step 2

2. **Query ImageKit API**: Fetch images from `/venues/{slug}/`
   - Returns list of images with URLs, provider, dimensions
   - Formatted exactly like database-stored images

3. **Display images**: Use fetched images in gallery component

### 3. **Zero Impact on Production**

- **Production**: Always uses database URLs (no API calls)
- **Local dev**: Queries ImageKit only when DB has no images
- **Cost**: One ImageKit API call per venue page load in dev (acceptable)

## Setup Requirements

### Environment Variables

Make sure `.env` or `.env.local` contains:

```bash
# Required for local dev image fetching
IMAGEKIT_PRIVATE_KEY=your_private_key_here
```

### Configuration

Already configured in `config/dev.exs`:

```elixir
config :eventasaurus, :environment, :dev
```

## Testing

### Test the Fetcher Directly

```bash
# Test fetching images for a venue
mix run test_imagekit_fetch.exs
```

This will:
1. Check ImageKit configuration
2. Fetch images for a test venue slug
3. Test with non-existent venue

### Test in Browser

1. Start local server: `mix phx.server`
2. Create or find a venue with no images in local DB
3. Visit venue page: `http://localhost:4000/venues/{slug}`
4. If the venue exists in production ImageKit, images will display!

## How Images Are Uploaded

When you upload venue images (via backfill jobs or enrichment):

```elixir
# Uploads to: /venues/{slug}/gp-a8f3d2.jpg
# Tags with: ["google_places", "venue:blue-note-jazz-club"]
```

The filename is deterministic (hash-based), so the same provider URL always generates the same filename.

## Troubleshooting

### No images showing in local dev

**Check:**
1. Does the venue exist in production with images?
2. Is `IMAGEKIT_PRIVATE_KEY` set in `.env`?
3. Check logs for ImageKit API errors

**Debug:**
```bash
# Check if images exist in ImageKit
mix run test_imagekit_fetch.exs

# Or test in IEx:
iex -S mix
iex> Eventasaurus.ImageKit.Fetcher.list_venue_images("your-venue-slug")
```

### API authentication errors

**Solution:**
- Verify `IMAGEKIT_PRIVATE_KEY` is correct
- Check ImageKit dashboard for API key permissions

### Wrong venue's images showing

**This shouldn't happen** - but if it does:
- Verify venue slug is correct
- Check ImageKit folder structure matches `/venues/{slug}/`

## Related Files

- **Fetcher**: `lib/eventasaurus/imagekit/fetcher.ex` - Queries ImageKit API
- **Component**: `lib/eventasaurus_web/live/venue_live/components/image_gallery.ex` - Uses fetcher
- **Upload**: `lib/eventasaurus_discovery/venue_images/orchestrator.ex` - Uploads with slug-based paths
- **Config**: `lib/eventasaurus/imagekit/filename.ex` - Builds folder paths

## Future Improvements

- **Caching**: Cache fetched images per session to reduce API calls
- **Batch fetching**: Fetch images for multiple venues in one API call
- **Preloading**: Preload images when listing venues
