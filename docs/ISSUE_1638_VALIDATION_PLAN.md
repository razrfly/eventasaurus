# Issue #1638 Validation Plan - A-Grade City Resolution

**Purpose:** Comprehensive validation of city resolution improvements across all scrapers and VenueProcessor Layer 2 safety net.

**Context:** After implementing A-grade city resolution for 5 scrapers and VenueProcessor validation, we need to verify:
1. No invalid cities exist in database (postcodes, street addresses, numeric values)
2. VenueProcessor Layer 2 safety net is working
3. All A-grade scrapers are functioning correctly
4. Documentation is accurate and consistent

---

## Phase 1: Database Validation (Critical)

**Goal:** Verify ZERO invalid cities exist in database

### Query 1: Detect UK Postcodes
```sql
-- Should return 0 rows if validation is working
SELECT c.id, c.name, co.name as country
FROM cities c
JOIN countries co ON c.country_id = co.id
WHERE c.name ~* '^[A-Z]{1,2}[0-9]{1,2}[A-Z]?\s*[0-9][A-Z]{2}$'
LIMIT 20;
```
**Expected:** 0 rows
**Examples of invalid:** "SW18 2SS", "E1 6AN", "W1F 7BG"

### Query 2: Detect Pure Numeric (ZIP codes, numbers)
```sql
-- Should return 0 rows if validation is working
SELECT c.id, c.name, co.name as country
FROM cities c
JOIN countries co ON c.country_id = co.id
WHERE c.name ~* '^[0-9]+$'
LIMIT 20;
```
**Expected:** 0 rows
**Examples of invalid:** "90210", "10001", "12345"

### Query 3: Detect Street Addresses
```sql
-- Should return 0 rows if validation is working
SELECT c.id, c.name, co.name as country
FROM cities c
JOIN countries co ON c.country_id = co.id
WHERE c.name ~* '^[0-9]+\s+.*(street|road|avenue|lane|drive|way|court|place|boulevard|st|rd|ave|ln|dr|blvd)'
LIMIT 20;
```
**Expected:** 0 rows
**Examples of invalid:** "123 Main Street", "76 Narrow Street", "13 Bollo Lane"

### Query 4: Detect Empty or Single Character
```sql
-- Should return 0 rows if validation is working
SELECT c.id, c.name, co.name as country
FROM cities c
JOIN countries co ON c.country_id = co.id
WHERE LENGTH(TRIM(c.name)) <= 1 OR TRIM(c.name) = ''
LIMIT 20;
```
**Expected:** 0 rows
**Examples of invalid:** "", " ", "A", "1"

### Query 5: Detect Venue-like Names
```sql
-- Should return 0 rows if validation is working
SELECT c.id, c.name, co.name as country
FROM cities c
JOIN countries co ON c.country_id = co.id
WHERE c.name ~* '\b(bar|pub|restaurant|cafe|hotel|inn|club|tavern|lounge)\b'
LIMIT 20;
```
**Expected:** 0 rows
**Examples of invalid:** "The Blue Bar", "Rose Crown", "Red Lion Inn"

### ✅ Success Criteria Phase 1
- **ALL 5 queries return 0 rows**
- If any query returns rows: VenueProcessor Layer 2 safety net failed

---

## Phase 2: Data Quality Assessment

### Query 6: Venue Distribution by Source
```sql
-- Check venue/city stats per source
SELECT
  s.name as source,
  COUNT(DISTINCT v.id) as venue_count,
  COUNT(DISTINCT v.city_id) as cities_used,
  COUNT(DISTINCT CASE WHEN v.city_id IS NULL THEN v.id END) as venues_without_city,
  COUNT(DISTINCT CASE WHEN v.latitude IS NOT NULL THEN v.id END) as venues_with_gps,
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN v.city_id IS NOT NULL THEN v.id END) / NULLIF(COUNT(DISTINCT v.id), 0), 2) as city_coverage_pct
FROM venues v
JOIN sources s ON v.source_id = s.id
GROUP BY s.name
ORDER BY venue_count DESC;
```
**Expected:**
- A-grade scrapers (GeeksWhoDrink, Bandsintown, Ticketmaster, CinemaCity, ResidentAdvisor) should have >95% city_coverage_pct
- GPS coordinates should be present for most venues

