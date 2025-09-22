# Occurrence Bug Analysis Report

## Key Finding: False Positive Rate

You were absolutely right to be skeptical! The 57% occurrence rate is **completely wrong**.

### What's Actually Happening

```sql
Occurrence Count | Number of Events | Status
-----------------|------------------|--------
1                | 203              | ❌ BUG - Single events shouldn't have occurrences
2                | 5                | ✅ Correct - Recurring events
3                | 1                | ✅ Correct - Recurring events
61               | 1                | ✅ Correct - Muzeum Banksy
```

**Real recurring event rate: 1.9%** (7 out of 367 events)
**False positive rate: 55.3%** (203 single events incorrectly marked)

## The Bug

In `event_processor.ex` line 235:
```elixir
# CRITICAL FIX: Always initialize occurrences for new events
occurrences: initialize_occurrence_with_source(data)
```

This initializes EVERY new event with an occurrence structure, even single events. This is wrong!

## The Fix

Remove the automatic initialization. Only add occurrences when:
1. An event is identified as recurring (matches existing event)
2. Multiple dates are being consolidated

## UI Recommendations for Stacked Events

### Visual Indicators

1. **Occurrence Badge**
   - Single events: No badge
   - Recurring: `📅 2 dates` or `📅 61 dates`

2. **Card Styling**
   ```css
   .event-recurring {
     border-left: 4px solid #4CAF50;
     /* Stacked shadow effect */
   }
   ```

3. **Text Indicators**
   - "Multiple dates available"
   - "Daily through Nov 21"
   - "Next: Sept 23 • 3 more dates"

## GitHub Actions

✅ Created Issue #1194 documenting the bug and UI improvements
✅ All previous issues (#1176, #1179, #1181, #1182, #1184) were already closed

## Summary

- **Fuzzy matching**: Working correctly ✅
- **Consolidation logic**: Working correctly ✅
- **Occurrence initialization**: Has a bug causing false positives ❌
- **Expected fix**: Will reduce occurrence rate from 57% to ~2%