# CityResolver Architecture Audit

**Date:** 2025-10-10
**Issue:** #1637
**Auditor:** Claude (Sequential Thinking Analysis)

---

## Executive Summary

Architectural audit of the CityResolver migration strategy reveals the approach is **fundamentally sound but architecturally incomplete**. We've been implementing validation at the transformer level (4/8 scrapers complete), but discovered that `VenueProcessor` - the central processing component where ALL venue data flows - lacks validation entirely.

**Recommendation:** Implement a **defense in depth** strategy with validation at BOTH layers:
1. **Layer 1 (Transformers)**: Source-specific validation ← *Current work, continue*
2. **Layer 2 (VenueProcessor)**: Safety net at system boundary ← *Missing, high priority*

**Grade:** Current approach: B- | Recommended hybrid approach: A

---

## Problem Statement

### Original Issue (#1631)
25% of cities in database (51/201) contain garbage data:
- UK/US postcodes: "SW18 2SS", "90210"
- Street addresses: "13 Bollo Lane", "76 Narrow Street"
- Venue names: "The Rose and Crown Pub"
- Numeric values: "12345", "999"

### Root Cause Analysis

**Immediate cause:** Naive string parsing in transformers extracting 2nd element of comma-split addresses without validation.

**Systemic cause:** `VenueProcessor.create_city()` accepts ANY string without validation:

```elixir
# lib/eventasaurus_discovery/scraping/processors/venue_processor.ex:381-388
defp create_city(name, country, data) do
  attrs = %{
    name: name,  # ❌ NO VALIDATION - this is where garbage enters database!
    slug: Normalizer.create_slug(name),
    country_id: country.id,
    latitude: data[:latitude],
    longitude: data[:longitude]
  }
  # ... direct database insertion
```

**Critical discovery:** VenueProcessor is the SINGLE POINT where all venue data flows before database insertion, yet it performs NO validation on city names.

---

## Architecture Analysis

### Data Flow

```
Scraper API
    ↓
Transformer (transforms source-specific format to unified format)
    ↓
VenueProcessor.process_venue_data() ← YOU ARE HERE (no validation!)
    ↓
VenueProcessor.normalize_venue_data() (passes city_name through directly)
    ↓
VenueProcessor.find_or_create_city()
    ↓
VenueProcessor.create_city() ← GARBAGE ENTERS DATABASE HERE
    ↓
Database (cities table polluted)
```

### Current Implementation (Phase 4)

**Completed migrations (4/8):**
- ✅ GeeksWhoDrink (Phase 2)
- ✅ BandsInTown (Phase 4)
- ✅ Ticketmaster (Phase 4)
- ✅ QuestionOne (Phase 4)

**Pattern applied:**
```elixir
# Each transformer adds:
alias EventasaurusDiscovery.Helpers.CityResolver

def resolve_location(latitude, longitude, api_city, known_country) do
  case CityResolver.resolve_city(latitude, longitude) do
    {:ok, city_name} -> {city_name, known_country}
    {:error, _} -> validate_api_city(api_city, known_country)
  end
end

defp validate_api_city(api_city, known_country) do
  case CityResolver.validate_city_name(api_city) do
    {:ok, validated} -> {validated, known_country}
    {:error, _} -> {nil, known_country}  # Prefer nil over garbage
  end
end
```

**Issues with transformer-only approach:**
1. ❌ Code duplication across 8 transformers
2. ❌ Requires manual migration of each scraper
3. ❌ Relies on developers remembering validation for new scrapers
4. ❌ Cannot guarantee all scrapers validate (human error risk)
5. ❌ Database pollution still POSSIBLE if transformer forgets validation

---

## Architectural Evaluation

### Approach 1: Transformer-Only Validation (Current)

**Pros:**
- ✅ Transformer has most context about data source
- ✅ Can provide source-specific fallback logic (UK vs US addresses)
- ✅ Validation happens early (fail fast principle)
- ✅ Source-specific logging and error handling

**Cons:**
- ❌ Code duplication across scrapers
- ❌ Requires manual migration (8 scrapers)
- ❌ Cannot prevent future pollution (new scrapers)
- ❌ Human error risk (developer forgets validation)

**Grade:** B- (solves immediate problem but not systemic)

---

### Approach 2: VenueProcessor-Only Validation (Considered but rejected)

**Pros:**
- ✅ Single point of validation (DRY)
- ✅ All scrapers benefit automatically
- ✅ Impossible to pollute database
- ✅ New scrapers automatically protected

**Cons:**
- ❌ VenueProcessor lacks source-specific context
- ❌ Cannot do smart fallbacks (UK vs US addresses)
- ❌ Wastes transformer work already completed
- ❌ Validation happens late in pipeline

**Grade:** C+ (prevents pollution but loses context and quality)

