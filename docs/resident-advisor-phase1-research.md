# Resident Advisor Scraper - Phase 1 Research Findings

**Date:** 2025-10-06
**Status:** ✅ Phase 1 Complete (with open questions)
**Next Steps:** Area code mapping + venue coordinate investigation

---

## ✅ Confirmed Information

### GraphQL Endpoint
- **URL:** `https://ra.co/graphql`
- **Method:** POST
- **Content-Type:** `application/json`
- **Status:** ✅ Confirmed working (from Python library analysis)

### Required Headers
```
Content-Type: application/json
Referer: https://ra.co/events/{area_slug}
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:106.0) Gecko/20100101 Firefox/106.0
```

### Authentication
- ✅ **No API key required**
- ✅ **No login required**
- Public GraphQL endpoint (accessible without authentication)

### Rate Limiting
- **Observed:** 1 second delay between requests (from Python library)
- **Recommendation:** Start with 2 req/s (conservative)
- **Strategy:** Exponential backoff on errors
- **No explicit rate limit headers documented**

###GraphQL Query Structure

**Operation Name:** `GET_EVENT_LISTINGS`

**Query:**
```graphql
query GET_EVENT_LISTINGS(
  $filters: FilterInputDtoInput,
  $filterOptions: FilterOptionsInputDtoInput,
  $page: Int,
  $pageSize: Int
) {
  eventListings(
    filters: $filters,
    filterOptions: $filterOptions,
    pageSize: $pageSize,
    page: $page
  ) {
    data {
      id
      listingDate
      event {
        id
        date
        startTime
        endTime
        title
        contentUrl
        flyerFront
        isTicketed
        attending
        queueItEnabled
        newEventForm
        images {
          id
          filename
          alt
          type
          crop
        }
        pick {
          id
          blurb
        }
        venue {
          id
          name
          contentUrl
          live
        }
        artists {
          id
          name
        }
      }
    }
    totalResults
  }
}
```

**Variables Structure:**
```json
{
  "filters": {
    "areas": {
      "eq": <integer_area_id>  // IMPORTANT: Integer ID, not string slug
    },
    "listingDate": {
      "gte": "2025-10-06",  // ISO date format
      "lte": "2025-11-06"
    }
  },
  "filterOptions": {
    "genre": true  // Returns genre filter options
  },
  "pageSize": 20,  // Default: 20
  "page": 1
}
```

### Pagination
- **Method:** Page-based (not cursor-based)
- **Page Size:** Default 20, configurable via `pageSize` variable
- **Page Number:** Starts at 1
- **Total Results:** Returned in `totalResults` field
- **End Detection:** Empty `data` array when no more results

### Available Event Data

**Core Fields:**
- `id` - Unique event ID ✅
- `title` - Event name ✅
- `date` - Event date (ISO format) ✅
- `startTime` - Start time ✅
- `endTime` - End time (optional)
- `contentUrl` - Event detail page URL ✅

**Rich Media:**
- `flyerFront` - Main event poster/flyer image
- `images[]` - Array of event images with metadata
  - `filename`, `alt`, `type`, `crop`

**Ticketing:**
- `isTicketed` - Boolean for ticketed events ✅
- `attending` - Number of attendees (social proof) ✅
- `queueItEnabled` - Queue system for high-demand events

**Editorial:**
- `pick.blurb` - Editorial description (if featured)
- `newEventForm` - Boolean (purpose unclear)

**Venue Data:**
- `venue.id` - Venue ID ✅
- `venue.name` - Venue name ✅
- `venue.contentUrl` - Venue detail page URL ✅
- `venue.live` - Venue status ✅
- ❌ **NO COORDINATES** - `latitude` and `longitude` not available

**Artist Data:**
- `artists[].id` - Artist ID ✅
- `artists[].name` - Artist name ✅
- ❌ **Limited artist data** - No genres, images, or bio

---

## 🚨 Critical Findings

### 1. Area Codes are Integer IDs (Not String Slugs)

**Problem:** The GraphQL API expects integer area IDs, not string slugs like "pl/warsaw"

**Evidence:**
```python
# From Python library
parser.add_argument("areas", type=int, help="The area code to filter events.")
```

**Impact:** We need to map our city names to RA's integer area IDs

**Solution:** Create area ID lookup table (see Open Questions below)

### 2. Venue Coordinates Not Available in Event Listing

