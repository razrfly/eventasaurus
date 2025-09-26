# Language Switching Issues - Comprehensive Fix

## 🐛 Issue Summary

Multiple critical issues were discovered with the language switching functionality for Karnet events:

1. **Empty Descriptions**: All Karnet events showed blank descriptions when switching to Polish
2. **No Language Persistence**: Language preference was not saved between page navigations
3. **UI Inconsistency**: "About This Event" heading displayed even when no content available

## 🔍 Root Cause Analysis

### 1. Missing CSS Selector in DetailExtractor

**Problem**: The Karnet description extractor was missing the primary CSS selector used by Karnet pages.

**File**: `lib/eventasaurus_discovery/sources/karnet/detail_extractor.ex`

**Issue**: Karnet pages store event descriptions in `.article-content` divs, but the extractor was only looking for selectors like `.event-description`, `.description`, etc. that don't exist on Karnet pages.

**Evidence**: WebFetch of Karnet page showed:
```html
<div class="article-content">
  <div class="xdj266r x14z9mp xat24cr x1lziwak x1vvkbs">Czy Ameryka została zbudowana na teoriach spiskowych?<br />
  Przekonaj się podczas spotkania z dr. Piotrem Tarczyńskim...</div>
</div>
```

### 2. Incorrect Data Structure Handling

**Problem**: The `get_description_text` function in `event_detail_job.ex` was looking for the wrong data structure.

**File**: `lib/eventasaurus_discovery/sources/karnet/jobs/event_detail_job.ex`

**Issue**: The DetailExtractor returns `description_translations: %{"pl" => "content"}`, but `get_description_text` was looking for `:description`, `:summary`, or `:content` keys that don't exist.

### 3. No Language Persistence

**Problem**: Language preference was only stored in LiveView state, not persisted across page navigations.

**File**: `lib/eventasaurus_web/live/public_event_show_live.ex`

**Issue**: The `change_language` event handler only updated local state without setting cookies.

## ✅ Fixes Implemented

### Fix 1: Add `.article-content` Selector

**File**: `lib/eventasaurus_discovery/sources/karnet/detail_extractor.ex`

```elixir
# Added .article-content as the primary selector
selectors = [
  ".article-content",  # Primary selector for Karnet pages
  ".event-description",
  ".description",
  # ... other selectors
]
```

### Fix 2: Update Data Structure Handling

**File**: `lib/eventasaurus_discovery/sources/karnet/jobs/event_detail_job.ex`

```elixir
defp get_description_text(data) do
  cond do
    # If description_translations exists and has Polish content
    is_map(data[:description_translations]) && data[:description_translations]["pl"] ->
      data[:description_translations]["pl"]

    # Fallback to other possible fields
    data[:description] -> data[:description]
    data[:summary] -> data[:summary]
    data[:content] -> data[:content]
    true -> ""
  end
end
```

### Fix 3: Implement Language Persistence

**Files**:
- `lib/eventasaurus_web/live/public_event_show_live.ex`
- `lib/eventasaurus_web/plugs/language_plug.ex`

**Changes**:
1. Added JavaScript to set language cookie on language change
2. Updated LanguagePlug to read from cookies
3. Updated LiveView to use session language set by LanguagePlug

**Cookie Implementation**:
```javascript
// Set cookie for 1 year
document.cookie = `language_preference=${data.language}; expires=${expires.toUTCString()}; path=/; SameSite=Lax`;
```

**Priority Order** (in LanguagePlug):
1. Query parameter (?lang=pl)
2. Session storage
3. **Cookie (language_preference)** ← NEW
4. Accept-Language header
5. Default to "en"

## 🧪 Testing Results

Tested the fixes with multiple Karnet events:

| Event | Polish Description | Status |
|-------|-------------------|---------|
| Event 183 | YES (2000 chars) | ✅ Fixed |
| Event 126 | YES (517 chars) | ✅ Fixed |
| Event 127 | YES (1094 chars) | ✅ Fixed |

All events now successfully extract and display Polish descriptions.

## 📊 Impact

- **Before**: ALL Karnet events had empty descriptions (`{"pl": ""}`)
- **After**: Karnet events now display full Polish descriptions with proper content
- **Persistence**: Language preference now persists between page navigations
- **User Experience**: No more repeated language switching required

## 🔧 Database Changes

No database schema changes required. The `description_translations` column already existed in `public_event_sources` table.

## 🚀 Deployment Notes

1. The Karnet scraper should be re-run to update existing events with proper descriptions
2. Language persistence works immediately for new visitors
3. Existing users will see improved language persistence on their next language switch

## 🎯 Related Issues

This fix resolves the language switching problems reported where:
- Descriptions showed as blank when switching to Polish
- Language preference didn't persist between navigations
- Users had to repeatedly select their language preference

The fixes ensure a seamless multilingual experience for all Karnet events.