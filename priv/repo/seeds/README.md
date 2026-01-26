# Production Seeds

## Purpose

This directory contains **production-essential seed data** that should exist in all environments (development, staging, production). These seeds create reference data and configuration that the application depends on to function correctly.

## When to Use Production Seeds

Add seeds here **only** when:

- ✅ The data is **required** for the application to function
- ✅ The data is **reference/lookup data** (categories, locations, sources)
- ✅ The data should exist in **all environments** including production
- ✅ The data is relatively **static** and doesn't change frequently
- ✅ The data is **not user-generated** or test-specific

## When NOT to Use Production Seeds

Do **not** add seeds here for:

- ❌ Test data or development-only data → Use `priv/repo/dev_seeds/`
- ❌ User accounts for testing → Use `priv/repo/dev_seeds/`
- ❌ Scenario-specific test data → Use `priv/repo/dev_seeds/scenarios/`
- ❌ Large datasets for performance testing → Use `priv/repo/dev_seeds/`

## Running Production Seeds

```bash
# Run all production seeds
mix run priv/repo/seeds.exs

# Or during setup/migrations
mix ecto.setup  # Includes seeds
```

## Current Production Seeds

### Main Entry Point

**`seeds.exs`** - Main orchestrator that:
1. Creates essential user accounts (Holden's personal account)
2. Calls all individual seed files below
3. Validates authentication configuration

### Reference Data Seeds

#### `categories.exs`
- **Purpose**: Seeds event categories for the discovery system
- **Data**: 15 event categories (Concerts, Festivals, Theatre, Sports, etc.)
- **Details**: Each category has name, slug, icon, color, and display order
- **Idempotent**: Yes - uses `on_conflict` to update existing categories
- **Dependencies**: None
- **Note**: Category mappings are managed via YAML files in `priv/category_mappings/`

#### `locations.exs`
- **Purpose**: Seeds countries and cities for event locations
- **Data**: Core countries and major cities worldwide
- **Details**: Includes coordinates, timezone information
- **Idempotent**: Yes
- **Dependencies**: None

#### `sources.exs`
- **Purpose**: Seeds event scraping sources for automated discovery
- **Data**: 14 event sources (Ticketmaster, Bandsintown, Resident Advisor, etc.)
- **Details**: Each source has priority, domains, rate limits, and metadata
- **Idempotent**: Yes - updates existing sources by slug
- **Dependencies**: None
- **Coverage**: Music, trivia, cinema, sports, cultural events
- **Aggregation**: Some sources aggregate on index (trivia, movies)

#### `discovery_cities.exs`
- **Purpose**: Configures which cities have automated event discovery enabled
- **Data**: Cities where we actively scrape events
- **Details**: Links cities to active sources and scrapers
- **Idempotent**: Yes
- **Dependencies**: `locations.exs`, `sources.exs`

#### `discovery_config_krakow.exs`
- **Purpose**: City-specific discovery configuration for Krakow
- **Data**: Krakow-specific scraper settings and source priorities
- **Details**: Fine-tunes discovery behavior for Krakow's event scene
- **Idempotent**: Yes
- **Dependencies**: `locations.exs`, `sources.exs`, `discovery_cities.exs`

#### `city_alternate_names.exs`
- **Purpose**: Seeds alternate names and spellings for cities
- **Data**: Common variations (Warsaw/Warszawa, Krakow/Kraków/Cracow)
- **Details**: Used for fuzzy matching when scraping events
- **Idempotent**: Yes
- **Dependencies**: `locations.exs`

### ⚠️ Files That Should Be Moved

These files are currently in the production seeds directory but contain **test data** and should be moved to `priv/repo/dev_seeds/scenarios/`:

- **`poll_suggestions_test_data.exs`** - Creates test event for poll suggestions feature testing
- **`cocktail_poll_test.exs`** - Creates cocktail poll with CocktailDB data for testing

See [Issue #2239](https://github.com/razrfly/eventasaurus/issues/2239) for the reorganization plan.

## Seed Execution Order

Seeds are executed in this order (see `seeds.exs`):

1. **User Setup** - Creates Holden's account with authentication
2. **Locations** - Countries and cities
3. **Categories** - Event categories
4. **Sources** - Event scraping sources
5. **Discovery Config** - Automated discovery settings

This order ensures dependencies are met (e.g., discovery config needs locations and sources to exist).

## Adding New Production Seeds

### Step 1: Create the Seed File

Create a new `.exs` file in `priv/repo/seeds/`:

```elixir
# priv/repo/seeds/my_reference_data.exs

alias EventasaurusApp.Repo
alias EventasaurusApp.MyContext.MySchema

data = [
  %{name: "Item 1", slug: "item-1"},
  %{name: "Item 2", slug: "item-2"}
]

Enum.each(data, fn attrs ->
  # Use upsert pattern for idempotency
  %MySchema{}
  |> MySchema.changeset(attrs)
  |> Repo.insert!(
    on_conflict: {:replace, [:name, :updated_at]},
    conflict_target: :slug
  )
  IO.puts("✅ Ready: #{attrs.name}")
end)

IO.puts("\n✅ My reference data seeded successfully!")
```

### Step 2: Add to Main Seeds File

Add the file to `seeds.exs`:

```elixir
# Seed my reference data
IO.puts("\n🌱 Seeding my reference data...")
Code.eval_file("priv/repo/seeds/my_reference_data.exs")
```

### Step 3: Make Seeds Idempotent

**Always** make production seeds idempotent using `on_conflict`:

```elixir
# Good - Idempotent
Repo.insert!(changeset,
  on_conflict: {:replace, [:name, :updated_at]},
  conflict_target: :slug
)

# Bad - Will fail on reruns
Repo.insert!(changeset)
```

### Step 4: Test Thoroughly

```bash
# Test in development
mix ecto.reset  # Drops, creates, migrates, and seeds

# Run seeds again to test idempotency
mix run priv/repo/seeds.exs

# Verify data in database
mix ecto.query -r EventasaurusApp.Repo "SELECT * FROM my_table"
```

## Best Practices

### DO ✅

- **Make seeds idempotent** - Should be safe to run multiple times
- **Use `on_conflict`** - Upsert pattern prevents duplicate errors
- **Add descriptive output** - Use emoji and clear messages (🌱, ✅, ❌)
- **Keep data minimal** - Only seed what's truly essential
- **Document dependencies** - Note which seeds must run before others
- **Use constants** - Define data inline in the seed file
- **Version control seed data** - All data should be in the seed files

### DON'T ❌

- **Don't seed test data** - Test data belongs in `dev_seeds/`
- **Don't seed large datasets** - Keep production seeds lean
- **Don't make external API calls** - Seeds should be deterministic
- **Don't depend on order** - Be explicit about dependencies
- **Don't use Faker** - Production seeds should be consistent
- **Don't create user accounts** - Except essential system accounts

## Troubleshooting

### Seeds Fail on Fresh Database

**Problem**: Seeds try to reference data that doesn't exist yet

**Solution**: Check execution order in `seeds.exs` and ensure dependencies run first

### Seeds Fail on Reruns

**Problem**: Unique constraint violations

**Solution**: Use `on_conflict` with `conflict_target` for idempotency

### Seeds Are Too Slow

**Problem**: Seeding takes a long time

**Solution**:
- Review if data belongs in production seeds (move to dev_seeds if not essential)
- Consider using `Repo.insert_all` for bulk inserts
- Remove unnecessary validations during seeding

### Need to Update Existing Seed Data

**Problem**: Need to change production reference data

**Solution**:
1. Update the seed file with new data
2. Run `mix run priv/repo/seeds.exs` to update database
3. The `on_conflict` clause will update existing records

## Related Documentation

- **Development Seeds**: See `priv/repo/dev_seeds/README.md`
- **Mix Tasks**: See `lib/mix/tasks/seed.dev.ex` and `seed.clean.ex`
- **Reorganization Plan**: See [Issue #2239](https://github.com/razrfly/eventasaurus/issues/2239)
- **Category Mappings**: See `priv/category_mappings/README.md` (if exists)

## Questions?

If you're unsure whether something should be a production seed:

1. **Will it be needed in production?** → Yes = production seed
2. **Is it test/development data?** → Yes = development seed
3. **Does it change frequently?** → Yes = might be better as migration or admin UI
4. **Is it user-generated content?** → Yes = not a seed, create through app

When in doubt, ask the team or create it as a development seed first.
