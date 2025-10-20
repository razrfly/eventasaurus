# CodeRabbit Review Suggestions - Implementation Status

## Critical Issues ✅ Already Fixed

### 1. Cross-Year Date Range Bug
**Status**: ✅ **ALREADY FIXED**
**Files**:
- `lib/eventasaurus_discovery/sources/shared/parsers/date_patterns/english.ex` (lines 117-136)
- `lib/eventasaurus_discovery/sources/shared/parsers/multilingual_date_parser.ex` (lines 241-260)

**Issue**: Full-date range never matched; cross-year ranges normalized incorrectly
- Branch check used `/to.*to/` which never matched
- Only `end_year` was stored, causing cross-year inputs like "October 15, 2025 to January 19, 2026" to produce wrong start dates

**Fix Applied**:
- English parser now captures both `start_year` and `end_year`
- Multilingual parser has dedicated clause for cross-year normalization
- Both start and end dates use their respective years

---

## Major Issues - Recommended to Implement

### 2. Missing Short-Range Date Patterns
**Status**: ❌ **NOT IMPLEMENTED**
**Priority**: **HIGH** (15-20% miss rate)
**File**: `lib/eventasaurus_discovery/sources/sortiraparis/extractors/event_extractor.ex` (lines 332-352)

**Issue**: Common date formats not matched:
- English: "from July 4 to 6, 2025"
- English: "from 4 to 6 July 2025"
- French: "du 4 au 6 juillet 2025"

**Recommendation**: Add these patterns to the extraction regex list (most-specific first):

```elixir
patterns = [
  # Short range, EN: "from July 4 to 6, 2025"
  ~r/(?:From|from)\s+#{months}\s+\d+(?:er|st|nd|rd|th)?\s+to\s+\d+(?:er|st|nd|rd|th)?,?\s+\d{4}/i,
  # Short range, EN: "from 4 to 6 July 2025"
  ~r/(?:From|from)\s+\d+(?:er|st|nd|rd|th)?\s+to\s+\d+(?:er|st|nd|rd|th)?\s+#{months}\s+\d{4}/i,
  # Short range, FR: "du 4 au 6 juillet 2025"
  ~r/(?:Du|du)\s+\d+(?:er|e)?\s+au\s+\d+(?:er|e)?\s+#{months}\s+\d{4}/i,
  # ... existing patterns ...
]
```

**Impact**: Would reduce unknown_occurrence rate by 15-20%

---

### 3. Test File Crashes - Nil DateTime Guards
**Status**: ❌ **NOT IMPLEMENTED**
**Priority**: **MEDIUM** (test reliability)
**Files**:
- `test_live_scrape.exs` (lines 45-47)
- `test_unknown_occurrence.exs` (lines 33-36)

**Issue**: `DateTime.to_iso8601(event.starts_at)` crashes if `starts_at` is nil

**Recommendation**: Guard like `ends_at`:

```elixir
# test_live_scrape.exs line 45
-        ├─ Starts At: #{DateTime.to_iso8601(event.starts_at)}
+        ├─ Starts At: #{if event.starts_at, do: DateTime.to_iso8601(event.starts_at), else: "nil"}
```

**Impact**: Prevents test crashes when unknown_occurrence events have no dates

---

### 4. Test File Crashes - Metadata Access
**Status**: ❌ **NOT IMPLEMENTED**
**Priority**: **MEDIUM** (test reliability)
**Files**:
- `test_multilingual_parser_integration.exs` (lines 33-34, 142-145)

**Issue**: Using dot access (`event.metadata.occurrence_type`) on string-keyed metadata

**Recommendation**: Use bracket access:

```elixir
# Line 33-34
-    IO.puts("   Original date string: #{inspect(event.metadata.original_date_string)}")
+    IO.puts("   Original date string: #{inspect(event.metadata["original_date_string"])}")

# Lines 142-145
-    IO.puts("   Occurrence type: #{event.metadata.occurrence_type}")
+    IO.puts("   Occurrence type: #{event.metadata["occurrence_type"]}")
```

**Impact**: Prevents KeyError in test scripts

---

### 5. Missing DateParser Module
**Status**: ❌ **NOT IMPLEMENTED**
**Priority**: **MEDIUM** (tests cannot run)
**File**: `test/eventasaurus_discovery/sources/sortiraparis/parsers/date_parser_test.exs`

**Issue**: Tests reference `EventasaurusDiscovery.Sources.Sortiraparis.Parsers.DateParser` which doesn't exist

**Current Implementation**: Uses shared `MultilingualDateParser` instead

**Options**:
1. **Create wrapper module** at `lib/eventasaurus_discovery/sources/sortiraparis/parsers/date_parser.ex`
2. **Update tests** to use `MultilingualDateParser` directly
3. **Remove tests** if redundant with multilingual parser tests

