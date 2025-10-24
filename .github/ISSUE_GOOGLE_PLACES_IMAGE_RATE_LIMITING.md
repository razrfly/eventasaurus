# Google Places Image Enrichment: Rate Limiting and Observability Issues

## Problem Summary

Google Places image enrichment is experiencing intermittent failures where:
- Jobs report "Found 10 images" but only 4 ImageKit URLs appear in metadata
- Some jobs fail with `REQUEST_DENIED` on first attempt but succeed on retry
- Insufficient metadata to diagnose root cause of individual image failures
- Images display inconsistently on frontend (some load, some don't)

## Root Cause Analysis

### The Issue Flow

1. **Photo Reference Fetch** (✅ Works)
   - `Orchestrator.fetch_from_provider` calls Google Places API
   - Successfully retrieves 10 photo references
   - No errors at this stage

2. **Image Download** (❌ Fails Partially)
   - `Orchestrator.update_venue_with_images` (line 482) loops through 10 photos
   - For each photo: calls `upload_to_imagekit`
   - `ImageKit.Uploader.download_image` (line 76) makes `Req.get` to Google's photo URL
   - **Google rate limits some requests** → Returns 429 or REQUEST_DENIED
   - Uploader returns `{:error, {:http_status, 429}}` or similar

3. **Error Handling** (⚠️ Inadequate)
   - Orchestrator catches error (line 507-510)
   - Logs generic warning: "ImageKit upload failed for venue X"
   - Marks image with `upload_status: "failed"` but still adds to venue_images
   - Job continues processing remaining images

4. **Metadata Reporting** (❌ Misleading)
   - `EnrichmentJob.build_success_metadata` (line 502) counts `images_found: length(venue_images)`
   - This counts ALL images (uploaded + failed)
   - `extract_imagekit_urls` (line 524) only returns images with `upload_status: "uploaded"`
   - **Result**: "Found 10 images" but only 4 ImageKit URLs

## Evidence from Production

### Job 51963 (venue_id: 350)
```elixir
"images_found" => 10
"imagekit_urls" => [
  "https://ik.imagekit.io/wombie/venues/adam-mickiewicz-monument-krakow-1-405/gp-122d16.jpg",
  "https://ik.imagekit.io/wombie/venues/adam-mickiewicz-monument-krakow-1-405/gp-ebb7b3.jpg",
  "https://ik.imagekit.io/wombie/venues/adam-mickiewicz-monument-krakow-1-405/gp-504390.jpg",
  "https://ik.imagekit.io/wombie/venues/adam-mickiewicz-monument-krakow-1-405/gp-cf2780.jpg"
]
# Attempt 1: FAILED with "REQUEST_DENIED"
# Attempt 2: SUCCESS (but only 4/10 images uploaded)
```

### Job 51965 (venue_id: 352)
```elixir
"images_found" => 8
"imagekit_urls" => [3 URLs only]
# Attempt 1: SUCCESS (but only 3/8 images uploaded)
```

### Job 51960 (venue_id: 348)
```elixir
"images_found" => 10
"imagekit_urls" => [10 URLs - all successful]
# Attempt 1: SUCCESS (all images uploaded)
```

## Why We Don't See the Problem

### Missing Observability

**Current Logging** (orchestrator.ex:508-510):
```elixir
Logger.warning(
  "ImageKit upload failed for venue #{venue.id}, provider #{provider}: #{inspect(reason)}"
)
```

**What's Missing**:
- No capture of HTTP status codes (429, 403, etc.)
- No differentiation between rate_limit vs auth_error vs network_error
- No per-image failure tracking in job metadata
- No aggregate statistics on failure types
- Failed images not stored for retry attempts

### Misleading Metadata

**Current** (enrichment_job.ex:502):
```elixir
images_count = length(enriched_venue.venue_images || [])
%{
  images_found: images_count,  # ❌ Counts ALL images (uploaded + failed)
  imagekit_urls: extract_imagekit_urls(...)  # ✅ Only uploaded images
}
```

**Should Be**:
```elixir
%{
  images_discovered: 10,      # Total from provider
  images_uploaded: 4,         # Successfully uploaded to ImageKit
  images_failed: 6,          # Failed during upload
  failed_images: [           # Details for debugging
    %{url: "...", error: :rate_limited, status_code: 429},
    %{url: "...", error: :download_failed, status_code: 403}
  ]
}
```

## Impact

### User Experience
- Inconsistent image galleries (some venues have all images, others partial)
- No user-facing indication of why images are missing
- Refresh/retry doesn't help (same images fail consistently)

### Operations
- Cannot diagnose root cause from job metadata alone
- Must manually check logs to find errors
- No metrics on rate limit frequency or failure patterns
- Difficult to determine if issue is transient or systemic

### Business
- Poor venue representation (missing photos)
- API costs for failed attempts (still count against quota)
- Increased Oban retry load from intermittent failures

## Proposed Solutions

### 1. Enhanced Error Logging & Metadata ⭐ HIGH PRIORITY

**orchestrator.ex:507-517** - Capture detailed error information:
```elixir
case upload_result do
  {:ok, imagekit_url, imagekit_path} ->
    # ... existing success handling

  {:error, {:download_failed, {:http_status, status_code}}} ->
    error_detail = %{
      "url" => provider_url,
      "error" => "download_failed",
      "status_code" => status_code,
      "error_type" => classify_error(status_code),  # :rate_limited, :auth_error, etc.
      "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
    }

    Logger.warning("""
    ⚠️ Image download failed for venue #{venue.id}:
       Provider: #{provider}
       Status: #{status_code}
       Type: #{error_detail["error_type"]}
       URL: #{String.slice(provider_url, 0..80)}
    """)

    # Store error details for metadata
    Map.merge(base_image, %{
      "url" => provider_url,
      "upload_status" => "failed",
      "error_details" => error_detail
    })

  {:error, reason} ->
    # Handle other error types with similar detail
end
```

**enrichment_job.ex:490-509** - Add failure tracking to metadata:
```elixir
defp build_success_metadata(enriched_venue, start_time) do
  all_images = enriched_venue.venue_images || []
  uploaded_images = Enum.filter(all_images, fn img -> img["upload_status"] == "uploaded" end)
  failed_images = Enum.filter(all_images, fn img -> img["upload_status"] == "failed" end)

  # Extract failure statistics
  failure_breakdown =
    failed_images
    |> Enum.group_by(fn img -> get_in(img, ["error_details", "error_type"]) end)
    |> Enum.map(fn {error_type, images} -> {error_type, length(images)} end)
    |> Map.new()

  %{
    status: if(length(uploaded_images) > 0, do: "success", else: "no_images"),
    images_discovered: length(all_images),
    images_uploaded: length(uploaded_images),
    images_failed: length(failed_images),
    failure_breakdown: failure_breakdown,  # %{rate_limited: 5, auth_error: 1}
    failed_images: Enum.map(failed_images, fn img ->
      img["error_details"]
    end),
    imagekit_urls: extract_imagekit_urls(uploaded_images),
    # ... rest of metadata
  }
end
```

### 2. Rate Limiting Between Uploads ⭐ HIGH PRIORITY

**orchestrator.ex:479-521** - Add delay between ImageKit uploads:
```elixir
new_structured_images =
  images
  |> Enum.with_index()
  |> Enum.map(fn {img, index} ->
    provider_url = img.url || img["url"]
    provider = img.provider || img["provider"]

    # Add delay between uploads to respect Google rate limits
    # Skip delay for first image
    if index > 0 do
      delay_ms = calculate_upload_delay(provider, index)
      Logger.debug("⏱️  Rate limit delay: #{delay_ms}ms before image #{index + 1}")
      Process.sleep(delay_ms)
    end

    upload_result = upload_to_imagekit(venue, provider_url, provider)
    # ... rest of upload handling
  end)

defp calculate_upload_delay(provider, _index) do
  case provider do
    "google_places" -> 500  # 500ms delay for Google (2 requests/sec)
    "foursquare" -> 200     # 200ms for Foursquare
    _ -> 100                # 100ms default
  end
end
```

### 3. Exponential Backoff for Rate Limit Errors

**uploader.ex:74-87** - Retry with backoff on rate limits:
```elixir
defp download_image(url, attempt \\ 1, max_attempts \\ 3) do
  case Req.get(url, receive_timeout: @timeout_ms) do
    {:ok, %Req.Response{status: 200, body: body, headers: headers}} when is_binary(body) ->
      content_type = get_content_type(headers)
      {:ok, {body, content_type}}

    {:ok, %Req.Response{status: 429}} when attempt < max_attempts ->
      # Rate limited - exponential backoff
      backoff_ms = :math.pow(2, attempt) * 1000 |> round()
      Logger.warning("⚠️ Rate limited (attempt #{attempt}/#{max_attempts}), retrying in #{backoff_ms}ms")
      Process.sleep(backoff_ms)
      download_image(url, attempt + 1, max_attempts)

    {:ok, %Req.Response{status: 429}} ->
      {:error, {:http_status, 429}}

    {:ok, %Req.Response{status: status}} ->
      {:error, {:http_status, status}}

    {:error, exception} ->
      {:error, exception}
  end
end
```

### 4. Failed Image Retry on Next Enrichment (FUTURE)

Store failed photo references in venue metadata and retry on next enrichment:
```elixir
# Store failed photo URLs for retry
enrichment_metadata = %{
  # ... existing metadata
  "failed_photos_pending_retry" => failed_images |> Enum.map(fn img ->
    %{
      "provider_url" => img["url"],
      "provider" => img["provider"],
      "failed_at" => img["error_details"]["timestamp"],
      "error_type" => img["error_details"]["error_type"]
    }
  end)
}

# On next enrichment, retry failed photos first before fetching new ones
```

## Testing Strategy

1. **Local Testing**:
   - Create test venue with 10+ Google Places photos
   - Artificially limit rate to trigger errors
   - Verify error capture and metadata accuracy

2. **Production Monitoring**:
   - Deploy enhanced logging first
   - Monitor failure_breakdown metrics for 1 week
   - Analyze rate limit patterns before implementing delays

3. **Metrics to Track**:
   - Rate of 429 errors per provider
   - Average images_uploaded vs images_discovered ratio
   - Retry success rate for rate-limited images
   - Job execution time (with vs without delays)

## Implementation Priority

1. ⭐ **Phase 1** (Observability - Deploy First):
   - Enhanced error logging
   - Detailed metadata tracking
   - No behavior changes, pure observability

2. ⭐ **Phase 2** (Prevention - After analyzing metrics):
   - Rate limiting between uploads
   - Exponential backoff on 429 errors

3. **Phase 3** (Optimization - Future):
   - Failed image retry logic
   - Provider-specific rate limit configuration
   - Parallel upload with rate limiting

## Files to Modify

1. `lib/eventasaurus_discovery/venue_images/orchestrator.ex`
   - Lines 479-521: Add upload delays and enhanced error capture
   - Add `classify_error/1` and `calculate_upload_delay/2` helpers

2. `lib/eventasaurus_discovery/venue_images/enrichment_job.ex`
   - Lines 490-509: Update metadata structure
   - Add failure statistics and detailed error tracking

3. `lib/eventasaurus/imagekit/uploader.ex`
   - Lines 74-87: Add retry logic with exponential backoff
   - Improve error classification

## Related Issues

- Oban job 51963: REQUEST_DENIED on attempt 1, success on attempt 2
- Oban job 51965: 8 images discovered, only 3 uploaded
- Stats page showing inconsistent image display

## References

- Google Places Photo API: https://developers.google.com/maps/documentation/places/web-service/photos
- ImageKit Upload API: https://imagekit.io/docs/api-reference/upload-file/upload-file
- Code locations:
  - orchestrator.ex:479-521 (image upload loop)
  - enrichment_job.ex:490-509 (metadata building)
  - uploader.ex:74-87 (download_image function)
