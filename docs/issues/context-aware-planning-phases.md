# Context-Aware "Plan with Friends" - Phased Implementation

**Parent Issue**: #2404

This document breaks down the context-aware planning modal implementation into 8 manageable phases. Each phase can be implemented, tested, and approved independently before moving to the next.

---

## Phase 1: UI Clarity & Entry Point Setup

**Goal**: Improve clarity of existing modal options and add missing button on generic movie page

**Status**: Ready for implementation

### Scope

1. **Add "Plan with Friends" Button to Generic Movie Page**
   - Location: `/c/[city]/movies/[slug]`
   - Simple button addition - no complex logic yet
   - Wire up to open existing modal

2. **Make Quick Plan More Expressive**
   - Show exactly which theater user has chosen
   - Show exactly which time/showtime user has chosen
   - Make it crystal clear what the user is committing to
   - Example: "Quick Plan: [Movie Title] at [Venue Name] on [Date] at [Time]"

3. **Make Flexible Plan More Explicit**
   - Show "You've chosen: [Movie Title]"
   - Explain that there will be polling for venue location and/or date/time
   - Help users understand what "flexible plan with poll" means
   - Example subtext: "Create a poll to let your group vote on venue and showtime options"

4. **Remove Redundant Event Display**
   - Event context banner now exists at top with image + title
   - Remove duplicate event details previously shown at bottom
   - Reduce visual clutter

### Acceptance Criteria

- [ ] "Plan with Friends" button visible on generic movie page (`/c/[city]/movies/[slug]`)
- [ ] Quick Plan option shows complete context: theater, date, time
- [ ] Flexible Plan option clearly explains what will be polled
- [ ] No redundant event information displayed
- [ ] Mobile responsive design maintained
- [ ] Existing functionality preserved (no regressions)

### Technical Notes

**Files to Modify**:
- Movie page template (add button)
- `public_plan_with_friends_modal.ex` (update Quick/Flexible plan display text)

**Estimated Effort**: 2-3 story points

---

## Phase 2: Flexible Plan Core Flow

**Goal**: Ensure flexible planning works consistently from both entry points

**Status**: Blocked by Phase 1

### Scope

1. **Verify Consistent Behavior**
   - Flexible plan should work the same from both entry points (for now)
   - Date/time filtering functionality
   - Friend selection workflow
   - Poll creation and configuration
   - Review and finalization

2. **Fix Any Existing Issues**
   - "Change Time" button functionality (if not already fixed)
   - Filter application and reset
   - Occurrence selection and display
   - Poll option creation

3. **Establish Baseline**
   - Document current flexible plan behavior
   - Ensure it's working correctly before adding context-awareness
   - This becomes the "compare theaters" path in later phases

### Acceptance Criteria

- [ ] Flexible plan works from generic movie page entry
- [ ] Flexible plan works from specific showtime page entry
- [ ] Date/time filters apply correctly
- [ ] Friend selection and invitation works
- [ ] Poll creation succeeds with selected options
- [ ] All existing tests pass
- [ ] No regressions in flexible planning workflow

### Technical Notes

**Focus Areas**:
- `occurrence_query.ex` - Ensure querying works correctly
- `occurrence_formatter.ex` - Verify option formatting
- `occurrence_planning_workflow.ex` - Validate workflow orchestration

**Estimated Effort**: 3-5 story points

---

## Phase 3: Context-Aware Entry Points

**Goal**: Detect and pass entry point context to modal

**Status**: Blocked by Phase 2

### Scope

1. **Backend Context Detection**
   - Detect which page user is coming from
   - Create `entry_context` structure:
     ```elixir
     %{
       entry_point: :specific_showtime | :generic_movie,
       venue_id: integer() | nil,
       venue_name: string() | nil,
       public_event_id: integer()
     }
     ```

2. **Pass Context to Modal**
   - Update LiveView event handlers to build entry_context
   - Pass context when opening modal
   - Store in modal assigns

3. **Add Venue Context Banner**
   - For specific showtime entries, show: "Planning [Movie] at [Venue]"
   - Visible throughout flow to maintain user orientation
   - Distinct from existing event context banner

### Acceptance Criteria

