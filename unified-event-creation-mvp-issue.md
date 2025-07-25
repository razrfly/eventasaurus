# Unified Event Creation MVP: Intent-Based Flow with Smart Payment & Planning Integration

## Summary

This issue consolidates our event creation flow to use an intent-based approach that intelligently sets up polling, thresholds, and payment configurations based on natural user choices. Rather than removing existing fields like `polling_deadline` and `threshold_count`, we'll repurpose them through smarter UI that asks the right questions.

## Background

We currently have several disconnected systems:
- **Status states**: `draft`, `polling`, `threshold`, `confirmed`, `canceled`
- **Polling fields**: `polling_deadline` (for date/venue/general polls)
- **Threshold fields**: `threshold_count`, `threshold_revenue_cents`, `threshold_type`
- **Payment types**: `ticketed_event`, `contribution_collection`, `ticketless`
- **UI paths**: "Confirmed Event", "Planning Stage", "Threshold Pre-Sale"

These all work but create a confusing user experience. We need to unify them through intent-based questions.

## Proposed Solution

### Core Concept: Three Smart Dropdown Questions

Keep our existing form structure but replace confusing radio buttons with smart dropdowns that default to the current behavior. This maintains backward compatibility while simplifying the experience.

#### 1. "When is your event?" (Dropdown defaults to: "✓ I have a specific date")
```
✓ I have a specific date → Shows date/time pickers (DEFAULT)
? Not sure - let attendees vote → Sets up polling with polling_deadline
○ Still planning - date TBD → Hides date fields, keeps as draft
```

**Backend mapping:**
- "I have a specific date" → `status: :confirmed` (or `:threshold` if Q3 requires validation)
- "Not sure" → `status: :polling`, creates date poll, sets `polling_deadline`
- "Still planning" → `status: :draft`

#### 2. "Where is your event?" (Dropdown defaults to: "✓ I have a venue")
```
✓ I have a venue → Shows venue selector (DEFAULT)
? Let attendees vote on location → Creates location poll
💻 Virtual event → Shows virtual URL field
○ Location TBD → Hides venue field, marks as planning stage
```

**Backend mapping:**
- "I have a venue" → Standard venue selection (current behavior)
- "Let attendees vote" → Creates venue/location poll
- Combined with date voting → Both polls active under same `polling_deadline`

#### 3. "How will people join your event?" (Dropdown defaults to: "🤝 Free event - just RSVPs")
```
🤝 Free event - just RSVPs → Free event, no payment (DEFAULT)
🎟️ Paid tickets → Traditional ticketed event
🎁 Free with optional donations → Contribution collection
💰 Needs funding to happen → Crowdfunding with thresholds
📊 Testing interest first → Threshold validation
```

**Backend mapping:**
- "Free event" → `is_ticketed: false`, `taxation_type: "ticketless"` (current default)
- "Paid tickets" → `is_ticketed: true`, `taxation_type: "ticketed_event"`
- "Needs funding" → `status: :threshold`, `threshold_revenue_cents` required
- "Optional donations" → `is_ticketed: false`, `taxation_type: "contribution_collection"`
- "Testing interest" → `status: :threshold`, `threshold_count` required

### Smart Field Reveals

Based on answers, show only relevant fields:

#### If "Not sure yet" on date:
```elixir
# Show inline:
- Poll end date [_____] # Sets polling_deadline
- Options to vote on:
  □ Specific dates
  □ Date ranges
  □ Day of week preferences
```

#### If "Need funding first":
```elixir
# Show inline:
- Minimum funding goal: $[____] # Sets threshold_revenue_cents
- Campaign deadline: [_____] # Can reuse polling_deadline
- What happens if not funded:
  ○ Full refund
  ○ Event happens anyway
  ○ Organizer decides
```

#### If "Test interest":
```elixir
# Show inline:
- Minimum attendees needed: [____] # Sets threshold_count
- Decision deadline: [_____] # Can reuse polling_deadline
- Also require funding? □ Yes → Show revenue threshold too
```

### UI Flow Implementation

