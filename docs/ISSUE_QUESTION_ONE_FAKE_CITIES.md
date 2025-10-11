# CRITICAL: QuestionOne Creating 109 Fake Cities with Embedded Postcodes

**Severity:** 🔴 **CRITICAL** - Database pollution despite validation layers
**Status:** OPEN - Requires immediate fix
**Created:** 2025-10-11
**Discovered:** User report - http://localhost:4000/c/england-e5-8nn/trivia/question-one

---

## Problem Summary

QuestionOne scraper has created **109 fake cities** with embedded UK postcodes in their names, such as:
- "England E5 8NN"
- "London England W1F 8PU"
- "Cambridge England CB2 3AR"
- "Wembley England HA9 0HP"

This represents a **complete failure** of both validation layers:
- ❌ **Layer 1 (Transformer validation)** - Failed to detect embedded postcodes
- ❌ **Layer 2 (VenueProcessor safety net)** - Failed to detect embedded postcodes
- ❌ **Defense-in-depth architecture** - Both layers had the same blind spot

---

## Root Cause Analysis

### 1. CityResolver Validation Flaw

**File:** `lib/eventasaurus_discovery/helpers/city_resolver.ex`
**Line:** ~167

**Current regex (BROKEN):**
```elixir
# UK postcode pattern (e.g., "SW18 2SS", "E1 6AN")
Regex.match?(~r/^[A-Z]{1,2}\d{1,2}[A-Z]?\s*\d[A-Z]{2}$/i, trimmed) ->
  {:error, :postcode_pattern}
```

**Problem:** The `^` and `$` anchors mean this ONLY catches pure postcodes:
- ✅ "E5 8NN" → REJECTED (correct)
- ❌ "England E5 8NN" → ACCEPTED (bug!)
- ❌ "London England W1F 8PU" → ACCEPTED (bug!)

**Why this is catastrophic:**
- CityResolver is used by BOTH Layer 1 (transformers) and Layer 2 (VenueProcessor)
- Both layers have the exact same blind spot
- Defense-in-depth architecture completely failed
- No safety net caught the bad data

### 2. QuestionOne Address Parsing Flaw

**File:** `lib/eventasaurus_discovery/sources/question_one/jobs/venue_detail_job.ex`
**Lines:** 98-123

**Current logic (NAIVE):**
```elixir
defp parse_uk_address(address) when is_binary(address) do
  parts = String.split(address, ",") |> Enum.map(&String.trim/1)

  case parts do
    # 4+ parts: venue, street, city, postcode[, extras]
    [_venue, _street, city_candidate, _postcode | _rest] ->
      validate_and_return_city(city_candidate)  # Takes index 2 blindly

    # 3 parts: street, city, postcode
    [_street, city_candidate, _postcode] ->
      validate_and_return_city(city_candidate)  # Takes index 1 blindly
```

**Problem:** Uses fixed index positions assuming consistent address format
- Assumes: "Venue, Street, City, Postcode"
- Reality: UK addresses are highly variable in format

**Example failure:**
Address: "Pub Name, London England W1F 8PU"
- Split: ["Pub Name", "London England W1F 8PU"]
- 2 parts case
- Second part doesn't match pure postcode regex (has "London England" prefix)
- Falls through to... wait, let me check the 2-part case...

Actually, looking at the code, the 2-part case checks if the second part is a postcode:
```elixir
[city_candidate, postcode_candidate] ->
  if String.match?(postcode_candidate, ~r/^[A-Z]{1,2}\d{1,2}[A-Z]?\s*\d[A-Z]{2}$/i) do
    validate_and_return_city(city_candidate)
  else
    {:error, "Cannot determine city from 2-part address"}
  end
```

So "London England W1F 8PU" doesn't match the pure postcode pattern, so it returns error and city becomes nil.

**So where do these fake cities come from?**

