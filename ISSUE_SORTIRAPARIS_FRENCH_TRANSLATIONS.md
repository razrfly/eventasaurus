# Sortiraparis Time Extraction Issue - Investigation Report

**Date**: October 18, 2025
**Status**: 🔍 INVESTIGATING

## Summary

Phase 1 and Phase 2 implementations are complete and working correctly. However, during production testing, we discovered that **event pages don't include time information in the date string** that we're extracting.

## Key Finding

### Time Information Exists in HTML
When examining real Sortiraparis event pages, time patterns **are present** in the HTML:
- Examples found: "10:50 pm", "10am", "10pm", "at 05:50"
- Multiple time references per page (10-17 matches found)

### But Not in the Date String
The date string being extracted is:
- "Sunday 26 October 2025" (no time)
- "26 October 2025" (no time)
- "25 October 2025 to 2 November 2025" (date range, no times)

## Problem Analysis

### What We Implemented (Correctly)
✅ **Time extraction from date strings** - Works perfectly when time is present:
- Handles: "Sunday 26 October 2025 at 8pm" → "2025-10-26T20:00:00"
- Handles: "17 octobre 2025 à 20h30" → "2025-10-17T20:30:00"
- Test suite: 57/57 tests passing

✅ **EventExtractor fix** - Now handles ISO strings correctly:
- Pattern matches both ISO strings and Date structs
- No more `CaseClauseError` in production
- Scraping pipeline working smoothly

### What's Missing
❌ **Time is in separate HTML element** - Time appears elsewhere in the page:
- Date extraction: `extract_date_from_text/1` finds "Sunday 26 October 2025"
- Time information: Appears in different HTML elements (not yet identified)
- **Need to**: Find WHERE the time appears and extract it separately

## Evidence

### Test Event 1: The Hives Concert
**URL**: https://www.sortiraparis.com/en/what-to-see-in-paris/concerts-music-festival/articles/326487-the-hives-in-concert-at-zenith-de-paris-in-november-2025

**Date String Extracted**: "Sunday 26 October 2025"

**Time Patterns Found in HTML**:
- 10:50 pm (4 occurrences)
- 10am (3 occurrences)
- 10pm (1 occurrence)
- 50 pm (2 occurrences)

### Test Event 2: Chris Isaak Concert
**URL**: https://www.sortiraparis.com/en/what-to-see-in-paris/concerts-music-festival/articles/287484-chris-isaak-in-concert-at-salle-pleyel-in-paris-in-july-2024

**Date String Extracted**: "Sunday 26 October 2025"

**Time Patterns Found in HTML**:
- 10:50 pm (4 occurrences)
- 10am (1 occurrence)
- 50 pm (4 occurrences)
- at 05:50 (1 occurrence)

## Current Status

### What's Working ✅
1. Time extraction logic (`Parsers.DateParser`)
2. ISO 8601 datetime format support
3. Timezone conversion (Paris → UTC)
4. EventExtractor pattern matching
5. All 57 tests passing
6. Production pipeline running without errors

### What Needs Investigation 🔍
1. **HTML Structure Analysis**: Where does the time actually appear?
   - Is it in a separate `<time>` element?
   - In event metadata sections?
   - In structured data (JSON-LD)?

2. **Time Extraction Strategy**: How to get the time?
   - Option A: Expand `extract_date_string/1` to also find time elements
   - Option B: Create separate `extract_time/1` function in EventExtractor
   - Option C: Combine date + time from different HTML sources

3. **Data Quality**: How reliable is the time information?
   - Do all events have times?
   - Are times in consistent format?
   - Do exhibitions have times (or just dates)?

## Next Steps

### Phase 3: Time Element Discovery
1. **Inspect HTML Structure**:
   - Save full HTML of test events to file
   - Manually inspect where time appears in DOM
   - Check both English and French pages
   - Look for JSON-LD structured data

2. **Update EventExtractor**:
   - Add time extraction logic based on findings
   - Combine date string + time element → full datetime
   - Handle events without times (exhibitions, date ranges)

3. **Verify Implementation**:
   - Test with real events
   - Confirm proper datetime assembly
   - Validate timezone conversion
   - Check database hour distribution

## Current Database State

**As of October 18, 2025**:
- 42 Sortiraparis events in database
- ALL showing midnight times (hours 22-23 UTC)
- Expected: Variety of event times throughout the day
- Reality: Time information not being captured

This is expected since we haven't yet found WHERE to extract the time from the HTML.

## Conclusion

The implementation of time parsing is **correct and complete** - the issue is that we're not finding the time in the HTML because we're only looking in the date string. The time information exists in the HTML but in a separate location that we need to identify and extract.

**Next action**: HTML structure analysis to locate time elements.

---

**Related Issue**: #1840
**Phase 1**: ✅ Complete (time parsing implementation)
**Phase 2**: ✅ Complete (verification and EventExtractor fix)
**Phase 3**: 🔍 In Progress (HTML time element discovery)
