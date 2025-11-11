# City Slug Uniqueness Issue

## Problem Statement

City slugs are currently only unique within a country (composite unique constraint on `[:country_id, :slug]`), but routes use slug alone (`/admin/discovery/config/:slug`). This causes `Ecto.MultipleResultsError` when accessing cities with duplicate names across different countries.

### Current Behavior

**Database State:**
- Manchester (UK, id 130) → slug: `manchester`
- Manchester (US, id unknown) → slug: `manchester` ✅ (allowed by constraint)
- Dubai (AE) → slug: `dubai`
- Dubai (US) → slug: `dubai` ✅ (allowed by constraint)
- High Wycombe (GB) → slug: `high-wycombe`
- High Wycombe (AU) → slug: `high-wycombe` ✅ (allowed by constraint)
- West End (GB) → slug: `west-end`
- West End (AU) → slug: `west-end` ✅ (allowed by constraint)

**Route Behavior:**
```elixir
# Route: /admin/discovery/config/:slug
# Code: Repo.get_by!(City, slug: city_slug)
# Error: Ecto.MultipleResultsError: expected at most one result but got 2
```

**Sentry Issues:**
- EVENTASAURUS-22: Manchester config page crash
- EVENTASAURUS-23: Manchester config page crash
- Affects all duplicate city names

### Temporary Fix (Current)

Modified `city_discovery_config_live.ex` to arbitrarily select one city:
```elixir
city =
  from(c in City,
    where: c.slug == ^city_slug,
    order_by: [desc: c.discovery_enabled, asc: c.id],
    limit: 1
  )
  |> Repo.one!()
```

**Problem:** This is a band-aid. It picks one city non-deterministically and makes the other inaccessible.

## Desired Solution

Implement smart slug collision handling similar to Venue slugs:

### Progressive Disambiguation Strategy

**First city with a name:**
- Manchester (UK, id 130) → `manchester` ✓ (clean slug)

**Second city with same name:**
- Manchester (US, id 450) → `manchester-us` ✓ (slug + country code)

**Algorithm:**
1. Generate base slug from city name
2. Check if base slug exists globally (excluding current record)
3. If exists, append `-{lowercase_country_code}` (e.g., `-us`, `-gb`, `-ae`)
4. If that exists (edge case), fallback to timestamp suffix

### Key Principles

1. **Order by ID (oldest first):** Lowest ID gets clean slug
2. **Country code suffix:** Natural disambiguator for cities
3. **Global uniqueness:** Single unique constraint on `slug` column
4. **Stable slugs:** Don't regenerate on city name updates
5. **Deterministic:** Same inputs → same slug (no runtime randomness)

## Implementation Plan

### 1. Update City.Slug Module

**File:** `lib/eventasaurus_discovery/locations/city.ex`

Add custom slug generation similar to Venue.Slug:

```elixir
defmodule EventasaurusDiscovery.Locations.City.Slug do
  use EctoAutoslugField.Slug, from: :name, to: :slug
  import Ecto.Query
  alias EventasaurusApp.Repo

  def build_slug(sources, changeset) do
    base_slug = super(sources, changeset)
    ensure_unique_slug(base_slug, changeset)
  end

  defp ensure_unique_slug(base_slug, changeset) do
    existing_id = Ecto.Changeset.get_field(changeset, :id)

    cond do
      # Try base slug (city name only)
      !slug_exists?(base_slug, existing_id) ->
        base_slug

      # Try base slug + country code
      true ->
        country_code = get_country_code(changeset)
        slug_with_country = "#{base_slug}-#{country_code}"

        if !slug_exists?(slug_with_country, existing_id) do
          slug_with_country
        else
          # Fallback: base slug + timestamp (edge case)
          "#{base_slug}-#{System.system_time(:second)}"
        end
    end
  end

  defp slug_exists?(slug, existing_id) do
    query = from(c in EventasaurusDiscovery.Locations.City, where: c.slug == ^slug)

    query =
      if existing_id do
        from(c in query, where: c.id != ^existing_id)
      else
        query
      end

    Repo.exists?(query)
  end

  defp get_country_code(changeset) do
    country_id = Ecto.Changeset.get_field(changeset, :country_id)

    if country_id do
      case Repo.get(EventasaurusDiscovery.Locations.Country, country_id) do
        %{code: code} when is_binary(code) -> String.downcase(code)
        _ -> "unknown"
      end
    else
      "unknown"
    end
  end
end
```

### 2. Update City.changeset

**Change:**
```elixir
# Before
|> unique_constraint([:country_id, :slug])

# After
|> unique_constraint(:slug)
```

### 3. Create Migration

**File:** `priv/repo/migrations/YYYYMMDDHHMMSS_make_city_slugs_globally_unique.exs`

**Steps:**
1. Find all duplicate slug groups
2. For each group, order by ID ascending
3. Keep first city's slug unchanged (lowest ID)
4. Rename remaining cities: `slug-{country_code}`
5. Drop old unique index on `[:country_id, :slug]`
6. Add new unique index on `[:slug]`

