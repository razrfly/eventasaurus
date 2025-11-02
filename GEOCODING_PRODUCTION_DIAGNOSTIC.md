# Geocoding Library Production Diagnostics

Run these commands in production console to diagnose the geocoding library issue.

## Access Production Console

```bash
fly ssh console -a eventasaurus
/app/bin/eventasaurus remote
```

## Diagnostic Commands

### 1. Check if :geocoding Application is Loaded

```elixir
# Check if the geocoding application is started
Application.started_applications() |> Enum.find(fn {name, _, _} -> name == :geocoding end)

# Expected: {:geocoding, 'geocoding', '0.3.1'} or similar
# If nil: Application not loaded!
```

### 2. Test Geocoding Library Directly

```elixir
# Test with London coordinates (known good location)
:geocoding.reverse(51.5074, -0.1278)

# Expected successful result:
# {:ok, {"Europe", "GB", "London", 5.67}}
#        ^continent ^country ^city  ^distance

# If you get error:
# {:error, :not_found} → Library loaded but no data
# {:error, :enoent} → Data files missing
# ** (UndefinedFunctionError) → Library not compiled/loaded
```

### 3. Test with Inquizition Venue Coordinates

```elixir
# Test the actual failing venue coordinates (E17 5QJ = Walthamstow, London)
:geocoding.reverse(51.5922241, -0.0410249)

# Expected: {:ok, {"Europe", "GB", "London", ...}}
# This is the venue that's failing in production!
```

### 4. Check if Data Files Exist

```elixir
# Check if the geocoding priv directory exists
geocoding_priv = :code.priv_dir(:geocoding)
IO.puts("Geocoding priv dir: #{inspect(geocoding_priv)}")

# Expected: '/app/lib/geocoding-0.3.1/priv' or similar
# If :error → Priv directory not found!

# List files in priv directory (if it exists)
if is_list(geocoding_priv) do
  priv_path = List.to_string(geocoding_priv)
  case File.ls(priv_path) do
    {:ok, files} ->
      IO.puts("Files in priv dir:")
      Enum.each(files, &IO.puts("  - #{&1}"))
    {:error, reason} ->
      IO.puts("Cannot list priv dir: #{inspect(reason)}")
  end
else
  IO.puts("Priv dir not available: #{inspect(geocoding_priv)}")
end

# Expected files: cities.txt or similar GeoNames data file
```

### 5. Test CityResolver (Our Wrapper)

```elixir
# Test our CityResolver wrapper
alias EventasaurusDiscovery.Helpers.CityResolver

# London
CityResolver.resolve_city(51.5074, -0.1278)

# Inquizition venue (Walthamstow, London)
CityResolver.resolve_city(51.5922241, -0.0410249)

# New York (for comparison with Speed Quizzing)
CityResolver.resolve_city(40.7128, -74.0060)

# Manchester
CityResolver.resolve_city(53.4808, -2.2426)

# Expected: {:ok, "London"}, {:ok, "London"}, {:ok, "New York"}, {:ok, "Manchester"}
# If {:error, :not_found} → Library not working
# If {:error, :missing_coordinates} → Bad input
```

### 6. Check Release Path Structure

```elixir
# Check what libraries are included in the release
release_lib_path = "/app/lib"

case File.ls(release_lib_path) do
  {:ok, libs} ->
    geocoding_libs = Enum.filter(libs, &String.starts_with?(&1, "geocoding"))
    IO.puts("Geocoding libraries found:")
    Enum.each(geocoding_libs, fn lib ->
      IO.puts("  - #{lib}")
      priv_path = Path.join([release_lib_path, lib, "priv"])
      case File.exists?(priv_path) do
        true ->
          case File.ls(priv_path) do
            {:ok, files} -> IO.puts("    Priv files: #{inspect(files)}")
            _ -> IO.puts("    Priv dir exists but cannot list")
          end
        false ->
          IO.puts("    ❌ NO PRIV DIR!")
      end
    end)
  {:error, reason} ->
    IO.puts("Cannot list /app/lib: #{inspect(reason)}")
end
```

### 7. Check Erlang NIF Loading

```elixir
# Check if the NIF (Native Implemented Function) is loaded
:erlang.loaded_nifs() |> Enum.filter(fn {mod, _path} ->
  String.contains?(Atom.to_string(mod), "geocod")
end)

# Expected: List with geocoding NIF entry
# If empty: NIF not loaded (data files missing or compilation issue)
```

## Complete Diagnostic Script (Copy/Paste)