---

### Approach 3: Hybrid Defense in Depth (RECOMMENDED)

**Implementation:**

**Layer 1 - Transformers** (source-specific validation):
```elixir
# Each transformer continues to use CityResolver
def resolve_location(latitude, longitude, api_city, known_country) do
  case CityResolver.resolve_city(latitude, longitude) do
    {:ok, city_name} ->
      # Best quality - offline geocoding from coordinates
      {city_name, known_country}

    {:error, _} ->
      # Fallback - validate API city name
      validate_api_city(api_city, known_country)
  end
end
```

**Layer 2 - VenueProcessor** (safety net validation):
```elixir
defp create_city(name, country, data) when is_binary(name) do
  # SAFETY NET: Validate city name BEFORE database insertion
  case CityResolver.validate_city_name(name) do
    {:ok, validated_name} ->
      # Valid city name - proceed with creation
      attrs = %{
        name: validated_name,
        slug: Normalizer.create_slug(validated_name),
        country_id: country.id,
        latitude: data[:latitude],
        longitude: data[:longitude]
      }

      case %City{} |> City.changeset(attrs) |> Repo.insert() do
        {:ok, city} ->
          city

        {:error, changeset} ->
          Logger.warning("Failed to create city #{validated_name}: #{inspect(changeset.errors)}")
          # Existing fallback logic for duplicate handling...
      end

    {:error, reason} ->
      # REJECT garbage (postcodes, street addresses, numeric values)
      Logger.error("""
      ❌ REJECTED invalid city name: #{inspect(name)}
      Reason: #{reason}
      Source must provide valid city name or nil.
      """)
      nil  # Causes event creation to fail - this is correct behavior
  end
end

# Allow nil cities - better to have event without city than pollute database
defp create_city(nil, _country, _data), do: nil
```

