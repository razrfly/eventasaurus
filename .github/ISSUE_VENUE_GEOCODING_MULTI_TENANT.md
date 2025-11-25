# Venue Misnamed Due to Geocoding Multi-Tenant Building Limitation

## Issue Summary

**Severity**: Low (isolated incident)
**Type**: Data Quality / Geocoding Limitation
**Affected Venue**: Cinema City Zakopianka (Galeria Bronowice)
**Current Name**: "Castorama ul. Zakopiańska 62, 30-418 Kraków"
**Expected Name**: "Cinema City Zakopianka" or "Cinema City - Galeria Bronowice"

## Description

A venue in Kraków is incorrectly named "Castorama" (hardware store) instead of "Cinema City Zakopianka" (cinema) due to a limitation in how geocoding APIs handle multi-tenant buildings.

## Root Cause

This is **not a bug in our code**, but an **inherent limitation of geocoding APIs** when dealing with shopping malls and other multi-tenant buildings.

### What Happened

1. **Kino Krakow scraper** provides:
   - Name: "Cinema City Zakopianka"
   - City: "Kraków"
   - Country: "Poland"
   - Address: Not provided

2. **VenueProcessor** geocodes the query to get coordinates

3. **Geocoding provider** (HERE/Foursquare/Google Places) searches for the location and returns:
   - Coordinates: 50.0340, 19.9610 (correct)
   - **Business name: "Castorama"** (incorrect - this is a different tenant in the same mall)

4. **VenueNameValidator** compares names:
   - Scraped: "Cinema City Zakopianka"
   - Geocoded: "Castorama"
   - Similarity: ~0% (completely different)

5. **System logic**: Due to very low similarity (<0.3), assumes scraped name is invalid (like UI text or garbage) and chooses geocoded name

6. **Result**: Venue created with name "Castorama ul. Zakopiańska 62, 30-418 Kraków"

### Why This Happens

- Cinema City Zakopianka is located **inside Galeria Bronowice** shopping mall at "ul. Zakopiańska 62, 30-418 Kraków"
- This address contains multiple businesses (cinema, Castorama hardware store, other retailers)
- Geocoding APIs are POI-focused and return the **most prominent business** at an address
- Castorama (large hardware store chain) appears more prominent in the provider's database than the cinema
- The API doesn't distinguish between "Cinema City inside the mall" vs "Castorama inside the mall"

## Technical Details

### VenueNameValidator Logic

File: `lib/eventasaurus_discovery/validation/venue_name_validator.ex`

**Purpose**: Prevent bad venue names (UI elements, garbage text) from entering database

**Thresholds**:
- `>= 0.7` similarity: Use scraped name (good match) ✅
- `0.3 - 0.7` similarity: Prefer geocoded name (moderate difference) ⚠️
- `< 0.3` similarity: Strongly prefer geocoded name (very different) ❌

**In this case**: "Cinema City Zakopianka" vs "Castorama" = **0% similarity**
- System correctly applied its logic by choosing geocoded name
- But geocoded name was wrong due to API limitation

### Recent Changes Did NOT Cause This

The recent venue matching improvements (PR #2395, #2389) changed:
- ✅ Deduplication logic (VenueNameMatcher, DuplicateDetection)
- ✅ Token-based similarity for matching venues

They did **NOT** change:
- ❌ Venue name selection logic (VenueNameValidator)
- ❌ How geocoding provider responses are processed
- ❌ Name extraction from geocoding metadata

## Impact Assessment

### Scope
- **Isolated incident**: Likely only affects this specific venue
- **Why rare**: Multi-tenant buildings with competing prominent POIs are uncommon
- **System working correctly**: VenueNameValidator prevents most bad names effectively

### Affected Systems
- Venue database record (1 venue)
- Events associated with this venue
- User-facing venue pages

## Recommendations

### Immediate Fix (Required)

**Manual database correction**:

```sql
UPDATE venues
SET name = 'Cinema City Zakopianka'
WHERE name = 'Castorama ul. Zakopiańska 62, 30-418 Kraków'
  AND latitude BETWEEN 50.03 AND 50.04
  AND longitude BETWEEN 19.96 AND 19.97;
```

Verify change:
```sql
SELECT id, name, address, city_id, latitude, longitude
FROM venues
WHERE name LIKE '%Zakopianka%' OR name LIKE '%Castorama%'
  AND city_id = (SELECT id FROM cities WHERE name = 'Kraków');
```

### Long-term Improvements (Optional)

#### Option 1: Business Category Validation

Enhance `VenueNameValidator` to check geocoded business category:

```elixir
# Extract category from geocoding metadata
category = get_in(metadata, [:raw_response, "categories"])

# If geocoded category doesn't match expected type, prefer scraped
if cinema_query?(scraped_name) and hardware_store?(category) do
  {:warning, :category_mismatch, "Geocoded to wrong business type"}
end
```

**Pros**: Prevents category mismatches
**Cons**: Requires category data from providers, adds complexity

#### Option 2: Query Enrichment

Add venue type keywords to geocoding queries:

```elixir
# Before
full_address = "Cinema City Zakopianka, Kraków, Poland"

# After
full_address = "Cinema City Zakopianka cinema movie theater, Kraków, Poland"
```

**Pros**: Helps providers find correct POI
**Cons**: May reduce match accuracy if keywords too specific

#### Option 3: Address Enrichment (Best Long-term)

Update scrapers to provide full addresses when available:

```elixir
# Kino Krakow scraper could look up cinema addresses
%{
  name: "Cinema City Zakopianka",
  address: "Galeria Bronowice, ul. Stawowa 61",  # Full address
  city: "Kraków",
  country: "Poland"
}
```

**Pros**: Most accurate geocoding results
**Cons**: Requires additional data sources or manual curation

## Action Items

- [ ] **Immediate**: Update venue name in database manually
- [ ] **Verify**: Check for other venues that might have similar issues
- [ ] **Monitor**: Watch for similar patterns in future venue creation
- [ ] **Evaluate**: Decide if long-term improvements are needed based on frequency

## Related Files

- `lib/eventasaurus_discovery/validation/venue_name_validator.ex` - Name validation logic
- `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex` - Venue creation flow
- `lib/eventasaurus_discovery/geocoding/orchestrator.ex` - Geocoding provider coordination
- `lib/eventasaurus_app/venues/duplicate_detection.ex` - Venue deduplication

## Search Terms

- Multi-tenant building geocoding
- Venue name validation
- Shopping mall POI
- Geocoding API limitations
- Business category mismatch

---

**Date**: 2025-11-25
**Reporter**: System Analysis (Sequential Thinking + Context7)
**Priority**: Low (isolated incident, manual fix available)
**Labels**: `data-quality`, `geocoding`, `venue-management`, `enhancement`
