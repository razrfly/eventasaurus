# Phase 2: Plan with Friends Modal Refactoring

## Overview

Refactor the "Plan with Friends" modal to provide context-aware planning experiences for both event-specific pages and movie aggregation pages using a single, flexible component.

## Problem Statement

### Current Issues

1. **Incorrect Planning Mode for Movie Pages**
   - Movie aggregation pages show "Quick Plan" as default mode
   - Quick plan requires a specific occurrence (venue + time), but movie pages only have movie + city
   - Users are forced through an inappropriate flow that doesn't match their context

2. **Component Duplication Risk**
   - Modal has nil-check bandaids rather than proper context awareness
   - Different contexts (event vs movie) treated as edge cases rather than distinct use cases
   - Event-specific features (past participants) broken on movie pages

3. **User Experience Mismatch**
   - Event page users: Know exactly what/when/where → Quick plan makes sense
   - Movie page users: Only know what movie → MUST choose venue/time → Need filtering first

### Context Analysis

#### Event Page Context (`public_event` present)
```elixir
%{
  public_event: %PublicEvent{
    id: 123,
    title: "Bugonia at Agrafka",
    venue: %Venue{name: "Agrafka", ...},
    starts_at: ~U[2024-11-25 19:00:00Z]
  },
  selected_occurrence: %{...},  # Specific showtime selected
  movie_id: nil,
  city_id: nil
}
```

**User Journey:**
1. User viewing specific screening (venue + time known)
2. Can immediately invite friends ("Quick Plan")
3. OR can explore other showtimes ("Flexible Plan")

#### Movie Page Context (`movie_id` + `city_id` present)
```elixir
%{
  public_event: nil,
  selected_occurrence: nil,
  movie_id: 831,
  city_id: 1,
  city: %City{name: "Kraków", ...},
  movie: %Movie{title: "Bugonia", ...}
}
```

**User Journey:**
1. User viewing all screenings for a movie across venues
2. MUST choose date range, venues, times
3. Create poll with multiple venue/time options
4. No "quick plan" option makes sense here

## Desired State

### Single Component, Multiple Contexts

The modal should intelligently adapt based on available context:

| Context | Available Data | Initial Mode | Available Modes |
|---------|---------------|--------------|-----------------|
| **Event Page** | `public_event` with venue/time | `:selection` (choose quick or flexible) | `:quick`, `:flexible_filters`, `:flexible_review` |
| **Movie Page** | `movie_id` + `city_id` only | `:flexible_filters` (skip selection) | `:flexible_filters`, `:flexible_review` |
| **Venue Page** (future) | `venue_id` + `city_id` | `:flexible_filters` | `:flexible_filters`, `:flexible_review` |

### Component Architecture

```elixir
defmodule EventasaurusWeb.Components.PublicPlanWithFriendsModal do
  # Context detection
  defp determine_initial_mode(assigns) do
    cond do
      # Event page: Has specific occurrence → Show mode selection
      assigns.public_event && assigns.selected_occurrence ->
        :selection

      # Movie page: Only has movie/city → Skip to filtering
      assigns.movie_id && assigns.city_id ->
        :flexible_filters

      # Venue page: Only has venue → Skip to filtering
      assigns.venue_id && assigns.city_id ->
        :flexible_filters

      # Fallback
      true ->
        :selection
    end
  end

  # Available modes based on context
  defp available_modes(assigns) do
    cond do
      # Event page: Can quick plan OR flexible plan
      assigns.public_event && assigns.selected_occurrence ->
        [:selection, :quick, :flexible_filters, :flexible_review]

      # Movie/Venue pages: Only flexible planning
      assigns.movie_id || assigns.venue_id ->
        [:flexible_filters, :flexible_review]

      true ->
        [:selection]
    end
  end
end
```

## Technical Approach

### Phase 2.1: Context-Aware Mode Selection

**Goal:** Make initial mode dependent on available context

**Changes:**
1. Add `determine_initial_mode/1` function to detect context
2. Set `planning_mode` in `mount/1` based on context
3. Conditionally render mode selection screen only for event pages

