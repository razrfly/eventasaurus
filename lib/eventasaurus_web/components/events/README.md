# EventTimelineComponent System

A reusable Phoenix LiveView component system for displaying events in a rich timeline format with consistent design patterns across different contexts.

## Architecture

The EventTimelineComponent is composed of several modular sub-components:

- **EventTimelineComponent** - Main orchestrator component
- **TimelineFilters** - Handles time and ownership filtering (user dashboard only)
- **TimelineContainer** - Groups events by date and renders timeline structure  
- **TimelineEmptyState** - Context-specific empty states with call-to-action buttons
- **EventCard** - Rich event cards with metadata, images, and actions
- **EventCardBadges** - Status and role badge components
- **ParticipantAvatars** - Avatar display with tooltips and overflow handling

## Usage

### Basic Usage

```elixir
<.event_timeline 
  events={@events}
  context={:user_dashboard}
  loading={@loading}
  filters={%{
    time_filter: @time_filter,
    ownership_filter: @ownership_filter
  }}
  filter_counts={@filter_counts}
  config={%{
    title: "Events",
    subtitle: "Your events timeline",
    create_button_url: "/events/new",
    create_button_text: "Create Event",
    show_create_button: true
  }}
/>
```

### Context Types

#### `:user_dashboard`
- Shows role badges (Organizer/Attending) 
- Displays ownership filters
- Includes participant status update controls
- Shows "Manage" buttons for owned events

#### `:group_events`
- Simplified view without user-specific features
- Shows all events for the group context
- No ownership filters
- Context-appropriate empty states

### Configuration Options

```elixir
config = %{
  title: "Custom Title",           # Header title
  subtitle: "Custom subtitle",     # Header subtitle 
  create_button_url: "/custom/new", # Create button URL
  create_button_text: "Custom Text", # Create button text
  show_create_button: true,        # Show/hide create button
  description: "Custom description" # Empty state description
}
```

### Filter Structure

```elixir
filters = %{
  time_filter: :upcoming | :past | :archived,
  ownership_filter: :all | :created | :participating
}

filter_counts = %{
  upcoming: 5,
  past: 12,
  created: 3,
  participating: 14
}
```

## Event Data Structure

Events should include the following fields for full functionality:

```elixir
%{
  id: "event-id",
  title: "Event Title",
  description: "Optional description",
  slug: "event-slug",
  start_at: ~N[2024-01-01 10:00:00],
  timezone: "America/New_York", 
  status: :polling | :confirmed | :cancelled,
  cover_image_url: "https://...", # Optional
  venue: %{name: "Venue Name"} | nil,
  participants: [
    %{user: %{name: "User Name", email: "user@example.com"}},
    # ...
  ],
  participant_count: 25,
  user_role: "organizer" | "participant" | nil, # User dashboard only
  user_status: :interested | :accepted | :declined, # User dashboard only
  can_manage: true | false, # User dashboard only
  taxation_type: "ticketed_event" | nil
}
```

## Responsive Design

The component automatically adapts to different screen sizes:

### Desktop (`sm:block`)
- Full timeline with dots and connecting lines
- Side-by-side layout with date markers
- Large event cards with detailed information
- Comprehensive filter controls

### Mobile (`sm:hidden`)
- Simplified card layout
- Stacked date headers
- Compressed event cards
- Touch-optimized interactions

## Accessibility Features

- **ARIA Labels**: All interactive elements have proper ARIA labels
- **Keyboard Navigation**: Full keyboard accessibility for all controls
- **Focus Management**: Proper focus indicators and tab ordering
- **Screen Reader Support**: Semantic HTML with appropriate roles
- **Color Contrast**: WCAG AA compliant color combinations
- **Alternative Text**: All images include descriptive alt text

### ARIA Attributes

- `role="timeline"` on timeline container
- `aria-label` on filter buttons with counts
- `aria-expanded` on dropdown controls
- `tabindex` for keyboard navigation
- `aria-describedby` for tooltip relationships

## Performance Considerations

- **Lazy Loading**: Images are loaded lazily for large event lists
- **Virtual Scrolling**: Considered for very large datasets (>100 events)
- **Efficient Rendering**: Uses Phoenix LiveView's efficient diff algorithm
- **Cached Calculations**: Participant counts and dates are calculated once

## Error Handling

The component gracefully handles:

- Missing or malformed event data
- Network failures during loading
- Missing images (shows placeholder)
- Invalid date formats (shows "Date TBD")
- Permission errors (hides restricted actions)

## Testing Strategy

### Component Tests
```elixir
test "renders events in timeline format" do
  # Test basic rendering
end

test "shows appropriate badges for user context" do
  # Test context-specific features
end

test "handles empty state correctly" do
  # Test empty state rendering
end
```

### Integration Tests
```elixir
test "filtering works correctly" do
  # Test filter functionality
end

test "responsive design adapts to screen size" do
  # Test mobile/desktop layouts
end
```

### Accessibility Tests
```elixir
test "meets WCAG AA standards" do
  # Test accessibility compliance
end

test "keyboard navigation works" do
  # Test keyboard accessibility
end
```

## Common Issues

### Event Images Not Loading
- Check `cover_image_url` is a valid URL
- Ensure images are accessible from the client
- Component shows placeholder for missing images

### Filter Counts Not Updating
- Verify `filter_counts` map includes all filter keys
- Check that counts are calculated server-side
- Ensure LiveView is properly updating assigns

### Mobile Layout Issues
- Use browser dev tools to test responsive breakpoints
- Check Tailwind CSS classes for mobile variants
- Verify touch targets meet minimum size requirements

## Migration Guide

### From Legacy Dashboard Timeline

1. Replace inline timeline HTML with `<.event_timeline>` component
2. Move filter logic to component props
3. Update event data structure as needed
4. Test responsive behavior

### From Simple Group Event Grid

1. Replace grid layout with `<.event_timeline>` component
2. Set `context={:group_events}`
3. Configure appropriate empty state
4. Remove old grid CSS if no longer needed

## Contributing

When modifying the EventTimelineComponent:

1. Maintain backward compatibility with existing usage
2. Update this documentation for any API changes
3. Add tests for new functionality
4. Verify accessibility compliance
5. Test on multiple screen sizes and devices

## File Structure

```
/lib/eventasaurus_web/components/events/
├── README.md                    # This documentation
├── event_card.ex               # Event card component
├── event_card_badges.ex        # Badge components
├── participant_avatars.ex      # Avatar display
├── timeline_container.ex       # Timeline layout
├── timeline_date_marker.ex     # Date markers
├── timeline_empty_state.ex     # Empty states
└── timeline_filters.ex         # Filter controls
```