- [ ] Entry point correctly detected from generic movie page
- [ ] Entry point correctly detected from specific showtime page
- [ ] Venue context extracted for specific showtime entries
- [ ] `entry_context` passed to modal component
- [ ] Venue context banner displays for specific showtime entries
- [ ] Context preserved throughout modal flow
- [ ] Tests added for context detection logic

### Technical Notes

**Files to Modify**:
- Movie page LiveView (detect generic entry, pass context)
- Activity page LiveView (detect specific entry, pass venue context)
- `public_plan_with_friends_modal.ex` (accept and use entry_context)

**New State Management**:
```elixir
# Add to modal assigns
entry_context: %{
  entry_point: atom(),
  venue_id: integer() | nil,
  venue_name: string() | nil
}
```

**Estimated Effort**: 5-8 story points

---

## Phase 4: Path Selection UI (Specific Showtime Entry)

**Goal**: Let users explicitly choose their intent when coming from specific showtime page

**Status**: Blocked by Phase 3

### Scope

1. **Add Path Selection Step**
   - New modal step: `:path_selection`
   - Only shown for `entry_point: :specific_showtime`
   - Skipped for generic movie page entries

2. **Radio Button UI**
   ```
   Modal Heading: "What would you like to coordinate?"

   ○ "Best time to go to [Venue Name]" (DEFAULT)
      Subtext: "Find when your group can make it to this theater"

   ○ "Compare different theaters"
      Subtext: "See showtimes across all theaters and pick together"

   [Continue] button (disabled until selection made)
   ```

3. **Path Selection State**
   - Track selected path: `:theater_selected` | `:compare_theaters` | `nil`
   - Validate selection before allowing continue
   - Store selection for use in Phase 5

### Acceptance Criteria

- [ ] Path selection step appears for specific showtime entries
- [ ] Path selection step skipped for generic movie entries
- [ ] Two radio options with clear labels and subtext
- [ ] "Best time at [Venue]" pre-selected as default
- [ ] Continue button disabled until selection made
- [ ] Selection stored in modal state
- [ ] Mobile responsive layout
- [ ] Accessibility: Keyboard navigation works
- [ ] Accessibility: Screen readers announce options clearly

### Technical Notes

**New Planning Mode**:
```elixir
# Add to planning_mode values
:path_selection
```

**New State**:
```elixir
selected_path: :theater_selected | :compare_theaters | nil
```

**UI Component**:
- Create reusable radio button group component
- Include explanatory subtext
- Clear visual feedback for selection

**Estimated Effort**: 3-5 story points

---

## Phase 5: Path-Based Workflow Routing

**Goal**: Implement different workflows based on selected path

**Status**: Blocked by Phase 4

### Scope

1. **Path 1: Theater Selected**
   - Skip venue selection step entirely
   - Go directly to time/date filtering
   - Filter occurrences for ONLY the selected venue
   - Create poll with showtimes at this venue only
   - Maintain venue context banner throughout

2. **Path 2: Compare Theaters**
   - Show venue selection step (like generic flow)
   - Allow user to choose any venue
   - Continue with standard flexible plan flow
   - Clear indication they're comparing theaters

3. **Conditional Flow Logic**
   - Branch based on `selected_path` value
   - Smooth transitions between steps
   - Maintain context throughout flow
   - Handle back navigation correctly

4. **Venue Pre-filtering**
   - When Path 1 selected, filter occurrences by venue_id
   - Update occurrence query to accept venue filter
   - Ensure poll options reflect single-venue constraint

### Acceptance Criteria

- [ ] Path 1 skips venue selection, shows only time filtering
- [ ] Path 1 occurrences filtered to selected venue only
- [ ] Path 2 shows venue selection step
- [ ] Path 2 allows choosing any venue with showtimes
- [ ] Flow transitions are smooth and logical
- [ ] Back navigation works correctly for both paths
- [ ] Context banner remains visible throughout
- [ ] Poll created with correct venue filtering
- [ ] Tests for both workflow paths

### Technical Notes

**Flow State Machine**:
```elixir
# Path 1 flow
:path_selection → :flexible_filters (skip venue step)

# Path 2 flow
:path_selection → :venue_selection → :flexible_filters
```

