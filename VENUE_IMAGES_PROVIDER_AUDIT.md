# Venue Image Provider Audit Results

## Executive Summary

**Date**: 2025-01-22
**Status**: ✅ ALL PROVIDERS IMPLEMENTED
**Critical Finding**: The testing UI has a bug accessing `provider_ids` from venues

All four image providers (HERE, Geoapify, Foursquare, Google Places) have fully implemented `get_images/1` functions in their geocoding provider modules. The implementations are complete and follow correct API patterns.

**Root Cause of "No Images Found"**: The testing UI is failing at the provider_id accessor level (VenueImagesTestController.ex:165), preventing any API calls from being attempted.

---

## Provider Implementation Status

### ✅ HERE (EventasaurusDiscovery.Geocoding.Providers.Here)
**Status**: FULLY IMPLEMENTED
**Location**: lib/eventasaurus_discovery/geocoding/providers/here.ex (lines 176-261)

**Implementation Details**:
- **API Endpoint**: `https://lookup.search.hereapi.com/v1/lookup`
- **Method**: `get_images/1` (lines 176-189)
- **Authentication**: API key via `apiKey` parameter
- **Parameters**:
  - `id`: HERE place ID (format: `here:pds:place:...`)
  - `apiKey`: HERE_API_KEY environment variable
- **Response Parsing**: Extracts images from top-level `images` array
- **Image Structure**:
  ```elixir
  %{
    url: Map.get(img, "url") || Map.get(img, "src"),
    width: Map.get(img, "width"),
    height: Map.get(img, "height"),
    attribution: "HERE",
    source_url: Map.get(img, "source_url")
  }
  ```
- **Error Handling**:
  - 404 → `:no_results`
  - 401 → `:api_error` (auth failed)
  - 429 → `:rate_limited`
  - Empty images → `:no_images`

**API Documentation**: https://developer.here.com/documentation/geocoding-search-api/

**Assessment**: Implementation looks correct. Uses HERE Lookup API which is the appropriate endpoint for place details including images.

---

### ✅ Geoapify (EventasaurusDiscovery.Geocoding.Providers.Geoapify)
**Status**: FULLY IMPLEMENTED
**Location**: lib/eventasaurus_discovery/geocoding/providers/geoapify.ex (lines 174-270)

**Implementation Details**:
- **API Endpoint**: `https://api.geoapify.com/v2/place-details`
- **Method**: `get_images/1` (lines 174-187)
- **Authentication**: API key via `apiKey` parameter
- **Parameters**:
  - `id`: Geoapify place ID (long hex string format)
  - `apiKey`: GEOAPIFY_API_KEY environment variable
- **Response Parsing**: Extracts single image from `features[0].properties.image`
- **Image Structure**:
  ```elixir
  %{
    url: url,
    width: nil,
    height: nil,
    attribution: "Geoapify",
    source_url: nil
  }
  ```
- **Error Handling**:
  - 404 → `:no_results`
  - 401 → `:api_error` (auth failed)
  - 429 → `:rate_limited`
  - No image property → `:no_images`

**API Documentation**: https://www.geoapify.com/geocoding-api

**Assessment**: Implementation looks correct. Uses Geoapify Place Details API v2. Note: Only returns single image if available in properties.

---

### ✅ Foursquare (EventasaurusDiscovery.Geocoding.Providers.Foursquare)
**Status**: FULLY IMPLEMENTED
**Location**: lib/eventasaurus_discovery/geocoding/providers/foursquare.ex (lines 173-279)

**Implementation Details**:
- **API Endpoint**: `https://api.foursquare.com/v3/places/{place_id}/photos`
- **Method**: `get_images/1` (lines 173-186)
- **Authentication**: Bearer token via Authorization header
- **Parameters**:
  - Path: Foursquare place ID (fsq_id format)
  - `limit`: 10 photos
  - `sort`: "POPULAR"
- **Response Parsing**: Constructs URLs from `prefix + "original" + suffix`
- **Image Structure**:
  ```elixir
  %{
    url: "#{prefix}original#{suffix}",
    width: width,
    height: height,
    attribution: "Foursquare",
    source_url: nil
  }
  ```
- **Error Handling**:
  - 404 → `:no_results`
  - 401 → `:api_error` (auth failed)
  - 429 → `:rate_limited`
  - Empty photos array → `:no_images`

**API Documentation**: https://docs.foursquare.com/developer/reference/places-api-overview

**Assessment**: Implementation looks correct. Uses Foursquare Places Photos API v3 with proper URL construction from prefix/suffix pattern.

---

### ✅ Google Places (EventasaurusDiscovery.Geocoding.Providers.GooglePlaces)
**Status**: FULLY IMPLEMENTED (but INACTIVE in database)
**Location**: lib/eventasaurus_discovery/geocoding/providers/google_places.ex (lines 266-369)