**Files:**
- `lib/eventasaurus_web/components/public_plan_with_friends_modal.ex`
- `lib/eventasaurus_web/live/public_movie_screenings_live.ex`
- `lib/eventasaurus_web/live/public_event_show_live.ex`

### Phase 2.2: Flexible Mode Navigation

**Goal:** Allow event page users to switch between quick and flexible modes

**Changes:**
1. Add "Back to mode selection" button in quick/flexible modes
2. Implement mode switching logic
3. Preserve filter selections when switching modes

**User Flow:**
```
Event Page:
  Mode Selection → Quick Plan → [Back] → Mode Selection → Flexible → Review → Submit
                 → Flexible → Review → [Back] → Flexible → [Back] → Mode Selection
```

### Phase 2.3: Historical Participants Fix

**Goal:** Make "past participants" work for both event and movie contexts

**Current Issue:**
```elixir
# This only works when @public_event is present
exclude_event_ids={if @public_event, do: [@public_event.id], else: []}
```

**Solution:**
```elixir
# Query based on context - works for both
defp get_exclude_event_ids(assigns) do
  cond do
    assigns.public_event -> [@public_event.id]
    assigns.movie_id -> [] # Show all past events for this movie
    assigns.venue_id -> [] # Show all past events at this venue
    true -> []
  end
end
```

**Files:**
- `lib/eventasaurus_web/components/historical_participants_component.ex`

### Phase 2.4: UI/UX Polish

**Goal:** Clear, context-appropriate messaging

**Changes:**

1. **Event Context Banner** (when `@public_event` present):
   ```heex
   <div class="event-banner">
     <h3><%= @public_event.title %></h3>
     <p><%= @public_event.venue.name %></p>
     <p><%= format_datetime(@public_event.starts_at) %></p>
   </div>
   ```

2. **Movie Context Banner** (when `@movie_id` present):
   ```heex
   <div class="movie-banner">
     <h3><%= @movie.title %></h3>
     <p>Find showtimes in <%= @city.name %></p>
   </div>
   ```

3. **Mode-Specific Instructions**:
   - Quick Plan: "Create event for [specific time/venue]"
   - Flexible (movie): "Choose date range and venues to find showtimes"
   - Flexible (event): "Explore other showtimes for this movie"

## Implementation Plan

### Step 1: Add Context Detection (1-2 hours)

```elixir
# In public_plan_with_friends_modal.ex

def mount(socket) do
  {:ok,
   socket
   |> assign(:planning_mode, determine_initial_mode(socket.assigns))
   |> assign(:available_modes, available_modes(socket.assigns))}
end

defp determine_initial_mode(assigns) do
  cond do
    has_specific_occurrence?(assigns) -> :selection
    has_movie_context?(assigns) -> :flexible_filters
    has_venue_context?(assigns) -> :flexible_filters
    true -> :selection
  end
end

defp has_specific_occurrence?(assigns) do
  assigns[:public_event] && assigns[:selected_occurrence]
end

defp has_movie_context?(assigns) do
  assigns[:movie_id] && assigns[:city_id]
end

defp has_venue_context?(assigns) do
  assigns[:venue_id] && assigns[:city_id]
end
```

### Step 2: Conditional Mode Selection UI (1 hour)

```heex
<!-- Only show mode selection for event pages -->
<%= if @planning_mode == :selection && has_specific_occurrence?(assigns) do %>
  <%= render_mode_selection(assigns) %>
<% else %>
  <!-- Skip straight to filtering -->
  <%= render_filter_selection(assigns) %>
<% end %>
```

### Step 3: Add Mode Navigation (2 hours)

```elixir
def handle_event("back_to_selection", _, socket) do
  if :selection in socket.assigns.available_modes do
    {:noreply, assign(socket, :planning_mode, :selection)}
  else
    # Movie/venue pages can't go back to selection
    {:noreply, socket}
  end
end

def handle_event("switch_to_flexible", _, socket) do
  {:noreply, assign(socket, :planning_mode, :flexible_filters)}
end
```

### Step 4: Fix Historical Participants (1 hour)

