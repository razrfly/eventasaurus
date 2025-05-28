# Dark Mode Navbar Specification

## Overview
Implement a simple dark mode navbar variant for Eventasaurus themes that have dark backgrounds (cosmic, and potentially others). This follows Tailwind CSS dark mode best practices and the Radiant template approach.

## Problem Statement
- Current navbar uses light theme colors (`text-gray-700`, `bg-white`, etc.)
- Dark background themes (like cosmic) make the navbar unreadable
- Need a simple toggle between light and dark navbar variants

## Solution Approach

### 1. Theme Classification
**Light Themes (use normal navbar):**
- `:minimal` 
- `:velocity`
- `:retro` 
- `:celebration`
- `:nature`
- `:professional`

**Dark Themes (use dark navbar):**
- `:cosmic`
- Any future dark themes

### 2. Implementation Strategy

#### A. Theme Helper Function
Add a simple helper function to determine if a theme is dark:
```elixir
def dark_theme?(theme) when theme in [:cosmic], do: true
def dark_theme?(_theme), do: false
```

#### B. Conditional CSS Classes in Template
Replace hardcoded Tailwind classes with conditional ones:

**Current (hardcoded light):**
```heex
<header class="bg-white shadow-sm">
  <nav class="text-gray-700">
```

**New (conditional):**
```heex
<header class={if dark_theme?(@theme), do: "bg-gray-900 shadow-lg", else: "bg-white shadow-sm"}>
  <nav class={if dark_theme?(@theme), do: "text-gray-100", else: "text-gray-700"}>
```

#### C. Logo Variant (Future Enhancement)
- Keep current logo for light themes
- Add white/light logo variant for dark themes
- Use conditional rendering based on theme

### 3. Specific Color Mappings

#### Light Navbar (Default)
- Background: `bg-white`
- Text: `text-gray-700`
- Links: `text-gray-700 hover:text-gray-900`
- Borders: `border-gray-200`
- Shadow: `shadow-sm`

#### Dark Navbar
- Background: `bg-gray-900` or `bg-slate-900`
- Text: `text-gray-100`
- Links: `text-gray-100 hover:text-white`
- Borders: `border-gray-700`
- Shadow: `shadow-lg`

### 4. Implementation Steps

1. **Add theme classification helper** to `ThemeHelpers`
2. **Update root layout template** with conditional classes
3. **Test with cosmic theme** to ensure readability
4. **Add logo variant support** (optional future enhancement)

### 5. Benefits of This Approach

- **Simple**: Only two variants (light/dark)
- **Maintainable**: Uses standard Tailwind dark mode patterns
- **Scalable**: Easy to add new dark themes
- **Performance**: No CSS overrides, just conditional classes
- **Consistent**: Follows Tailwind/Radiant conventions

### 6. Files to Modify

1. `lib/eventasaurus_web/theme_helpers.ex` - Add `dark_theme?/1` function
2. `lib/eventasaurus_web/components/layouts/root.html.heex` - Update navbar classes
3. Test with cosmic theme

### 7. Future Enhancements

- Add logo variants for dark themes
- Support for user-toggled dark mode (independent of theme)
- Dark mode variants for other UI components as needed

## Success Criteria

- Cosmic theme navbar is fully readable with light text on dark background
- Light themes continue to work with existing navbar styling
- Implementation is simple and maintainable
- Easy to classify future themes as light or dark 