**Implementation Details**:
- **API Endpoint**: `https://maps.googleapis.com/maps/api/place/details/json`
- **Method**: `get_images/1` (lines 266-279)
- **Authentication**: API key via `key` parameter
- **Parameters**:
  - `place_id`: Google place ID (ChIJ... format)
  - `fields`: "photos"
  - `key`: GOOGLE_PLACES_API_KEY environment variable
- **Response Parsing**: Extracts photo references and constructs URLs
- **Image Structure**:
  ```elixir
  %{
    url: "https://maps.googleapis.com/maps/api/place/photo?maxwidth=#{width || 1600}&photo_reference=#{photo_reference}&key=#{api_key}",
    width: width,
    height: height,
    attribution: Enum.join(attributions, " | "),
    source_url: nil
  }
  ```
- **Error Handling**:
  - 404 → `:no_results`
  - 403 → `:api_error` (auth/billing failed)
  - 429 → `:rate_limited`
  - Empty photos → `:no_images`

**API Documentation**:
- https://developers.google.com/maps/documentation/places/web-service/details
- https://developers.google.com/maps/documentation/places/web-service/photos

**Assessment**: Implementation looks correct. Uses Google Places Details API with photos field, then constructs photo URLs with references. **Note**: Provider is disabled in database due to high cost ($0.034/request).

---

## Orchestrator Integration Review

**Location**: lib/eventasaurus_discovery/venue_images/orchestrator.ex

### Provider Module Mapping (lines 333-344)
```elixir
defp get_provider_module(provider_name) do
  case provider_name do
    "google_places" -> EventasaurusDiscovery.Geocoding.Providers.GooglePlaces ✅
    "foursquare" -> EventasaurusDiscovery.Geocoding.Providers.Foursquare ✅
    "here" -> EventasaurusDiscovery.Geocoding.Providers.Here ✅
    "geoapify" -> EventasaurusDiscovery.Geocoding.Providers.Geoapify ✅
    "unsplash" -> EventasaurusDiscovery.VenueImages.Providers.Unsplash ❌ (removed)
    _ -> nil
  end
end
```

**Status**: All mappings correct and modules exist.

### Image Fetching Flow (lines 184-214)
```elixir
defp fetch_from_provider(venue, provider) do
  with :ok <- RateLimiter.check_rate_limit(provider),
       {:ok, provider_module} <- get_provider_module_result(provider.name),
       {:ok, place_id} <- get_place_id(venue, provider.name) do

    RateLimiter.record_request(provider.name)

    case provider_module.get_images(place_id) do
      {:ok, images} when is_list(images) ->
        {:ok, provider.name, images, calculate_cost(provider, length(images))}

      {:error, reason} ->
        Logger.warning("⚠️ #{provider.name} failed: #{inspect(reason)}")
        {:error, provider.name, reason}
    end
  else
    {:error, :no_place_id} ->
      Logger.debug("⏭️  Skipping #{provider.name}: no provider_id available")
      {:error, provider.name, :no_place_id}

    # ... other error cases
  end
end
```

**Issue Found** (line 224):
```elixir
defp get_place_id(venue, provider_name) do
  case get_in(venue, [:provider_ids, provider_name]) ||
       get_in(venue, ["provider_ids", provider_name]) do
    nil -> {:error, :no_place_id}
    place_id -> {:ok, place_id}
  end
end
```

This accessor pattern tries both atom key and string key, which should work. However, the testing controller has a different (incorrect) pattern.

---

## Testing UI Bug Analysis

**Location**: lib/eventasaurus_web/controllers/dev/venue_images_test_controller.ex

### Issue at Line 165
```elixir
defp test_provider(venue, provider) do
  start_time = System.monotonic_time(:millisecond)

  # Get provider ID for this venue
  provider_id = get_in(venue.provider_ids, [provider.name])  # ❌ BUG HERE

  if provider_id do
    # Try to fetch images from this provider
    result = fetch_images_from_provider(venue, provider, provider_id)
    # ...
  else
    %{
      success: false,
      error: "No provider ID available for #{provider.name}",
      images: [],
      api_calls: [],
      cost: 0.0
    }
  end
end
```

**Problem**:
- `venue.provider_ids` is a JSONB map: `%{"here" => "id123", "geoapify" => "id456"}`
- `provider.name` returns string like `"here"`
- Pattern `get_in(venue.provider_ids, [provider.name])` doesn't work for string-keyed maps

**Solution**: Should use direct map access or Map.get:
```elixir
# Option 1: Direct map access
provider_id = venue.provider_ids[provider.name]

# Option 2: Map.get (safer)
provider_id = Map.get(venue.provider_ids, provider.name)

# Option 3: Match orchestrator pattern
provider_id =
  Map.get(venue.provider_ids, provider.name) ||
  Map.get(venue.provider_ids, String.to_atom(provider.name))
```

---

## Database State Verification

From previous investigation:
- **77 venues** have HERE provider_ids
- **83 venues** have Geoapify provider_ids
- **0 venues** have Foursquare provider_ids
- **0 venues** have Google Places provider_ids

