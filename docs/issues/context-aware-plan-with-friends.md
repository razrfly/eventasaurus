# Context-Aware "Plan with Friends" Modal

## Problem Statement

The "Plan with Friends" modal currently lacks context awareness about how the user arrived at it. This creates a confusing UX where users coming from different entry points (generic movie page vs. specific showtime page) receive the same interface, despite having different intents.

### Current Issues

1. **Missing Button on Generic Movie Page**: The "Plan with Friends" button is completely absent from generic movie pages like `/c/krakow/movies/bugonia-831`, forcing users to navigate to a specific showtime first.

2. **Context-Unaware Behavior on Specific Showtime Page**: When users click "Plan with Friends" from a specific showtime page like `/activities/bugonia-at-krakow-galeria-kazimierz-251127`, the modal ignores the venue context entirely. It doesn't acknowledge that the user already chose a specific theater.

3. **Ambiguous User Intent**: The system doesn't distinguish between two different user intents:
   - **Intent A**: "I want to see this film at this specific theater - let's coordinate which showtime"
   - **Intent B**: "I want to see this film, but let's compare all theaters and pick one together"

### Example URLs

- **Generic Movie Page** (missing button): `http://localhost:4000/c/krakow/movies/bugonia-831`
- **Specific Showtime Page** (context-unaware): `http://localhost:4000/activities/bugonia-at-krakow-galeria-kazimierz-251127`

## UX Research Findings

Based on research into established UX patterns (Laws of UX, industry best practices):

### Key Principles

1. **Progressive Disclosure**: Reveal complexity gradually based on user's entry point and choices
2. **Context-Aware Defaults**: Respect the user's entry point and pre-select sensible defaults (examples: Eventbrite, Fandango)
3. **Minimize Cognitive Load**: Don't force users to re-make decisions they've already implicitly made
4. **Display Choices as Group**: When alternatives exist, make them visible and explicit (radio buttons, not hidden options)

### Real-World Examples

- **Eventbrite**: When viewing a specific event occurrence, "Get Tickets" defaults to that date/time but allows changing
- **Fandango**: Movie page → choose theater first; Theater showtime page → that theater is pre-selected
- **OpenTable**: Restaurant page → choose date/time; Specific time slot → that slot is pre-selected with option to change

## Proposed Solution

Implement **two distinct flows** based on entry point, with clear paths and context awareness:

### Entry Point A: Generic Movie Page

**Location**: `/c/[city]/movies/[slug]`

**Changes Required**:
1. Add "Plan with Friends" button to movie page
2. Modal opens with venue selection as FIRST step
3. Linear flow: Choose Venue → Filter Times → Create Poll

**UI Specifications**:
```
Modal Title: "Plan [Movie Title] with Friends"
First Screen Heading: "Where should you watch it?"
Subheading: "Select a theater to see available showtimes"
[List of all venues with showtime counts]
Button: "Continue to Times" (after venue selected)
```

**User Flow**:
1. User clicks "Plan with Friends" from movie page
2. Modal shows all venues with showtimes
3. User selects a venue
4. Modal transitions to date/time filtering for that venue
5. User creates poll with selected options

### Entry Point B: Specific Showtime Page

**Location**: `/activities/[slug]`

**Changes Required**:
1. Add prominent context banner showing current venue
2. Provide TWO CLEAR PATHS as radio button selection
3. Different workflows based on path selection

**UI Specifications**:
```
Context Banner (colored, prominent):
  "Planning [Movie Title] at [Venue Name]"

Modal Heading: "What would you like to coordinate?"

Radio Button Options (required selection):
  ○ "Best time to go to [Venue Name]" (DEFAULT)
     Subtext: "Find when your group can make it to this theater"

  ○ "Compare different theaters"
     Subtext: "See showtimes across all theaters and pick together"

Continue Button: Disabled until selection made
```

**User Flow - Path 1 (Theater Selected)**:
1. User clicks "Plan with Friends" from specific showtime
2. Modal shows context banner with movie + venue
3. "Best time to go to [Venue]" is pre-selected
4. User clicks Continue
5. Modal skips venue selection, goes straight to time/date filtering for THIS venue
6. User creates poll with showtimes at this venue only

**User Flow - Path 2 (Compare Theaters)**:
1. User clicks "Plan with Friends" from specific showtime
2. Modal shows context banner with movie + venue
3. User selects "Compare different theaters"
4. User clicks Continue
5. Modal shows venue selection (same as Entry Point A)
6. Rest of flow matches Entry Point A

## Implementation Requirements

### Backend Changes

**Pass venue context to modal**:
```elixir
# In LiveView that opens modal
def handle_event("open_plan_modal", _params, socket) do
  entry_context = %{
    entry_point: :specific_showtime,  # or :generic_movie
    venue_id: socket.assigns.venue_id,  # if from specific showtime
    venue_name: socket.assigns.venue_name  # if from specific showtime
  }

  {:noreply,
   socket
   |> assign(:show_plan_modal, true)
   |> assign(:entry_context, entry_context)}
end
```

### Frontend Changes

**Modal Component** (`public_plan_with_friends_modal.ex`):

1. Accept new `entry_context` assign
2. Add context banner component for specific showtime entry
3. Add path selection step for specific showtime entry
4. Conditional flow based on entry point and path selection
5. Update `planning_mode` state machine to handle new flows

