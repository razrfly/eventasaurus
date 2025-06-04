# Event Creation Form UI Redesign Specification

## Overview

**UI-ONLY REDESIGN**: Transform our current form layout from a long vertical design to a more visual, compact two-column design that's approximately 50% shorter while **maintaining exactly the same functionality, validations, and logic**.

## What We're NOT Changing

- ❌ **No validation changes** - all current required/optional fields remain the same
- ❌ **No logic changes** - all form handling, submission, and processing stays identical
- ❌ **No field removal** - every current field will still be present
- ❌ **No behavioral changes** - all existing smart defaults, auto-detection, etc. stay the same
- ❌ **No data model changes** - same form data structure and submission

## What We ARE Changing

- ✅ **Visual layout only** - moving from vertical sections to two-column layout
- ✅ **Field positioning** - rearranging where fields appear on screen
- ✅ **Visual hierarchy** - making some fields more/less prominent
- ✅ **One functional addition** - auto-select random default image on page load

## Current Layout Problems (UI Only)

- Form appears overwhelming due to vertical length
- Image section takes excessive vertical space when empty
- Related fields are scattered across different sections
- Visual hierarchy doesn't match importance

## New Layout Structure (Pure UI Reorganization)

### Left Column (40% width)

```
┌─────────────────────┐
│                     │
│    COVER IMAGE      │
│  (randomly auto-    │
│   selected from     │
│   our defaults)     │
│     📷 Change       │
└─────────────────────┘

Theme Selection
[Minimal ▼] [🎨 Random]
```

### Right Column (60% width)

```
Event Title: [________________] *required

📅 Start: [Wed, Jun 4] [03:00 PM] *required  
📅 End:   [Wed, Jun 4] [04:00 PM]

Timezone: [Auto-detected ▼]

📍 Venue: [Search for venue...] *required
    □ This is a virtual/online event
    Meeting URL: [https://...]

Description: [________________] *required
Tagline: [________________]

Visibility: [Public ▼]

□ Let attendees vote on the event date
[Date polling explanation panel]

[Create Event Button]
```

## Detailed UI Changes

### Section 1: Cover Image (Left Column)

- **Current**: Large empty placeholder or selected image in vertical layout
- **New**: Move to left column, auto-select random default image on page load
- **Same functionality**: All image picker features, hidden fields, attribution
- **Only change**: Random selection on form load instead of empty state

### Section 2: Theme Selection (Left Column)

- **Current**: Full section with dropdown in middle of form
- **New**: Compact selection below image
- **Same functionality**: All theme options, form submission
- **Only change**: Visual position and styling

### Section 3: Basic Information (Right Column, Top)

- **Current**: Separate section with title, tagline, description, visibility
- **New**: Title prominent at top, tagline and visibility inline/compact
- **Same functionality**: All validation, required fields unchanged
- **Only change**: Visual arrangement and hierarchy

### Section 4: Date & Time (Right Column)

- **Current**: Large section with polling explanation, separate start/end grids
- **New**: Compact inline date/time pickers, collapsible polling section
- **Same functionality**: All date validation, timezone detection, polling logic
- **Only change**: More compact visual presentation

### Section 5: Venue (Right Column)

- **Current**: Large section with search, virtual toggle, hidden fields
- **New**: Single search line with inline virtual toggle
- **Same functionality**: All Google Places integration, hidden fields, validation
- **Only change**: More compact visual layout

### Section 6: Details Section

- **Current**: Separate section (now empty after removing cover_image_url field)
- **New**: Remove this empty section entirely
- **Same functionality**: N/A (section is already empty)

## Visual Hierarchy Changes (UI Only)

### More Prominent

- Event title (larger, top of right column)
- Cover image (larger, left column)
- Date/time fields (better visual grouping)

### Less Prominent (But Still Present)

- Tagline (smaller, inline)
- Visibility (compact dropdown)
- Advanced venue fields (maintain hidden fields)

### Collapsible/Hidden by Default

- Date polling explanation (expand when checkbox checked)
- Timezone selector (keep auto-detection, show dropdown when needed)
- Advanced options section (could group tagline, visibility)

## Technical Implementation Notes

### Maintain Exact Same Form Structure

- All `name` attributes stay identical
- All hidden fields remain in place
- All phx-* attributes and event handlers unchanged
- All validation rules and required attributes unchanged

### CSS/Layout Changes Only

- Use CSS Grid or Flexbox for two-column layout
- Responsive: stack vertically on mobile
- Visual styling updates only

### Single New Feature

- Add random image selection on form mount
- Modify existing image assignment logic in LiveView
- Use existing default image service

## Mobile Responsive Behavior

- **Desktop**: Two-column layout as described
- **Mobile**: Stack to single column (image top, fields below)
- **Same functionality**: All features work identically on mobile

## Success Criteria

- ✅ Form appears ~50% shorter visually
- ✅ All existing functionality works identically  
- ✅ All tests continue to pass
- ✅ No changes to form data structure or submission
- ✅ Random image selection improves UX
- ✅ Better visual hierarchy guides user attention

This redesign is purely cosmetic reorganization with one small UX improvement (random image selection) while maintaining 100% functional compatibility. 