**Occurrence Query Updates**:
```elixir
# Add venue_id filter option
OccurrenceQuery.find_occurrences(series_type, series_id, %{
  venue_ids: [venue_id],  # Single venue for Path 1
  date_range: ...,
  time_preferences: ...
})
```

**Estimated Effort**: 8-13 story points

---

## Phase 6: Generic Movie Page Flow

**Goal**: Implement venue selection for generic movie page entries

**Status**: Can be done in parallel with Phase 4/5

### Scope

1. **Add Venue Selection Step**
   - New modal step: `:venue_selection`
   - Shows all venues with showtime counts
   - Presented as first step after mode selection

2. **Venue Selection UI**
   ```
   Heading: "Where should you watch it?"
   Subheading: "Select a theater to see available showtimes"

   [List of venues with showtime counts]
   - Cinema City Galeria Krakowska (12 showtimes)
   - Kino Pod Baranami (8 showtimes)
   - etc.

   [Continue to Times] button (enabled after selection)
   ```

3. **Linear Flow**
   - Mode Selection → Venue Selection → Time Filtering → Review → Create
   - Clear progression indicators
   - Easy back navigation

### Acceptance Criteria

- [ ] Venue selection step appears for generic movie entries
- [ ] All venues with showtimes listed with counts
- [ ] Venues sorted by showtime count (descending) or alphabetically
- [ ] Clear heading and subtext
- [ ] Single venue selection (radio buttons or cards)
- [ ] Continue button enabled after selection
- [ ] Selected venue passed to occurrence filtering
- [ ] Mobile responsive design
- [ ] Accessible keyboard navigation

### Technical Notes

**Venue Data Fetching**:
```elixir
# Query to get venues with showtime counts
def get_venues_with_showtimes(movie_id, filter_criteria) do
  # Return list of %{venue_id, venue_name, showtime_count}
end
```

**New Planning Mode**:
```elixir
:venue_selection
```

**State**:
```elixir
selected_venue_id: integer() | nil
selected_venue_name: string() | nil
```

**Estimated Effort**: 5-8 story points

---

## Phase 7: Edge Cases & Error Handling

**Goal**: Handle all edge cases and error states gracefully

**Status**: Blocked by Phases 5 & 6

### Scope

1. **Single Venue Edge Case**
   - Generic page with only ONE venue having showtimes
   - Still show venue selection for consistency
   - Add helpful text: "Only 1 theater showing this film"
   - Auto-select but allow user to see the selection

2. **Venue No Longer Has Showtimes**
   - Specific showtime page where venue lost showtimes
   - Context banner: "Note: [Venue] showtimes may have changed"
   - Auto-select Path 2 (Compare theaters) as default
   - Disable Path 1 option with explanation

3. **No Showtimes Anywhere**
   - Movie has no upcoming showtimes in any venue
   - Show helpful message: "No upcoming showtimes available"
   - Offer to notify when showtimes added (future enhancement)
   - Gracefully close modal or provide alternatives

4. **Path Switching Mid-Flow**
   - User clicks "Change Venue" after selecting Path 1
   - Reset to venue selection screen
   - Show confirmation toast: "Switching to compare all theaters"
   - Clear any venue-specific filters

5. **Standard Error States**
   - **No venues match filters**: "No theaters match your preferences. Try adjusting your date/time filters."
   - **No friends selected**: Disable "Create Poll" button with tooltip
   - **Network error**: Show retry option with clear error message
   - **Venue not found**: Fallback to generic flow with warning

### Acceptance Criteria

- [ ] Single venue scenario shows selection with helpful message
- [ ] Venue without showtimes disables Path 1 appropriately
- [ ] No showtimes scenario shows clear message
- [ ] Path switching resets state and shows confirmation
- [ ] All error states have clear, actionable messages
- [ ] Error recovery paths work correctly
- [ ] Graceful fallbacks prevent broken states
- [ ] Tests cover all edge cases
- [ ] Error tracking/logging implemented

### Technical Notes

**Error Handling Strategy**:
```elixir
# Validate venue has showtimes before showing Path 1
defp validate_venue_showtimes(venue_id, filter_criteria) do
  case count_showtimes(venue_id, filter_criteria) do
    0 -> {:error, :no_showtimes}
    count -> {:ok, count}
  end
end
```

**User Messaging**:
- Clear, non-technical language
- Actionable next steps
- Maintain helpful tone

