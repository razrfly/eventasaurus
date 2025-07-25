# Event Creation Flow Unification: Streamlining Status, Payment, and Planning Workflows

## Problem Analysis

### Current System Architecture
After auditing the codebase, I've identified several interconnected but potentially confusing systems that need better integration:

#### 1. Event Status System (`EventStateMachine`)
**Current statuses:**
- `draft` → Initial state, minimal requirements
- `polling` → Date/time polling active (requires `polling_deadline`)
- `threshold` → Pre-sale validation mode (requires `threshold_count` and/or `threshold_revenue_cents`)
- `confirmed` → Standard event, ready to go
- `canceled` → Event canceled (requires `canceled_at`)

**Computed phases** (runtime state):
- `planning` → Event being planned
- `polling` → Actively polling for interest
- `awaiting_confirmation` → Polling deadline passed, awaiting organizer decision
- `prepaid_confirmed` → Threshold met with prepayment
- `ticketing` → Event confirmed and tickets are being sold
- `open` → Event confirmed and open for attendance
- `ended` → Event has completed
- `canceled` → Event was canceled

#### 2. Money Collection System
**Taxation types:**
- `ticketed_event` → Traditional paid events with Stripe
- `contribution_collection` → Manual payment tracking
- `ticketless` → Free events, no money collection

**Ticket pricing models:**
- `fixed` → Set price
- `flexible` → Pay-what-you-want (min/max/suggested)
- `dynamic` → Variable pricing

**Threshold system:**
- `attendee_count` → Minimum participant threshold
- `revenue` → Minimum revenue threshold
- `both` → Both attendee and revenue thresholds must be met

#### 3. Polling System
**New generic polling** (replaced old date polling):
- Poll types: `movie`, `places`, `custom`, `time`, `general`, `venue`, `date_selection`
- Voting systems: `binary`, `approval`, `ranked`, `star`
- Phases: `list_building`, `voting_with_suggestions`, `voting_only`, `closed`

### Current Problems

#### 1. **Confusing Status Labels**
The UI shows "Confirmed Event", "Planning Stage", and "Threshold Pre-Sale" but:
- These don't clearly communicate the user's intent
- The relationship between status and money collection is unclear
- "Planning Stage" could mean several different things

#### 2. **Disconnected Decision Points**
Users need to make several related decisions that aren't logically connected:
- Do you know the exact date/time?
- Are you collecting money?
- What type of payment collection?
- Do you want to validate demand first?
- Are you polling for preferences?

#### 3. **Feature Conflicts**
Current conflicts and ambiguities:
- **Threshold + Polling**: Can you have both? The codebase allows it but UX implications are unclear
- **Free events with thresholds**: Doesn't make business sense but is technically possible
- **Polling without confirmed date**: The old date polling was removed but status can still be "polling"
- **Contribution collection + thresholds**: Manual payment tracking conflicts with automated threshold validation

#### 4. **Missing Validation Logic**
- No clear validation between `taxation_type`, `is_ticketed`, and `status`
- Threshold settings can exist without threshold status
- Polling deadline can exist without polling status

## Proposed Solution

### 1. **Intent-Based Event Creation Flow**

Instead of forcing users to understand technical statuses, design the flow around **user intent**:

#### Step 1: Event Purpose
*"What kind of event are you planning?"*
- 🎟️ **Ticketed Event** → Traditional paid event
- 🤝 **Community Gathering** → Free event, just RSVPs
- 💰 **Crowdfunded Event** → Needs minimum funding to happen
- 🎁 **Contribution-Based** → Suggested donations, pay-what-you-can
- 📊 **Interest Check** → Validate demand before committing

#### Step 2: Planning Status
*"How much do you know about the event?"*
- ✅ **Details confirmed** → Date, time, venue set
- 📅 **Need help with date/time** → Poll attendees for preferences
- 📍 **Need help with venue/details** → Poll attendees for preferences
- 🤔 **Still figuring it out** → Draft mode, minimal requirements

#### Step 3: Conditional Logic
Based on selections, show relevant options:

**For Interest Check:**
- Minimum attendees needed
- Optional: Minimum funding needed
- Polling options (date, venue, etc.)

**For Crowdfunded:**
- Minimum funding amount
- Payment collection method
- Threshold type (attendees vs revenue vs both)

**For Contribution-Based:**
- Payment collection method (Stripe vs manual tracking)
- Suggested amount
- Price flexibility

### 2. **Unified State Management**

Create a new abstraction layer that maps user intentions to technical implementation:

```elixir
defmodule EventasaurusApp.EventWizard do
  @doc """
  Determines the appropriate technical status based on user selections
  """
  def infer_technical_status(wizard_state) do
    case wizard_state do
      %{purpose: "interest_check", planning_status: "details_confirmed"} -> 
        {:threshold, threshold_settings}
      
      %{purpose: "interest_check", planning_status: "need_date_poll"} -> 
        {:polling, polling_settings}
      
      %{purpose: "community_gathering", planning_status: "details_confirmed"} -> 
        {:confirmed, free_event_settings}
      
      %{purpose: "ticketed_event", planning_status: "still_planning"} -> 
        {:draft, draft_settings}
      
      # ... other combinations
    end
  end
end
```

