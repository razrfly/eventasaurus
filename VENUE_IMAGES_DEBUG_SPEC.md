# Venue Image System - Debugging and Testing Interface Specification

## Problem Analysis

### Current State
The venue image enrichment system is running but **no images are being found** from any provider (HERE, Geoapify, Foursquare). Investigation reveals:

1. **Provider IDs exist**: Database has ~77 venues with HERE IDs, ~83 with Geoapify IDs
2. **Enrichment job runs**: Successfully processes venues and makes API calls
3. **No images returned**: All providers return "no images available" or "no results found"
4. **Unsplash misconfiguration**: Unsplash is in `venue_data_providers` but shouldn't be (it's generic, not venue-specific)

### Root Cause Hypotheses
1. **API Implementation Issues**: Provider adapters may not be correctly calling image endpoints
2. **Response Parsing**: Image data may be in responses but not being extracted correctly
3. **Authentication**: API keys may not be properly configured or passed
4. **ID Format**: Provider IDs may not be in the correct format for image queries
5. **Endpoint Selection**: May be using wrong API endpoints that don't return images

### Investigation Findings

**Database State:**
- Total venues: ~1150
- Venues with HERE provider_ids: 77 (format: `here:pds:place:...`)
- Venues with Geoapify provider_ids: 83 (format: long hex string)
- Venues with Foursquare provider_ids: 0
- Venues with Google Places provider_ids: 0

**Example Test Venues:**
- Venue 68 "Miejska Biblioteka Publiczna w Skawinie" - has HERE ID
- Venue 74 "Mashroom" - has Geoapify ID
- Venue 360 "The Railway Telegraph, Forrest Hill" - has HERE ID

---

## Immediate Actions Required

### 1. Remove Unsplash from Venue Data Providers
**Reason**: Unsplash is a generic photo service, not venue-specific. It doesn't provide images for specific venues based on location/ID.

**Action**:
```sql
DELETE FROM venue_data_providers WHERE name = 'unsplash';
```

### 2. Create Enhanced Testing Interface

Transform `/dev/venue-images` into an interactive testing page with manual controls to debug each provider.

---

## Enhanced Testing Interface Specification

### Page URL
`/dev/venue-images` (existing page, to be enhanced)

### New Sections to Add

#### Section 1: Manual Test Controls (Top Priority)

**Purpose**: Allow developers to manually test image fetching for specific venues with specific provider IDs.

**UI Components**:

1. **Venue Selector**
   - Dropdown or searchable list of venues
   - Show venues that have ANY provider_ids populated
   - Display: `[ID] Name (City) - Providers: [here, geoapify, ...]`
   - Select top 10-20 venues with provider_ids by default

2. **Provider ID Editor** (for selected venue)
   - Form with inputs for each provider:
     ```
     HERE ID:       [text input] [Save]
     Geoapify ID:   [text input] [Save]
     Foursquare ID: [text input] [Save]
     Google Places: [text input] [Save]
     ```
   - Show current values from `venues.provider_ids` JSONB field
   - Allow manual entry/editing of provider IDs for testing
   - "Save Provider IDs" button to update the venue

3. **Test Buttons**
   - **"Fetch Images from All Providers"** - triggers full enrichment
   - Individual provider buttons:
     - "Test HERE Images"
     - "Test Geoapify Images"
     - "Test Foursquare Images"
     - "Test Google Places Images"
   - Each button triggers a **synchronous** API call (not background job)

4. **Real-Time Results Display**
   - **API Request Log** section showing:
     - Provider name
     - API endpoint called
     - Request parameters
     - Response status
     - Response body (formatted JSON)
     - Errors (if any)
   - **Images Found** section showing:
     - Thumbnail preview of each image
     - Image URL
     - Image dimensions
     - Provider attribution
     - Image metadata
   - **Summary Stats**:
     - Total images found: X
     - Providers succeeded: Y
     - Providers failed: Z
     - Total cost: $X.XXXX

#### Section 2: Provider Configuration Dashboard

**Purpose**: Show provider status and allow quick configuration changes.

**UI Components**:

1. **Provider Status Table**
   - Provider name
   - Active/Inactive toggle
   - API Key status (✓ or ✗)
   - Priority for images
   - Quick "Test API Key" button
   - Last successful image fetch timestamp

2. **API Key Checker**
   - For each provider, show:
     - Environment variable name
     - Status: Present / Missing
     - Test button to validate key works

#### Section 3: Test Venue Recommendations

**Purpose**: Suggest venues that are likely to have images for testing.

**UI Components**:

1. **Recommended Test Venues**
   - List of venues with:
     - Multiple provider IDs populated
     - Well-known venues (higher chance of having images)
     - Geographic diversity
   - Quick "Select for Testing" button

2. **Venue Search**
   - Search by name
   - Filter by:
     - Has provider ID for specific provider
     - City
     - Venue type

---

## API Endpoints to Add

### POST `/dev/venue-images/test-enrichment`
**Purpose**: Synchronously test image enrichment for a specific venue

**Request Body**:
```json
{
  "venue_id": 123,
  "provider": "here" // optional, test specific provider only
}
```