**Movie Page Template**:
- Add "Plan with Friends" button
- Wire up event to open modal with `entry_point: :generic_movie`

**Activity Page Template**:
- Ensure existing "Plan with Friends" button passes venue context
- Wire up event with `entry_point: :specific_showtime` and venue details

## Edge Cases & Error Handling

### Edge Cases

1. **Generic page with only ONE venue having showtimes**
   - Still show venue selection step for consistency
   - Add helpful text: "Only 1 theater showing this film"

2. **Specific page where venue NO LONGER has showtimes**
   - Context banner shows: "Note: [Venue] showtimes may have changed"
   - Auto-select Path 2 (Compare theaters) as default
   - Disable Path 1 if venue has zero available showtimes

3. **Movie with NO showtimes anywhere**
   - Modal shows message: "No upcoming showtimes available"
   - Offer to notify when showtimes added (future enhancement)

4. **User switches from Path 1 to Path 2 mid-flow**
   - Reset to venue selection screen
   - Show confirmation toast: "Switching to compare all theaters"
   - Clear any venue-specific filters

### Error States

- **No venues match filters**: "No theaters match your preferences. Try adjusting your date/time filters."
- **No friends selected**: Disable "Create Poll" button with tooltip
- **Network error**: Show retry option with clear error message
- **Venue not found**: Fallback to generic flow with warning message

## Success Metrics

### Quantitative Metrics
1. **User Comprehension**: 90%+ of users understand which path they're on (via user testing)
2. **Task Completion Rate**: Reduced drop-off in modal flow by 30%
3. **Path Selection Accuracy**: 85%+ of users choose correct path based on their intent
4. **Support Tickets**: Reduce "which theater am I booking?" questions by 50%

### Qualitative Metrics
- User feedback: "The flow was clear and intuitive"
- Users successfully distinguish between "pick a time at this theater" vs "compare all theaters"
- No confusion about whether venue is already selected

## Acceptance Criteria

### Generic Movie Page Flow
- [ ] "Plan with Friends" button visible on movie page
- [ ] Button opens modal with venue selection as first step
- [ ] Modal title: "Plan [Movie Title] with Friends"
- [ ] Heading: "Where should you watch it?"
- [ ] All venues with showtimes displayed as selectable options
- [ ] "Continue to Times" button enabled after venue selection
- [ ] Linear flow: Venue → Times → Create Poll
- [ ] Mobile responsive design maintained

### Specific Showtime Page Flow
- [ ] Context banner displays: "Planning [Movie Title] at [Venue Name]"
- [ ] Two radio button paths displayed prominently:
  - Path 1: "Best time to go to [Venue Name]" (default)
  - Path 2: "Compare different theaters"
- [ ] Path selection is required before continuing
- [ ] Path 1 flow: Skips venue selection, goes directly to time filtering for specified venue
- [ ] Path 2 flow: Shows venue selection screen (same as generic flow)
- [ ] Context banner visible throughout flow to maintain orientation
- [ ] Mobile responsive design maintained

### Cross-Cutting Requirements
- [ ] All edge cases handled gracefully (single venue, no showtimes, etc.)
- [ ] Error states have clear messaging and recovery options
- [ ] Accessibility: Screen readers can distinguish between paths
- [ ] Accessibility: Radio buttons are keyboard navigable
- [ ] Existing flexible planning functionality preserved
- [ ] Tests added for both entry point flows
- [ ] Tests added for path selection logic
- [ ] Tests added for edge cases

## Technical Notes

### State Management

Current `planning_mode` values:
- `:selection` - Initial mode selection (quick vs flexible)
- `:quick` - Quick plan flow
- `:flexible_filters` - Filter selection
- `:flexible_review` - Review selected options

Proposed additions:
- `:venue_selection` - Selecting venue (generic flow or Path 2)
- `:path_selection` - Choosing Path 1 vs Path 2 (specific showtime only)

### Data Flow

```elixir
# Entry context structure
%{
  entry_point: :specific_showtime | :generic_movie,
  venue_id: integer() | nil,
  venue_name: string() | nil,
  public_event_id: integer()
}

# Path selection (specific showtime only)
%{
  selected_path: :theater_selected | :compare_theaters | nil
}
```

### Component Hierarchy

```
PublicPlanWithFriendsModal
├── EventContextBanner (existing - shows movie + image)
├── VenueContextBanner (new - shows venue for specific showtime)
├── PathSelectionStep (new - Path 1 vs Path 2 radio buttons)
├── ModeSelectionStep (existing - quick vs flexible)
├── VenueSelectionStep (new - choose theater)
├── FilterSelectionStep (existing - date/time filters)
└── ReviewStep (existing - review & create poll)
```

## Related Issues

- Venue name bug (Castorama vs Zaco Pianka) - separate issue
- "Change Time" button not working - fixed in previous work

## UX Inspiration & References

- **Laws of UX**: Progressive Disclosure, Hick's Law (minimize choices)
- **Eventbrite**: Context-aware event booking
- **Fandango**: Theater-first vs movie-first flows
- **OpenTable**: Time slot selection with context awareness

---

**Priority**: High
**Complexity**: Medium
**Estimated Effort**: 8-13 story points
**Labels**: UX, Frontend, Enhancement, Planning Flow