```erb
<!-- Replace current "Setup Path" radio buttons with: -->

<div class="space-y-6">
  <!-- Question 1: Date Knowledge -->
  <div class="border rounded-lg p-4">
    <label class="text-sm font-medium">Do you know when this event will happen?</label>
    <select name="event[date_certainty]" class="mt-2">
      <option value="confirmed">✓ Yes, I have a specific date</option>
      <option value="polling">? Not sure - let attendees vote</option>
      <option value="planning">○ Still planning - date TBD</option>
    </select>
    
    <!-- Shows if "confirmed" selected -->
    <div id="date-fields" class="mt-4">
      <%= date and time pickers %>
    </div>
    
    <!-- Shows if "polling" selected -->
    <div id="date-poll-fields" class="mt-4 hidden">
      <label>When should voting end?</label>
      <input type="datetime-local" name="event[polling_deadline]">
      <!-- Poll configuration options -->
    </div>
  </div>

  <!-- Question 2: Venue Knowledge -->
  <div class="border rounded-lg p-4">
    <label class="text-sm font-medium">Do you know where it will be?</label>
    <select name="event[venue_certainty]">
      <option value="confirmed">✓ Yes, I have a venue</option>
      <option value="polling">? Let attendees vote</option>
      <option value="virtual">💻 Virtual event</option>
      <option value="tbd">○ Location TBD</option>
    </select>
    <!-- Conditional fields based on selection -->
  </div>

  <!-- Question 3: Participation Method -->
  <div class="border rounded-lg p-4">
    <label class="text-sm font-medium">How will people participate?</label>
    <div class="grid grid-cols-1 gap-3">
      <label class="border rounded p-3 cursor-pointer hover:bg-gray-50">
        <input type="radio" name="event[participation_type]" value="ticketed">
        <span class="ml-2">🎟️ They'll buy tickets</span>
      </label>
      <label class="border rounded p-3 cursor-pointer hover:bg-gray-50">
        <input type="radio" name="event[participation_type]" value="free">
        <span class="ml-2">🤝 It's free - just RSVPs</span>
      </label>
      <label class="border rounded p-3 cursor-pointer hover:bg-gray-50">
        <input type="radio" name="event[participation_type]" value="crowdfunding">
        <span class="ml-2">💰 I need funding first</span>
      </label>
      <label class="border rounded p-3 cursor-pointer hover:bg-gray-50">
        <input type="radio" name="event[participation_type]" value="contribution">
        <span class="ml-2">🎁 Free but accepting donations</span>
      </label>
      <label class="border rounded p-3 cursor-pointer hover:bg-gray-50">
        <input type="radio" name="event[participation_type]" value="interest">
        <span class="ml-2">📊 I want to test interest first</span>
      </label>
    </div>
    
    <!-- Conditional threshold/payment fields appear here -->
  </div>
</div>
```

### Backend Status Resolution

```elixir
defmodule EventasaurusWeb.EventLive.FormHelpers do
  def resolve_event_attributes(params) do
    base_attrs = %{}
    
    # Date certainty determines initial status
    base_attrs = case params["date_certainty"] do
      "confirmed" -> Map.put(base_attrs, :status, :confirmed)
      "polling" -> 
        base_attrs
        |> Map.put(:status, :polling)
        |> Map.put(:polling_deadline, params["polling_deadline"])
      "planning" -> Map.put(base_attrs, :status, :draft)
    end
    
    # Participation type determines payment and thresholds
    case params["participation_type"] do
      "ticketed" ->
        base_attrs
        |> Map.put(:is_ticketed, true)
        |> Map.put(:taxation_type, "ticketed_event")
        
      "free" ->
        base_attrs
        |> Map.put(:is_ticketed, false)
        |> Map.put(:taxation_type, "ticketless")
        
      "crowdfunding" ->
        base_attrs
        |> Map.put(:status, :threshold)
        |> Map.put(:is_ticketed, true)
        |> Map.put(:taxation_type, "ticketed_event")
        |> Map.put(:threshold_revenue_cents, dollars_to_cents(params["funding_goal"]))
        |> Map.put(:threshold_type, "revenue")
        
      "contribution" ->
        base_attrs
        |> Map.put(:is_ticketed, false)
        |> Map.put(:taxation_type, "contribution_collection")
        
      "interest" ->
        base_attrs
        |> Map.put(:status, :threshold)
        |> Map.put(:threshold_count, params["minimum_attendees"])
        |> Map.put(:threshold_type, "attendee_count")
    end
  end
end
```

## Benefits

1. **No field removal needed** - We keep `polling_deadline`, `threshold_count`, etc.
2. **Natural language** - Users answer questions, not configure technical fields
3. **Smart defaults** - System infers correct status and settings
4. **Progressive disclosure** - Only show fields when relevant
5. **Validation built-in** - Impossible to create invalid combinations

## Implementation Tasks

1. [ ] Update event creation form with three-question flow
2. [ ] Create `resolve_event_attributes/1` function to map answers to fields
3. [ ] Update form JavaScript for conditional field display
4. [ ] Add validation to ensure question answers match field values
5. [ ] Update event display to show user-friendly status messages
6. [ ] Test all combinations of answers map correctly
7. [ ] Update existing events to work with new flow

## Edge Cases to Handle

- **Multiple uncertainties**: Date polling + venue polling (both use same `polling_deadline`)
- **Threshold + Polling**: Interest validation while also polling for date/venue
- **Status transitions**: Moving from polling → threshold → confirmed as decisions are made
- **Default values**: Smart defaults when fields are left empty

## Success Metrics

- Reduced time to create events
- Fewer support questions about event setup
- Higher completion rate for event creation
- No invalid status/payment combinations

## Related Issues

- #678 - Payment Features (contribution, crowdfunding, donation)
- #679 - Intent-based event creation

This approach maintains all existing functionality while making the user experience dramatically simpler.