# Image Picker Unification Specification

## Problem Statement

The new event page and edit event page currently use **completely different image picker implementations**, resulting in inconsistent user experience and duplicated code.

## Current State Analysis

### **New Event Page - ADVANCED IMPLEMENTATION**
- ✅ **Unified Search**: Uses `unified_search` event handler
- ✅ **TMDB + Unsplash**: Shows both movie database and stock photo results
- ✅ **Default Images**: Shows categorized default images (general, abstract, invites, tech)
- ✅ **Advanced Layout**: Left sidebar with categories, main content area
- ✅ **Upload Support**: File upload functionality
- ✅ **Consistent Metadata**: Standardized image data structure

### **Edit Event Page - LEGACY IMPLEMENTATION**
- ❌ **Unsplash Only**: Uses old `search_unsplash` event handler
- ❌ **No TMDB**: Missing movie database search results
- ❌ **No Defaults**: No default image categories shown
- ❌ **Simple Layout**: Basic grid without categories
- ❌ **Limited Upload**: Basic upload without advanced features
- ❌ **Inconsistent Metadata**: Different data structure

## Root Cause

The edit page was never updated during the image refactor and still uses the **old image picker implementation** from before the unified interface was created.

## Solution Approach

### **Strategy: Component Extraction + Unification**

1. **Extract Unified Component**: Create a reusable `ImagePickerModal` component
2. **Single Event Handler**: Use `unified_search` for both pages
3. **Consistent Data Flow**: Same image selection logic and metadata
4. **Shared Styling**: Identical layout and user experience

## Proposed Implementation

### **1. Create Shared Component**
- **File**: `lib/eventasaurus_web/components/image_picker_modal.ex`
- **Purpose**: Single reusable image picker component
- **Features**: All advanced functionality from new page

### **2. Component Interface**
```elixir
<.image_picker_modal
  id="image-picker"
  show={@show_image_picker}
  current_image={@form_data.cover_image_url}
  on_select="image_selected"
  on_close="close_image_picker"
  search_results={@search_results}
  default_images={@default_images}
  upload={@uploads.cover_image}
/>
```

### **3. Unified Event Handlers**
- **Remove**: `search_unsplash` from edit page
- **Use**: `unified_search` for both pages
- **Standardize**: Image selection and upload logic

### **4. Consistent Data Structure**
Both pages will use the same metadata format:
```elixir
%{
  "source" => "unsplash|tmdb|default|upload",
  "url" => "https://...",
  "title" => "Image title",
  "filename" => "filename.jpg",
  # ... additional source-specific metadata
}
```

## Implementation Steps

### **Phase 1: Component Extraction**
1. Create `ImagePickerModal` component in `components/`
2. Move all image picker HTML from `new.html.heex` to component
3. Extract image picker JavaScript/hooks to shared location
4. Test component works identically on new page

### **Phase 2: Edit Page Migration**
1. Replace edit page image picker with new component
2. Update edit page event handlers to use `unified_search`
3. Remove old `search_unsplash` logic from edit LiveView
4. Update edit page image selection handling

### **Phase 3: Code Cleanup**
1. Remove duplicate image picker HTML from both templates
2. Remove old event handlers and functions
3. Consolidate image-related JavaScript
4. Update tests to use unified component

### **Phase 4: Testing & Validation**
1. Verify feature parity between new and edit pages
2. Test all image sources (TMDB, Unsplash, default, upload)
3. Validate metadata consistency
4. Check mobile responsiveness

## Expected Benefits

### **User Experience**
- ✅ **Consistent Interface**: Same image picker across all pages
- ✅ **Feature Parity**: Edit page gets TMDB search and default images
- ✅ **Better Organization**: Categorized default images on edit page
- ✅ **Upload Consistency**: Same upload experience everywhere

### **Developer Experience**
- ✅ **DRY Code**: Single image picker implementation
- ✅ **Easier Maintenance**: Changes in one place affect all pages
- ✅ **Consistent Logic**: Same event handlers and data flow
- ✅ **Better Testing**: Single component to test thoroughly

### **Technical Benefits**
- ✅ **Code Reduction**: ~50% less image picker code
- ✅ **Consistent Metadata**: Standardized across all pages
- ✅ **Unified Styling**: Same Tailwind classes and layout
- ✅ **Shared Hooks**: Consolidated JavaScript functionality

## Files to Modify

### **New Files**
- `lib/eventasaurus_web/components/image_picker_modal.ex`

### **Modified Files**
- `lib/eventasaurus_web/live/event_live/new.html.heex` (remove inline picker)
- `lib/eventasaurus_web/live/event_live/edit.html.heex` (replace old picker)
- `lib/eventasaurus_web/live/event_live/edit.ex` (update event handlers)
- `test/eventasaurus_web/live/event_live/edit_test.exs` (update tests)

### **Removed Code**
- Old image picker HTML in `edit.html.heex`
- `search_unsplash` event handler in `edit.ex`
- Duplicate image selection logic

## Testing Requirements

### **Functional Testing**
- [ ] New page image picker works identically after refactor
- [ ] Edit page gains TMDB search functionality  
- [ ] Edit page shows default image categories
- [ ] Upload works on both pages
- [ ] Image metadata is consistent across pages

### **Regression Testing**
- [ ] All existing image functionality preserved
- [ ] Event creation/editing still works correctly
- [ ] Form validation unchanged
- [ ] Mobile responsiveness maintained

### **Integration Testing**
- [ ] Image picker opens/closes correctly on both pages
- [ ] Search results display properly
- [ ] Image selection updates form correctly
- [ ] Upload progress and errors handled consistently

## Success Criteria

### **Functional Parity**
- Edit page has **exact same image picker** as new page
- TMDB search works on edit page
- Default images show on edit page
- Upload functionality identical

### **Code Quality**
- Single image picker component used by both pages
- No duplicate image picker HTML
- Consistent event handlers across pages
- Unified testing approach

### **User Experience**
- No visual differences between new/edit image pickers
- Same interaction patterns and workflows
- Consistent performance and responsiveness
- Identical mobile experience

## Risk Mitigation

### **Backwards Compatibility**
- Preserve all existing functionality during migration
- Maintain same form data structure
- Keep same CSS classes for styling consistency

### **Testing Strategy**
- Test new component on new page before migrating edit page
- Run full test suite after each phase
- Manual testing of all image sources and workflows

### **Rollback Plan**
- Keep old edit page implementation during migration
- Use feature flags if needed for gradual rollout
- Maintain git history for easy reversion if needed 