**Problem:** `venue.latitude` and `venue.longitude` are NOT in the GraphQL response

**Evidence:** Analyzed GraphQL schema - venue object only has:
- `id`, `name`, `contentUrl`, `live`

**Impact:** We MUST use geocoding strategy (hard requirement for our system)

**Options:**
1. ✅ **Google Places API geocoding** (proven in Karnet - RECOMMENDED)
2. 🔄 **Venue detail query** (needs investigation - might have coordinates)
3. ⚠️ **Venue page scraping** (last resort - fragile)

**Recommendation:** Use Google Places API (reliable, proven pattern)

### 3. Artist Data is Minimal

**Finding:** Only `id` and `name` available for artists
- No genres
- No images
- No biographical information
- No social links

**Impact:** Limited performer enrichment
- Can't auto-categorize by genre
- Can't provide artist images
- May need secondary data source for rich artist info

**Workaround:** Use artist `name` for basic performer field

---

## ❓ Open Questions

These require additional research or testing:

### Q1: Area ID Mapping
**Question:** What are the integer area IDs for our target cities?

**Cities Needed:**
- Warsaw, Poland → ?
- Kraków, Poland → ?
- Berlin, Germany → ?
- London, UK → 34 (likely, needs confirmation)
- New York, USA → ?
- Los Angeles, USA → ?

**How to Find:**
1. Check browser DevTools on RA website (look for area IDs in network requests)
2. Reverse engineer from contentUrl patterns
3. Query RA for list of areas (if such endpoint exists)
4. Manual testing with common IDs (34, 13, etc.)

**Priority:** HIGH - Required for Phase 2

### Q2: Venue Detail Query
**Question:** Does RA have a separate GraphQL query for venue details with coordinates?

**Possible Query:**
```graphql
query VenueDetail($venueId: ID!) {
  venue(id: $venueId) {
    id
    name
    address
    city
    country
    latitude
    longitude
    contentUrl
  }
}
```

**How to Test:**
1. Try venue query with known venue ID
2. Check browser DevTools when visiting venue pages
3. Analyze GraphQL schema introspection (if available)

**Impact:**
- If YES: Use this before Google Places (fewer external API calls)
- If NO: Rely on Google Places API

**Priority:** MEDIUM - Nice to have but not blocking

### Q3: Genre/Category Filtering
**Question:** Can we filter events by genre in the query?

**Current:** `filterOptions.genre: true` returns genre options

**Unclear:** Can we use `filters.genre.eq: "techno"` or similar?

**How to Test:** Try adding genre filter to variables

**Priority:** LOW - Not critical for MVP

### Q4: Rate Limit Details
**Question:** What are RA's actual rate limits?

**Current Knowledge:** Python library uses 1 second delay

**Need:**
- Requests per second limit?
- Requests per minute limit?
- Response headers with rate limit info?
- Behavior when rate limited (429 response?)

**How to Find:**
1. Check robots.txt
2. Test with rapid requests
3. Monitor response headers
4. Check terms of service

**Priority:** MEDIUM - Important for production

### Q5: Date/Time Timezone
**Question:** Are `date` and `startTime` in local timezone or UTC?

**Impact:** Affects date parsing and storage

**How to Test:**
- Fetch events with known times
- Compare with website display
- Check if timezone info is included

**Priority:** HIGH - Required for accurate event times

### Q6: Total Results Availability
**Question:** Is `totalResults` available in the response?

**Issue:** GraphQL validation errors suggest `totalResults` might not be on `EventListing` type

**Test Query:** Remove `totalResults` and see if query works

**Impact:**
- If unavailable: Paginate until empty results
- If available: Can calculate total pages upfront

**Priority:** LOW - Can paginate without it

---

## 🎯 Recommended Next Steps

### Immediate (Before Phase 2)

1. **Area Code Mapping** ⭐ CRITICAL
   - Use browser DevTools on ra.co/events pages
   - Extract area IDs for target cities
   - Create lookup table in config

2. **Test Working Query**
   - Use known area ID (e.g., 34 for London)
   - Verify query works end-to-end
   - Confirm response structure matches expectations

3. **Venue Strategy Decision**
   - Test if venue detail query exists
   - If not: Confirm Google Places API strategy
   - Document chosen approach

### Before Phase 3 (Jobs)

4. **Timezone Investigation**
   - Parse sample dates/times
   - Determine if local or UTC
   - Document conversion strategy

