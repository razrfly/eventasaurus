# Calendar Component - Technical Documentation

## Overview

The `CalendarComponent` is a Phoenix LiveComponent that provides an interactive calendar interface for date selection in event creation. It supports both single and multiple date selection with full accessibility and responsive design.

## Architecture

### Component Structure
```
lib/eventasaurus_web/components/
├── calendar_component.ex          # Main calendar LiveComponent
└── event_components.ex           # Form components including calendar integration
```

### JavaScript Integration
```
assets/js/
├── app.js                        # Main application with hooks
└── hooks/
    ├── CalendarKeyboardNav       # Keyboard navigation for calendar
    └── CalendarFormSync          # Syncs calendar state with form
```

## Component API

### CalendarComponent

#### Required Assigns
- `id` (string): Unique identifier for the component
- `selected_dates` (list): List of `Date` structs representing selected dates

#### Optional Assigns
- `current_month` (Date): Month to display (defaults to current month)
- `hover_date` (Date): Date currently being hovered (for styling)

#### Events Sent to Parent
- `{:selected_dates_changed, dates}`: Sent when date selection changes

### Usage Example

```elixir
<.live_component
  module={CalendarComponent}
  id="event-calendar"
  selected_dates={@selected_dates}
/>
```

## Implementation Details

### Date Selection Logic

The component maintains state for:
- `current_month`: The month currently being displayed
- `selected_dates`: List of selected dates
- `hover_date`: Currently hovered date for visual feedback

```elixir
def handle_event("toggle_date", %{"date" => date_string}, socket) do
  case Date.from_iso8601(date_string) do
    {:ok, date} ->
      updated_dates = toggle_date_in_list(socket.assigns.selected_dates, date)
      send(self(), {:selected_dates_changed, updated_dates})
      {:noreply, assign(socket, :selected_dates, updated_dates)}
    
    {:error, _} ->
      {:noreply, socket}
  end
end
```

### Accessibility Implementation

#### ARIA Structure
- `role="application"` on main container
- `role="grid"` on calendar grid
- `role="gridcell"` on date buttons
- `role="columnheader"` on day headers
- `aria-pressed` for selection state
- `aria-label` with full date descriptions

#### Keyboard Navigation
Implemented via JavaScript hook with Phoenix LiveView integration:

```javascript
Hooks.CalendarKeyboardNav = {
  mounted() {
    this.el.addEventListener('keydown', (e) => {
      if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Enter', 'Space'].includes(e.key)) {
        e.preventDefault();
        const focusedDate = this.getFocusedDate();
        this.pushEvent("key_navigation", {
          key: e.key,
          date: focusedDate
        });
      }
    });
  }
}
```

### Responsive Design

#### Breakpoint Strategy
- **Mobile (< 640px)**: Single column layout, abbreviated day names
- **Tablet (640px - 1024px)**: Optimized spacing, full day names
- **Desktop (> 1024px)**: Full layout with hover effects

#### CSS Classes
```css
/* Mobile-first approach */
.calendar-day {
  @apply w-8 h-8 sm:w-10 sm:h-10;
}

.day-header {
  @apply text-xs sm:text-sm;
}

/* Responsive text */
.hidden.sm:inline  /* Desktop text */
.sm:hidden         /* Mobile text */
```

## Form Integration

### Hidden Field Synchronization

The calendar integrates with Phoenix forms through a hidden field:

```html
<input 
  type="hidden" 
  name="event[selected_poll_dates]" 
  value={Enum.join(@selected_dates, ",")}
/>
```

### JavaScript Hook Integration

```javascript
Hooks.CalendarFormSync = {
  mounted() {
    this.handleEvent("calendar_dates_changed", ({ dates }) => {
      const hiddenInput = document.querySelector('[name="event[selected_poll_dates]"]');
      if (hiddenInput) {
        hiddenInput.value = dates.join(',');
        hiddenInput.dispatchEvent(new Event('change', { bubbles: true }));
      }
    });
  }
}
```

