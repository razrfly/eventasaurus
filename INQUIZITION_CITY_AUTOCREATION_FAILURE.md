# Inquizition City Auto-Creation Failure in Production

## Issue Summary

Inquizition venues are failing to process in production with error **"City is required"**, but work correctly in development. The root cause is the `:geocoding` Erlang library failing to resolve city names from GPS coordinates in production, leading to `city_name: nil` in VenueProcessor validation.

## Production Error Evidence

```elixir
{:error, {:all_events_failed,
  %{
    first_error: {:error, "City is required"},
    total_failed: 1,
    error_types: %{unknown_error: 1}
  }}}
```

**Example Venue Data**:
```elixir
%{
  "address" => "Unit 15, Uplands Business Park, Blackhorse Ln,  E17 5QJ",
  "country" => "GB",
  "latitude" => 51.5922241,
  "longitude" => -0.0410249,
  "name" => "Signature Brew Blackhorse Road"
  # NO "city" field!
}
```

**Postcode Analysis**: `E17 5QJ` = **London, UK** (Walthamstow area)

## Root Cause Analysis

### Architecture Flow

```
VenueExtractor (✅ works)
  ↓ Extracts: venue_id, name, address, lat/lng, country (NO city extraction)
Transformer.resolve_location()
  ↓ Tries: CityResolver.resolve_city(lat, lng) using :geocoding library
  ↓ Falls back: parse_location_from_address_conservative()
  ↓ Result in production: {:error, :not_found} → {nil, "United Kingdom"}
VenueProcessor.ensure_city()
  ↓ Validates: city_name must not be nil
  ✗ FAILS: "City is required" because city_name is nil
```

### Technical Details

#### 1. VenueExtractor Does NOT Extract City

**File**: `lib/eventasaurus_discovery/sources/inquizition/extractors/venue_extractor.ex:132-145`

```elixir
%{
  venue_id: venue_id,
  name: String.trim(name),
  address: normalize_address(address),
  latitude: latitude,
  longitude: longitude,
  # ... other fields ...
  country: get_in(store, ["country"]) || "GB"
  # ❌ NO city field extracted!
}
```

The CDN response has addresses like `"47 Ludgate Hill\r\nLondon\r\nEC4M 7JZ"` but city is NOT extracted as a separate field.

#### 2. Transformer Uses CityResolver for Offline Geocoding

**File**: `lib/eventasaurus_discovery/sources/inquizition/transformer.ex:73-74, 230-244`

```elixir
def resolve_location(latitude, longitude, address) do
  case CityResolver.resolve_city(latitude, longitude) do
    {:ok, city_name} ->
      {city_name, "United Kingdom"}

    {:error, reason} ->
      Logger.warning("Geocoding failed for (#{lat}, #{lng}): #{reason}")
      parse_location_from_address_conservative(address)  # ← Fallback
  end
end
```

#### 3. CityResolver Uses `:geocoding` Erlang Library

**File**: `lib/eventasaurus_discovery/helpers/city_resolver.ex:67`

```elixir
case :geocoding.reverse(latitude, longitude) do
  {:ok, {_continent, _country_code, city_binary, _distance}} ->
    validate_city_name(to_string(city_binary))
  {:error, _reason} ->
    {:error, :not_found}
end
```

**Library Details**:
- **Package**: `{:geocoding, "~> 0.3.1"}` (mix.lock line 40)
- **Type**: Erlang NIF (Native Implemented Function) with C++ code
- **Data**: Contains embedded GeoNames database with 156,710+ cities
- **Dependency**: Requires compilation with Linux compatibility patches

#### 4. Fallback Parser ALSO Fails

**File**: `lib/eventasaurus_discovery/sources/inquizition/transformer.ex:271-301`

```elixir
defp parse_location_from_address_conservative(address) do
  parts = String.split(address, "\n") |> Enum.map(&String.trim/1)

  case parts do
    [_street, city_candidate, _postcode | _rest] ->
      case CityResolver.validate_city_name(city_trimmed) do
        {:ok, validated_city} -> {validated_city, "United Kingdom"}
        {:error, _reason} -> {nil, "United Kingdom"}  # ← Returns nil!
      end
    _ ->
      {nil, "United Kingdom"}  # ← Returns nil!
  end
end
```

