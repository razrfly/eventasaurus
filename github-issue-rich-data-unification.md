# Event Creation Flow Unification - Rich Data Integration

## Overview

Currently, Eventasaurus has two separate systems for importing rich external data from TMDB (The Movie Database):

1. **Image Picker System** - When selecting an image from TMDB during event creation/editing, it saves basic movie data alongside the image
2. **Rich Data Import System** - Manual import of comprehensive movie/TV metadata through a dedicated modal

This issue outlines the consolidation of these systems to provide a unified, streamlined experience.

## Current State Analysis

### System 1: Image Picker with Basic TMDB Data
**Location**: `lib/eventasaurus_web/components/image_picker_modal.ex`

**Functionality**:
- Unified search across Unsplash, TMDB, and default images
- When TMDB image is selected, stores basic metadata:
  ```json
  {
    "cover_image_url": "https://image.tmdb.org/...",
    "tmdb_data": {
      "id": 550,
      "title": "Fight Club",
      "type": "movie",
      "poster_path": "/path.jpg",
      "release_date": "1999-10-15"
    },
    "source": "tmdb"  
  }
  ```
- Stored in `external_image_data` field
- Used in: new/edit event pages, group creation

### System 2: Rich Data Import System
**Location**: `lib/eventasaurus_web/components/rich_data_import_modal.ex`

**Functionality**:  
- Comprehensive metadata import from TMDB, Spotify, etc.
- Fetches detailed information including:
  - Cast and crew information
  - Plot synopsis, genres, ratings
  - Images (posters, backdrops, logos)
  - Release information, runtime
  - Production companies and countries
- Stored in `rich_external_data` field  
- Accessed via "Import Rich Data" button

### Current Workflow Issues

1. **Redundant API Calls**: Both systems call TMDB API separately for the same content
2. **Inconsistent UX**: Users need to understand two different systems for similar functionality  
3. **Data Fragmentation**: Basic data in `external_image_data`, detailed data in `rich_external_data`
4. **Missed Opportunities**: Users selecting TMDB images don't get automatic rich data benefits

## Proposed Solution

### Phase 1: Automatic Rich Data Import on TMDB Image Selection

When a user selects a TMDB image from the image picker, automatically fetch and store comprehensive rich data.

**Technical Implementation**:

1. **Modified Image Selection Handler**:
   ```elixir
   # In image picker modal JS hook or LiveView handler
   def handle_event("image_selected", %{"source" => "tmdb", "tmdb_data" => tmdb_data}, socket) do
     # Existing image handling
     socket = handle_image_selection(socket, image_data)
     
     # NEW: Automatically fetch rich data
     case fetch_rich_data_for_tmdb(tmdb_data) do
       {:ok, rich_data} ->
         socket
         |> assign(:rich_external_data, rich_data)
         |> put_flash(:info, "Movie data imported automatically!")
       {:error, _} ->
         # Graceful degradation - just use basic image data
         socket
     end
   end
   ```

2. **Unified Data Storage**:
   - Consolidate both `external_image_data` and `rich_external_data` 
   - Store comprehensive data in `rich_external_data` with image info included
   - Maintain backward compatibility

3. **Enhanced Rich Data Manager**:
   ```elixir
   defmodule EventasaurusWeb.Services.RichDataManager do
     # New function for automatic import during image selection
     def auto_import_from_image_selection(tmdb_data) do
       # Fetch comprehensive data using existing infrastructure
       get_details(:tmdb, tmdb_data.id, tmdb_data.type)
     end
   end
   ```

### Phase 2: User Control Toggle

Add a user preference to enable/disable automatic rich data import.

**Implementation**:

1. **User Setting**:
   ```elixir
   # Add to user schema or event creation preferences
   field :auto_import_rich_data, :boolean, default: true
   ```

2. **UI Toggle**:
   - Checkbox in event creation settings
   - "Automatically import movie/TV data when selecting images"
   - Per-event or user-level preference