**Pros:**
- ✅ Best quality city names (Layer 1 source-specific handling)
- ✅ Impossible to pollute database (Layer 2 safety net)
- ✅ Future scrapers automatically protected (Layer 2)
- ✅ Transformer work not wasted (provides quality, Layer 1)
- ✅ Defense in depth (security architecture pattern)
- ✅ Fail safe system (even buggy transformers can't pollute)

**Cons:**
- Minor: Adds ~30 lines to VenueProcessor (one-time cost)

**Grade:** A (solves both immediate and systemic problems)

---

## Grading Summary

| Criterion | Transformer-Only | VenueProcessor-Only | Hybrid (Recommended) |
|-----------|-----------------|---------------------|---------------------|
| **Correctness** | B+ | B+ | A |
| **Maintainability** | C | B+ | B+ |
| **Robustness** | B- | A | A |
| **Performance** | A | A | A |
| **Architecture** | C+ | B | A- |
| **Data Quality** | B+ | C | A |
| **Future-Proof** | C | A | A |
| **Overall** | **B-** | **B** | **A** |

---

## Recommendation

### Immediate Actions (High Priority)

1. **Add VenueProcessor safety net** (Issue #1637)
   - Modify `VenueProcessor.create_city/3` to validate city names
   - Add `alias EventasaurusDiscovery.Helpers.CityResolver`
   - Reject invalid cities (postcodes, addresses, numeric values)
   - Allow `nil` cities (prefer missing data over garbage)
   - Add comprehensive tests

2. **Verify no regressions**
   - Run existing tests
   - Verify 4 migrated scrapers still work
   - Check that events with valid cities are created
   - Check that events with garbage cities are rejected

### Follow-Up Actions (Medium Priority)

3. **Complete remaining transformer migrations**
   - ResidentAdvisor (replace Google Places with CityResolver)
   - CinemaCity (conditional based on coordinates)
   - Karnet (needs geocoding first)
   - KinoKrakow (needs geocoding first)

4. **Update documentation**
   - CITY_RESOLVER_MIGRATION_GUIDE.md (explain hybrid approach)
   - SCRAPER_MANIFESTO.md (add VenueProcessor safety net requirement)

---

## Technical Rationale

### Why Defense in Depth?

This is a classic **security architecture pattern** applied to data quality:

1. **Multiple Layers of Defense**: If one layer fails (transformer forgets validation), the next layer catches it (VenueProcessor validates)

2. **Fail Safe Design**: System is designed so that even with bugs/mistakes, the database cannot be polluted

3. **Principle of Least Privilege**: Transformers can *suggest* city names, but VenueProcessor has *authority* to accept/reject

4. **Single Point of Enforcement**: VenueProcessor is the system boundary - perfect place for final validation

### Why Both Layers Matter

- **Without Layer 1 (Transformers)**: VenueProcessor has no source context, cannot do smart fallbacks, lower data quality

- **Without Layer 2 (VenueProcessor)**: Database pollution possible if transformer forgets validation, no systematic guarantee

- **With Both Layers**: Optimal data quality from transformers + systematic protection from VenueProcessor

### Comparison to Similar Patterns

This is analogous to:
- **Input validation** (client-side) + **server-side validation** (backend)
- **TypeScript types** (compile-time) + **runtime validation** (Zod/Yup)
- **Firewall** (network) + **SELinux** (kernel)

---

## Test Strategy

### VenueProcessor Safety Net Tests

```elixir
defmodule EventasaurusDiscovery.Scraping.Processors.VenueProcessorTest do
  describe "create_city/3 validation" do
    test "rejects UK postcodes" do
      assert create_city("SW18 2SS", country, %{}) == nil
    end

    test "rejects US ZIP codes" do
      assert create_city("90210", country, %{}) == nil
    end

    test "rejects street addresses" do
      assert create_city("13 Bollo Lane", country, %{}) == nil
      assert create_city("76 Narrow Street", country, %{}) == nil
    end

    test "rejects numeric values" do
      assert create_city("12345", country, %{}) == nil
    end

    test "accepts valid city names" do
      assert %City{name: "London"} = create_city("London", country, %{})
      assert %City{name: "New York"} = create_city("New York", country, %{})
    end

    test "allows nil city names" do
      assert create_city(nil, country, %{}) == nil
    end

    test "logs rejection with reason" do
      # Verify error logging includes validation failure reason
    end
  end
end
```

### Integration Tests

```elixir
describe "end-to-end venue processing with validation" do
  test "rejects events with invalid city names" do
    venue_data = %{
      name: "Test Venue",
      city: "SW18 2SS",  # Invalid postcode
      country: "United Kingdom",
      latitude: 51.5,
      longitude: -0.1
    }

    assert {:error, _} = VenueProcessor.process_venue_data(venue_data, source)
  end

  test "creates events with valid city names" do
    venue_data = %{
      name: "Test Venue",
      city: "London",  # Valid city
      country: "United Kingdom",
      latitude: 51.5,
      longitude: -0.1
    }

    assert {:ok, venue} = VenueProcessor.process_venue_data(venue_data, source)
    assert venue.city.name == "London"
  end

  test "creates events with nil city names" do
    venue_data = %{
      name: "Test Venue",
      city: nil,  # Allowed
      country: "United Kingdom",
      latitude: 51.5,
      longitude: -0.1
    }

    assert {:ok, venue} = VenueProcessor.process_venue_data(venue_data, source)
    assert is_nil(venue.city_id)
  end
end
```

---

## Migration Path

### Phase 5A: Add VenueProcessor Safety Net (This Issue)

**Estimated effort:** 2-3 hours

**Files to modify:**
- `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex`
  - Add `alias EventasaurusDiscovery.Helpers.CityResolver` (line ~8)
  - Update `create_city/3` function (lines 381-416)
  - Add `create_city/3` clause for nil handling

- `test/eventasaurus_discovery/scraping/processors/venue_processor_test.exs`
  - Add validation test suite (~50 lines)

**Testing:**
1. Run full test suite
2. Verify 4 migrated scrapers still work
3. Manually test with known garbage city names
4. Check database for new pollution (should be zero)

### Phase 5B: Complete Remaining Migrations (Future)

**Estimated effort:** 4-6 hours total

- ResidentAdvisor: 1-2 hours
- CinemaCity: 1 hour (conditional)
- Karnet: 1-2 hours (geocoding needed)
- KinoKrakow: 1-2 hours (geocoding needed)

---

## Conclusion

The CityResolver migration strategy is **fundamentally correct** - we've identified the right solution (offline geocoding with validation). However, we applied it at only ONE layer (transformers) when the architecture requires TWO layers (transformers + VenueProcessor).

**The work completed is NOT wasted** - transformer migrations provide high-quality, source-specific city resolution. But we need the VenueProcessor safety net to make the system bulletproof against future pollution.

**This is a textbook example of "defense in depth"** - multiple layers of protection ensure that even if one layer fails, the system remains secure.

**Recommendation: Implement hybrid approach immediately** - add VenueProcessor safety net (Phase 5A), then complete remaining transformer migrations (Phase 5B) at a more leisurely pace.

---

## Related Documentation

- [CITY_RESOLVER_MIGRATION_GUIDE.md](./CITY_RESOLVER_MIGRATION_GUIDE.md) - Step-by-step migration instructions
- [SCRAPER_MANIFESTO.md](./SCRAPER_MANIFESTO.md) - Geocoding & city resolution strategy
- Issue #1631 - Original city pollution problem
- Issue #1637 - VenueProcessor safety net implementation (this audit)

---

**Questions or concerns?** Discuss on issue #1637 or Slack #engineering.