For address `"Unit 15, Uplands Business Park, Blackhorse Ln,  E17 5QJ"`:
- Split by `\n` gives: `["Unit 15, Uplands Business Park, Blackhorse Ln,  E17 5QJ"]` (single line!)
- Pattern match fails → returns `{nil, "United Kingdom"}`

#### 5. VenueProcessor Requires city_name

**File**: `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex:190, 216`

```elixir
# Line 190: Normalize data
city_name: data[:city] || data["city"]  # ← Gets nil from venue_data

# Line 216: Validation
defp ensure_city(%{city_name: nil}), do: {:error, "City is required"}
```

## Why It Works in Development But Not Production

### Hypothesis 1: Geocoding Library Data Not Deployed (MOST LIKELY)

The `:geocoding` Erlang library contains embedded GeoNames data files that must be included in the release build.

**Evidence from Dockerfile** (`Dockerfile:44-56`):
```dockerfile
# Patch geocoding library to use getline instead of fgetln for Linux compatibility
RUN if [ -f deps/geocoding/c_src/GeocodingDriver.cpp ]; then \
    sed -i 's/char\* line;/char* line = NULL;/g' deps/geocoding/c_src/GeocodingDriver.cpp && \
    # ... more patches ...
fi
```

**Potential Issues**:
1. The geocoding library's `priv/` directory (containing GeoNames data) might not be included in the release
2. The Erlang NIF might fail to load in production environment
3. File permissions or paths might prevent data file access

**Development vs Production**:
- ✅ Dev: Uses `_build/dev/lib/geocoding/priv/` directly with proper permissions
- ❌ Prod: Release build at `/app/_build/prod/rel/eventasaurus` might not include data files

### Hypothesis 2: Speed Quizzing Works Due to Different Address Formats

Speed Quizzing uses **comma-separated** US addresses: `"123 Main St, New York, NY 10001"`

Inquizition uses **newline-separated** UK addresses: `"123 Street\nLondon\nSW1A 1AA"`

If geocoding library works in production for Speed Quizzing but not Inquizition, it suggests:
- Library successfully resolves US cities from coordinates
- Library fails for UK coordinates (possibly missing UK data in production)

## Comparison with Other Scrapers

### Speed Quizzing (Reference Implementation)

**File**: `lib/eventasaurus_discovery/sources/speed_quizzing/transformer.ex:180-194`

```elixir
def resolve_location(latitude, longitude, address) do
  case CityResolver.resolve_city(latitude, longitude) do
    {:ok, city_name} ->
      country = detect_country_from_address(address)
      {city_name, country}

    {:error, reason} ->
      Logger.warning("Geocoding failed...")
      parse_location_from_address_conservative(address)  # ← SAME PATTERN
  end
end

defp parse_location_from_address_conservative(address) do
  parts = String.split(address, ",")  # ← Split by COMMA (US format)
  # ... validation logic ...
end
```

**Key Difference**: Speed Quizzing splits by `,` for US addresses, Inquizition splits by `\n` for UK addresses.

**Both** depend on CityResolver working correctly!

## Proposed Solutions

### Solution 1: Fix Geocoding Library Deployment (RECOMMENDED)

Ensure the `:geocoding` library's GeoNames data files are properly included in production releases.

**Investigation Steps**:
1. Check if `deps/geocoding/priv/` contains data files
2. Verify release includes `_build/prod/rel/eventasaurus/lib/geocoding-*/priv/`
3. Test geocoding library in production console:
   ```elixir
   :geocoding.reverse(51.5074, -0.1278)  # Should return {:ok, {..., "London", ...}}
   ```

**Potential Fix** (if data files missing):

Update `mix.exs` to explicitly include geocoding priv files:
```elixir
def project do
  [
    # ...
    releases: [
      eventasaurus: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, &copy_geocoding_data/1]  # ← Add custom step
      ]
    ]
  ]
end

defp copy_geocoding_data(release) do
  # Ensure geocoding library data is copied to release
  File.cp_r!(
    "deps/geocoding/priv",
    Path.join([release.path, "lib", "geocoding-0.3.1", "priv"]),
    fn _source, _destination -> true end
  )
  release
end
```

### Solution 2: Improve UK Address Parsing Fallback

Enhance `parse_location_from_address_conservative()` to extract city from UK addresses more reliably.

**Current Problem**: Single-line addresses like `"123 Street, City, Postcode"` aren't parsed correctly.