**Estimated Effort**: 5-8 story points

---

## Phase 8: Testing, Accessibility & Polish

**Goal**: Ensure quality, accessibility, and performance

**Status**: Blocked by all previous phases

### Scope

1. **Comprehensive Testing**
   - Unit tests for all new functions
   - Integration tests for both entry point flows
   - Tests for both path selection outcomes
   - Edge case test coverage
   - Regression testing for existing functionality

2. **Accessibility (a11y)**
   - Screen reader compatibility verification
   - Keyboard navigation testing
   - ARIA labels for all interactive elements
   - Focus management between steps
   - Color contrast verification
   - Semantic HTML structure

3. **Mobile Responsiveness**
   - Test on mobile devices (iOS/Android)
   - Touch-friendly tap targets
   - Responsive grid layouts
   - Modal sizing on small screens
   - Horizontal scrolling prevention

4. **Performance Optimization**
   - Minimize re-renders
   - Optimize occurrence queries
   - Lazy load venue lists if needed
   - Debounce filter changes

5. **User Testing & Feedback**
   - Internal user testing
   - Gather feedback on clarity
   - Measure task completion rates
   - Iterate based on findings

6. **Documentation**
   - Update user-facing documentation
   - Code documentation and comments
   - Developer guides for future maintenance

### Acceptance Criteria

- [ ] All unit tests passing (>90% coverage)
- [ ] Integration tests for both entry points passing
- [ ] All edge case tests passing
- [ ] No regressions in existing tests
- [ ] WCAG 2.1 AA compliance verified
- [ ] Screen reader testing completed (VoiceOver, NVDA)
- [ ] Keyboard navigation works throughout flow
- [ ] Mobile responsive verified on iOS and Android
- [ ] Performance benchmarks met (no degradation)
- [ ] User testing completed with >85% task success rate
- [ ] Documentation updated and reviewed
- [ ] Code reviewed and approved

### Technical Notes

**Testing Tools**:
- ExUnit for Elixir unit tests
- Wallaby for integration tests
- Playwright for E2E testing
- Axe for accessibility scanning

**Performance Targets**:
- Modal open time: <200ms
- Occurrence query: <500ms
- Poll creation: <1s

**Documentation Updates**:
- User guide: Planning events with friends
- Developer guide: Modal flow state machine
- API documentation: Entry context structure

**Estimated Effort**: 8-13 story points

---

## Implementation Strategy

### Phase Dependencies

```
Phase 1 (Foundation)
  ↓
Phase 2 (Baseline Functionality)
  ↓
Phase 3 (Context Infrastructure)
  ↓
  ├─→ Phase 4 (Path Selection UI)
  │     ↓
  │   Phase 5 (Path Routing)
  │
  └─→ Phase 6 (Generic Flow)

Phase 5 & 6 converge
  ↓
Phase 7 (Edge Cases)
  ↓
Phase 8 (Quality & Polish)
```

### Parallelization Opportunities

- **Phase 6 can start after Phase 3** (doesn't depend on Phase 4/5)
- Testing can begin incrementally after each phase
- Documentation can be written alongside development

### Rollout Strategy

1. **Phase 1-2**: Quick wins, immediate UX improvements
2. **Phase 3-6**: Core feature development, major functionality
3. **Phase 7-8**: Hardening and quality assurance

### Success Metrics

**After Phase 1-2**:
- User comprehension of Quick vs Flexible plan: 80%+

**After Phase 3-6**:
- Task completion rate: 85%+
- User comprehension of path options: 90%+

**After Phase 7-8**:
- Zero critical bugs
- WCAG 2.1 AA compliance: 100%
- User satisfaction: 4.5/5+

---

## Approval Checkpoints

Each phase requires approval before proceeding:

1. ✅ **Phase Design Review**: Approve phase scope and approach
2. ✅ **Implementation Review**: Code review and functionality check
3. ✅ **Testing Review**: Verify tests pass and coverage adequate
4. ✅ **User Acceptance**: Validate phase meets user needs

**Current Status**: Phase 1 ready for design review and approval

---

**Total Estimated Effort**: 39-63 story points (distributed across 8 phases)

**Recommended Approach**: Implement phases sequentially with approval gates, allowing for feedback and iteration between phases.