3. **Conditional Logic**:
   ```elixir
   if socket.assigns.current_user.auto_import_rich_data do
     # Auto-import rich data
   else
     # Just save image data
   end
   ```

### Phase 3: Rich Data Import Modal Deprecation

Once automatic import is working reliably:

1. **Remove Manual Button**: Hide "Import Rich Data" button by default
2. **Admin Override**: Keep functionality available for advanced users or edge cases
3. **Migration Path**: Provide clear migration for existing manual workflows

## Implementation Plan

### Phase 1: Core Integration (2-3 days)

**Tasks**:
1. Modify `ImagePicker` JS hook to detect TMDB selections
2. Update image selection handlers in `new.ex` and `edit.ex` 
3. Integrate with existing `RichDataManager` service
4. Add error handling for API failures
5. Update event schema to handle unified data structure
6. Test automatic import across all image picker contexts

**Files to Modify**:
- `assets/js/hooks/image_picker.js` (or equivalent)
- `lib/eventasaurus_web/live/event_live/new.ex`
- `lib/eventasaurus_web/live/event_live/edit.ex` 
- `lib/eventasaurus_web/live/group_live/new.ex`
- `lib/eventasaurus_web/live/group_live/edit.ex`
- `lib/eventasaurus_web/services/rich_data_manager.ex`

### Phase 2: User Control (1-2 days)

**Tasks**:
1. Add user preference field and migration
2. Create settings UI component
3. Implement conditional import logic
4. Add user onboarding/education
5. Update tests for both enabled/disabled states

**Files to Modify**:
- `lib/eventasaurus_app/accounts/user.ex`
- Add migration for user preference
- Update event creation templates with toggle
- Update image selection logic with preference check

### Phase 3: Cleanup & Migration (1 day)

**Tasks**:
1. Add feature flag for rich data import modal visibility
2. Create data migration script for existing events
3. Update documentation and help text
4. Performance testing and optimization
5. Remove unused code and imports

## Technical Considerations

### API Rate Limiting
- TMDB has rate limits (40 requests/second)
- Implement caching to avoid duplicate requests
- Consider batch processing for multiple selections

### Error Handling
- Graceful degradation when rich data fetch fails
- Maintain basic image functionality as fallback
- User-friendly error messages

### Data Migration
- Existing events with separate image/rich data
- Consolidation strategy for data consistency
- Backward compatibility during transition

### Performance Impact
- Additional API call on image selection
- Caching strategy for popular content
- Async processing to avoid blocking UI

## Benefits

1. **Streamlined UX**: Single action gets both image and rich data
2. **Reduced Friction**: No need to manually import rich data
3. **API Efficiency**: Single comprehensive request vs multiple basic requests
4. **Data Consistency**: Unified storage and retrieval patterns
5. **Feature Discovery**: Users naturally discover rich data features

## Risks & Mitigations

### Risk: API Failures Break Image Selection
**Mitigation**: Implement graceful degradation - if rich data fetch fails, proceed with basic image selection

### Risk: Performance Degradation  
**Mitigation**: Implement caching, async processing, and request batching

### Risk: User Confusion During Transition
**Mitigation**: Clear communication, gradual rollout, and optional manual control

### Risk: Data Inconsistency
**Mitigation**: Comprehensive testing, data validation, and migration scripts

## Success Metrics

1. **User Engagement**: Increased usage of rich data features
2. **API Efficiency**: Reduced redundant TMDB API calls
3. **User Satisfaction**: Positive feedback on streamlined workflow
4. **Technical Debt**: Reduced code duplication and maintenance overhead

## Testing Strategy

### Unit Tests
- Rich data auto-import functionality
- Error handling and graceful degradation
- Data validation and storage

### Integration Tests  
- End-to-end image selection with rich data
- Cross-browser compatibility
- Performance under load

### User Acceptance Tests
- Event creation workflows
- Rich data display and functionality
- Settings and preferences

This consolidation will significantly improve the user experience while reducing technical complexity and API overhead. The phased approach ensures minimal disruption to existing functionality while providing clear migration paths.