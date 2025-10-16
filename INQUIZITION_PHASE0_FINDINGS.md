# Inquizition Scraper - Phase 0 Investigation Findings

**Date**: 2025-10-15
**Issue**: #1766
**Investigator**: Claude Code with Playwright MCP
**Status**: ✅ **SUCCESS - Option 1 Confirmed**

---

## 🎯 Executive Summary

**RECOMMENDED APPROACH**: **Option 1 - StoreLocatorWidgets CDN Endpoint**

The investigation successfully identified a publicly accessible CDN endpoint that provides all venue data in JSON format. **No paid APIs required** - this will be implemented exactly like Quizmeisters (free, fast, reliable).

---

## 🔍 Investigation Results

### CDN Endpoint Discovery

**Endpoint URL**:
```
https://cdn.storelocatorwidgets.com/json/7f3962110f31589bc13cdc3b7b85cfd7
```

**Key Details**:
- **Format**: JSONP with `slw()` callback wrapper
- **Access**: Publicly accessible (no authentication required)
- **UID**: `7f3962110f31589bc13cdc3b7b85cfd7` (Inquizition's StoreLocatorWidgets account)
- **Total Venues**: 143 venues
- **Update Frequency**: Real-time (CDN serves latest data)
- **Cost**: **FREE** ✅

### Discovery Method

1. Loaded https://inquizition.com/find-a-quiz/ using Playwright
2. Waited for StoreLocatorWidgets widget to initialize
3. Captured network requests
4. Identified CDN request: `https://cdn.storelocatorwidgets.com/json/7f3962110f31589bc13cdc3b7b85cfd7?callback=slw&_=1760544979212`
5. Tested direct access without callback parameter
6. **Confirmed**: Endpoint is publicly accessible and returns full venue data

---

## 📊 Data Structure

### Response Format

```json
{
  "stores": [
    {
      "storeid": "97520779",
      "name": "Andrea Ludgate Hill",
      "display_order": "999999",
      "data": {
        "address": "47 Ludgate Hill\r\nLondon\r\nEC4M 7JZ",
        "description": "Tuesdays, 6.30pm",
        "website": "https://andreabars.com/bookings/",
        "website_text": "Book your table",
        "phone": "020 7236 1942",
        "email": "ludgatehill@andreabars.com",
        "priority_setting": "Random",
        "map_lat": "51.513898",
        "map_lng": "-0.1026125",
        "markerid": "default"
      },
      "custom_data": false,
      "filters": ["Tuesday"],
      "google_placeid": "",
      "update_code": "",
      "update_storeid": "0",
      "timezone": "Europe/London",
      "country": "GB",
      "filters_bitwise": 1
    }
  ],
  "settings": { ... },
  "markers": { ... },
  "filters": { ... },
  "branding": { ... }
}
```

### Available Data Fields

#### Required Fields (All Present)
- ✅ `storeid`: Unique venue identifier
- ✅ `name`: Venue name
- ✅ `data.address`: Full address (multi-line, includes postcode)
- ✅ `data.description`: Schedule text (e.g., "Tuesdays, 6.30pm")
- ✅ `data.map_lat`: GPS latitude (as string)
- ✅ `data.map_lng`: GPS longitude (as string)
- ✅ `data.phone`: Phone number
- ✅ `timezone`: "Europe/London" (all venues)
- ✅ `country`: "GB" (United Kingdom)
- ✅ `filters`: Day of week array (e.g., ["Tuesday"])

#### Optional Fields
- ⚠️ `data.website`: Venue booking/website URL
- ⚠️ `data.email`: Venue email address
- ❌ `data.image_url`: Not present (confirmed - no images)

#### Derived Fields
- 🔄 External ID: Will use `inquizition_{storeid}`
- 🔄 Day of week: Parse from `filters` array
- 🔄 Time: Parse from `data.description` (e.g., "Tuesdays, 6.30pm")

---

## ✅ Phase 0 Decision

**SELECTED APPROACH**: **Option 1 - StoreLocatorWidgets CDN Endpoint**

### Why Option 1?

1. **Free**: No API costs, no authentication required
2. **Fast**: Direct HTTP GET request, JSON response
3. **Reliable**: Stable third-party CDN (storelocatorwidgets.com)
4. **Simple**: Identical architecture to Quizmeisters
5. **Complete Data**: All required fields present (except images)
6. **GPS Provided**: No geocoding needed (lat/lng included)

### Implementation will be:
- Nearly identical to Quizmeisters scraper
- HTTP client with exponential backoff retry
- JSON parsing (strip JSONP wrapper)
- Single-stage architecture (no detail pages needed)
- EventFreshnessChecker integration (80-90% reduction)

---

## 📋 Implementation Checklist

### Core Components Needed

**HTTP Client** (`client.ex`):
```elixir
def fetch_venues do
  url = "https://cdn.storelocatorwidgets.com/json/7f3962110f31589bc13cdc3b7b85cfd7"

  case HTTPoison.get(url, [], timeout: 30_000, recv_timeout: 30_000) do
    {:ok, %{status_code: 200, body: body}} ->
      # Strip JSONP wrapper: slw({...})
      json = body
        |> String.replace_prefix("slw(", "")
        |> String.replace_suffix(")", "")

      {:ok, Jason.decode!(json)}
    {:error, reason} -> {:error, reason}
  end
end
```

**Venue Extractor** (`extractors/venue_extractor.ex`):
```elixir
def extract_venues(response) do
  response["stores"]
  |> Enum.map(&parse_venue/1)
  |> Enum.filter(& &1 != nil)
end

defp parse_venue(store) do
  %{
    venue_id: store["storeid"],
    name: store["name"],
    address: store["data"]["address"],
    latitude: parse_float(store["data"]["map_lat"]),
    longitude: parse_float(store["data"]["map_lng"]),
    phone: store["data"]["phone"],
    website: store["data"]["website"],
    email: store["data"]["email"],
    time_text: store["data"]["description"],
    filters: store["filters"],
    timezone: store["timezone"],
    country: store["country"]
  }
end
```

**Time Parser** (`helpers/time_parser.ex`):
- Parse `data.description`: "Tuesdays, 6.30pm" → {:tuesday, ~T[18:30:00]}
- Parse `filters`: ["Tuesday"] → :tuesday
- Handle various formats: "6.30pm", "18:30", "6:30 PM"

**Transformer** (`transformer.ex`):
- Generate external_id: `inquizition_{storeid}`
- Build recurrence_rule: weekly, day from filters, time from description
- Set pricing: £2.50, GBP, is_ticketed=true
- Set country: "United Kingdom"
- Set timezone: "Europe/London"
- Parse address for postcode
- Use CityResolver for city name

### Data Parsing Notes

**Address Parsing**:
```
"47 Ludgate Hill\r\nLondon\r\nEC4M 7JZ"
```
- Multi-line with `\r\n` separators
- Last line typically contains postcode
- Extract postcode: `EC4M 7JZ`
- City: Parse from address or use CityResolver

**Schedule Parsing Examples**:
- "Tuesdays, 6.30pm" → Tuesday, 18:30
- "Wednesdays, 7pm" → Wednesday, 19:00
- "Every Thursday 8:00 PM" → Thursday, 20:00

---

## 🎯 Next Steps

1. ✅ **Phase 0 Complete** - CDN endpoint identified and tested
2. ⏭️ **Begin Phase 1** - Implement core infrastructure:
   - Create `source.ex` (priority 35)
   - Create `config.ex` with CDN URL
   - Create `client.ex` with HTTP client
   - Create `extractors/venue_extractor.ex` for JSON parsing
   - Write unit tests (15+ tests)

---

## 📊 Comparison to Original Plan

| Aspect | Original Plan | Actual Result |
|--------|---------------|---------------|
| **API Type** | Unknown, possibly Zyte | StoreLocatorWidgets CDN ✅ |
| **Cost** | Potentially $1-3/month | **FREE** ✅ |
| **Authentication** | Possibly required | **None required** ✅ |
| **Data Format** | Possibly HTML | **JSON** ✅ |
| **Complexity** | Unknown | **Simple (like Quizmeisters)** ✅ |
| **GPS Coordinates** | Possibly needs geocoding | **Provided** ✅ |
| **Total Venues** | ~100 estimated | **143 actual** ✅ |

---

## 🏆 Success Factors

1. **No Zyte API Needed** ✅ - Avoided $1-3/month recurring cost
2. **No Playwright in Production** ✅ - Used only for one-time research
3. **Free & Fast** ✅ - Direct HTTP endpoint, no authentication
4. **GPS Provided** ✅ - No geocoding API calls needed
5. **Simple Architecture** ✅ - Identical to Quizmeisters (proven pattern)
6. **Complete Data** ✅ - All required fields except images

---

## 📝 Additional Findings

### StoreLocatorWidgets Service

- **Provider**: storelocatorwidgets.com (third-party SaaS)
- **CDN**: Cloudflare-based distribution
- **Reliability**: High (established service, stable infrastructure)
- **Update Frequency**: Real-time (data served from CDN cache)
- **Monitoring**: CDN URL is stable and unlikely to change

### Inquizition Data Quality

- **Complete Addresses**: All venues have full addresses with postcodes
- **GPS Accuracy**: Coordinates provided, no geocoding errors
- **Phone Numbers**: Present for all venues checked
- **Schedule Consistency**: Format is consistent ("Day, Time")
- **No Images**: Confirmed - no image URLs in data structure

### Maintenance Considerations

- **Low Maintenance**: CDN endpoint is stable
- **No Authentication**: No API key rotation or auth issues
- **EventFreshnessChecker**: Will reduce load by 80-90%
- **UK Only**: Single country, stable venue database
- **Third-Party Service**: StoreLocatorWidgets unlikely to change structure

---

## 🎓 Lessons Learned

1. **Research Pays Off**: Investigating before implementation saved $1-3/month and complexity
2. **Network Tab is Essential**: Playwright's network monitoring revealed the CDN endpoint
3. **JSONP Pattern**: Recognized the `slw()` callback wrapper pattern
4. **Direct Testing**: Testing CDN access directly confirmed public availability
5. **Data Structure Inspection**: Full JSON inspection revealed all available fields

---

## 📎 Appendix

### Raw CDN Response Structure

**Top-level keys**:
- `stores` - Array of 143 venue objects
- `settings` - Widget configuration
- `markers` - Map marker settings
- `filters` - Day-of-week filter configuration
- `branding` - StoreLocatorWidgets branding
- `css` - Custom CSS settings
- `layout` - Widget layout configuration
- `expressmaps_api_key` - Map API key
- `mapbox_api_key` - Alternative map provider
- `maptiler_api_key` - Alternative map provider
- `plan_type` - StoreLocatorWidgets subscription tier
- `plan_expiry` - Subscription expiration
- `reviews_enabled` - Feature flag
- `display_order_set` - Venue ordering
- `filter_layout` - Filter UI configuration

### Sample Venues (Full Data)

**Andrea Ludgate Hill (Tuesday 6:30pm)**:
```json
{
  "storeid": "97520779",
  "name": "Andrea Ludgate Hill",
  "data": {
    "address": "47 Ludgate Hill\r\nLondon\r\nEC4M 7JZ",
    "description": "Tuesdays, 6.30pm",
    "website": "https://andreabars.com/bookings/",
    "website_text": "Book your table",
    "phone": "020 7236 1942",
    "email": "ludgatehill@andreabars.com",
    "map_lat": "51.513898",
    "map_lng": "-0.1026125"
  },
  "filters": ["Tuesday"],
  "timezone": "Europe/London",
  "country": "GB"
}
```

### Testing Commands

```bash
# Fetch all venues
curl -s "https://cdn.storelocatorwidgets.com/json/7f3962110f31589bc13cdc3b7b85cfd7"

# Parse JSON (strip JSONP wrapper)
curl -s "https://cdn.storelocatorwidgets.com/json/7f3962110f31589bc13cdc3b7b85cfd7" \
  | sed 's/^slw(//' | sed 's/)$//' \
  | jq '.stores'

# Count venues
curl -s "https://cdn.storelocatorwidgets.com/json/7f3962110f31589bc13cdc3b7b85cfd7" \
  | sed 's/^slw(//' | sed 's/)$//' \
  | jq '.stores | length'

# View first venue
curl -s "https://cdn.storelocatorwidgets.com/json/7f3962110f31589bc13cdc3b7b85cfd7" \
  | sed 's/^slw(//' | sed 's/)$//' \
  | jq '.stores[0]'
```

---

**Status**: ✅ **Phase 0 COMPLETE - Proceeding to Phase 1 Implementation**

**Recommendation**: Implement using Option 1 (StoreLocatorWidgets CDN) - identical architecture to Quizmeisters, **zero API costs**, **no authentication required**.
