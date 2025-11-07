# Phase 3: Scraper Processing Logs Dashboard - UX & Functionality Issues

**Date:** 2025-11-07
**Dashboard URL:** `/admin/scraper-logs`
**Status:** Analysis Complete - No Code Changes

---

## Executive Summary

The Scraper Processing Logs dashboard has **critical filter functionality broken** due to missing form wrappers in the LiveView template. Additionally, the UI provides poor visibility into scraper health due to excessive vertical space usage and lack of overview capabilities. While the backend handlers are solid, the frontend needs significant UX improvements to be truly useful for monitoring scraper health.

---

## Testing Methodology

1. **Code Analysis:** Reviewed `scraper_logs_live.ex` and `scraper_logs_live.html.heex`
2. **Playwright Testing:** Tested all filters, buttons, and interactions in live browser
3. **Browser Console Monitoring:** Captured Phoenix LiveView errors and events
4. **Visual Analysis:** Assessed UI/UX issues with screenshots

---

## Critical Issues

### 1. ❌ Source Filter Broken

**User Claim:** "You can choose the source filter and it doesn't do anything"

**Status:** **CONFIRMED - Critical Bug**

**Evidence:**
```
Browser Console Error:
Error: form events require the input to be inside a form
```

**Root Cause:**
The source filter dropdown (`scraper_logs_live.html.heex:11-28`) uses `phx-change="select_source"` but is **not wrapped in a `<form>` tag**. Phoenix LiveView requires all form inputs with change events to be inside a form element.

**Current Code:**
```heex
<!-- Lines 11-28 -->
<div>
  <label class="block text-sm font-medium text-gray-700 mb-2">
    Source Filter
  </label>
  <select
    phx-change="select_source"
    name="source"
    class="block w-full rounded-md border-gray-300..."
  >
    <option value="all">All Sources</option>
    <%= for source <- @sources do %>
      <option value={source.name}><%= source.name %></option>
    <% end %>
  </select>
</div>
```

**Backend Handler Status:** ✅ Working correctly (`scraper_logs_live.ex:48-60`)

**Impact:** Users cannot filter by source, making it impossible to focus on specific scraper issues.

---

### 2. ❌ Time Range Filter Broken

**User Claim:** "You can do the date range. It doesn't do anything"

**Status:** **CONFIRMED - Critical Bug**

**Evidence:**
```
Browser Console Error:
Error: form events require the input to be inside a form
```

**Root Cause:**
Same issue as source filter - the time range dropdown (`scraper_logs_live.html.heex:30-45`) uses `phx-change="set_time_range"` but lacks a `<form>` wrapper.

**Current Code:**
```heex
<!-- Lines 30-45 -->
<div>
  <label class="block text-sm font-medium text-gray-700 mb-2">
    Time Range
  </label>
  <select
    phx-change="set_time_range"
    name="days"
    class="block w-full rounded-md border-gray-300..."
  >
    <option value="1">Last 24 hours</option>
    <option value="7">Last 7 days</option>
    <option value="30">Last 30 days</option>
    <option value="90">Last 90 days</option>
  </select>
</div>
```

**Backend Handler Status:** ✅ Working correctly (`scraper_logs_live.ex:63-79`)

**Impact:** Users stuck viewing last 7 days only, cannot analyze historical trends or recent issues.

---

### 3. ❌ Table Sorting Non-Existent

**User Claim:** "The sorting doesn't work"

**Status:** **CONFIRMED - Feature Never Implemented**

**Evidence:**
- Clicked on "Timestamp" column header - no action occurred
- Table headers (`scraper_logs_live.html.heex:236-251`) have no `phx-click` handlers
- No sorting state in LiveView assigns
- Headers are plain `<th>` tags with no interactivity

**Current Code:**
```heex
<!-- Lines 236-251 -->
<thead class="bg-gray-50">
  <tr>
    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
      Timestamp
    </th>
    <th scope="col" class="px-6 py-3...">Source</th>
    <th scope="col" class="px-6 py-3...">Status</th>
    <th scope="col" class="px-6 py-3...">Error Type</th>
    <th scope="col" class="px-6 py-3...">Details</th>
  </tr>
</thead>
```

**Impact:** Cannot sort by timestamp (most critical for finding recent issues), source, or error type. Makes troubleshooting difficult.

---

## User Experience Issues

### 4. ⚠️ Excessive Vertical Space Usage

**User Claim:** "The UI isn't very helpful. It shouldn't take up the entire screen"

**Status:** **CONFIRMED - Poor UX**