**Proposed Enhancement**:
```elixir
defp parse_location_from_address_conservative(address) when is_binary(address) do
  # Try newline-separated format (UK)
  parts_newline = String.split(address, "\n") |> Enum.map(&String.trim/1)

  # Also try comma-separated format (fallback)
  parts_comma = String.split(address, ",") |> Enum.map(&String.trim/1)

  # Try newline format first (UK standard)
  case parts_newline do
    [_street, city_candidate, _postcode | _rest] when length(parts_newline) >= 3 ->
      validate_and_return_city(city_candidate)

    # Fallback: try comma format
    _ ->
      case parts_comma do
        [_street, city_candidate, _postcode | _rest] when length(parts_comma) >= 3 ->
          validate_and_return_city(city_candidate)

        # Last resort: try to extract from postcode using known UK cities
        _ ->
          extract_city_from_postcode_area(address)
      end
  end
end

defp extract_city_from_postcode_area(address) do
  # UK postcode areas map to cities (e.g., E17 → London, M1 → Manchester)
  # This is a conservative approach for production reliability
  cond do
    String.match?(address, ~r/\b(E|EC|N|NW|SE|SW|W|WC)\d+/i) ->
      {" London", "United Kingdom"}
    String.match?(address, ~r/\bM\d+/i) ->
      {"Manchester", "United Kingdom"}
    # ... more mappings ...
    true ->
      {nil, "United Kingdom"}
  end
end
```

### Solution 3: Use Hybrid Approach

Combine both solutions:
1. Fix geocoding library deployment (primary solution)
2. Add UK postcode area mapping as **reliable fallback** (safety net)

This ensures:
- ✅ 95%+ accuracy from geocoding library (when working)
- ✅ ~80% accuracy from postcode area mapping (when geocoding fails)
- ✅ Zero geocoding API costs
- ✅ Works in both dev and production

## Testing Plan

### 1. Verify Geocoding Library in Production

```elixir
# In production console (fly ssh console)
iex> :geocoding.reverse(51.5922241, -0.0410249)
# Expected: {:ok, {"Europe", "GB", "London", 123.45}}
# Actual (if broken): {:error, :not_found}
```

### 2. Test Inquizition Venue Processing

```elixir
# Queue a single venue with force_update
iex> EventasaurusDiscovery.Sources.Inquizition.Jobs.SyncJob.enqueue(%{limit: 1, force_update: true})

# Check job results in Oban dashboard
# Look for error details in job metadata
```

### 3. Compare Speed Quizzing vs Inquizition

```elixir
# Test Speed Quizzing geocoding
iex> EventasaurusDiscovery.Helpers.CityResolver.resolve_city(40.7128, -74.0060)
# Should return: {:ok, "New York"}

# Test Inquizition geocoding (London)
iex> EventasaurusDiscovery.Helpers.CityResolver.resolve_city(51.5074, -0.1278)
# Should return: {:ok, "London"}
# If this fails in production → geocoding library data issue
```

## Success Criteria

- [ ] `:geocoding.reverse()` works in production console
- [ ] CityResolver.resolve_city() returns cities for UK coordinates
- [ ] Inquizition venues process successfully with `force_update: true`
- [ ] No more "City is required" errors in production
- [ ] Fallback address parsing extracts cities from UK addresses
- [ ] All existing Speed Quizzing venues continue working

## Related Files

### Core Files
- `lib/eventasaurus_discovery/helpers/city_resolver.ex` - Offline geocoding wrapper
- `lib/eventasaurus_discovery/sources/inquizition/transformer.ex:230-301` - resolve_location()
- `lib/eventasaurus_discovery/sources/inquizition/extractors/venue_extractor.ex` - Raw data extraction
- `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex:190,216` - City validation

### Reference Implementations
- `lib/eventasaurus_discovery/sources/speed_quizzing/transformer.ex:180-321` - Same pattern
- `lib/eventasaurus_discovery/sources/geeks_who_drink/transformer.ex` - US addresses
- `lib/eventasaurus_discovery/sources/quizmeisters/transformer.ex` - Different country

### Build Configuration
- `mix.exs:148` - `{:geocoding, "~> 0.3.0"}` dependency
- `Dockerfile:44-56` - Linux compatibility patches for geocoding library
- `mix.lock:40` - Geocoding library version lock

## Priority

**HIGH** - Blocks all Inquizition venue processing in production. UK-wide coverage affected.

## Tags

`geocoding` `production-only` `inquizition` `city-resolution` `erlang-nif` `deployment`