**Expected Provider ID Formats**:
- **HERE**: `"here:pds:place:826gcpuw-7987e8d009d14eb6bb9bc65acb7d9ba8"`
- **Geoapify**: `"5188e9647bdefe314059e26712ab758f4a40f00102f90174df7f0b00000000c00203"`
- **Foursquare**: `"4a1b2c3d..."` (fsq_id format)
- **Google Places**: `"ChIJxyz..."` (ChIJ... format)

---

## API Key Status Check

**Required Environment Variables**:
```bash
# Check if API keys are configured
echo $HERE_API_KEY          # Required for HERE
echo $GEOAPIFY_API_KEY      # Required for Geoapify
echo $FOURSQUARE_API_KEY    # Required for Foursquare
echo $GOOGLE_PLACES_API_KEY # Required for Google Places (disabled provider)
```

---

## Priority 3 Audit Conclusions

### ✅ What's Working
1. **All provider modules exist and implement `get_images/1`**
2. **API endpoints are correct for each provider**
3. **Authentication patterns are correct**
4. **Error handling is comprehensive**
5. **Orchestrator integration is properly implemented**
6. **Provider ID accessor in orchestrator handles both atom and string keys**

### ❌ What's Broken
1. **Testing UI provider ID accessor** (VenueImagesTestController.ex:165)
   - Uses incorrect pattern: `get_in(venue.provider_ids, [provider.name])`
   - Should use: `Map.get(venue.provider_ids, provider.name)`

2. **No real-world API testing performed yet**
   - Need to fix accessor bug first
   - Then test with actual venue IDs to verify API responses

### ⚠️ Potential Issues (Untested)
1. **HERE API response format** - Implementation assumes `images` array at top level, needs verification with real API response
2. **Geoapify single image limitation** - Only extracts one image from properties.image field
3. **Foursquare URL construction** - Assumes prefix/suffix pattern, needs verification
4. **Google Places photo URLs** - Constructs URLs with API key embedded (security consideration)

---

## Next Steps (Priority 4)

### Immediate Fix Required
1. **Fix testing UI provider ID accessor**
   - File: `VenueImagesTestController.ex`
   - Line: 165
   - Change: `get_in(venue.provider_ids, [provider.name])` → `Map.get(venue.provider_ids, provider.name)`

### Manual API Testing Plan
After fixing accessor:
1. Select venue with HERE ID (e.g., Venue 360, Venue 68)
2. Click "Test HERE Images" button
3. Review API request/response in UI
4. Verify images are returned
5. Repeat for Geoapify, Foursquare
6. Document actual API response formats

### API Documentation Cross-Reference
Compare actual responses with:
- **HERE**: https://developer.here.com/documentation/geocoding-search-api/dev_guide/topics/endpoint-lookup-brief.html
- **Geoapify**: https://apidocs.geoapify.com/docs/place-details/
- **Foursquare**: https://location.foursquare.com/developer/reference/place-photos
- **Google Places**: https://developers.google.com/maps/documentation/places/web-service/photos

---

## Cost Analysis

**Per-Image Costs** (from provider metadata):
- **HERE**: Free tier (250K requests/month)
- **Geoapify**: Free tier (90K requests/month, 3K/day)
- **Foursquare**: Free tier (500 requests/day)
- **Google Places**: $0.017 per request (EXPENSIVE - disabled)

**Current Priority Order** (from database `priorities.images`):
1. Google Places (priority 1) - **INACTIVE**
2. Geoapify (priority 10)
3. HERE (priority 3)
4. Foursquare (unknown - need to check database)

---

## Recommendations

1. **Fix accessor bug immediately** - Blocking all testing
2. **Test with real venues** - Verify API response formats
3. **Add debug logging** - Log actual API responses for analysis
4. **Consider response format variations** - APIs may return different structures
5. **Add API response examples to code comments** - Document expected formats
6. **Monitor API usage** - Track free tier limits
7. **Re-evaluate priority order** - Google Places disabled but priority 1

---

## Files Audited

- ✅ `lib/eventasaurus_discovery/geocoding/providers/here.ex` (266 lines)
- ✅ `lib/eventasaurus_discovery/geocoding/providers/geoapify.ex` (275 lines)
- ✅ `lib/eventasaurus_discovery/geocoding/providers/foursquare.ex` (284 lines)
- ✅ `lib/eventasaurus_discovery/geocoding/providers/google_places.ex` (374 lines)
- ✅ `lib/eventasaurus_discovery/venue_images/orchestrator.ex` (428 lines)
- ✅ `lib/eventasaurus_discovery/venue_images/provider.ex` (54 lines)
- ❌ `lib/eventasaurus_web/controllers/dev/venue_images_test_controller.ex` (267 lines) - **BUG FOUND**

---

**Audit Completed**: 2025-01-22
**Next Action**: Fix testing UI accessor bug and proceed with manual API testing