**Migration Code:**
```elixir
defmodule EventasaurusApp.Repo.Migrations.MakeCitySlugsGloballyUnique do
  use Ecto.Migration
  import Ecto.Query
  alias EventasaurusApp.Repo

  def up do
    # Step 1: Find and fix duplicate slugs
    rename_duplicate_slugs()

    # Step 2: Drop old composite unique index
    drop_if_exists unique_index(:cities, [:country_id, :slug])

    # Step 3: Add global unique index
    create unique_index(:cities, [:slug])
  end

  def down do
    # Reverse: drop global unique index
    drop_if_exists unique_index(:cities, [:slug])

    # Re-add composite unique index
    create unique_index(:cities, [:country_id, :slug])

    # Note: Cannot automatically reverse slug renames
    # Manual intervention required if rollback needed
  end

  defp rename_duplicate_slugs do
    # Find all duplicate slug groups
    duplicate_groups =
      from(c in "cities",
        join: co in "countries",
        on: c.country_id == co.id,
        group_by: c.slug,
        having: count(c.id) > 1,
        select: {c.slug, fragment("array_agg(? ORDER BY ?)", c.id, c.id), fragment("array_agg(?)", co.code)}
      )
      |> Repo.all()

    # Process each duplicate group
    Enum.each(duplicate_groups, fn {slug, city_ids, country_codes} ->
      # First city (lowest ID) keeps clean slug
      # Remaining cities get renamed
      city_ids
      |> Enum.drop(1)
      |> Enum.with_index(1)
      |> Enum.each(fn {city_id, index} ->
        country_code = Enum.at(country_codes, index) |> String.downcase()
        new_slug = "#{slug}-#{country_code}"

        execute("""
        UPDATE cities
        SET slug = '#{new_slug}'
        WHERE id = #{city_id}
        """)
      end)
    end)
  end
end
```

### 4. Revert Temporary Fix

**File:** `lib/eventasaurus_web/live/admin/city_discovery_config_live.ex`

**Revert to:**
```elixir
city = Repo.get_by!(City, slug: city_slug) |> Repo.preload(:country)
```

After migration, all slugs will be unique so this will work correctly.

## Current Duplicate Slugs (To Be Fixed by Migration)

Based on local database analysis, these duplicates need renaming:

1. **manchester** (2 cities)
   - Manchester, GB (id 130) → `manchester` ✓ (keep)
   - Manchester, US → `manchester-us` (rename)

2. **dubai** (2 cities)
   - Dubai, AE (lowest ID) → `dubai` ✓ (keep)
   - Dubai, US → `dubai-us` (rename)

3. **high-wycombe** (2 cities)
   - High Wycombe, GB (lowest ID) → `high-wycombe` ✓ (keep)
   - High Wycombe, AU → `high-wycombe-au` (rename)

4. **west-end** (2 cities)
   - West End, GB (lowest ID) → `west-end` ✓ (keep)
   - West End, AU → `west-end-au` (rename)

## Breaking Changes

### URL Changes

**Before Migration:**
- `/admin/discovery/config/manchester` → crashes (multiple results)
- `/admin/discovery/config/dubai` → crashes (multiple results)

**After Migration:**
- `/admin/discovery/config/manchester` → Manchester, UK ✓ (first by ID)
- `/admin/discovery/config/manchester-us` → Manchester, US ✓ (new URL)
- `/admin/discovery/config/dubai` → Dubai, AE ✓ (first by ID)
- `/admin/discovery/config/dubai-us` → Dubai, US ✓ (new URL)

### Impact Assessment

**Low Risk:**
- Admin pages only (not public-facing)
- Already crashing for duplicate cities
- Clean slugs preserved for oldest cities (most likely to be linked)
- User explicitly requested this change

**Potential Issues:**
- Bookmarks to duplicate cities will break (unlikely - they were crashing)
- Hardcoded slugs in code/tests need updating
- External integrations using city slugs need updating

## Testing Strategy

### Unit Tests

1. **Test City.Slug.build_slug/2:**
   - First "London" → `london`
   - Second "London" in different country → `london-us`
   - Updating existing city doesn't regenerate slug
   - Missing country code → fallback to `unknown`

2. **Test slug collision handling:**
   - Base slug available → use it
   - Base slug taken → append country code
   - Both taken (edge case) → append timestamp

### Migration Tests

1. Verify duplicate slugs renamed correctly
2. Verify oldest city keeps clean slug
3. Verify new unique constraint works
4. Verify index changes applied

### Integration Tests

1. Access `/admin/discovery/config/manchester` → loads Manchester, UK
2. Access `/admin/discovery/config/manchester-us` → loads Manchester, US
3. Create new "Paris" in US → automatically gets `paris-us` slug
4. No `Ecto.MultipleResultsError` crashes

## Success Criteria

- [ ] All city slugs are globally unique
- [ ] Oldest city with each name keeps clean slug
- [ ] New cities automatically handle slug collisions
- [ ] No `Ecto.MultipleResultsError` crashes
- [ ] Routes work for all cities
- [ ] Migration is reversible (with manual slug restoration)
- [ ] Tests pass for slug generation logic
- [ ] Sentry errors EVENTASAURUS-22 and EVENTASAURUS-23 resolved

## Related Files

- `lib/eventasaurus_discovery/locations/city.ex` - City model and slug generation
- `lib/eventasaurus_web/live/admin/city_discovery_config_live.ex` - Admin config page (currently has temp fix)
- `lib/eventasaurus_web/router.ex` - Route definitions
- `lib/eventasaurus_app/venues/venue.ex` - Reference implementation for slug collision handling
- `priv/repo/migrations/*_make_city_slugs_globally_unique.exs` - New migration

## References

- **Sentry Issues:** EVENTASAURUS-22, EVENTASAURUS-23
- **Similar Implementation:** Venue.Slug (lines 1-85 in `venue.ex`)
- **Route Definition:** Line 85 in `router.ex` (`/discovery/config/:slug`)
- **Current Constraint:** Line 41 in `city.ex` (`unique_constraint([:country_id, :slug])`)