### Query 7: Sample Venues from A-Grade Scrapers
```sql
-- Manual inspection of venue quality
SELECT
  s.name as source,
  v.name as venue_name,
  c.name as city_name,
  co.name as country_name,
  v.latitude,
  v.longitude
FROM venues v
LEFT JOIN cities c ON v.city_id = c.id
LEFT JOIN countries co ON c.country_id = co.id
JOIN sources s ON v.source_id = s.id
WHERE s.slug IN ('geeks-who-drink', 'bandsintown', 'ticketmaster', 'cinema-city', 'resident-advisor')
ORDER BY s.name, v.id
LIMIT 50;
```
**Manual Review:** Check that city names look legitimate (not postcodes, addresses, etc.)

### Query 8: Verify Special Characters Handled Correctly
```sql
-- Check cities with special characters and multi-word names
SELECT c.id, c.name, co.name as country
FROM cities c
JOIN countries co ON c.country_id = co.id
WHERE c.name ~ '[^A-Za-z0-9\s\-]'  -- Special characters
   OR c.name LIKE '% %'              -- Multi-word
ORDER BY c.name
LIMIT 20;
```
**Expected:** Legitimate cities with special chars (São Paulo, Kraków, New York)
**Should NOT see:** Postcodes, addresses, or garbage data

### Query 9: Verify City Coverage Matches Grade Claims
```sql
-- Verify A-grade scrapers have high city coverage
SELECT
  s.name as source,
  s.slug,
  COUNT(DISTINCT pe.id) as total_events,
  COUNT(DISTINCT CASE WHEN v.city_id IS NOT NULL THEN pe.id END) as events_with_city,
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN v.city_id IS NOT NULL THEN pe.id END) / NULLIF(COUNT(DISTINCT pe.id), 0), 2) as city_coverage_pct,
  COUNT(DISTINCT c.id) as unique_cities
FROM sources s
LEFT JOIN public_event_sources pes ON s.id = pes.source_id
LEFT JOIN public_events pe ON pes.event_id = pe.id
LEFT JOIN venues v ON pe.venue_id = v.id
LEFT JOIN cities c ON v.city_id = c.id
GROUP BY s.name, s.slug
ORDER BY total_events DESC;
```
**Expected:**
- GeeksWhoDrink: >95% city coverage
- Bandsintown: >95% city coverage
- Ticketmaster: >95% city coverage
- CinemaCity: >95% city coverage
- ResidentAdvisor: >95% city coverage

### ✅ Success Criteria Phase 2
- A-grade scrapers have >95% city coverage
- Sample venues look legitimate
- Special characters handled correctly
- No garbage data in manual inspection

---

## Phase 3: Log Analysis

### Search 1: VenueProcessor Rejections
```bash
# Search application logs for rejection messages
grep -i "VenueProcessor REJECTED" /path/to/logs/*.log
```
**Expected:** Some rejection logs (proves Layer 2 is working)
**Example:**
```
❌ VenueProcessor REJECTED invalid city name (Layer 2 safety net):
City name: "SW18 2SS"
Country: United Kingdom
Reason: Matches UK postcode pattern
```

### Search 2: CityResolver Validation Failures
```bash
# Search for city validation failures
grep -i "City name failed validation\|failed validation" /path/to/logs/*.log
```
**Expected:** Some validation warnings (system catching issues)

### Search 3: Geocoding Errors/Warnings
```bash
# Search for geocoding issues
grep -i "geocoding failed\|No city found for coordinates\|CityResolver" /path/to/logs/*.log
```
**Expected:** Some warnings (acceptable - shows fallback working)

### ✅ Success Criteria Phase 3
- VenueProcessor rejection logs exist (proves Layer 2 works)
- Validation warnings present (system is actively checking)
- No catastrophic geocoding failures

---

## Phase 4: Documentation Review

### Checklist: Documentation Consistency

