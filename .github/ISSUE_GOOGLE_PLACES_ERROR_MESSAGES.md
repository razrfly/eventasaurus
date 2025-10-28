# Google Places API Error Messages Are Too Vague in Oban Job Metadata

## Issue Description

When Google Places API calls fail, the error messages shown in Oban job metadata are too vague to diagnose the actual problem. Users see generic errors like `"API error: INVALID_REQUEST"` without any context about WHY the request was invalid.

## Example from Production

```
Job ID: 56497
Error: API authentication/configuration error: google_places: "API error: INVALID_REQUEST"

Meta:
%{
  "providers" => %{
    "google_places" => %{
      "reason" => "\"API error: INVALID_REQUEST\"",
      "status" => "failed"
    }
  }
}
```

**Question:** Is this an API key problem? Wrong place_id format? Missing required fields? Rate limit? We have no idea!

## Root Cause Analysis

### Google DOES Provide Detailed Error Messages

According to Google Places API documentation and our code, Google returns detailed error information:

```json
{
  "status": "INVALID_REQUEST",
  "error_message": "The provided place_id is not valid for this request type"
}
```

### We ARE Logging The Details (But Not Surfacing Them)

All 4 Google Places service files follow this pattern:

**File: `lib/eventasaurus_web/services/google_places/details.ex:44-46`**
```elixir
{:ok, %{"status" => status, "error_message" => message}} ->
  Logger.error("Google Places Details API error: #{status} - #{message}")
  {:error, "API error: #{status}"}  # ← Discards the message!
```

**Other affected files:**
- `lib/eventasaurus_web/services/google_places/geocoding.ex:29-31`
- `lib/eventasaurus_web/services/google_places/text_search.ex:28-30`
- `lib/eventasaurus_web/services/google_places/autocomplete.ex:28-30`

### Error Flow Path

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Google API Response                                          │
│    {"status": "INVALID_REQUEST",                                │
│     "error_message": "Place ID format is invalid"}              │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 2. Service Layer (details.ex, geocoding.ex, etc.)              │
│    ✓ Logs: "INVALID_REQUEST - Place ID format is invalid"      │
│    ✗ Returns: {:error, "API error: INVALID_REQUEST"}           │
│                         ↑ Lost the helpful message!             │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 3. Orchestrator (orchestrator.ex:352-357)                      │
│    Stores in error_details: %{"google_places" => reason}       │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ 4. Oban Job Metadata (enrichment_job.ex:915)                   │
│    Shows: "reason" => "\"API error: INVALID_REQUEST\""         │
│           ↑ No context for debugging!                           │
└─────────────────────────────────────────────────────────────────┘
```

## Impact

### Developer Experience
- Cannot diagnose production issues without digging through application logs
- Must hunt for the corresponding log entry matching the job timestamp
- Wastes time guessing at problems that Google already told us about

### Operations
- Difficult to distinguish between different failure types:
  - Invalid API key vs. Invalid place_id format
  - Missing required fields vs. Quota exceeded
  - Authentication issues vs. Request configuration problems
- Cannot write effective monitoring/alerting based on error types

### User Support
- Support team cannot help users debug issues without access to raw logs
- Cannot provide actionable error messages in UI

## Solution

### What Needs to Change

Update all 4 Google Places service files to include the `error_message` in the returned error tuple:

**Before:**
```elixir
{:ok, %{"status" => status, "error_message" => message}} ->
  Logger.error("Google Places Details API error: #{status} - #{message}")
  {:error, "API error: #{status}"}
```

**After:**
```elixir
{:ok, %{"status" => status, "error_message" => message}} ->
  Logger.error("Google Places Details API error: #{status} - #{message}")
  {:error, "API error: #{status} - #{message}"}
```

### Files to Update

1. `lib/eventasaurus_web/services/google_places/details.ex:46`
2. `lib/eventasaurus_web/services/google_places/geocoding.ex:31`
3. `lib/eventasaurus_web/services/google_places/text_search.ex:30`
4. `lib/eventasaurus_web/services/google_places/autocomplete.ex:30`

### Expected Result

After the fix, Oban job metadata will show:

```elixir
%{
  "providers" => %{
    "google_places" => %{
      "reason" => "API error: INVALID_REQUEST - The place_id format is invalid. Expected format: ChIJ...",
      "status" => "failed"
    }
  }
}
```

Now we can immediately see:
- ✓ What went wrong: "place_id format is invalid"
- ✓ What was expected: "ChIJ..." format
- ✓ How to fix it: Check the place_id we're sending

## Additional Considerations

### Fallback for Missing error_message

Some API responses might not include `error_message`. Handle this gracefully:

```elixir
{:ok, %{"status" => status} = response} ->
  message = Map.get(response, "error_message", "No additional details provided")
  Logger.error("Google Places Details API error: #{status} - #{message}")
  {:error, "API error: #{status} - #{message}"}
```

### Other Google Services to Check

While investigating, also check if other Google-related services have the same issue:
- TMDBService (similar pattern at: `lib/eventasaurus_web/services/tmdb_service.ex`)
- Other API integrations that might discard error messages

### Testing

After the fix:
1. Trigger a known error (e.g., invalid place_id format)
2. Check Oban job metadata includes the full error message
3. Verify logs still contain the error (should be unchanged)
4. Confirm monitoring/alerting can parse the detailed errors

## References

- **Oban Job Example:** Job #56497 (venue_id: 679)
- **Code Investigation:** Sequential thinking analysis (2025-10-28)
- **Google Places API Docs:** https://developers.google.com/maps/documentation/places/web-service/details
- **Related Files:**
  - Orchestrator: `lib/eventasaurus_discovery/venue_images/orchestrator.ex:256-286`
  - Enrichment Job: `lib/eventasaurus_discovery/venue_images/enrichment_job.ex:226-235`

## Priority

**High** - This affects our ability to diagnose and fix production issues efficiently. Without detailed error messages, we're flying blind when things go wrong.