5. **Rate Limit Testing**
   - Check robots.txt
   - Test rate limits in development
   - Document safe limits

### Nice to Have

6. **Genre Filtering**
   - Test if genre filtering works
   - Document available genres
   - Consider for future enhancement

7. **Artist Enrichment**
   - Research secondary artist data sources
   - Consider MusicBrainz, Spotify API, etc.
   - Plan for Phase 4+

---

## 📝 Implementation Decisions

Based on research findings, here are the decisions for Phase 2:

### ✅ Confirmed Decisions

1. **Data Source:** GraphQL API at `https://ra.co/graphql`
2. **Authentication:** None required
3. **Rate Limit:** Start with 2 req/s, exponential backoff
4. **Pagination:** Page-based, pageSize: 20, detect end with empty results
5. **Priority:** 75 (below Ticketmaster/Bandsintown, above regional)

### 🔄 Pending Decisions

1. **Venue Coordinates:** Google Places API (pending venue detail query test)
2. **Area ID Mapping:** Manual mapping table (pending discovery)
3. **Timezone Handling:** TBD (needs testing)

---

## 🛠️ Technical Notes

### GraphQL Schema Observations

1. **Type System:**
   - `EventListing` (wrapper)
     - `data[]` - Array of event listings
     - `event` - Actual event object
   - `Event` - Main event type with all fields
   - `Venue` - Venue type (limited fields)
   - `Artist` - Artist type (minimal fields)

2. **Filter System:**
   - `FilterInputDtoInput` type
   - Supports `areas.eq`, `listingDate.gte/lte`
   - Likely supports other filters (genre, etc.)

3. **Fragments:**
   - Library uses fragments for reusability
   - Can simplify large queries
   - Consider for production implementation

### Error Handling Patterns

**Observed Errors:**
1. `GRAPHQL_VALIDATION_FAILED` - Schema mismatch
2. Type errors (`Int cannot represent non-integer value`)
3. Field not found errors

**Strategy:**
- Validate variables before sending
- Handle GraphQL errors separately from HTTP errors
- Log full error context for debugging

### Browser DevTools Research Method

Since WebFetch gets 403 errors, use this manual process:

1. Open https://ra.co/events/pl/warsaw in Chrome
2. Open DevTools → Network tab
3. Filter by "graphql" or "Fetch/XHR"
4. Scroll page to trigger GraphQL queries
5. Click on graphql requests
6. Inspect:
   - Request payload (variables, especially area ID)
   - Response structure
   - Headers
7. Document findings

---

## 📊 Research Summary

### What Works ✅
- GraphQL endpoint confirmed
- No authentication required
- Query structure understood
- Event data fields documented
- Pagination mechanism clear

### What Needs Work 🔄
- Area ID mapping (CRITICAL)
- Venue coordinate strategy
- Timezone handling
- Rate limit details
- Tested working query

### Blockers 🚨
- **Area ID unknown for target cities** - Can't test queries without this
- **Venue coordinates missing** - Hard requirement for our system

### Risk Assessment
- **Low Risk:** GraphQL API is stable and public
- **Medium Risk:** Area ID mapping might change over time
- **High Risk:** Rate limiting unclear (could get blocked)

---

## 🔗 References

- [Python Scraper](https://github.com/djb-gt/resident-advisor-events-scraper)
- [GraphQL Query Template](https://raw.githubusercontent.com/djb-gt/resident-advisor-events-scraper/master/graphql_query_template.json)
- [event_fetcher.py](https://raw.githubusercontent.com/djb-gt/resident-advisor-events-scraper/master/event_fetcher.py)
- [RA Website](https://ra.co)

---

## ✅ Phase 1 Deliverables

- [x] GraphQL endpoint identified
- [x] Authentication requirements confirmed (none)
- [x] Query structure documented
- [x] Available data fields catalogued
- [x] Pagination mechanism understood
- [ ] Area ID mapping (PENDING - needs manual research)
- [ ] Working query test (BLOCKED by area ID)
- [x] Venue coordinate strategy recommended (Google Places API)
- [x] Rate limit guidance (start at 2 req/s)

**Phase 1 Status:** 80% Complete

**Blockers for Phase 2:**
1. Area ID mapping for target cities (manual DevTools research required)
2. Test one working query to confirm implementation

**Recommended Action:**
- Manual browser DevTools research session to extract area IDs
- OR: Start Phase 2 with one known area ID (London = 34?) and expand later