**Current Implementation:**
Each source gets a large card (`scraper_logs_live.html.heex:107-171`) with:
- Large heading + success rate badge
- 3-column stats grid (Total/Successes/Failures)
- "Top Error Types" breakdown section
- Border, padding, color-coded background

**Example Card Size:**
```
Cinema City - 68.1%
┌─────────────────────────────────────────┐
│ Total: 1512  Successes: 1030  Failures: 482 │
│ Top Error Types:                         │
│   • Unknown error: 482 (100.0%)         │
└─────────────────────────────────────────┘
```

**Impact:**
- With 14 active sources, requires **excessive scrolling** to see all scrapers
- Cannot quickly scan all scraper health status
- Difficult to compare scrapers side-by-side

---

### 5. ⚠️ No Overview Capability

**User Claim:** "We should see an overall, you know, it would be nice to see a percentage per scraper, but more of an overview"

**Status:** **CONFIRMED - Missing Feature**

**What's Missing:**
- Compact table view showing all sources at a glance
- Side-by-side success rate comparison
- Quick visual health indicators (🟢 >90%, 🟡 70-90%, 🔴 <70%)
- Sorting by health status or failure count
- Ability to quickly identify problematic scrapers

**Current Behavior:** Must scroll through large cards to see each source individually.

---

### 6. ⚠️ Poor Drill-Down UX

**User Claim:** "It should really let you give you an overview, but then allow you to drill down by source filter"

**Status:** **CONFIRMED - Poor Information Architecture**