### 3. **Smart Validation Rules**

Implement business logic validation that prevents impossible combinations:

```elixir
defmodule EventasaurusApp.Events.EventValidator do
  def validate_event_configuration(changeset) do
    changeset
    |> validate_payment_threshold_consistency()
    |> validate_polling_status_consistency()
    |> validate_taxation_ticketing_consistency()
    |> validate_threshold_business_logic()
  end
  
  defp validate_payment_threshold_consistency(changeset) do
    # Free events (ticketless) cannot have revenue thresholds
    # Contribution collection needs manual tracking capabilities
    # etc.
  end
end
```

### 4. **Progressive Disclosure UI**

Design the creation flow to only show relevant options:

```
Event Creation Wizard:
├── Step 1: Purpose Selection (always shown)
├── Step 2: Planning Status (always shown)  
├── Step 3A: Payment Settings (conditional on purpose)
│   ├── Stripe Integration
│   ├── Manual Tracking Options
│   └── Pricing Model Selection
├── Step 3B: Threshold Settings (conditional on purpose)
│   ├── Minimum Attendees
│   ├── Minimum Revenue
│   └── Validation Rules
├── Step 3C: Polling Setup (conditional on planning status)
│   ├── Date/Time Polls
│   ├── Venue Polls
│   ├── Preference Polls
│   └── Deadline Management
└── Step 4: Review & Create
```

### 5. **Status Display Overhaul**

Replace technical status names with user-friendly descriptions:

**Current → Proposed:**
- "Confirmed Event" → "Ready to Go" / "Open for Registration"
- "Planning Stage" → "Getting Feedback" / "Collecting Votes"
- "Threshold Pre-Sale" → "Validating Interest" / "Crowdfunding Active"

Add contextual information:
- "Waiting for 15 more people to sign up"
- "Polling closes in 3 days"
- "Collected $450 of $1000 goal"

## Implementation Plan

### Phase 1: Backend Foundation (Week 1)
1. Create `EventWizard` module for intent-to-configuration mapping
2. Enhance validation logic in `Event` changeset
3. Add migration for wizard state storage (if needed)
4. Update `EventStateMachine` with new business rules

### Phase 2: Frontend Wizard (Week 2)
1. Build progressive disclosure creation form
2. Update event status displays
3. Add contextual help text and explanations
4. Implement smart defaults and recommendations

### Phase 3: Migration & Testing (Week 3)
1. Create data migration for existing events
2. Update existing event management interfaces
3. Comprehensive testing of all combinations
4. User acceptance testing

## Database Changes Needed

### Minimal Schema Changes
Most logic can be implemented without schema changes, but consider:

```sql
-- Optional: Store wizard selections for future reference
ALTER TABLE events ADD COLUMN creation_wizard_state JSONB;

-- Optional: Computed field for user-friendly status
ALTER TABLE events ADD COLUMN display_status TEXT GENERATED ALWAYS AS (
  CASE 
    WHEN status = 'confirmed' AND is_ticketed THEN 'Open for Registration'
    WHEN status = 'polling' THEN 'Getting Feedback'
    WHEN status = 'threshold' THEN 'Validating Interest'
    ELSE 'In Planning'
  END
) STORED;
```

## Success Metrics

### User Experience
- Reduced time-to-create for new events
- Decreased support tickets about event configuration
- Higher completion rate in event creation flow

### System Health
- Fewer invalid event configurations
- Reduced edge cases in status transitions
- Cleaner separation of concerns

### Business Impact
- More diverse event types created
- Better adoption of advanced features (thresholds, polling)
- Clearer path for new feature additions

## Migration Strategy

### For Existing Events
1. **Preserve all existing functionality** - no breaking changes
2. **Gradual migration** - new wizard for new events, legacy interface remains
3. **Optional upgrade** - allow existing event owners to "upgrade" to new system
4. **Data integrity** - ensure all existing events have valid configurations

### For New Features
The wizard approach makes it much easier to add new event types:
- **Hybrid events** (in-person + virtual)
- **Multi-session events** (workshops, courses)
- **Marketplace events** (vendor fairs)
- **Charity fundraisers**

## Conclusion

The current system has excellent technical foundations but suffers from poor information architecture. By focusing on **user intent** rather than **technical implementation**, we can create a much more intuitive and powerful event creation experience.

The key insight is that users don't think in terms of "polling status" and "threshold revenue" - they think in terms of "I want to see if people are interested" and "I need to collect money first." The system should translate user intentions into technical configurations automatically.

This approach will:
1. **Reduce cognitive load** for event creators
2. **Prevent configuration errors** through smart validation
3. **Enable new features** through flexible architecture
4. **Maintain backward compatibility** with existing events
5. **Scale to new event types** easily

---

**Related Issues:**
- #678 (Sales/Contribution Integration)
- Previous polling system discussions
- Threshold system implementation

**Technical Debt:**
- Remove unused polling deadline fields where not needed
- Consolidate validation logic across Event/Order/Ticket models
- Consider extracting payment logic into separate service