**Recommendation**: Option 2 or 3 - avoid unnecessary wrapper modules

---

## Minor Issues - Nice to Have

### 6. JSONB Index for occurrence_type
**Status**: ❌ **NOT IMPLEMENTED**
**Priority**: LOW (performance optimization)
**File**: `lib/eventasaurus_discovery/public_events.ex` (lines 738-756)

**Issue**: Queries `metadata->>'occurrence_type'` without index

**Recommendation**: Add expression index in migration:

```sql
CREATE INDEX idx_public_event_sources_occurrence_type
ON public_event_sources ((metadata->>'occurrence_type'));
```

**Impact**: Improves query performance as dataset grows

---

### 7. Division by Zero Guard
**Status**: ❌ **NOT IMPLEMENTED**
**Priority**: LOW (edge case)
**File**: `test_direct_urls.exs` (lines 89-90)

**Issue**: Potential division by zero if all tests fail during fetching

**Recommendation**: Add guard:

```elixir
success_rate = if length(results) > 0 do
  Float.round(successes / length(results) * 100, 1)
else
  0.0
end
```

---

### 8. Documentation Fix
**Status**: ❌ **NOT IMPLEMENTED**
**Priority**: LOW (documentation accuracy)
**File**: `lib/eventasaurus_discovery/sources/shared/parsers/multilingual_date_parser.ex` (lines 382-386)

**Issue**: Doc example shows `:polish` but it's not in `@language_modules`

**Recommendation**: Update example:

```elixir
-      # => [:french, :english, :polish]
+      # => [:french, :english]
```

---

### 9. Original Date String Metadata
**Status**: ❌ **NOT IMPLEMENTED**
**Priority**: LOW (debugging aid)
**File**: `UNKNOWN_OCCURRENCE_AUDIT.md` assessment

**Issue**: `original_date_string` field is empty in production metadata

**Root Cause**: Field name mismatch between EventExtractor and Transformer

**Recommendation**:
1. Investigate actual field name from EventExtractor
2. Add fallback to try multiple field names
3. Add logging when empty

**Impact**: Better debugging and monitoring of date parsing failures

---

---

## ADDITIONAL CRITICAL SECURITY ISSUES

### 10. Missing Admin Role Verification
**Status**: ❌ **NOT IMPLEMENTED**
**Priority**: **CRITICAL** (Security vulnerability)
**File**: `lib/eventasaurus_web/controllers/admin/source_stats_controller.ex`

**Issue**: API endpoint `/api/admin/stats/source/:source_slug` allows ANY authenticated user to access admin statistics

**Root Cause**:
- Pipeline uses only `:api_authenticated` (checks if user exists)
- Controller has NO admin role verification
- `require_authenticated_api_user` plug validates JWT but NOT admin status

**Security Impact**:
- **Information Disclosure**: Non-admin users can access comprehensive discovery statistics
- **Access Control Bypass**: "/api/admin/" prefix implies admin-only but doesn't enforce it
- **No Authorization Layer**: Missing role-based access control

**Recommendation**: Add admin verification plug

**Option 1: Create Admin API Pipeline**
```elixir
# router.ex
pipeline :admin_api do
  plug :require_authenticated_api_user
  plug :require_admin_role  # NEW PLUG NEEDED
end

scope "/api/admin", EventasaurusWeb.Admin, as: :admin_api do
  pipe_through [:secure_api, :admin_api]  # Changed from :api_authenticated

  get "/stats/source/:source_slug", SourceStatsController, :show
end
```

**Option 2: Controller-Level Check**
```elixir
# source_stats_controller.ex
def show(conn, params) do
  with {:ok, user} <- verify_admin_user(conn) do
    # existing implementation
  else
    {:error, :not_admin} ->
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Admin access required"})
  end
end

defp verify_admin_user(conn) do
  case conn.assigns[:current_user] do
    %{role: "admin"} = user -> {:ok, user}
    _ -> {:error, :not_admin}
  end
end
```

**Recommendation**: Use **Option 1** (pipeline approach) for consistency with other admin routes

---

### 11. Unsafe JSONB Integer Casting
**Status**: ❌ **NOT IMPLEMENTED**
**Priority**: **HIGH** (Runtime error potential)
**File**: `lib/eventasaurus_discovery/admin/discovery_stats_collector.ex`

**Issue**: Casting `args->>'city_id'` to integer without validation can crash queries

**Locations**:
- Line 147-148: `get_metadata_based_source_stats/2`
- Line 233-235: `get_detailed_source_stats/2`
- Line 384-386: `get_event_level_stats/3`
- Line 447-449: Another query function