**Current Issues:**
- Source filter broken (see Issue #1)
- No clear separation between overview and detail views
- All detail shown at once in large cards
- Unknown errors section shows ALL sources mixed together

**User Vision:**
1. **Overview Page:** Compact table with all sources, success rates, key metrics
2. **Detail Page:** Click a source → see detailed error breakdown, recent logs, trends

**Current Reality:** Single page trying to do both, succeeding at neither.

---

## What's Working ✅

### 1. Status Filter Buttons

**User Claim:** "The sorting doesn't work" (referring to status filter)

**Status:** **WORKS CORRECTLY** ✅

**Evidence:**
- Clicked "Failures" button → table successfully filtered to show only failures
- Console showed LiveView update event
- Uses `phx-click="filter_status"` (not `phx-change`)
- Backend handler working correctly (`scraper_logs_live.ex:95-112`)

**Why It Works:** Uses `phx-click` on buttons instead of `phx-change` on form inputs.

---

### 2. Refresh Button

**User Claim:** "The refresh button doesn't do anything. It doesn't need to be there"

**Status:** **WORKS CORRECTLY** ✅

**Evidence:**
- Clicked refresh button → data updated successfully
- PubQuiz Poland: 83.5% → 81.9%
- Totals increased (new logs processed)
- Console showed LiveView update event
- Backend handler working correctly (`scraper_logs_live.ex:82-92`)

**Recommendation:** Keep the refresh button - it's functional and useful for monitoring live data.

---

### 3. Backend Handlers

**Status:** ✅ All backend event handlers properly implemented

**Working Handlers:**
- `handle_event("select_source", ...)` - Lines 48-60
- `handle_event("set_time_range", ...)` - Lines 63-79
- `handle_event("refresh", ...)` - Lines 82-92
- `handle_event("filter_status", ...)` - Lines 95-112

**Analysis:** Backend logic is solid. Issues are purely frontend (missing form wrappers, missing sorting UI).

---

### 4. Error Categorization System

**Status:** ✅ Comprehensive and well-implemented

**Implementation:**
- Centralized in `ScraperProcessingLogs.categorize_error/1`
- Handles multiple error formats (strings, changesets, exceptions, tuples)
- 20+ error categories defined
- Unknown errors surface for investigation

**What's Good:**
- Job-level vs processing-level error distinction
- HTTP errors (timeout, 403, 404, 500, rate limit)
- Venue errors (geocoding, missing coordinates, unknown country)
- Event validation errors (missing title, start time, etc.)

---

### 5. Unknown Errors Section

**Status:** ✅ Helpful debugging feature

**What It Shows:**
- Last 10 uncategorized errors
- Source name + Job ID
- Error message preview
- Timestamp
- Metadata context

**Value:** Helps identify new error patterns that need categorization.

---

## Proposed Solutions

### Short-Term Fixes (Critical)

1. **Wrap Filters in Form Tag**
   ```heex
   <form phx-change="filter_change">
     <!-- Source filter select -->
     <!-- Time range filter select -->
   </form>
   ```
   - Consolidate into single form with unified handler
   - Fix both source and time range filters simultaneously

2. **Add Table Sorting**
   - Add `phx-click` handlers to column headers
   - Track sort column + direction in assigns
   - Add visual sort indicators (▲/▼)
   - Sort by: timestamp, source, status, error type

### Medium-Term UX Improvements

3. **Two-Page Design**

   **Overview Page:** `/admin/scraper-logs`
   - Compact table: Source | Success Rate | Total | Failures | Last Error | Actions
   - Color-coded health indicators
   - Sortable columns
   - Click source name → drill into detail page

   **Detail Page:** `/admin/scraper-logs/:source_name`
   - Source-specific stats and trends
   - Error type breakdown (current large card format)
   - Recent logs filtered by source
   - Time-series chart (optional)

4. **Compact Overview Table Design**
   ```
   Source              | Health | Total | Fails | Last Error      | Actions
   ──────────────────────────────────────────────────────────────────────────
   🟢 Ticketmaster     | 100%   | 158   | 0     | —               | [View]
   🟢 Bandsintown      | 100%   | 179   | 0     | —               | [View]
   🟡 PubQuiz Poland   | 81.9%  | 105   | 19    | Http forbidden  | [View]
   🔴 Cinema City      | 68.1%  | 1512  | 482   | Unknown error   | [View]
   ```
   - 4-5 sources visible without scrolling
   - Quick health status at a glance
   - Drill down via [View] link

### Long-Term Enhancements

5. **Real-Time Updates**
   - Subscribe to scraper job completions via PubSub
   - Auto-refresh stats every 30s
   - Live badge showing "X new logs"

6. **Trend Visualization**
   - Success rate sparklines (7-day trend)
   - Error type distribution pie chart per source
   - Alert threshold indicators

7. **Bulk Actions**
   - "Retry Failed Jobs" button per source
   - "Export Error Report" functionality
   - Acknowledge/dismiss unknown errors

---

## Technical Recommendations

### Form Wrapper Pattern
```heex
<form phx-change="update_filters">
  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
    <div>
      <label>Source Filter</label>
      <select name="source">...</select>
    </div>
    <div>
      <label>Time Range</label>
      <select name="time_range">...</select>
    </div>
  </div>
</form>
```

### Sorting Implementation
```elixir
def mount(_params, _session, socket) do
  socket
  |> assign(:sort_by, :timestamp)
  |> assign(:sort_dir, :desc)
  # ... rest of assigns
end

def handle_event("sort", %{"column" => column}, socket) do
  # Toggle direction if same column, else default to desc
  sort_dir =
    if socket.assigns.sort_by == String.to_atom(column) do
      toggle_direction(socket.assigns.sort_dir)
    else
      :desc
    end

  socket
  |> assign(:sort_by, String.to_atom(column))
  |> assign(:sort_dir, sort_dir)
  |> load_recent_logs()
  |> then(&{:noreply, &1})
end
```

---

## Files Involved

- **Backend:** `lib/eventasaurus_web/live/admin/scraper_logs_live.ex`
- **Frontend:** `lib/eventasaurus_web/live/admin/scraper_logs_live.html.heex`
- **Router:** `lib/eventasaurus_web/router.ex:61`
- **Context:** `lib/eventasaurus_discovery/scraper_processing_logs.ex`

---

## User Claims vs Reality

| User Claim | Status | Notes |
|------------|--------|-------|
| "Sorting doesn't work" | ✅ Confirmed | Table sorting never implemented |
| "Source filter doesn't do anything" | ✅ Confirmed | Missing form wrapper |
| "Date range doesn't do anything" | ✅ Confirmed | Missing form wrapper |
| "Refresh button doesn't do anything" | ❌ Incorrect | Refresh works correctly |
| "UI takes up entire screen" | ✅ Confirmed | Large cards use excessive space |
| "Need overview + drill down" | ✅ Confirmed | Single-page design insufficient |

---

## Next Steps

1. **Immediate:** Fix form wrapper issue (blocks core filtering functionality)
2. **Short-term:** Add table sorting (improves troubleshooting workflow)
3. **Medium-term:** Design two-page overview + detail architecture
4. **Long-term:** Real-time updates and trend visualization

---

## Conclusion

The Scraper Processing Logs dashboard has **solid backend infrastructure** (handlers, error categorization, data collection), but the **frontend implementation has critical bugs** (missing form wrappers) and **poor UX design** (excessive space, no overview capability).

**Priority:** Fix form wrappers first (blocks all filtering), then redesign for overview + drill-down pattern.

**Recommendation:** Two-page design with compact overview table showing health percentages, then detailed drill-down pages per source with current card format.