## Validation

### Date Polling Validation

Custom validation function in the event form:

```elixir
defp validate_date_polling(changeset, params) do
  if Map.get(params, "enable_date_polling") == "true" do
    selected_dates = parse_selected_dates(params)
    
    if length(selected_dates) < 2 do
      add_error(changeset, :selected_poll_dates, "must select at least 2 dates for polling")
    else
      changeset
    end
  else
    changeset
  end
end
```

## Testing Strategy

### Unit Tests
- Component rendering with various states
- Date selection/deselection logic
- Month navigation
- Accessibility attributes
- Responsive design elements

### Integration Tests
- Form submission with selected dates
- Validation error handling
- Calendar/form synchronization
- Event creation flow

### Example Test
```elixir
test "selects a date when clicked" do
  {:ok, view, _html} = live_isolated(build_conn(), CalendarComponent, %{
    id: "test-calendar",
    selected_dates: []
  })

  future_date = Date.add(Date.utc_today(), 5)
  date_string = Date.to_iso8601(future_date)

  view
  |> element("button[phx-value-date='#{date_string}']")
  |> render_click()

  assert has_element?(view, "button[phx-value-date='#{date_string}'][aria-pressed='true']")
end
```

## Performance Considerations

### Optimization Strategies
1. **Minimal Re-renders**: Only update changed dates
2. **Efficient Date Calculations**: Cache month grids
3. **Debounced Events**: Prevent excessive event firing
4. **Lazy Loading**: Load only visible month data

### Memory Management
- Clean up event listeners in JavaScript hooks
- Avoid storing large date ranges in component state
- Use efficient data structures for date comparisons

## Browser Compatibility

### Supported Features
- **Date Input Fallback**: For browsers without full calendar support
- **Touch Events**: Mobile gesture support
- **Keyboard Navigation**: Full accessibility compliance
- **CSS Grid**: With flexbox fallbacks

### Polyfills Required
- None (uses only standard web APIs)

## Deployment Considerations

### Asset Compilation
Ensure JavaScript hooks are properly included in the build:

```javascript
// In app.js
import { CalendarKeyboardNav, CalendarFormSync } from "./hooks/calendar_hooks"

let Hooks = {
  CalendarKeyboardNav,
  CalendarFormSync,
  // ... other hooks
}
```

### CSS Optimization
Calendar styles are included in the main CSS bundle with Tailwind CSS purging enabled.

## Future Enhancements

### Planned Features
1. **Date Range Selection**: Click and drag to select ranges
2. **Recurring Date Patterns**: Weekly/monthly recurring options
3. **Time Zone Display**: Show dates in multiple time zones
4. **Bulk Operations**: Select/deselect all visible dates

### API Extensions
```elixir
# Potential future API
<.live_component
  module={CalendarComponent}
  id="event-calendar"
  selected_dates={@selected_dates}
  mode={:range}                    # :single, :multiple, :range
  min_date={Date.utc_today()}
  max_date={Date.add(Date.utc_today(), 365)}
  disabled_dates={@blackout_dates}
  time_zone={@user_timezone}
/>
```

## Troubleshooting

### Common Issues

**Calendar not updating after date selection**
- Check that `selected_dates_changed` message is being handled
- Verify JavaScript hooks are properly mounted

**Accessibility issues**
- Ensure all ARIA attributes are present
- Test with screen readers
- Verify keyboard navigation works

**Mobile responsiveness problems**
- Check Tailwind CSS classes are applied correctly
- Test on actual devices, not just browser dev tools
- Verify touch events are working

### Debug Tools

```elixir
# Enable debug logging in development
config :logger, level: :debug

# Add debug output to component
def handle_event("toggle_date", params, socket) do
  IO.inspect(params, label: "Calendar Event")
  # ... rest of handler
end
```

---

*Last updated: January 2025* 