**Response**:
```json
{
  "success": true,
  "venue_id": 123,
  "venue_name": "Test Venue",
  "results": {
    "here": {
      "success": true,
      "images_found": 5,
      "images": [
        {
          "url": "https://...",
          "width": 1024,
          "height": 768,
          "attribution": "HERE"
        }
      ],
      "api_calls": [
        {
          "url": "https://places.api.here.com/...",
          "status": 200,
          "response_time_ms": 245
        }
      ],
      "cost": 0.0001
    },
    "geoapify": {
      "success": false,
      "error": "No images available",
      "api_calls": [...]
    }
  },
  "total_images": 5,
  "total_cost": 0.0001
}
```

### PUT `/dev/venue-images/update-provider-ids`
**Purpose**: Update provider_ids for a venue (dev only)

**Request Body**:
```json
{
  "venue_id": 123,
  "provider_ids": {
    "here": "here:pds:place:...",
    "geoapify": "51abc123...",
    "foursquare": "4a1b2c3d...",
    "google_places": "ChIJxyz..."
  }
}
```

---

## Implementation Plan

### Priority 1: Remove Unsplash (5 minutes)
- [ ] Delete Unsplash from `venue_data_providers` table
- [ ] Verify it doesn't break anything
- [ ] Restart any running enrichment jobs

### Priority 2: Add Manual Testing UI (2-3 hours)
- [ ] Add venue selector dropdown to existing page
- [ ] Add provider ID editor form
- [ ] Add test buttons for each provider
- [ ] Add results display section
- [ ] Implement synchronous test endpoint
- [ ] Add real-time logging display

### Priority 3: Provider Audit (1-2 hours per provider)
- [ ] Review HERE adapter implementation
- [ ] Review Geoapify adapter implementation
- [ ] Review Foursquare adapter implementation
- [ ] Check API documentation for each provider
- [ ] Verify image endpoints are correct
- [ ] Test with curl/Postman directly

### Priority 4: Fix Issues Found (varies)
- [ ] Fix API endpoint URLs if incorrect
- [ ] Fix response parsing if broken
- [ ] Fix authentication if failing
- [ ] Add better error logging
- [ ] Add request/response debugging

---

## Provider Audit Checklist

For each provider (HERE, Geoapify, Foursquare, Google Places):

### 1. API Documentation Review
- [ ] Find official API documentation for images/photos endpoint
- [ ] Document correct endpoint URL format
- [ ] Document required parameters
- [ ] Document authentication method
- [ ] Document response format
- [ ] Document rate limits and costs

### 2. Adapter Implementation Review
- [ ] Locate adapter module (e.g., `EventasaurusDiscovery.VenueImages.Adapters.Here`)
- [ ] Verify `fetch_images/2` function exists
- [ ] Check API endpoint URL construction
- [ ] Check authentication header/param passing
- [ ] Check request parameters match API docs
- [ ] Check response parsing matches API response format
- [ ] Check image URL extraction logic
- [ ] Check error handling

### 3. Manual API Testing
- [ ] Get test venue provider ID
- [ ] Construct API request manually
- [ ] Test with curl/Postman
- [ ] Verify response contains images
- [ ] Document actual response format
- [ ] Compare with adapter implementation

### 4. Integration Testing
- [ ] Use dev UI to test venue with this provider
- [ ] Verify API call is made correctly
- [ ] Verify response is parsed correctly
- [ ] Verify images are extracted
- [ ] Verify images are saved to venue

---

## Test Venues Dataset

Create a curated list of test venues known to have images:

### High-Confidence Test Venues
1. **ICE Kraków Congress Centre** (ID: 5)
   - Large, well-known venue
   - Likely has images in all providers

2. **Venue 360** "The Railway Telegraph, Forrest Hill"
   - Has HERE ID: `here:pds:place:826gcpuw-7987e8d009d14eb6bb9bc65acb7d9ba8`

3. **Venue 8** "Cybermachina Bydgoszcz"
   - Has Geoapify ID: `5188e9647bdefe314059e26712ab758f4a40f00102f90174df7f0b00000000c00203`

### Manual Testing Process
1. Select test venue in UI
2. Verify/add provider IDs
3. Click "Fetch Images from All Providers"
4. Review results:
   - API calls made
   - Responses received
   - Images found
   - Errors encountered
5. Debug based on results
6. Fix issues
7. Retest

---

## Expected Outcomes

After implementing this spec:

1. **Immediate**: Unsplash removed from providers list
2. **Short-term**: Interactive testing UI allows manual debugging of each provider
3. **Medium-term**: Identify and fix root cause of "no images found" issue
4. **Long-term**: Reliable image enrichment from multiple providers

---

## Success Criteria

- [ ] Can manually test image fetching for any venue
- [ ] Can see exact API requests and responses
- [ ] Can identify which provider adapters are broken
- [ ] Can fix adapters based on real API responses
- [ ] Successfully fetch images from at least one provider
- [ ] Verify images are saved correctly to venues
- [ ] Verify images display correctly in frontend

---

## Notes

- **Synchronous Testing**: The test UI should make synchronous API calls (not background jobs) for immediate feedback
- **Logging**: Add extensive debug logging to see exactly what's being sent/received
- **Provider IDs**: The ability to manually edit provider_ids is crucial for testing different venues/providers
- **Documentation**: Use Context7 to check official API docs for HERE and Geoapify
- **Incremental Approach**: Fix one provider at a time, verify it works, then move to next

---

## Next Steps

1. Remove Unsplash from database
2. Create enhanced testing UI
3. Test with known venue IDs
4. Review provider adapter code
5. Compare with official API documentation
6. Fix implementation issues
7. Verify images are fetched successfully
