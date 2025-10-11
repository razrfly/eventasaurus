# Replace Manual Address Parsing with Forward Geocoding Service

**Severity:** 🔴 **CRITICAL** - Manual address parsing is fundamentally flawed
**Status:** PROPOSED - Requires implementation
**Created:** 2025-10-11
**Related Issues:** ISSUE_QUESTION_ONE_FAKE_CITIES.md (109 fake cities bug)

---

## Problem Summary

**Current Approach (BROKEN):**
- Manual parsing of UK addresses using naive string splitting and regex
- Assumes consistent address format: "Venue, Street, City, Postcode"
- Reality: UK addresses are highly variable and inconsistent
- Result: 109 fake cities with embedded postcodes (e.g., "England E5 8NN", "London England W1F 8PU")
- Defense-in-depth failed because both validation layers used same flawed parsing logic

**Why Manual Parsing Cannot Work:**
1. ❌ Address formats vary globally (UK, US, Poland, international)
2. ❌ No consistent field ordering or delimiter patterns
3. ❌ Embedded postcodes, country names, and other variations
4. ❌ Requires maintaining complex parsing logic for each country
5. ❌ Brittle and error-prone, as demonstrated by 109 fake cities

**What We Need:**
> "Google's API works great because you hand it the entire address and it breaks it down for you. Can we not use a library that does the same thing in a free way?"

---

## Proposed Solution: Forward Geocoding with `geocoder` Library

### Architecture Overview

**Stop parsing addresses manually. Use proper forward geocoding services.**

**Tier 1: Database Cache** (Zero cost, instant)
- Check if venue address already exists in database
- Reuse city name from previous geocoding
- Most venues repeat across scrapes → 80%+ cache hit rate