**Root Cause**:
```elixir
where: fragment("(? ->> 'city_id')::integer = ?", j.args, ^city_id)
```

If `city_id` field contains non-numeric value, PostgreSQL raises `invalid input syntax for type integer`

**Recommendation**: Add regex guard before casting

```elixir
# Before
where: fragment("(? ->> 'city_id')::integer = ?", j.args, ^city_id)

# After
where: fragment("?->>'city_id' ~ '^[0-9]+$'", j.args),
where: fragment("(? ->> 'city_id')::integer = ?", j.args, ^city_id)
```

**Impact**: Prevents query crashes from malformed job arguments

---

### 12. LiveView Crash from Unsafe Atom Conversion
**Status**: ❌ **NOT IMPLEMENTED**
**Priority**: **MEDIUM** (LiveView stability)
**File**: `lib/eventasaurus_web/live/admin/discovery_stats_live/source_detail.ex`

**Issue**: `String.to_existing_atom/1` raises if client sends unexpected value

**Locations**:
- Line 116: `handle_event("sort_categories", ...)`
- Line 131: `handle_event("sort_venues", ...)`

**Root Cause**:
```elixir
def handle_event("sort_categories", %{"by" => sort_by}, socket) do
  sort_atom = String.to_existing_atom(sort_by)  # CRASH if unexpected value
  # ...
end
```

**Recommendation**: Safe atom conversion with fallback

```elixir
def handle_event("sort_categories", %{"by" => sort_by}, socket) do
  sort_atom = safe_sort_atom(sort_by, :category)
  categories = sort_categories(socket.assigns.comprehensive_stats.top_categories, sort_atom)
  # ...
end

def handle_event("sort_venues", %{"by" => sort_by}, socket) do
  sort_atom = safe_sort_atom(sort_by, :venue)
  venues = sort_venues(socket.assigns.comprehensive_stats.venue_stats.top_venues, sort_atom)
  # ...
end

defp safe_sort_atom("count", _), do: :count
defp safe_sort_atom("name", _), do: :name
defp safe_sort_atom("percentage", :category), do: :percentage
defp safe_sort_atom(_, _), do: :count  # Default fallback
```

**Impact**: Prevents LiveView crashes from malicious/unexpected client input

---

### 13. Test Script Pattern Matching Bug
**Status**: ❌ **NOT IMPLEMENTED**
**Priority**: **LOW** (Test accuracy)
**File**: `test_french_fetch_failures.exs`

**Issue**: Inconsistent tuple pattern matching produces incorrect counts

**Root Cause** (lines 87-96):
- Success results: `{event_id, {:success, :extracted, length}}` (3-tuple)
- Failure results: `{event_id, {:failed, :bot_protection}}` (2-tuple)
- Current patterns don't correctly distinguish between success/failure structures

**Recommendation**: Use explicit pattern matching

```elixir
# Before (incorrect)
success_count = Enum.count(results, fn {_, {status, _, _}} -> status == :success end)
bot_protection_count = Enum.count(results, fn {_, {_, reason}} -> reason == :bot_protection end)

# After (correct)
success_count = Enum.count(results, fn
  {_, {:success, _, _}} -> true
  _ -> false
end)

bot_protection_count = Enum.count(results, fn
  {_, {:failed, :bot_protection}} -> true
  _ -> false
end)
```

---

## Implementation Priority

### **IMMEDIATE** (Security Fix - URGENT)
1. **🚨 Missing admin role verification** - **CRITICAL SECURITY ISSUE**
   - ANY authenticated user can access admin API
   - Requires admin role check in controller or pipeline

### **HIGH** (Stability & Performance)
2. ❌ Unsafe JSONB casting - **Prevents query crashes**
3. ❌ LiveView atom conversion - **Prevents crashes**
4. ✅ Cross-year date range bug - **Already fixed**
5. ❌ Missing short-range patterns - **15-20% improvement**
6. ❌ Nil DateTime guards in tests - **Prevents crashes**
7. ❌ Metadata access fixes in tests - **Prevents KeyError**

### **MEDIUM** (Following Sprint)
8. ❌ DateParser module or test updates
9. ❌ JSONB index optimization

### **LOW** (As Needed)
10. ❌ Test script pattern matching
11. ❌ Division by zero guards
12. ❌ Documentation fixes
13. ❌ Original date string metadata fix

---

## Notes

- **CRITICAL**: Issue #10 (admin auth) must be fixed before next deployment
- Most critical date parsing issues (cross-year dates) are **already resolved**
- Remaining issues are primarily **security**, **stability**, and **performance optimizations**
- Short-range pattern addition would have **highest immediate impact** on data quality
