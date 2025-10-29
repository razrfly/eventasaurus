# City Name Variations - Duplicate City Issue

**Status:** ✅ IMPLEMENTED (Closed in Issue #2052)
**Priority:** Medium
**Created:** 2025-10-29
**Updated:** 2025-10-29
**Category:** Data Quality, Internationalization

> **Implementation Note:** This issue was successfully resolved in Issue #2052 with a 3-phase approach:
> - Phase 1: Alternate names system to prevent duplicates during import
> - Phase 2: Admin UI for managing alternate names and merging duplicate cities
> - Phase 3: VenueStore integration for manual venue creation forms
>
> All features have been implemented and verified. See Issue #2052 for implementation details.

---

## 🎯 Problem Statement

The system is creating duplicate city records when the same city is referenced by different language variations or spellings. This causes:

1. **UI Issues:** Breadcrumbs showing duplicate city names (e.g., "Warsaw > Warsaw" or "Warszawa > Warszawa")
2. **Data Fragmentation:** Events and venues split across duplicate city records
3. **User Confusion:** Same city appearing multiple times in dropdowns and stats
4. **Analytics Problems:** City-level statistics incorrectly split across variations

### Current Examples

| Canonical Name | Variations | Database State |
|----------------|------------|----------------|
| Warsaw | Warszawa | Both exist (id: 6, 32) |
| Kraków | Krakow, Krakau | Kraków exists, others may appear |
| Paris | Paris 1, Paris 2, etc. | These are actually districts (different issue) |

### Database Evidence

```sql
-- Warsaw has 2 entries
SELECT id, name, slug FROM cities WHERE name ILIKE '%warsaw%';
-- Results:
--  6 | Warsaw   | warsaw   | 0 venues
-- 32 | Warszawa | warszawa | 132 venues

-- Kraków variations
SELECT id, name, slug FROM cities WHERE name ILIKE '%krak%';
--  5 | Kraków   | krakow   | (venues exist)
```

### Impact on User Experience

1. **Event Pages:** Breadcrumbs showing "Warsaw > Warsaw" with slightly different spellings
2. **City Stats:** Duplicate entries that should be aggregated
3. **Search Results:** Users searching "Warsaw" miss "Warszawa" events
4. **Admin Dashboard:** City lists cluttered with duplicates

---

## 🔍 Root Cause Analysis

### Where Duplicates Originate

City names come from multiple external sources, each using different conventions:

1. **Ticketmaster API:** Returns English names ("Warsaw")
2. **Local Polish APIs (Karnet, etc.):** Return native names ("Warszawa")
3. **BandsInTown:** Returns various spellings depending on venue data
4. **Manual Entry:** Admins might use different conventions
5. **Geocoding Library:** Returns canonical GeoNames entries (often English)

### Current City Creation Logic

Located in `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex:290-331`:

```elixir
defp ensure_city(%{city_name: city_name, country_name: country_name} = data) do
  # First try exact name match
  city = Repo.one(from c in City,
    where: c.name == ^city_name and c.country_id == ^country.id)

  # Then try slug match (e.g., "Kraków" vs "Krakow")
  city = city || Repo.one(from c in City,
    where: c.slug == ^Normalizer.create_slug(city_name) and c.country_id == ^country.id)

  # If not found, create new city
  city = city || create_city(city_name, country, data)
end
```

**Problem:** "Warsaw" and "Warszawa" generate different slugs, so slug matching doesn't help:
- "Warsaw" → slug: "warsaw"
- "Warszawa" → slug: "warszawa"

### Why This Differs from Paris Districts

Paris 1, Paris 2, etc. are **actual districts (arrondissements)** - different geographic entities that should remain separate. Warsaw/Warszawa are the **same city** with different language variations.

---

## 💡 Proposed Solution

### Two-Phase Approach

#### Phase 1: Data Migration (Immediate Fix)

Clean up existing duplicates through database migration:

```elixir
# Migration: Consolidate Warsaw variations
defmodule EventasaurusApp.Repo.Migrations.ConsolidateCityNameVariations do
  use Ecto.Migration

  def up do
    # 1. Move all venues from duplicate cities to canonical city
    execute """
    UPDATE venues
    SET city_id = 32  -- Warszawa (has data)
    WHERE city_id = 6 -- Warsaw (empty)
    """

    # 2. Delete empty duplicate city
    execute "DELETE FROM cities WHERE id = 6"

    # 3. Optional: Rename to English canonical name
    execute "UPDATE cities SET name = 'Warsaw' WHERE id = 32"

    # Note: Add similar migrations for other known duplicates
  end

  def down do
    # Rollback not fully possible - would need to restore duplicates
    # Consider keeping for audit trail
  end
end
```

#### Phase 2: Prevention (Systematic Fix)

Add alternate names support to prevent future duplicates:

**1. Database Schema Change:**

```elixir
# Migration: Add alternate names to cities
defmodule EventasaurusApp.Repo.Migrations.AddAlternateNamesToCities do
  use Ecto.Migration

  def change do
    alter table(:cities) do
      add :alternate_names, :jsonb, default: "[]"
    end

    # Add GIN index for fast alternate name lookups
    create index(:cities, [:alternate_names],
      using: :gin,
      name: :cities_alternate_names_gin_index
    )
  end
end
```

**2. Update City Schema:**

```elixir
# lib/eventasaurus_discovery/locations/city.ex
schema "cities" do
  field(:name, :string)
  field(:slug, Slug.Type)
  field(:alternate_names, {:array, :string}, default: [])  # ["Warszawa", "Warschau"]
  # ... rest
end

def changeset(city, attrs) do
  city
  |> cast(attrs, [:name, :alternate_names, ...])
  |> validate_required([:name, :country_id])
  # ...
end
```

**3. Create City Name Normalizer Module:**

```elixir
defmodule EventasaurusDiscovery.Helpers.CityNameNormalizer do
  @moduledoc """
  Handles city name variations and alternate names lookup.
  Prevents duplicate cities due to language/spelling variations.
  """

  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusApp.Repo
  import Ecto.Query

  @doc """
  Finds a city by name, checking both canonical name and alternate names.
  Returns the canonical city record regardless of which name was matched.

  ## Examples
      iex> find_by_any_name("Warsaw", country_id: 1)
      %City{id: 32, name: "Warsaw", alternate_names: ["Warszawa", "Warschau"]}

      iex> find_by_any_name("Warszawa", country_id: 1)
      %City{id: 32, name: "Warsaw", alternate_names: ["Warszawa", "Warschau"]}
  """
  def find_by_any_name(city_name, country_id: country_id) do
    normalized_name = normalize_name(city_name)

    from(c in City,
      where: c.country_id == ^country_id,
      where:
        fragment("LOWER(?)", c.name) == ^normalized_name or
        fragment("? @> ?::jsonb", c.alternate_names, ^Jason.encode!([city_name]))
    )
    |> Repo.one()
  end

  defp normalize_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.downcase()
  end
end
```

**4. Update VenueProcessor:**

```elixir
# lib/eventasaurus_discovery/scraping/processors/venue_processor.ex
defp ensure_city(%{city_name: city_name, country_name: country_name} = data) do
  country = find_or_create_country(country_name)

  if country == nil do
    {:error, "Cannot process city without valid country"}
  else
    # NEW: Check canonical name AND alternate names
    city = CityNameNormalizer.find_by_any_name(city_name, country_id: country.id)

    # If not found, create it
    city = city || create_city(city_name, country, data)

    if city do
      # Schedule coordinate calculation if needed
      if is_nil(city.latitude) || is_nil(city.longitude) do
        schedule_city_coordinate_update(city.id)
      end

      {:ok, city}
    else
      {:error, "Failed to find or create city: #{city_name}"}
    end
  end
end
```

**5. Populate Alternate Names:**

Create a Mix task or admin UI to add alternate names:

```elixir
# lib/mix/tasks/cities.add_alternate_names.ex
defmodule Mix.Tasks.Cities.AddAlternateNames do
  use Mix.Task
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City

  @shortdoc "Add alternate names to cities"

  # Predefined mappings for major cities
  @alternate_names_map %{
    "Warsaw" => ["Warszawa", "Warschau"],
    "Kraków" => ["Krakow", "Krakau", "Cracow"],
    "Prague" => ["Praha"],
    "Vienna" => ["Wien"],
    "Munich" => ["München"],
    # Add more as needed
  }

  def run(_args) do
    Mix.Task.run("app.start")

    Enum.each(@alternate_names_map, fn {canonical_name, alternates} ->
      city = Repo.get_by(City, name: canonical_name)

      if city do
        city
        |> City.changeset(%{alternate_names: alternates})
        |> Repo.update()
        |> case do
          {:ok, _} -> IO.puts("✓ Added alternates for #{canonical_name}")
          {:error, _} -> IO.puts("✗ Failed to update #{canonical_name}")
        end
      else
        IO.puts("⚠ City not found: #{canonical_name}")
      end
    end)
  end
end
```

---

## 🎨 UI Improvements

### Breadcrumb Consistency

Ensure breadcrumbs always use the canonical `city.name`:

```elixir
# lib/eventasaurus_web/live/event_live/show.ex
defp build_breadcrumbs(event) do
  [
    %{label: "Home", path: "/"},
    %{label: event.venue.city.name, path: city_path(event.venue.city)},  # Use canonical name
    %{label: event.title, path: nil}
  ]
end
```

### Search Enhancement

Update search to check alternate names:

```elixir
# Search query should match canonical OR alternate names
def search_cities(query) do
  normalized = String.downcase(query)

  from(c in City,
    where:
      fragment("LOWER(?)", c.name) == ^normalized or
      fragment("? @> ?::jsonb", c.alternate_names, ^Jason.encode!([query]))
  )
end
```

---

## 🧪 Testing Strategy

### Data Migration Tests

```elixir
defmodule EventasaurusApp.Repo.Migrations.ConsolidateCityNameVariationsTest do
  use EventasaurusApp.DataCase

  test "consolidates Warsaw variations into canonical city" do
    # Setup: Create duplicate cities
    country = insert(:country, name: "Poland")
    warsaw = insert(:city, name: "Warsaw", country_id: country.id)
    warszawa = insert(:city, name: "Warszawa", country_id: country.id)

    venue_in_warszawa = insert(:venue, city_id: warszawa.id)

    # Run migration
    Migration.up()

    # Verify: Warszawa city deleted, venues moved to Warsaw
    assert Repo.get(City, warsaw.id) != nil
    assert Repo.get(City, warszawa.id) == nil

    updated_venue = Repo.get(Venue, venue_in_warszawa.id)
    assert updated_venue.city_id == warsaw.id
  end
end
```

### City Name Normalizer Tests

```elixir
defmodule EventasaurusDiscovery.Helpers.CityNameNormalizerTest do
  use EventasaurusApp.DataCase

  describe "find_by_any_name/2" do
    test "finds city by canonical name" do
      country = insert(:country)
      city = insert(:city, name: "Warsaw", country_id: country.id,
                     alternate_names: ["Warszawa"])

      result = CityNameNormalizer.find_by_any_name("Warsaw", country_id: country.id)
      assert result.id == city.id
    end

    test "finds city by alternate name" do
      country = insert(:country)
      city = insert(:city, name: "Warsaw", country_id: country.id,
                     alternate_names: ["Warszawa", "Warschau"])

      result = CityNameNormalizer.find_by_any_name("Warszawa", country_id: country.id)
      assert result.id == city.id
      assert result.name == "Warsaw"  # Returns canonical city
    end

    test "returns nil when city not found" do
      country = insert(:country)
      result = CityNameNormalizer.find_by_any_name("NonExistent", country_id: country.id)
      assert result == nil
    end

    test "is case-insensitive" do
      country = insert(:country)
      city = insert(:city, name: "Warsaw", country_id: country.id,
                     alternate_names: ["Warszawa"])

      result = CityNameNormalizer.find_by_any_name("WARSZAWA", country_id: country.id)
      assert result.id == city.id
    end
  end
end
```

### Integration Tests

```elixir
test "prevents duplicate city creation with alternate name" do
  country = insert(:country, name: "Poland")

  # First event creates "Warsaw"
  event1_data = %{city: "Warsaw", country: "Poland", latitude: 52.2297, longitude: 21.0122}
  {:ok, venue1} = VenueProcessor.process_venue(event1_data)
  warsaw = venue1.city

  # Add alternate name
  warsaw
  |> City.changeset(%{alternate_names: ["Warszawa"]})
  |> Repo.update!()

  # Second event uses "Warszawa" - should find existing city
  event2_data = %{city: "Warszawa", country: "Poland", latitude: 52.2297, longitude: 21.0122}
  {:ok, venue2} = VenueProcessor.process_venue(event2_data)

  # Verify both venues use same city
  assert venue1.city_id == venue2.city_id
  assert venue2.city.name == "Warsaw"  # Canonical name

  # Verify no duplicate created
  assert Repo.aggregate(City, :count) == 1
end
```

---

## 📊 Success Metrics

### Before Implementation

- [x] Document all existing city name variations in database
- [x] Count venues/events affected by duplicates
- [x] Identify sources that produce variations

### After Phase 1 (Migration)

- [ ] Zero duplicate cities for known variations (Warsaw, Kraków, etc.)
- [ ] All venues consolidated under canonical cities
- [ ] Breadcrumbs show consistent city names
- [ ] City stats accurately aggregated

### After Phase 2 (Prevention)

- [ ] Zero new duplicates created over 30 days
- [ ] Alternate names successfully match incoming variations
- [ ] Search finds cities regardless of name variation used
- [ ] Admin UI allows easy alternate name management

---

## 🚀 Implementation Plan

### Phase 1: Quick Fix (1-2 hours)

1. [ ] Audit database for all duplicate cities
2. [ ] Create data migration to consolidate duplicates
3. [ ] Test migration on staging data
4. [ ] Deploy migration to production
5. [ ] Verify UI shows correct breadcrumbs

### Phase 2: Prevention (3-4 hours)

1. [ ] Create database migration for `alternate_names` field
2. [ ] Update `City` schema and changeset
3. [ ] Implement `CityNameNormalizer` module
4. [ ] Update `VenueProcessor.ensure_city/1` logic
5. [ ] Create Mix task to populate alternate names
6. [ ] Add tests (unit + integration)
7. [ ] Update documentation

### Phase 3: Enhancement (Optional, 2-3 hours)

1. [ ] Build admin UI for managing alternate names
2. [ ] Add search improvements for alternate names
3. [ ] Create monitoring dashboard for duplicate detection
4. [ ] Add alternate names to city API responses

---

## 🔗 Related Issues & Documentation

- [CITY_RESOLVER_MIGRATION_GUIDE.md](./CITY_RESOLVER_MIGRATION_GUIDE.md) - Related city name validation work
- [SCRAPER_MANIFESTO.md](./SCRAPER_MANIFESTO.md) - Geocoding strategy
- Issue #1631 - City pollution prevention (related but different issue)

---

## 🤔 Open Questions

1. **Canonical Name Standard:** Should we prefer English names or native names as canonical?
   - **Recommendation:** English for consistency (Warsaw > Warszawa, Munich > München)
   - Matches Google Maps, international travel booking sites
   - Easier for English-speaking admins and users

2. **GeoNames Integration:** Should we fetch alternate names from GeoNames API automatically?
   - **Recommendation:** Start with manual mapping, add API integration later if needed
   - GeoNames has 20M+ alternates, most unnecessary
   - Manual curation gives better control

3. **Case Sensitivity:** Should alternate names be case-sensitive?
   - **Recommendation:** No, always normalize to lowercase for matching
   - Users don't care about "WARSAW" vs "Warsaw"

4. **Backward Compatibility:** What happens to existing URLs with old city slugs?
   - **Recommendation:** Add slug redirects or update slugs to canonical
   - Ensure SEO not impacted

---

## 🎯 Acceptance Criteria

- [ ] No duplicate cities for Warsaw, Kraków, or other known variations
- [ ] Breadcrumbs consistently show canonical city names
- [ ] Event ingestion from all sources uses single city per location
- [ ] Search works with both canonical and alternate names
- [ ] City stats accurately aggregated (no splitting)
- [ ] Tests cover all edge cases (case sensitivity, race conditions, etc.)
- [ ] Documentation updated with examples
- [ ] Admin can easily add alternate names via Mix task or UI

---

**Next Steps:** Review this proposal, approve approach, and begin Phase 1 implementation.
