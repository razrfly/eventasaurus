# Geocoding Library Segfault Fix - RESOLVED

**Status**: ✅ **FIXED and deployed to production**

**Production Test Result**:
```elixir
iex> :geocoding.reverse(51.5922241, -0.0410249)
{:ok, {:europe, :gb, "Harringay", 4190.183711}}
```

## Problem Summary

The `:geocoding` Erlang library (v0.3.1) was experiencing segmentation faults (SIGSEGV/SIGABRT) in production Docker containers due to BSD→Linux API incompatibility in `GeocodingDriver.cpp`.

**Symptoms**:
- Development (macOS): ✅ Works
- Production (Linux Docker): ❌ Crashes with exit status 134 (SIGABRT)
- Error: `{:error, {:error, {:exit_status, 134}}}`

## Root Cause Analysis

### The Bug

The C++ code used BSD's `fgetln()` API, which was patched to use POSIX `getline()`. However, **the semantic differences between these APIs caused heap corruption**:

**fgetln() behavior**:
```cpp
while ((line = fgetln(db_file, &line_size))) {
    // line is reassigned each iteration to fgetln's internal buffer
    // Parsing functions can modify 'line' safely because it's reassigned next loop
    id = read_integer(&line);  // modifies line pointer
}
```

**Initial broken getline() attempt**:
```cpp
char* line = NULL;
size_t line_size = 0;

while (getline(&line, &line_size, db_file) != -1) {
    // getline() allocates buffer and expects 'line' to remain stable!
    id = read_integer(&line);  // ❌ MODIFIES line pointer!
    // Next iteration: getline(&line, ...) receives corrupted pointer
    // → tries to realloc() from invalid address → SIGABRT
}
```

**The Critical Insight**: The parsing functions (`read_integer()`, `read_double()`, `read_string()`) all advance the `line` pointer by calling `strtol(*line, line, 10)` and similar functions. With `fgetln()`, this was fine because `line` was completely reassigned each iteration. With `getline()`, we're passing `&line`, so getline() expects that pointer address to remain stable for proper memory management.

### The Fix

**Use TWO separate pointers**:
- `buffer` → Owned by getline(), never modified, used for realloc() and free()
- `line` → Parsing pointer, initialized from buffer each iteration, can be modified freely

```cpp
char* buffer = NULL;
size_t buffer_size = 0;
ssize_t nread;

while ((nread = getline(&buffer, &buffer_size, db_file)) != -1) {
    char* line = buffer;  // Create separate parsing pointer
    if (nread > 0 && line[nread-1] == '\n') {
        line[nread-1] = '\0';
        nread--;
    }
    char* end = line + nread;

    // Parsing functions modify 'line', but 'buffer' remains stable
    id = read_integer(&line);
    latitude = read_double(&line);
    longitude = read_double(&line);
    // ... rest of parsing
}
if (buffer) free(buffer);  // Free using original buffer pointer
```

## Files Changed

**Dockerfile** (line 24):
- Added `patch` utility to apt-get install (was missing!)

**Dockerfile** (lines 44-57):
- Patch application with before/after validation

**geocoding_fix.patch**:
- Implements the two-pointer solution
- Properly strips newline and manages memory

## Verification

1. ✅ Build succeeded with patch applied
2. ✅ Compilation succeeded (only warnings, no errors)
3. ✅ Production test: `:geocoding.reverse(51.5922241, -0.0410249)` returns correct result
4. ✅ Inquizition scraper can now auto-create cities from coordinates

## Analysis Process

This fix was discovered through:
1. **Sequential Thinking MCP**: 10-step systematic analysis
2. **Root Cause Investigation**: Understanding fgetln vs getline semantics
3. **Pointer Arithmetic Analysis**: Tracking how line pointer is modified
4. **Memory Management Review**: Identifying the realloc() corruption pattern

## Impact

- ✅ All scrapers can now use CityResolver for offline geocoding
- ✅ Inquizition VenueDetailJob no longer fails with "City is required"
- ✅ No more segfaults in production
- ✅ Works identically in development and production

## Related Issues

- #2123 - Inquizition error tracking and force_update
- Root cause of Inquizition VenueDetailJob failures (now resolved)
