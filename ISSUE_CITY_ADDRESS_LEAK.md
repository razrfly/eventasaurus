# City Address Leak - Street Addresses Creating City Records

**Status:** 🔴 CRITICAL - Active Data Pollution
**Priority:** P0 - Immediate Fix Required
**Category:** Data Quality, Security, Validation
**Created:** 2025-01-05

---

## 🎯 Problem Statement

Street addresses are leaking into the `cities` table as if they were city names, polluting the database with invalid geographic data. This is a **regression** - we fixed this previously but the validation has holes.

### Evidence of Pollution

The following records exist in the cities table (they shouldn't):

| Invalid "City" Name | Country | Coordinates | What It Actually Is |
|---------------------|---------|-------------|---------------------|
| 10-16 Botchergate | United Kingdom | 54.8911, -2.9319 | Street address in Carlisle |
| 12 Derrys Cross | United Kingdom | 50.3702, -4.1465 | Street address in Plymouth |
| 1-3 Regent Street | United Kingdom | 51.9001, -2.0746 | Street address in Swindon |
| 168 Lower Briggate | United Kingdom | 53.7951, -1.5425 | Street address in Leeds |
| 17A Wallgate | United Kingdom | 53.5454, -2.6321 | Street address in Wigan |
| 23-26 High Street | United Kingdom | 50.7003, -1.2926 | Street address in Isle of Wight |
| 25-27 Mount Pleasant Road | United Kingdom | 53.4314, -3.0444 | Street address in Wirral |
| 33-35 Market Street | United Kingdom | 53.7608, -2.701 | Street address in Blackburn |
| 3-4 Northumberland Place | United Kingdom | 51.3824, -2.3595 | Street address in Bath |
| 39-40 Fore Bondgate | United Kingdom | 54.6653, -1.6771 | Street address in Bishop Auckland |
| 40 Bondgate | United Kingdom | 53.904, -1.6914 | Street address in Ripon |
| 425 Burwood Hwy | Australia | -37.8692, 145.2442 | Street address in Melbourne |
| 46-54 Collie St | Australia | -32.0572, 115.7458 | Street address in Perth |
| 48 Chapeltown | United Kingdom | 53.7922, -1.6721 | Street address in Leeds |
| 54-56 Whitegate Drive | United Kingdom | 53.8165, -3.0367 | Street address in Blackpool |
| 6-7 Cornhill | United Kingdom | 51.1281, -3.0036 | Street address in Bridgwater |
| 6C Christchurch Road | United Kingdom | 50.7221, -1.8651 | Street address in Bournemouth |
| 7-9 | United Kingdom | 51.304, 0.4771 | Incomplete street number |
| 7a Cotton Road | United Kingdom | 51.2743, 1.0678 | Street address in Canterbury |
| 8-9 Catalan Square | United Kingdom | 53.4749, -2.2562 | Street address in Manchester |
| 98 Highgate | United Kingdom | 54.3254, -2.7477 | Street address in Kendal |

**Pattern**: All start with numbers (street numbers), followed by UK/Australian street names that don't contain American keywords like "Street", "Road", "Avenue".

---

## 🔍 Root Cause Analysis

### Three Security Holes Identified

#### Hole #1: CityResolver Regex Too Narrow (US-Centric)

**Location**: `lib/eventasaurus_discovery/helpers/city_resolver.ex:169-174`

**Current Validation**:
```elixir
# Street address pattern (starts with number + contains street keywords)
Regex.match?(
  ~r/^\d+\s+.*(street|road|avenue|lane|drive|way|court|place|boulevard|st|rd|ave|ln|dr|blvd)/i,
  trimmed
) ->
  {:error, :street_address_pattern}
```

**Problem**:
- Only catches addresses with **American street keywords**: "Street", "Road", "Avenue", "Lane", "Drive", etc.
- Misses **UK street name suffixes**: "gate", "Cross", "Wharf", "Row", "Walk", "Wynd", "Mews", etc.
- Misses **Australian patterns**: "Hwy", "Parade", "Esplanade", "Crescent", etc.
- Misses **generic numeric patterns**: "7-9", "425 Burwood Hwy", "7a Cotton Road"

**Why This Fails**:
```
"168 Lower Briggate" - No "street/road/avenue" keyword → PASSES validation ❌
"10-16 Botchergate" - No "street/road/avenue" keyword → PASSES validation ❌
"425 Burwood Hwy" - "Hwy" not in keyword list → PASSES validation ❌
```

#### Hole #2: CityManager Bypasses Validation

**Location**: `lib/eventasaurus_discovery/admin/city_manager.ex:30-35`

**Current Code**:
```elixir
def create_city(attrs) do
  %City{}
  |> City.changeset(attrs)
  |> validate_country_exists(attrs)
  |> Repo.insert()
end
```

**Problem**:
- Goes **straight to `City.changeset`** without calling `CityResolver.validate_city_name`
- VenueProcessor has Layer 2 safety net (line 360: `CityResolver.validate_city_name`)
- CityManager completely bypasses this validation
- Admin UI and bulk imports use CityManager → validation skipped entirely

**Attack Vector**: Any admin creating a city manually or bulk imports will skip validation.

#### Hole #3: No Schema-Level Validation

**Location**: `lib/eventasaurus_discovery/locations/city.ex:27-42`

**Current Code**:
```elixir
def changeset(city, attrs) do
  city
  |> cast(attrs, [:name, :country_id, :latitude, ...])
  |> validate_required([:name, :country_id])
  |> Slug.maybe_generate_slug()
  |> foreign_key_constraint(:country_id)
  |> unique_constraint([:country_id, :slug])
end
```

**Problem**:
- Only validates that `name` exists (not nil)
- **No content validation** on what the name contains
- No defense in depth at the schema level

---

## 💡 Proposed Solution

### Fix #1: Universal Street Address Pattern (Language-Agnostic)

**Replace US-centric keyword matching with universal numeric-prefix detection:**

```elixir
# lib/eventasaurus_discovery/helpers/city_resolver.ex

# OLD (line 169-174):
Regex.match?(
  ~r/^\d+\s+.*(street|road|avenue|lane|drive|way|court|place|boulevard|st|rd|ave|ln|dr|blvd)/i,
  trimmed
) ->
  {:error, :street_address_pattern}

# NEW (simpler, universal):
# Street address pattern - ANY string starting with number + hyphen/space
# Catches all international street address formats regardless of language
Regex.match?(~r/^\d+[-\s]/, trimmed) ->
  {:error, :street_address_pattern}
```

**Why This Works**:
- ✅ Catches **ALL numeric-prefix addresses** regardless of country/language
- ✅ UK: "10-16 Botchergate", "168 Lower Briggate"
- ✅ US: "123 Main Street", "456 Oak Avenue"
- ✅ Australia: "425 Burwood Hwy", "46-54 Collie St"
- ✅ Number ranges: "7-9", "23-26 High Street"
- ✅ Letter suffixes: "7a Cotton Road", "17A Wallgate"

**What It Rejects**:
- `"10-16 Botchergate"` → Starts with number → ❌ Rejected
- `"425 Burwood Hwy"` → Starts with number → ❌ Rejected
- `"7-9"` → Starts with number → ❌ Rejected

**What It Allows** (valid cities):
- `"London"` → No numeric prefix → ✅ Allowed
- `"New York"` → No numeric prefix → ✅ Allowed
- `"São Paulo"` → No numeric prefix → ✅ Allowed

### Fix #2: Add Validation to CityManager

**Location**: `lib/eventasaurus_discovery/admin/city_manager.ex`

```elixir
# Add at top with other aliases (line 12):
alias EventasaurusDiscovery.Helpers.CityResolver

# Update create_city function (line 30):
def create_city(attrs) do
  # Layer 2 safety net: Validate city name BEFORE creating record
  case CityResolver.validate_city_name(attrs[:name] || attrs["name"]) do
    {:ok, validated_name} ->
      # City name is valid, proceed with creation
      attrs_with_validated_name = Map.put(attrs, :name, validated_name)

      %City{}
      |> City.changeset(attrs_with_validated_name)
      |> validate_country_exists(attrs_with_validated_name)
      |> Repo.insert()

    {:error, reason} ->
      # City name is invalid (postcode, street address, etc.)
      # Return changeset error for consistent API
      changeset =
        %City{}
        |> City.changeset(attrs)
        |> Ecto.Changeset.add_error(:name, "is invalid: #{reason}")

      {:error, changeset}
  end
end
```

### Fix #3: Schema-Level Validation (Defense in Depth)

**Location**: `lib/eventasaurus_discovery/locations/city.ex`

```elixir
# Add at top with other aliases (after line 7):
alias EventasaurusDiscovery.Helpers.CityResolver

# Update changeset function (line 27):
def changeset(city, attrs) do
  city
  |> cast(attrs, [:name, :country_id, :latitude, :longitude, :discovery_enabled, :discovery_config, :alternate_names])
  |> validate_required([:name, :country_id])
  |> validate_city_name_content()  # NEW: Layer 3 validation
  |> Slug.maybe_generate_slug()
  |> foreign_key_constraint(:country_id)
  |> unique_constraint([:country_id, :slug])
end

# Add new private function (after line 42):
# Layer 3 defense: Schema-level city name validation
# Prevents ANY path from creating invalid city records
defp validate_city_name_content(changeset) do
  case get_change(changeset, :name) do
    nil ->
      # No change to name, skip validation (for updates that don't touch name)
      changeset

    name ->
      # Validate city name content using CityResolver rules
      case CityResolver.validate_city_name(name) do
        {:ok, _validated_name} ->
          changeset

        {:error, reason} ->
          add_error(changeset, :name, "is invalid: #{reason}")
      end
  end
end
```

---

## 🧪 Testing Strategy

### Unit Tests for CityResolver

```elixir
# test/eventasaurus_discovery/helpers/city_resolver_test.exs

describe "validate_city_name/1 - international street addresses" do
  test "rejects UK street addresses without American keywords" do
    uk_addresses = [
      "10-16 Botchergate",
      "12 Derrys Cross",
      "168 Lower Briggate",
      "48 Chapeltown",
      "98 Highgate",
      "40 Bondgate",
      "6-7 Cornhill"
    ]

    for address <- uk_addresses do
      assert {:error, :street_address_pattern} = CityResolver.validate_city_name(address),
             "Expected UK address '#{address}' to be rejected"
    end
  end

  test "rejects Australian street addresses" do
    aus_addresses = [
      "425 Burwood Hwy",
      "46-54 Collie St"
    ]

    for address <- aus_addresses do
      assert {:error, :street_address_pattern} = CityResolver.validate_city_name(address),
             "Expected Australian address '#{address}' to be rejected"
    end
  end

  test "rejects street addresses with letter suffixes" do
    assert {:error, :street_address_pattern} = CityResolver.validate_city_name("7a Cotton Road")
    assert {:error, :street_address_pattern} = CityResolver.validate_city_name("17A Wallgate")
    assert {:error, :street_address_pattern} = CityResolver.validate_city_name("6C Christchurch Road")
  end

  test "rejects number ranges without full address" do
    assert {:error, :street_address_pattern} = CityResolver.validate_city_name("7-9")
    assert {:error, :street_address_pattern} = CityResolver.validate_city_name("23-26 High Street")
  end

  test "accepts valid city names without numeric prefixes" do
    valid_cities = [
      "London",
      "Manchester",
      "Sydney",
      "Melbourne",
      "New York",
      "Los Angeles"
    ]

    for city <- valid_cities do
      assert {:ok, ^city} = CityResolver.validate_city_name(city),
             "Expected city '#{city}' to be accepted"
    end
  end
end
```

### Integration Tests for CityManager

```elixir
# test/eventasaurus_discovery/admin/city_manager_test.exs

describe "create_city/1 validation" do
  setup do
    country = insert(:country, name: "United Kingdom", code: "GB")
    %{country: country}
  end

  test "rejects UK street addresses", %{country: country} do
    result = CityManager.create_city(%{
      name: "10-16 Botchergate",
      country_id: country.id,
      latitude: 54.8911,
      longitude: -2.9319
    })

    assert {:error, changeset} = result
    assert "is invalid" in errors_on(changeset).name
  end

  test "rejects Australian street addresses", %{country: country} do
    aus_country = insert(:country, name: "Australia", code: "AU")

    result = CityManager.create_city(%{
      name: "425 Burwood Hwy",
      country_id: aus_country.id,
      latitude: -37.8692,
      longitude: 145.2442
    })

    assert {:error, changeset} = result
    assert "is invalid" in errors_on(changeset).name
  end

  test "accepts valid city names", %{country: country} do
    result = CityManager.create_city(%{
      name: "London",
      country_id: country.id,
      latitude: 51.5074,
      longitude: -0.1278
    })

    assert {:ok, city} = result
    assert city.name == "London"
  end
end
```

### Schema-Level Tests

```elixir
# test/eventasaurus_discovery/locations/city_test.exs

describe "City.changeset/2 name validation" do
  test "rejects street addresses at schema level" do
    country = insert(:country)

    changeset = City.changeset(%City{}, %{
      name: "10-16 Botchergate",
      country_id: country.id
    })

    refute changeset.valid?
    assert "is invalid" in errors_on(changeset).name
  end

  test "accepts valid city names at schema level" do
    country = insert(:country)

    changeset = City.changeset(%City{}, %{
      name: "London",
      country_id: country.id
    })

    assert changeset.valid?
  end
end
```

---

## 🎯 Implementation Plan

### Phase 1: Immediate Fix (Critical - 1 hour)

- [ ] **Fix CityResolver regex** (universal numeric-prefix pattern)
  - File: `lib/eventasaurus_discovery/helpers/city_resolver.ex:169-174`
  - Replace keyword-based validation with `~r/^\d+[-\s]/`
  - Add tests for UK/Australian addresses

### Phase 2: Close Bypass Holes (High Priority - 1 hour)

- [ ] **Add validation to CityManager.create_city**
  - File: `lib/eventasaurus_discovery/admin/city_manager.ex:30`
  - Call `CityResolver.validate_city_name` before insert
  - Add integration tests

- [ ] **Add schema-level validation to City.changeset**
  - File: `lib/eventasaurus_discovery/locations/city.ex:27`
  - Add `validate_city_name_content/1` private function
  - Add schema tests

### Phase 3: Data Cleanup (Medium Priority - 2 hours)

- [ ] **Identify all polluted city records**
  - Query: `SELECT * FROM cities WHERE name ~ '^\d+'`
  - Export to CSV for manual review

- [ ] **Create cleanup migration**
  - Reassign venues from invalid cities to correct cities
  - Delete invalid city records
  - Log all changes for audit trail

- [ ] **Verify cleanup**
  - Run query again to confirm no invalid cities remain
  - Check venue assignments are correct

### Phase 4: Monitoring (Low Priority - 30 minutes)

- [ ] **Add logging for rejected city names**
  - Log when CityResolver rejects a name
  - Track which sources are sending bad data

- [ ] **Dashboard alert for invalid cities**
  - Admin dashboard shows count of rejected validations
  - Alert if count spikes (indicates new scraper bug)

---

## 📊 Success Metrics

### Before Implementation
- [ ] Document count of polluted city records: `SELECT COUNT(*) FROM cities WHERE name ~ '^\d+'`
- [ ] List all affected venues/events

### After Implementation
- [ ] Zero new invalid cities created over 30 days
- [ ] All existing invalid cities cleaned up
- [ ] All three validation layers tested and verified
- [ ] No regression in valid city creation

---

## 🔗 Related Issues & Documentation

- Issue #2052 - City name variations (alternate names system)
- `docs/ISSUE_CITY_NAME_VARIATIONS.md` - Previous city validation work
- `test/eventasaurus_discovery/scraping/processors/venue_processor_city_validation_test.exs` - Existing tests

---

## 🚨 Why This Is Critical

1. **Data Pollution**: Invalid cities corrupt analytics, search, and user experience
2. **SEO Impact**: Search engines index garbage city names
3. **User Trust**: Shows low data quality, damages credibility
4. **Regression**: We fixed this before, but validation holes allow re-infection
5. **Scale**: Problem will grow as more UK/Australian venues are added

---

## ✅ Acceptance Criteria

- [ ] All three validation holes are plugged (CityResolver, CityManager, City schema)
- [ ] Regex catches international street addresses (UK, AU, US, etc.)
- [ ] No US-centric assumptions in validation logic
- [ ] All existing invalid cities identified and cleaned up
- [ ] Tests cover UK, Australian, and US address patterns
- [ ] Zero new invalid cities created after deployment
- [ ] Documentation updated with new validation rules
- [ ] Admin UI shows validation errors clearly

---

**Priority**: Fix Phase 1 and Phase 2 immediately (critical path). Phase 3 can follow once validation is solid.

**Estimated Effort**: 2-3 hours for implementation + testing, 2 hours for cleanup = **4-5 hours total**
