# Categorized Unsplash Gallery - Manual Testing Guide

This guide walks through manual testing of Phase 3 (Venue Integration) of the Categorized Unsplash Gallery system.

## Prerequisites

1. Server running: `mix phx.server`
2. At least one city with categorized gallery populated
3. Test venues with various types

## Setup Test Data

### 1. Fetch Categorized Images for a City

```elixir
# In IEx (iex -S mix phx.server)
alias EventasaurusApp.Repo
alias EventasaurusDiscovery.Locations.City

# Fetch all categories for Warsaw
mix unsplash.fetch_category Warsaw all
# Or specific categories:
mix unsplash.fetch_category Warsaw general
mix unsplash.fetch_category Warsaw historic
mix unsplash.fetch_category Warsaw architecture
```

### 2. Create Test Venues

```elixir
alias EventasaurusApp.Venues.Venue

# Get Warsaw city
city = Repo.get_by(City, slug: "warsaw") |> Repo.preload(:country)

# Test Venue 1: Theater (should map to "historic")
{:ok, theater} =
  %Venue{}
  |> Venue.changeset(%{
    name: "National Opera House",
    venue_type: "venue",
    source: "test",
    latitude: 52.2297,
    longitude: 21.0122,
    city_id: city.id,
    metadata: %{"category" => "opera"}
  })
  |> Repo.insert()

# Test Venue 2: Modern Arena (should map to "architecture")
{:ok, arena} =
  %Venue{}
  |> Venue.changeset(%{
    name: "Warsaw Spire Arena",
    venue_type: "venue",
    source: "test",
    latitude: 52.2319,
    longitude: 21.0034,
    city_id: city.id,
    metadata: %{"architectural_style" => "modern"}
  })
  |> Repo.insert()

# Test Venue 3: Old Town Location (should map to "old_town")
{:ok, old_town} =
  %Venue{}
  |> Venue.changeset(%{
    name: "Old Town Square",
    venue_type: "venue",
    source: "test",
    latitude: 52.2492,
    longitude: 21.0122,
    city_id: city.id
  })
  |> Repo.insert()

# Test Venue 4: Generic venue (should map to "general")
{:ok, generic} =
  %Venue{}
  |> Venue.changeset(%{
    name: "Generic Event Space",
    venue_type: "venue",
    source: "test",
    latitude: 52.2297,
    longitude: 21.0122,
    city_id: city.id
  })
  |> Repo.insert()

# Test Venue 5: Venue with own images (should use venue image)
{:ok, venue_with_image} =
  %Venue{}
  |> Venue.changeset(%{
    name: "Venue With Photos",
    venue_type: "venue",
    source: "test",
    latitude: 52.2297,
    longitude: 21.0122,
    city_id: city.id,
    venue_images: [
      %{
        "url" => "https://example.com/venue-photo.jpg",
        "provider" => "test"
      }
    ]
  })
  |> Repo.insert()
```

## Test Scenarios

### Test 1: Venue with Own Images

```elixir
# Preload city_ref for fallback to work
venue = Repo.get(Venue, venue_with_image.id) |> Repo.preload(:city_ref)

# Should return venue's own image
{:ok, url, :venue} = Venue.get_cover_image(venue)
IO.puts("✓ Venue image: #{url}")
# Expected: venue's own image URL, CDN-wrapped
```

### Test 2: Theater → Historic Category

```elixir
venue = Repo.get(Venue, theater.id) |> Repo.preload(:city_ref)

# Should map to historic category
{:ok, url, source} = Venue.get_cover_image(venue)
IO.puts("✓ Theater venue → #{source}: #{url}")
# Expected: source = :city_category or :city_general
```

### Test 3: Modern Arena → Architecture Category

```elixir
venue = Repo.get(Venue, arena.id) |> Repo.preload(:city_ref)

{:ok, url, source} = Venue.get_cover_image(venue)
IO.puts("✓ Modern arena → #{source}: #{url}")
# Expected: source = :city_category or :city_general
```

### Test 4: Old Town → Old Town Category

```elixir
venue = Repo.get(Venue, old_town.id) |> Repo.preload(:city_ref)

{:ok, url, source} = Venue.get_cover_image(venue)
IO.puts("✓ Old town → #{source}: #{url}")
# Expected: source = :city_category or :city_general
```

### Test 5: Generic Venue → General Category

```elixir
venue = Repo.get(Venue, generic.id) |> Repo.preload(:city_ref)

{:ok, url, source} = Venue.get_cover_image(venue)
IO.puts("✓ Generic venue → #{source}: #{url}")
# Expected: source = :city_category or :city_general
```

### Test 6: Manual Category Override