```elixir
IO.puts("=== GEOCODING LIBRARY DIAGNOSTICS ===\n")

# 1. Application Status
IO.puts("1. Application Status:")
case Application.started_applications() |> Enum.find(fn {name, _, _} -> name == :geocoding end) do
  {_, _, version} -> IO.puts("   ✅ Loaded: version #{version}")
  nil -> IO.puts("   ❌ NOT LOADED")
end

# 2. Priv Directory Check
IO.puts("\n2. Priv Directory:")
case :code.priv_dir(:geocoding) do
  {:error, reason} ->
    IO.puts("   ❌ Priv dir error: #{inspect(reason)}")
  priv_path when is_list(priv_path) ->
    path_str = List.to_string(priv_path)
    IO.puts("   Path: #{path_str}")
    case File.ls(path_str) do
      {:ok, files} ->
        IO.puts("   Files: #{inspect(files)}")
        # Check if data files exist
        has_data = Enum.any?(files, &String.contains?(&1, ["cities", "data", "txt", "dat"]))
        if has_data do
          IO.puts("   ✅ Data files found")
        else
          IO.puts("   ⚠️  No obvious data files")
        end
      {:error, e} ->
        IO.puts("   ❌ Cannot list: #{inspect(e)}")
    end
end

# 3. Direct Library Test
IO.puts("\n3. Direct Library Tests:")
test_coords = [
  {"London", 51.5074, -0.1278},
  {"Inquizition Venue (London E17)", 51.5922241, -0.0410249},
  {"New York", 40.7128, -74.0060},
  {"Manchester", 53.4808, -2.2426}
]

Enum.each(test_coords, fn {name, lat, lng} ->
  case :geocoding.reverse(lat, lng) do
    {:ok, {_continent, _country, city, _dist}} ->
      IO.puts("   ✅ #{name}: #{city}")
    {:error, reason} ->
      IO.puts("   ❌ #{name}: #{inspect(reason)}")
    other ->
      IO.puts("   ⚠️  #{name}: Unexpected result #{inspect(other)}")
  end
end)

# 4. CityResolver Test
IO.puts("\n4. CityResolver Wrapper Tests:")
alias EventasaurusDiscovery.Helpers.CityResolver

Enum.each(test_coords, fn {name, lat, lng} ->
  case CityResolver.resolve_city(lat, lng) do
    {:ok, city} ->
      IO.puts("   ✅ #{name}: #{city}")
    {:error, reason} ->
      IO.puts("   ❌ #{name}: #{inspect(reason)}")
  end
end)

IO.puts("\n=== DIAGNOSTIC COMPLETE ===")
```

## Interpreting Results

### Scenario A: Library Working ✅

```
✅ Loaded: version 0.3.1
✅ Data files found
✅ London: London
✅ Inquizition Venue: London
✅ New York: New York
```

**Conclusion**: Library is fine! Issue must be elsewhere (check address parsing logic).

### Scenario B: Library Loaded, No Data ❌

```
✅ Loaded: version 0.3.1
❌ Priv dir error: :bad_name
❌ London: :not_found
❌ Inquizition Venue: :not_found
```

**Conclusion**: Library compiled but GeoNames data files NOT included in release.
**Solution**: Fix release build to include `deps/geocoding/priv/` directory.

### Scenario C: Library Not Loaded ❌

```
❌ NOT LOADED
** (UndefinedFunctionError) function :geocoding.reverse/2 is undefined
```

**Conclusion**: Geocoding dependency not included in release at all.
**Solution**: Check `mix.exs` dependencies and release configuration.

### Scenario D: NIF Compilation Issue ❌

```
✅ Loaded: version 0.3.1
✅ Data files found
❌ London: :enoent (or similar file error)
```

**Conclusion**: C++ NIF not properly compiled for production environment.
**Solution**: Check Dockerfile patches (lines 44-56) and Linux compatibility.

## Next Steps Based on Results

### If Data Files Missing (Most Likely):

Update `mix.exs` to include geocoding priv in release:

```elixir
def project do
  [
    # ...
    releases: [
      eventasaurus: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, &copy_geocoding_data/1]
      ]
    ]
  ]
end

defp copy_geocoding_data(release) do
  IO.puts("Copying geocoding data files...")

  source = "deps/geocoding/priv"

  # Find the geocoding library version in release
  lib_dir = Path.join(release.path, "lib")
  geocoding_lib =
    File.ls!(lib_dir)
    |> Enum.find(&String.starts_with?(&1, "geocoding-"))

  if geocoding_lib do
    dest = Path.join([lib_dir, geocoding_lib, "priv"])
    File.mkdir_p!(dest)
    File.cp_r!(source, dest)
    IO.puts("✅ Copied geocoding data to #{dest}")
  else
    IO.warn("⚠️  Could not find geocoding library in release")
  end

  release
end
```

### If Everything Works:

Then the issue is in the **address parsing fallback logic**. The geocoding library is returning `:not_found` for the specific coordinates, and our fallback parser is also failing.

**Solution**: Enhance UK address parsing with postcode-to-city mapping.

## Quick Test in Development First

Before deploying to production, test in dev console:

```bash
iex -S mix
```

```elixir
# Should work in dev
:geocoding.reverse(51.5074, -0.1278)

# Check where dev data lives
:code.priv_dir(:geocoding) |> List.to_string() |> IO.puts()
# Should show: /path/to/project/_build/dev/lib/geocoding-0.3.1/priv
```

This will confirm the library works in dev and help us understand the structure.