**File 1: SCRAPER_MANIFESTO.md**
- [ ] Pattern 5 (ResidentAdvisor) documented with code example
- [ ] Grade summary table shows 5/9 scrapers at A-grade
- [ ] City Resolution Decision Tree is accurate
- [ ] Code examples compile and work

**File 2: CITY_RESOLVER_ARCHITECTURE_AUDIT.md**
- [ ] Audit reflects current state after implementation
- [ ] Grade assessments match actual scraper implementations
- [ ] Recommendations are still relevant or marked complete

**File 3: CITY_RESOLVER_MIGRATION_GUIDE.md**
- [ ] Migration patterns are accurate
- [ ] Code examples use correct functions (Logger.warning, not Logger.warn)
- [ ] Conservative fallback examples don't hardcode countries

**File 4: PHASE_4_COMPLETION_SUMMARY.md**
- [ ] ResidentAdvisor upgrade accurately documented
- [ ] Test results match actual implementation
- [ ] Grade claim (A-grade) matches Query 9 results

**File 5: PHASE_5_COMPLETION_SUMMARY.md**
- [ ] VenueProcessor Layer 2 implementation documented
- [ ] Defense-in-depth architecture explained
- [ ] Claims about database pollution prevention verified by Phase 1 queries

### ✅ Success Criteria Phase 4
- All documentation files are internally consistent
- Code examples are accurate and up-to-date
- Grade claims match implementation reality
- No contradictions between documents

---

## Final Validation Summary

### Overall Success Criteria

✅ **Phase 1 (Critical):** All 5 database queries return 0 rows (no invalid cities)
✅ **Phase 2:** A-grade scrapers have >95% city coverage with legitimate city names
✅ **Phase 3:** VenueProcessor rejection logs prove Layer 2 safety net is working
✅ **Phase 4:** Documentation is consistent and accurate

### If Any Phase Fails

**Phase 1 Failure (Invalid cities in database):**
- This is CRITICAL - VenueProcessor Layer 2 safety net failed
- Investigate which scraper created the bad data
- Check VenueProcessor.create_city/3 implementation
- Review CityResolver.validate_city_name/1 patterns

**Phase 2 Failure (Low city coverage):**
- Check transformer implementation for that scraper
- Review GPS coordinates availability
- Verify CityResolver.resolve_city/2 is being called
- Check for nil city fallback handling

**Phase 3 Failure (No rejection logs):**
- Either no bad data attempted (good) or Layer 2 not working (bad)
- Try running scrapers again to generate new data
- Check Logger configuration is working

**Phase 4 Failure (Documentation inconsistent):**
- Update docs to match actual implementation
- Fix code examples
- Reconcile grade claims with Query 9 results

---

## Quick Validation Commands

**Run all Phase 1 queries at once:**
```bash
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -f validation_queries_phase1.sql
```

**Run all Phase 2 queries at once:**
```bash
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -f validation_queries_phase2.sql
```

**Search all logs at once:**
```bash
grep -E "VenueProcessor REJECTED|City name failed validation|geocoding failed" /path/to/logs/*.log | tee log_analysis.txt
```

---

## Expected Timeline

- **Phase 1:** 5 minutes (run queries, verify 0 rows)
- **Phase 2:** 15 minutes (run queries, manual inspection)
- **Phase 3:** 10 minutes (search logs, analyze results)
- **Phase 4:** 15 minutes (review docs, check consistency)

**Total:** ~45 minutes for complete validation

---

## Post-Validation Actions

### If All Validations Pass ✅
1. Close issue #1638 with validation results
2. Create summary comment with Query 9 results (city coverage by scraper)
3. Archive validation plan for future reference

### If Any Validations Fail ❌
1. Document failure details
2. Create follow-up issue with specific problems found
3. Prioritize based on severity (Phase 1 failures are critical)
4. Re-run validation after fixes

---

## Notes

- Database has been dropped and reloaded, so all data is fresh
- All local scrapers have been run
- VenueProcessor Layer 2 should have caught any invalid city names
- This validation plan requires NO code changes
- All queries are read-only and safe to run on production database