```elixir
# Override theater to use architecture category instead
{:ok, theater_updated} =
  Repo.get(Venue, theater.id)
  |> Venue.changeset(%{
    metadata: %{
      "category" => "opera",
      "unsplash_category" => "architecture"  # Manual override
    }
  })
  |> Repo.update()

venue = Repo.get(Venue, theater_updated.id) |> Repo.preload(:city_ref)
{:ok, url, source} = Venue.get_cover_image(venue)
IO.puts("✓ Overridden theater → #{source}: #{url}")
# Expected: Should use architecture category, not historic
```

### Test 7: CDN Options

```elixir
venue = Repo.get(Venue, generic.id) |> Repo.preload(:city_ref)

# With CDN transformations
{:ok, url, _source} = Venue.get_cover_image(venue, width: 800, quality: 90)
IO.puts("✓ CDN options applied: #{url}")
# In production, should see CDN params in URL
```

### Test 8: Fallback to General

```elixir
# Create venue that maps to non-existent category
{:ok, landmark} =
  %Venue{}
  |> Venue.changeset(%{
    name: "Test Landmark",
    venue_type: "venue",
    source: "test",
    latitude: 52.2297,
    longitude: 21.0122,
    city_id: city.id,
    metadata: %{"category" => "castle"}  # Maps to historic/city_landmarks
  })
  |> Repo.insert()

# If historic/city_landmarks category has no images, should fallback to general
venue = Repo.get(Venue, landmark.id) |> Repo.preload(:city_ref)
{:ok, url, source} = Venue.get_cover_image(venue)
IO.puts("✓ Fallback to general → #{source}: #{url}")
# Expected: source = :city_general if primary category empty
```

### Test 9: No Images Available

```elixir
# Create city without gallery
{:ok, country} =
  EventasaurusDiscovery.Locations.Country.changeset(
    %EventasaurusDiscovery.Locations.Country{},
    %{name: "Test Country", code: "TC"}
  )
  |> Repo.insert()

{:ok, empty_city} =
  City.changeset(%City{}, %{
    name: "Empty City",
    country_id: country.id,
    latitude: Decimal.new("0.0"),
    longitude: Decimal.new("0.0")
  })
  |> Repo.insert()

{:ok, empty_venue} =
  %Venue{}
  |> Venue.changeset(%{
    name: "Venue in Empty City",
    venue_type: "venue",
    source: "test",
    latitude: 0.0,
    longitude: 0.0,
    city_id: empty_city.id
  })
  |> Repo.insert()

venue = Repo.get(Venue, empty_venue.id) |> Repo.preload(:city_ref)
result = Venue.get_cover_image(venue)
IO.puts("✓ No images → #{inspect(result)}")
# Expected: {:error, :no_image}
```

## Verify CategoryMapper Logic

```elixir
alias EventasaurusApp.Venues.CategoryMapper

# Test category detection
venue = Repo.get(Venue, theater.id)
category = CategoryMapper.determine_category(venue)
IO.puts("Theater category: #{category}")  # Expected: "historic"

venue = Repo.get(Venue, arena.id)
category = CategoryMapper.determine_category(venue)
IO.puts("Arena category: #{category}")    # Expected: "architecture"

venue = Repo.get(Venue, old_town.id)
category = CategoryMapper.determine_category(venue)
IO.puts("Old town category: #{category}") # Expected: "old_town"

venue = Repo.get(Venue, generic.id)
category = CategoryMapper.determine_category(venue)
IO.puts("Generic category: #{category}")  # Expected: "general"

# Test fallback chain
venue = Repo.get(Venue, theater.id)
fallback_chain = CategoryMapper.get_fallback_chain(venue)
IO.inspect(fallback_chain, label: "Fallback chain")
# Expected: ["historic", "general"] or similar
```

## View in Dev UI

Visit `/admin/unsplash` to see:
- All cities with categorized galleries
- Category tabs for each city
- Daily rotating images per category
- Image counts and search terms

## Expected Results Summary

| Test Scenario | Expected Result |
|---------------|----------------|
| Venue with own images | Returns venue image with `:venue` source |
| Theater venue | Maps to `historic` category |
| Modern arena | Maps to `architecture` category |
| Old town venue | Maps to `old_town` category |
| Generic venue | Maps to `general` category |
| Manual override | Uses override category instead of auto-detected |
| CDN options | URL includes CDN transformations (production) |
| Category fallback | Falls back to `general` when primary empty |
| No images | Returns `{:error, :no_image}` |

## Troubleshooting

### Issue: CDN URLs not appearing
- **Cause**: CDN disabled in development by default
- **Solution**: Set `CDN_ENABLED=true` in environment or check config

### Issue: Category not detecting correctly
- **Check**: Venue metadata, name patterns
- **Debug**: Use `CategoryMapper.determine_category(venue)` to see detection

### Issue: No fallback to city images
- **Check**: `city_ref` is preloaded: `Repo.preload(:city_ref)`
- **Check**: City has categorized gallery (not legacy format)

### Issue: Wrong category selected
- **Override**: Set `metadata["unsplash_category"]` to force specific category
- **Debug**: Check priority order in CategoryMapper
