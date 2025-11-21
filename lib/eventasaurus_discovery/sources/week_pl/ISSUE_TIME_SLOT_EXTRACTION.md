# Issue: week.pl Time Slot Extraction Returns 0 Slots Despite Website Showing Availability

## Problem Summary

The week.pl scraper reports "0 days, 0 unique time slots" for restaurants, but the website clearly shows available time slots (18:00, 18:30, 19:00, 19:30, 20:00) for the same restaurants.

## Evidence

### Scraper Logs
```
[info] [WeekPl.Client] ✅ Loaded wola-verde with 0 days, 0 unique time slots
[info] [WeekPl.Client] ✅ Loaded la-forchetta with 0 days, 0 unique time slots
[info] [WeekPl.Client] ✅ Loaded molto with 0 days, 0 unique time slots
```

### Website Screenshot Evidence
User screenshot shows 5 restaurants in Kraków for tomorrow's date with visible time slots:
- 18:00 (some available, some grayed out)
- 18:30 (some available, some grayed out)
- 19:00 (some available, some grayed out)
- 19:30 (some available, some grayed out)
- 20:00 (some available, some grayed out)

## Key User Requirement

**Critical insight from user**: "We need to get the time slots that COULD be available, whether or not they're available or not. We need to get the time slots."

This means we need:
- The **POTENTIAL** booking time slots a restaurant offers (their schedule/menu of times)
- NOT real-time availability status
- Similar to how the website shows ALL time slots (some clickable/available, some grayed out/unavailable)

## Sequential Thinking Analysis

### Root Cause Investigation

#### 1. Current Query Structure
The `fetch_restaurant_detail` function in `client.ex` (lines 128-150) queries:

```graphql
query GetRestaurantDetail($id: ID!) {
  restaurant(id: $id) {
    id
    name
    slug
    address
    description
    latitude
    longitude
    tags {
      name
    }
    reservables {
      ... on Daily {
        id
        startsAt
        possibleSlots
      }
    }
  }
}
```

**Analysis**: The query DOES request `reservables` with `possibleSlots`, so the GraphQL query structure appears correct.

#### 2. Client-Side Date Filtering
The client code (lines 164-175) filters reservables:

```elixir
filtered_reservables =
  (restaurant["reservables"] || [])
  |> Enum.filter(fn reservable ->
    case Date.from_iso8601(reservable["startsAt"]) do
      {:ok, reservable_date} ->
        Date.compare(reservable_date, start_date) != :lt and
          Date.compare(reservable_date, end_date) != :gt
      _ ->
        false
    end
  end)
```

**Analysis**: This filters to only include dates within 2 weeks of the requested date. If the API returns reservables outside this range, they would be filtered out.

#### 3. Potential Root Causes

**Hypothesis A: API Returns Empty Reservables**
The GraphQL API might not be returning any `reservables` data at all for these restaurants. Possible reasons:
- The API endpoint might require authentication or special headers
- The restaurant data might not include reservables in the response
- There might be a different GraphQL query or endpoint for getting time slot data

**Hypothesis B: API Returns Reservables But Empty possibleSlots**
The API returns `reservables` with `startsAt` dates but the `possibleSlots` arrays are empty:
- The API might require different query parameters to populate possibleSlots
- The possibleSlots might be in a different field or nested differently
- The website might be using a different API call to get time slot data

**Hypothesis C: Date Range Filtering Issue**
The API returns reservables but they're outside the 2-week date range:
- The `startsAt` dates might be formatted differently than expected
- The date comparison logic might have a bug
- The API might return dates in a different timezone

**Hypothesis D: Website Uses Different API Call**
The website might be making a completely different API call:
- Different GraphQL query with different fields
- Different endpoint altogether (REST API vs GraphQL)
- Multiple API calls aggregated together
- Client-side generation of time slot options based on restaurant metadata

#### 4. What We Need

Based on user requirements, we need to extract:
- **Time slot schedule**: The list of booking times a restaurant offers (18:00, 18:30, 19:00, etc.)
- **Not availability status**: We don't need to know if slots are currently available
- **Potential options**: All time slots that COULD be booked, regardless of current status

This is similar to a restaurant's "hours of operation" - we need their booking schedule, not real-time seat availability.

## Diagnostic Steps Required

### 1. Examine Phase 2 Observability Data
Check the `api_response` field in `job_execution_summaries` to see what the GraphQL API actually returns:

```sql
SELECT
  id,
  worker,
  results->>'status' as status,
  results->'api_response' as api_response,
  results->'query_params' as query_params
FROM job_execution_summaries
WHERE worker = 'EventasaurusDiscovery.Sources.WeekPl.Jobs.RestaurantDetailJob'
  AND created_at > NOW() - INTERVAL '1 day'
ORDER BY created_at DESC
LIMIT 5;
```

This will show:
- Whether `reservables` array exists in the response
- Whether `possibleSlots` arrays are populated or empty
- The actual structure of the GraphQL response

### 2. Compare with Website API Calls
Use browser DevTools Network tab to:
- Capture the actual API calls the website makes
- Compare GraphQL query structure with ours
- Check if different fields or fragments are used
- Identify if multiple API calls are made and aggregated

### 3. Test Query Variations
Try different GraphQL query approaches:
- Query without date/time filters
- Request additional fields that might contain time slot data
- Use different fragment structures for the Union type
- Test the restaurants listing query vs detail query

### 4. Examine Apollo State Structure
Log the complete `apollo_state` structure to identify:
- What keys exist in the response
- Where time slot data might be nested
- If there are alternative fields to `possibleSlots`

## Impact

**Current**: No events are created because we extract 0 time slots, leading to "no_slots" status.

**Desired**: Extract the restaurant's time slot schedule (potential booking times) to create events, even if real-time availability isn't known.

## Related Files

- `lib/eventasaurus_discovery/sources/week_pl/client.ex` (lines 125-238) - GraphQL query and response handling
- `lib/eventasaurus_discovery/sources/week_pl/jobs/restaurant_detail_job.ex` (lines 186-216) - Time slot extraction
- `lib/eventasaurus_discovery/sources/week_pl/FINAL_VALIDATION.md` - Previous validation showing 5 restaurants found

## Next Steps

1. **Examine observability data** to see actual API responses (Phase 2 diagnostics)
2. **Reverse engineer website** API calls using browser DevTools
3. **Test query modifications** based on findings
4. **Update GraphQL query** if needed to request correct fields
5. **Modify extraction logic** if data is in different structure
6. **Consider alternative approach** if API doesn't provide time slot schedule data

## References

- GitHub Issue #2332 - Phase 1 (date fix) and Phase 2 (observability)
- User feedback: "we need the time slots that could be available... these time slots, whether or not they're available or not, we need to get the time slots"
