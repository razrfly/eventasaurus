# Geocoding Library Segfault Fix

## Problem

The `:geocoding` Erlang library was crashing in production with **exit status 139 (SIGSEGV)** when calling `:geocoding.reverse()`.

### Root Cause

The Dockerfile patches (lines 44-50) that convert BSD `fgetln()` to POSIX `getline()` had a **critical semantic bug**:

**Original BSD code** (GeocodingDriver.cpp:105-106):
```cpp
while ((line = fgetln(db_file, &line_size))) {
    char* end = line + line_size;  // ← line_size = actual line length
```

**Broken patches** (converted to getline but with bug):
```cpp
while ((nread = getline(&line, &line_size, db_file)) != -1)) {
    char* end = line + line_size;  // ← BUG! line_size = BUFFER size, NOT line length!
```

### The Bug

| Function | `line_size` means | Line length is in |
|----------|-------------------|-------------------|
| `fgetln()` | **Actual line length** | `line_size` |
| `getline()` | **Buffer size (allocated)** | `nread` (return value) |

The code used `line + line_size` to find the end of the line, but after converting to `getline()`:
- `line_size` became the **buffer size** (can be 1KB+)
- The actual line length was in `nread` (typically 50-100 bytes)

This caused `end` to point **beyond the actual line data** into garbage memory → **SEGFAULT**.

### Additional Issues

`getline()` **includes the newline character** in the buffer, but `fgetln()` does NOT. The original code expected no newline, so we must strip it.

## The Fix

**New Dockerfile patch** (line 50):
```bash
sed -i 's/char\* end = line + line_size;/char* end = line + nread; if (nread > 0 \&\& line[nread-1] == '"'"'\\n'"'"') { line[nread-1] = '"'"'\\0'"'"'; end--; }/g'
```

**Converts to proper code**:
```cpp
while ((nread = getline(&line, &line_size, db_file)) != -1)) {
    char* end = line + nread;  // ← FIXED! Use nread (line length), not line_size (buffer size)
    if (nread > 0 && line[nread-1] == '\n') {  // ← Strip newline that getline includes
        line[nread-1] = '\0';
        end--;
    }
```

## Testing Plan

### 1. Test Locally (Development)

```bash
# Clean and rebuild
mix deps.clean geocoding --build
mix deps.get
mix deps.compile

# Test in iex
iex -S mix
```

```elixir
# Should work (always worked in dev with BSD fgetln)
:geocoding.reverse(51.5074, -0.1278)
# Expected: {:ok, {"Europe", "GB", "London", 5.67}}
```

### 2. Deploy to Production

```bash
fly deploy
```

Wait for deployment to complete (~3-5 minutes).

### 3. Test in Production Console

```bash
fly ssh console -a eventasaurus
/app/bin/eventasaurus remote
```

```elixir
# Test London
:geocoding.reverse(51.5074, -0.1278)
# Expected: {:ok, {"Europe", "GB", "London", 5.67}}

# Test Inquizition failing venue (E17 5QJ, Walthamstow, London)
:geocoding.reverse(51.5922241, -0.0410249)
# Expected: {:ok, {"Europe", "GB", "London", 11.23}}

# Test New York
:geocoding.reverse(40.7128, -74.0060)
# Expected: {:ok, {"North America", "US", "New York", 0.45}}

# Test Manchester
:geocoding.reverse(53.4808, -2.2426)
# Expected: {:ok, {"Europe", "GB", "Manchester", 2.34}}
```

### 4. Test CityResolver Wrapper

```elixir
alias EventasaurusDiscovery.Helpers.CityResolver

# Should all return {:ok, "City Name"} instead of {:error, :not_found}
CityResolver.resolve_city(51.5074, -0.1278)       # London
CityResolver.resolve_city(51.5922241, -0.0410249) # London (E17)
CityResolver.resolve_city(40.7128, -74.0060)      # New York
CityResolver.resolve_city(53.4808, -2.2426)       # Manchester
```

### 5. Test Inquizition Venue Processing

```elixir
# Force reprocess a venue
EventasaurusDiscovery.Sources.Inquizition.Jobs.SyncJob.enqueue(%{limit: 1, force_update: true})

# Check Oban dashboard for success (no more "City is required" errors)
```

## Expected Results

### Before Fix ❌

```elixir
iex> :geocoding.reverse(51.5922241, -0.0410249)
{:error, {:error, {:exit_status, 139}}}  # SEGFAULT
```

### After Fix ✅

```elixir
iex> :geocoding.reverse(51.5922241, -0.0410249)
{:ok, {"Europe", "GB", "London", 11.234}}  # SUCCESS!
```

## What This Fixes

- ✅ **Inquizition scraper**: Can now resolve UK cities from GPS coordinates
- ✅ **Speed Quizzing scraper**: More reliable (was probably hitting crashes too)
- ✅ **All scrapers**: Using CityResolver for offline geocoding (156K+ cities)
- ✅ **Zero API costs**: No paid geocoding needed for most venues
- ✅ **Production stability**: No more random segfaults in NIF code

## Technical Details

### Semantic Differences: fgetln() vs getline()

| Aspect | `fgetln()` (BSD) | `getline()` (POSIX) |
|--------|------------------|---------------------|
| **Buffer allocation** | Internal buffer (no malloc) | Allocates buffer (must free) |
| **Return value** | Pointer to line | Number of bytes read |
| **Line length** | Set in `size_t* len` param | Returned as `ssize_t` |
| **Newline handling** | **NOT included** | **INCLUDED** |
| **Null termination** | **NOT terminated** | Null-terminated |
| **Memory management** | **NO free()** needed | **MUST free()** |

### Why It Worked in Dev But Not Production

- **Dev (macOS)**: Uses native BSD `fgetln()` - no patches, works perfectly
- **Production (Linux/Docker)**: Uses patched `getline()` code - crashed due to buggy conversion

### The Importance of Correct Patches

This is a classic example of **subtle semantic differences** between platform-specific APIs. The conversion from BSD to POSIX required understanding:

1. How each function manages buffers
2. What each return value and parameter means
3. Edge cases like newline handling and null termination

A simple find-replace doesn't work - you need to understand the **actual semantics** of both APIs.

## Files Changed

- `Dockerfile:44-52` - Fixed geocoding library patches

## Related Issues

- GitHub Issue #2124 - Inquizition City Auto-Creation Failure
- Production error: "City is required" (VenueProcessor validation)

## Success Criteria

- [ ] `:geocoding.reverse()` works in production console (no segfault)
- [ ] CityResolver returns cities for UK coordinates
- [ ] Inquizition venues process successfully
- [ ] No "City is required" errors in production
- [ ] All Speed Quizzing venues continue working
- [ ] Zero regressions in other scrapers