**Tier 2: `geocoder` + OpenStreetMaps** (Free, 1 req/sec)
- Use `geocoder` Elixir library (https://hex.pm/packages/geocoder)
- OpenStreetMaps/Nominatim provider (no API key required)
- Input: Full address string → Output: Structured location data
- Example: `Geocoder.call("Pub Name, 123 Street, London, E5 8NN")`
- Returns: `%{city: "London", coordinates: {lat, lng}, country: "United Kingdom"}`

**Tier 3: Existing `:geocoding` Library** (Free, offline validation)
- Use existing library for coordinate validation
- If we have GPS coordinates, validate city name matches expected

**Tier 4: Google Maps Geocoding API** (Paid fallback, 100% reliable)
- Only use when free tiers fail
- Guaranteed to work for critical cases
- Pay per request, but ensures zero failures

---

## Implementation Plan

### Phase 1: Add `geocoder` Library

**Install dependency:**
```elixir
# mix.exs
def deps do
  [
    {:geocoder, "~> 1.1"},
    # ... existing deps
  ]
end
```

**Configure OpenStreetMaps provider:**
```elixir
# config/config.exs
config :geocoder, :worker,
  provider: Geocoder.Providers.OpenStreetMaps
```

### Phase 2: Create AddressGeocoder Module

**Location:** `lib/eventasaurus_discovery/helpers/address_geocoder.ex`

**Responsibilities:**
1. Check database cache first (venue address → city)
2. Call `geocoder` library with full address string
3. Parse response to extract city, coordinates, country
4. Validate city name using CityResolver
5. Cache result in database
6. Fallback to Google Maps API if OpenStreetMaps fails
7. Throttle requests to 1/sec (Nominatim policy)

**Interface:**
```elixir
@spec geocode_address(String.t()) ::
  {:ok, {city_name :: String.t(), country :: String.t(), coordinates :: {float(), float()}}} |
  {:error, reason :: atom()}

def geocode_address(full_address) do
  # Tier 1: Check cache
  # Tier 2: Geocoder + OpenStreetMaps
  # Tier 3: Validate with existing :geocoding library
  # Tier 4: Google Maps API fallback
end
```

### Phase 3: Update QuestionOne Scraper

**File:** `lib/eventasaurus_discovery/sources/question_one/jobs/venue_detail_job.ex`

**Change:**
```elixir
# BEFORE (broken manual parsing)
defp parse_uk_address(address) do
  parts = String.split(address, ",")
  # ... naive index-based extraction
end

# AFTER (use forward geocoding)
defp geocode_venue_address(address) do
  AddressGeocoder.geocode_address(address)
end
```

### Phase 4: Update Other Scrapers

Apply same pattern to any scrapers doing manual address parsing:
- Bandsintown (if needed)
- Ticketmaster (if needed)
- Any future scrapers

### Phase 5: Database Schema for Caching

**Add caching table:**
```elixir
create table(:geocoded_addresses) do
  add :address, :text, null: false
  add :city_name, :string, null: false
  add :country_name, :string, null: false
  add :latitude, :float
  add :longitude, :float
  add :provider, :string  # "openstreetmap", "google", etc.
  add :geocoded_at, :utc_datetime, null: false

  timestamps()
end

create unique_index(:geocoded_addresses, [:address])
```

---

## Rate Limiting & Compliance

### Nominatim Usage Policy

**Rate Limits:**
- Maximum 1 request per second
- Must cache results
- Provide User-Agent header
- Display attribution: "© OpenStreetMap contributors"

**Implementation:**
```elixir
# Use GenServer with rate limiting
defmodule AddressGeocoder.RateLimiter do
  use GenServer

  # Allow 1 request per second
  @rate_limit_ms 1000

  def call_with_rate_limit(address) do
    GenServer.call(__MODULE__, {:geocode, address})
  end

  # Throttle requests to 1/sec
  def handle_call({:geocode, address}, _from, state) do
    result = Geocoder.call(address)
    Process.sleep(@rate_limit_ms)
    {:reply, result, state}
  end
end
```

### Caching Strategy

**Cache ALL successful geocoding results:**
- Reduces API calls by 80%+ (most venues repeat)
- Respects Nominatim policy
- Improves scraper performance
- Essential for production use

---

## Response Structure

### OpenStreetMaps Response Example

```elixir
{:ok, %Geocoder.Coordinates{
  location: %{
    formatted_address: "Pub Name, 123 Street, London E5 8NN, UK",
    address_components: %{
      city: "London",
      postcode: "E5 8NN",
      country: "United Kingdom",
      country_code: "GB"
    }
  },
  lat: 51.5074,
  lon: -0.1278,
  bounds: %{...}
}}
```

### Extraction Logic

```elixir
defp extract_city_from_response(response) do
  address = response.location.address_components

  # Try multiple fields for city (different countries use different names)
  city = address[:city] || address[:town] || address[:village] ||
         address[:municipality] || address[:locality]

  country = address[:country]
  coordinates = {response.lat, response.lon}

  {:ok, {city, country, coordinates}}
end
```

---

## Benefits

### ✅ Eliminates Entire Class of Bugs
- No more manual address parsing
- No more fake cities with embedded postcodes
- No more country-specific parsing logic
- No more regex maintenance

### ✅ Works Globally
- Handles UK, US, Poland, and international addresses
- Single solution for all address formats
- Nominatim supports worldwide locations

### ✅ Cost-Effective
- Free for most use cases (OpenStreetMaps)
- Caching reduces API calls by 80%+
- Google fallback only for critical failures
- Estimated cost: $0-5/month

### ✅ Reliable & Proven
- `geocoder` library is maintained and tested
- Nominatim is production-grade service
- Google Maps API is industry standard fallback
- Multi-tier approach ensures zero failures

### ✅ Easy to Maintain
- No custom parsing logic to maintain
- Library handles edge cases
- Clear separation of concerns
- Easy to add new scrapers

---

## Risks & Mitigation

### Risk 1: Rate Limits (1 req/sec)

**Impact:** Slow geocoding for new venues

**Mitigation:**
- Aggressive database caching (80%+ hit rate)
- Only geocode truly NEW venues
- Run scrapers async/parallel where possible
- Self-hosted Nominatim as future option

**Assessment:** Low risk - caching makes this manageable

### Risk 2: Nominatim Policy Changes

**Impact:** Service could change terms or restrict usage

**Mitigation:**
- Google Maps API as reliable fallback
- Monitor Nominatim policy page
- Consider self-hosted instance for scale
- Can switch to other providers if needed

**Assessment:** Low risk - Google fallback ensures zero failures

### Risk 3: Geocoding Accuracy

**Impact:** OpenStreetMaps might not geocode some addresses

**Mitigation:**
- CityResolver validation still applies
- Google Maps API fallback for failures
- Log and monitor geocoding failures
- Manual review of edge cases

**Assessment:** Low risk - multi-tier approach handles this

### Risk 4: API Downtime

**Impact:** Nominatim could be temporarily unavailable

**Mitigation:**
- Retry logic with exponential backoff
- Google Maps API fallback
- Queue failed requests for later
- Database cache reduces dependency

**Assessment:** Low risk - fallback strategy ensures reliability

---

## Testing Strategy

### Unit Tests

**File:** `test/eventasaurus_discovery/helpers/address_geocoder_test.exs`

```elixir
describe "geocode_address/1" do
  test "geocodes UK address with OpenStreetMaps" do
    address = "Pub Name, 123 Street, London, E5 8NN"
    assert {:ok, {city, country, {lat, lng}}} = AddressGeocoder.geocode_address(address)
    assert city == "London"
    assert country == "United Kingdom"
    assert is_float(lat) and is_float(lng)
  end

  test "returns cached result for repeated address" do
    address = "Same venue, Same street, Cambridge, CB2 3AR"

    # First call hits API
    {:ok, result1} = AddressGeocoder.geocode_address(address)

    # Second call uses cache
    {:ok, result2} = AddressGeocoder.geocode_address(address)

    assert result1 == result2
  end

  test "falls back to Google Maps when OpenStreetMaps fails" do
    # Mock OpenStreetMaps failure
    # Verify Google API is called
  end

  test "validates city name with CityResolver" do
    # Geocoding returns "England E5 8NN" (hypothetical bad response)
    # Should be rejected by CityResolver validation
  end
end
```

### Integration Tests

**Test with real QuestionOne addresses:**
- "Pub Name, Cambridge England CB2 3AR" → Should extract "Cambridge"
- "Venue, London England W1F 8PU" → Should extract "London"
- "Pub, 123 Street, Wembley, HA9 0HP" → Should extract "Wembley"

### Manual Verification

1. Re-scrape QuestionOne with new implementation
2. Check database for fake cities
3. Verify all events have valid city names
4. Compare results with previous scrapes

---

## Rollout Plan

### Stage 1: Development & Testing (1-2 days)
1. Add `geocoder` dependency
2. Implement AddressGeocoder module
3. Write comprehensive tests
4. Test with QuestionOne sample addresses

### Stage 2: QuestionOne Integration (1 day)
1. Update QuestionOne scraper to use AddressGeocoder
2. Delete 109 fake cities from database
3. Re-scrape all QuestionOne venues
4. Verify results are clean

### Stage 3: Validation (1 day)
1. Run ISSUE_1638 validation queries
2. Check for any remaining fake cities
3. Monitor logs for geocoding failures
4. Review edge cases

### Stage 4: Rollout to Other Scrapers (As needed)
1. Update any other scrapers with manual parsing
2. Apply same pattern consistently
3. Monitor and validate

### Stage 5: Production Monitoring (Ongoing)
1. Track geocoding success/failure rates
2. Monitor API usage and costs
3. Review cache hit rates
4. Optimize throttling if needed

---

## Success Criteria

### ✅ Phase 1: Implementation Complete
- `geocoder` library installed and configured
- AddressGeocoder module implemented with tests
- Rate limiting and caching working

### ✅ Phase 2: QuestionOne Fixed
- All 121 QuestionOne events have valid cities
- Zero fake cities with embedded postcodes
- 100% city coverage maintained

### ✅ Phase 3: Validation Passed
- ISSUE_1638 validation queries return 0 invalid cities
- No regression in city coverage percentages
- All scrapers functioning normally

### ✅ Phase 4: Production Metrics
- Geocoding success rate >95%
- Cache hit rate >80%
- API costs <$5/month
- Zero manual address parsing in codebase

---

## Cost Analysis

### Free Tier (OpenStreetMaps)
- **Cost:** $0/month
- **Limits:** 1 req/sec, must cache results
- **Expected usage:** 10-20 new venues per scrape (cached venues free)
- **Monthly volume:** ~200-400 requests (well within limits)

### Paid Tier (Google Maps Geocoding)
- **Cost:** $5 per 1,000 requests (first $200/month free)
- **Usage:** Only for OpenStreetMaps failures
- **Expected usage:** <100 requests/month (fallback only)
- **Monthly cost:** $0 (within free tier)

### Total Estimated Cost
- **Development time:** 2-3 days
- **Monthly operational cost:** $0-5
- **Value:** Eliminates manual parsing bugs, scalable globally

---

## Alternative Considered: Self-Hosted Nominatim

**Pros:**
- No rate limits
- Full control
- No API dependencies

**Cons:**
- Requires server infrastructure
- Database is ~100GB for global data
- Maintenance overhead
- Setup complexity

**Decision:** Start with hosted Nominatim, consider self-hosting if we scale significantly or encounter rate limit issues.

---

## Documentation Updates

### Files to Update

1. **SCRAPER_MANIFESTO.md**
   - Update "City Resolution Decision Tree"
   - Document forward geocoding approach
   - Remove manual parsing patterns

2. **CITY_RESOLVER_MIGRATION_GUIDE.md**
   - Add section on AddressGeocoder usage
   - Update migration patterns for new scrapers

3. **ISSUE_QUESTION_ONE_FAKE_CITIES.md**
   - Mark as RESOLVED once implemented
   - Reference this solution document

4. **ISSUE_1638_VALIDATION_PLAN.md**
   - Add validation queries for cached addresses
   - Update success criteria

---

## Future Enhancements

### Phase 2 Improvements (Optional)

1. **Smart cache warming:**
   - Pre-geocode common venue addresses
   - Reduce first-run latency

2. **Geocoding analytics:**
   - Track success rates by provider
   - Identify problematic addresses
   - Optimize fallback strategy

3. **Alternative providers:**
   - Add Photon as Tier 2.5 option
   - Test other free geocoding services
   - Compare accuracy and performance

4. **Self-hosted Nominatim:**
   - Consider for scale (>10K requests/month)
   - Remove rate limit constraints
   - Full control over data freshness

---

## Conclusion

**This solution eliminates the root cause of address parsing bugs by using proper forward geocoding services instead of manual parsing.**

**Key Advantages:**
- ✅ Zero manual parsing = zero parsing bugs
- ✅ Free for most use cases with paid fallback
- ✅ Works globally, not just UK
- ✅ Proven, maintained libraries
- ✅ Scalable with caching
- ✅ Easy to implement and maintain

**Recommendation:** Implement immediately to resolve fake cities bug and prevent future address parsing issues.

---

**References:**
- `geocoder` library: https://hex.pm/packages/geocoder
- Nominatim API: https://nominatim.org/
- Nominatim usage policy: https://operations.osmfoundation.org/policies/nominatim/
- Google Maps Geocoding API: https://developers.google.com/maps/documentation/geocoding