Most likely from 3-part addresses like:
- "Venue Name, England E5 8NN, Extra"
- Split: ["Venue Name", "England E5 8NN", "Extra"]
- Takes index 1 = "England E5 8NN"
- Validates through CityResolver
- CityResolver ACCEPTS it (because it doesn't start with the postcode pattern)
- Fake city created

---

## Database Impact

### Query Results

```sql
SELECT COUNT(*) as total_fake_cities
FROM cities
WHERE name ~* '[A-Z]{1,2}[0-9]{1,2}[A-Z]?\s*[0-9][A-Z]{2}';
```
**Result:** **109 fake cities**

### Sample Fake Cities

| City Name | Venues Affected |
|-----------|----------------|
| England W5 5DB | 1 |
| England E14 7HG | 1 |
| Cambridge England CB2 3AR | 1 |
| Wembley England HA9 0HP | 1 |
| St Albans England AL1 1NG | 1 |
| London England W1F 8PU | 1 |
| London England SE11 5AW | 1 |
| England E5 8NN | 1 |
| ... (101 more) | ... |

**Total venues affected:** 109 (one per fake city)

---

## Why Validation Failed

### Issue #1638 Validation Was Insufficient

The Phase 1 validation queries from `ISSUE_1638_VALIDATION_PLAN.md` only checked for:

```sql
-- Query 1: UK Postcodes (ANCHORED - only catches pure postcodes)
WHERE c.name ~* '^[A-Z]{1,2}[0-9]{1,2}[A-Z]?\s*[0-9][A-Z]{2}$'
```

This missed cities with **embedded** postcodes because:
- `^` requires the pattern to be at the START
- `$` requires the pattern to be at the END
- "England E5 8NN" doesn't start OR end with just the postcode

**The validation was too narrow** - it only caught pure postcodes, not "Location + Postcode" combinations.

---

## Fix Strategy

### Phase 1: Update CityResolver Validation (CRITICAL)

**File:** `lib/eventasaurus_discovery/helpers/city_resolver.ex`
**Line:** ~167

**Change:**
```elixir
# BEFORE (broken - anchored)
Regex.match?(~r/^[A-Z]{1,2}\d{1,2}[A-Z]?\s*\d[A-Z]{2}$/i, trimmed) ->
  {:error, :postcode_pattern}

# AFTER (fixed - unanchored, detects anywhere)
Regex.match?(~r/[A-Z]{1,2}\d{1,2}[A-Z]?\s*\d[A-Z]{2}/i, trimmed) ->
  {:error, :contains_postcode}
```

**Impact:**
- ✅ "E5 8NN" → REJECTED (still works)
- ✅ "England E5 8NN" → REJECTED (now caught!)
- ✅ "London England W1F 8PU" → REJECTED (now caught!)
- ✅ "Cambridge CB2 3AR" → REJECTED (now caught!)

### Phase 2: Improve QuestionOne Address Parsing

**File:** `lib/eventasaurus_discovery/sources/question_one/jobs/venue_detail_job.ex`

**Strategy:** Instead of using fixed index positions, intelligently find the city:

```elixir
defp parse_uk_address(address) when is_binary(address) do
  parts = String.split(address, ",") |> Enum.map(&String.trim/1)

  case parts do
    parts when length(parts) >= 2 ->
      # Strategy: Find the postcode part, then take the part BEFORE it as city
      postcode_index = Enum.find_index(parts, fn part ->
        String.match?(part, ~r/^[A-Z]{1,2}\d{1,2}[A-Z]?\s*\d[A-Z]{2}$/i)
      end)

      city_candidate = cond do
        # Found a postcode and there's a part before it
        postcode_index && postcode_index > 0 ->
          Enum.at(parts, postcode_index - 1)

        # No clear postcode, try second-to-last part
        length(parts) >= 2 ->
          Enum.at(parts, -2)

        # Fallback to first part
        true ->
          Enum.at(parts, 0)
      end

      # Validate the candidate - will now catch embedded postcodes
      validate_and_return_city(city_candidate)

    # Single part address - can't extract city
    _ ->
      {:error, "Address format not recognized"}
  end
end
```

**Alternative approach (even safer):**
Try each part through CityResolver validation until one passes:

```elixir
defp parse_uk_address(address) when is_binary(address) do
  parts = String.split(address, ",") |> Enum.map(&String.trim/1)

  # Remove the postcode part(s)
  non_postcode_parts = Enum.reject(parts, fn part ->
    String.match?(part, ~r/^[A-Z]{1,2}\d{1,2}[A-Z]?\s*\d[A-Z]{2}$/i)
  end)

  # Try each remaining part, starting from the end (cities usually near end)
  city_candidate = Enum.reverse(non_postcode_parts)
    |> Enum.find(fn part ->
      case CityResolver.validate_city_name(part) do
        {:ok, _} -> true
        {:error, _} -> false
      end
    end)

  case city_candidate do
    nil -> {:error, "No valid city found in address"}
    city -> validate_and_return_city(city)
  end
end
```

### Phase 3: Database Cleanup

**Query to identify all affected cities:**
```sql
SELECT c.id, c.name, co.name as country, COUNT(v.id) as venue_count
FROM cities c
JOIN countries co ON c.country_id = co.id
LEFT JOIN venues v ON v.city_id = c.id
WHERE c.name ~* '[A-Z]{1,2}[0-9]{1,2}[A-Z]?\s*[0-9][A-Z]{2}'
GROUP BY c.id, c.name, co.name
ORDER BY venue_count DESC;
```

**Cleanup strategy:**

**Option A: Delete fake cities (will NULL venue.city_id)**
```sql
-- First, check if we have ON DELETE SET NULL constraint
-- If not, manually set venues to NULL first
UPDATE venues SET city_id = NULL
WHERE city_id IN (
  SELECT id FROM cities
  WHERE name ~* '[A-Z]{1,2}[0-9]{1,2}[A-Z]?\s*[0-9][A-Z]{2}'
);

-- Then delete fake cities
DELETE FROM cities
WHERE name ~* '[A-Z]{1,2}[0-9]{1,2}[A-Z]?\s*[0-9][A-Z]{2}';
```

**Option B: Try to fix cities before deleting**
For cities like "London England W1F 8PU", we could extract "London":
```sql
-- This would require a migration script to parse and fix
-- More complex but preserves venue-city relationships
```

**Recommendation:** Use Option A (delete), then re-scrape QuestionOne with fixed validation.

### Phase 4: Re-scrape QuestionOne

After fixes:
1. Clear all QuestionOne events and venues
2. Re-run QuestionOne scraper
3. Verify no fake cities created
4. Check city coverage is still 100%

### Phase 5: Add Test Cases

**File:** `test/eventasaurus_discovery/helpers/city_resolver_test.exs`

Add test cases for embedded postcodes:
```elixir
test "rejects city names with embedded UK postcodes" do
  invalid_cities = [
    "England E5 8NN",
    "London England W1F 8PU",
    "Cambridge England CB2 3AR",
    "Wembley England HA9 0HP",
    "St Albans AL1 1NG Extra",
    "City W5 5DB Location"
  ]

  for city <- invalid_cities do
    assert {:error, :contains_postcode} = CityResolver.validate_city_name(city),
           "Expected #{city} to be rejected"
  end
end

test "still rejects pure postcodes" do
  pure_postcodes = ["E5 8NN", "W1F 8PU", "CB2 3AR", "HA9 0HP"]

  for postcode <- pure_postcodes do
    assert {:error, :contains_postcode} = CityResolver.validate_city_name(postcode)
  end
end
```

**File:** `test/eventasaurus_discovery/sources/question_one/jobs/venue_detail_job_test.exs`

Add test cases for address parsing:
```elixir
test "extracts city correctly from various UK address formats" do
  test_cases = [
    {"Venue, Street, London, E5 8NN", "London"},
    {"Venue, London, E5 8NN", "London"},
    {"Venue, Cambridge, CB2 3AR", "Cambridge"},
    {"Venue, 123 Street, Wembley, HA9 0HP", "Wembley"}
  ]

  for {address, expected_city} <- test_cases do
    assert {:ok, {^expected_city, "United Kingdom"}} = parse_uk_address(address)
  end
end

test "rejects addresses with embedded postcodes in city position" do
  bad_addresses = [
    "Venue, England E5 8NN, Extra",
    "Venue, London England W1F 8PU"
  ]

  for address <- bad_addresses do
    case parse_uk_address(address) do
      {:error, _} -> assert true
      {:ok, {city, _}} -> assert false, "Should have rejected city: #{city}"
    end
  end
end
```

---

## Validation Updates

### Update ISSUE_1638_VALIDATION_PLAN.md

**Current Query 1 (insufficient):**
```sql
WHERE c.name ~* '^[A-Z]{1,2}[0-9]{1,2}[A-Z]?\s*[0-9][A-Z]{2}$'
```

**Updated Query 1 (catches embedded postcodes):**
```sql
WHERE c.name ~* '[A-Z]{1,2}[0-9]{1,2}[A-Z]?\s*[0-9][A-Z]{2}'
```

**Add new Query 1b:**
```sql
-- Detect cities with suspicious patterns (location + postcode)
SELECT c.id, c.name, co.name as country
FROM cities c
JOIN countries co ON c.country_id = co.id
WHERE c.name ~* '(england|london|birmingham|manchester|liverpool).*[A-Z]{1,2}[0-9]{1,2}'
   OR c.name ~* '[0-9]{1,2}[A-Z]{2}.*england'
LIMIT 20;
```

---

## Timeline

### Immediate (Today)
1. ✅ Document the issue (this file)
2. ✅ Update CityResolver.validate_city_name (remove anchors)
3. ✅ Add test cases for embedded postcodes
4. ✅ Run tests to verify fix (29 tests pass)

### Next (Tomorrow)
5. ⏳ Improve QuestionOne address parsing
6. ⏳ Add address parsing test cases
7. ⏳ Run tests to verify fix
8. ⏳ Update validation plan documentation

### Cleanup (After fixes verified)
9. ⏳ Delete 109 fake cities from database
10. ⏳ Verify venue relationships handled correctly
11. ⏳ Re-scrape QuestionOne (all 121 events)
12. ⏳ Verify new city coverage is 100%
13. ⏳ Verify no fake cities created

### Validation (Final)
14. ⏳ Run updated ISSUE_1638 validation queries
15. ⏳ Verify all queries return 0 rows
16. ⏳ Update ISSUE_1638_VALIDATION_RESULTS.md
17. ⏳ Close this issue

---

## Lessons Learned

### What Went Wrong

1. **Regex pattern was too specific**
   - Anchored regex only caught exact matches
   - Didn't consider substring/embedded patterns
   - No test cases for "Location + Postcode" combinations

2. **Validation queries were too narrow**
   - ISSUE_1638 validation used same anchored regex
   - Passed validation despite 109 fake cities existing
   - Need broader pattern matching in validation

3. **Defense-in-depth failed**
   - Both Layer 1 and Layer 2 used same CityResolver function
   - Both had the same blind spot
   - Not truly independent validation layers

4. **Insufficient test coverage**
   - No test cases for embedded postcodes
   - No test cases for variable UK address formats
   - No integration tests catching the actual data

### How to Prevent This

1. **Use unanchored regex for detection**
   - Check for patterns ANYWHERE in string, not just start/end
   - `~r/[A-Z]{2}\d{2}/` not `~r/^[A-Z]{2}\d{2}$/`

2. **Make validation layers truly independent**
   - Layer 1: Specific pattern matching (transformer logic)
   - Layer 2: Different validation approach (statistical, AI-based, or database lookup)
   - Don't use the same function in both layers

3. **Comprehensive test cases**
   - Test edge cases and combinations
   - Test real-world data patterns
   - Add integration tests with actual scraper data

4. **Better validation queries**
   - Use broad pattern matching
   - Check for suspicious combinations
   - Visual inspection of random samples

5. **Staged rollout**
   - Test new scrapers with small data sets first
   - Manual review of first 50-100 cities created
   - Gradual rollout to full dataset

---

## References

- **Original issue:** #1638 - A-grade city resolution
- **Validation plan:** `docs/ISSUE_1638_VALIDATION_PLAN.md`
- **Validation results:** `docs/ISSUE_1638_VALIDATION_RESULTS.md` (INVALID - missed 109 fake cities)
- **User report:** http://localhost:4000/c/england-e5-8nn/trivia/question-one

---

## Next Steps

**IMMEDIATE ACTION REQUIRED:**
1. Fix CityResolver regex (remove anchors)
2. Add test cases
3. Verify fix catches embedded postcodes
4. Clean database
5. Re-scrape QuestionOne

**This issue BLOCKS closing #1638 until resolved.**