```elixir
# Update HistoricalParticipantsComponent to accept context params
<.live_component
  module={HistoricalParticipantsComponent}
  id={@id <> "_historical"}
  organizer={@organizer}
  selected_users={@selected_users}
  context={build_participant_context(assigns)}
/>

defp build_participant_context(assigns) do
  %{
    exclude_event_ids: get_exclude_event_ids(assigns),
    movie_id: assigns[:movie_id],
    venue_id: assigns[:venue_id],
    scope: determine_scope(assigns)
  }
end
```

### Step 5: Context-Aware Messaging (1 hour)

```elixir
defp get_context_banner(assigns) do
  cond do
    assigns[:public_event] -> render_event_banner(assigns)
    assigns[:movie_id] -> render_movie_banner(assigns)
    assigns[:venue_id] -> render_venue_banner(assigns)
    true -> nil
  end
end
```

## Testing Strategy

### Unit Tests

```elixir
describe "context detection" do
  test "event page context sets selection mode" do
    assigns = %{
      public_event: build(:public_event),
      selected_occurrence: build(:occurrence)
    }

    assert determine_initial_mode(assigns) == :selection
  end

  test "movie page context sets flexible mode" do
    assigns = %{
      movie_id: 831,
      city_id: 1,
      public_event: nil
    }

    assert determine_initial_mode(assigns) == :flexible_filters
  end
end
```

### Integration Tests (Playwright)

```javascript
// Event page: Should show mode selection
test('event page shows quick and flexible options', async ({ page }) => {
  await page.goto('/activities/bugonia-at-agrafka-251125')
  await page.click('button:has-text("Plan with Friends")')

  // Should see mode selection
  await expect(page.locator('text=Quick Plan')).toBeVisible()
  await expect(page.locator('text=Flexible Plan')).toBeVisible()
})

// Movie page: Should skip mode selection
test('movie page goes straight to filtering', async ({ page }) => {
  await page.goto('/c/krakow/movies/bugonia-831')
  await page.click('button:has-text("Plan with Friends")')

  // Should NOT see mode selection
  await expect(page.locator('text=Quick Plan')).not.toBeVisible()

  // Should see filtering UI
  await expect(page.locator('text=Date Range')).toBeVisible()
  await expect(page.locator('text=Time Preferences')).toBeVisible()
})
```

## Success Criteria

- [ ] Movie page modal skips "quick plan" and goes straight to flexible filtering
- [ ] Event page modal shows mode selection with both quick and flexible options
- [ ] Users can navigate back from quick/flexible modes to mode selection (event page only)
- [ ] Historical participants component works on both event and movie pages
- [ ] Context banners show appropriate information based on page type
- [ ] All nil-check bandaids replaced with proper context awareness
- [ ] Zero LiveView crashes when opening modal from any page type
- [ ] Playwright tests pass for both event and movie page flows

## Migration Notes

### Breaking Changes
None - this is a pure refactoring that improves UX without changing APIs

### Rollout Strategy
1. Deploy phase 2.1-2.3 together (context awareness + navigation)
2. Monitor for any LiveView crashes in production
3. Deploy phase 2.4 (UI polish) separately
4. Gather user feedback on new flows

## Future Enhancements (Phase 3+)

- **Venue-specific planning**: `/venues/agrafka` → Plan events at this venue
- **Smart defaults**: Pre-select venues based on user's past attendance
- **Saved preferences**: Remember user's preferred date ranges and times
- **Group availability**: Show when most friends are available
- **Calendar integration**: Block out times when organizer is busy

## References

- Phoenix LiveView Component Patterns: https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html
- Current modal implementation: `lib/eventasaurus_web/components/public_plan_with_friends_modal.ex`
- Event page LiveView: `lib/eventasaurus_web/live/public_event_show_live.ex`
- Movie page LiveView: `lib/eventasaurus_web/live/public_movie_screenings_live.ex`

## Related Issues

- Phase 1 (completed): Fix modal crashes on movie pages (#TBD)
- Historical participants enhancement (#TBD)
- Poll creation flow improvements (#TBD)
