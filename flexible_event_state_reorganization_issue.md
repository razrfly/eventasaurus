# Flexible Event State Reorganization: Combining Planning and Threshold Features

## Problem Statement

The current event state system creates artificial barriers between different planning workflows that should ideally be combinable. Specifically:

1. **Rigid State Separation**: The current system forces events into distinct states (`planning` → `polling` → `threshold` → `confirmed`) when real-world event planning often requires hybrid approaches.

2. **Planning + Threshold Gap**: Organizers want to simultaneously ask for date preferences AND set participant thresholds (e.g., "We need at least 10 people - which date works for these 10?").

3. **UI Complexity**: The public event page becomes cluttered when polling is enabled, dumping calendar interface directly into the main event content rather than organizing it cleanly.

4. **Inconsistent Organization**: Date polling is embedded inline in events, while generic polling lives in separate tabs, creating user confusion about where different features are located.

## Current Architecture Analysis

### State Management Overview

**Location**: `lib/eventasaurus_app/event_state_machine.ex`

**Current States**:
- `:draft` → `:polling` → `:threshold` → `:confirmed` → `:canceled`

**Current Phases** (computed):
- `:planning` → `:polling` → `:awaiting_confirmation` → `:prepaid_confirmed`/`:ticketing` → `:open` → `:ended`

### Current Limitations

#### 1. **Mutually Exclusive States**
```elixir
# From event_state_machine.ex:74-92
def infer_status(attrs) when is_map(attrs) do
  cond do
    has_value?(attrs, :canceled_at) -> :canceled
    has_value?(attrs, :polling_deadline) -> :polling  # Blocks threshold
    has_value?(attrs, :threshold_count) -> :threshold # Blocks polling
    true -> :confirmed
  end
end
```

**Issue**: An event cannot simultaneously poll for dates AND require thresholds.

#### 2. **Inflexible Phase Logic**
```elixir
# From event_state_machine.ex:219-253
def computed_phase_uncached(%EventasaurusApp.Events.Event{} = event, %DateTime{} = current_time) do
  cond do
    event.status == :polling -> :polling          # Pure polling mode
    event.status == :threshold -> :awaiting_confirmation  # Pure threshold mode
    # No hybrid support
  end
end
```

#### 3. **UI Layout Issues**

**Date Polling**: Embedded directly in public event page (lines 1304-1516 in `public_event_live.ex`)
- Clutters main event content
- No clean separation of concerns
- Hard to organize with other event details

**Generic Polling**: Separate tab in event management
- Different UX patterns for similar functionality
- Inconsistent user mental model

### Polling Systems Architecture Comparison

| Aspect | Date Polling (Legacy) | Generic Polling (Modern) |
|--------|----------------------|--------------------------|
| **Integration** | Inline in event page | Separate management tab |
| **Flexibility** | Date selection only | Multiple poll types & voting systems |
| **State Integration** | Tightly coupled to event lifecycle | Modular, independent |
| **UI Organization** | Embedded, clutters page | Clean tab separation |

## Proposed Solutions

### 1. **Flexible State Combinations**

#### A. **Enhanced State Machine**
```elixir
# Proposed enhancement to infer_status/1
def infer_status(attrs) when is_map(attrs) do
  cond do
    has_value?(attrs, :canceled_at) -> :canceled
    
    # NEW: Support hybrid states
    has_value?(attrs, :polling_deadline) && has_value?(attrs, :threshold_count) -> :polling_with_threshold
    has_value?(attrs, :polling_deadline) -> :polling
    has_value?(attrs, :threshold_count) -> :threshold
    
    true -> :confirmed
  end
end
```

#### B. **New Hybrid Phases**
```elixir
# Proposed new phases
:planning_with_threshold     # Planning stage but with threshold requirement announced
:polling_with_threshold      # Active polling but with threshold constraints
:threshold_polling_ended     # Polling ended, checking if threshold met
```

### 2. **Unified Polling Architecture**

#### A. **Component-Based Organization**
Move date polling to the same organizational pattern as generic polling:

```
Event Page Structure:
├── Main Content (Event Details)
├── Navigation Tabs
│   ├── Overview (Basic info, description)
│   ├── Planning (All polling/planning tools)
│   │   ├── Date Polling
│   │   ├── Interest Polling  
│   │   ├── Threshold Settings
│   │   └── Generic Polls
│   ├── Registration (Tickets, etc.)
│   └── Participants
```

#### B. **Planning Tab Integration**
Create a dedicated "Planning" tab that contains:
- **Date Selection**: Current date polling functionality
- **Interest Tracking**: Show current participant count vs threshold
- **Threshold Visualization**: Progress bars, requirements
- **Planning Polls**: Generic polls relevant to planning (venue, time, etc.)

### 3. **Enhanced State Combinations**

#### A. **Planning + Threshold Workflow**
```
State: :planning_with_threshold
Phase: :planning_with_threshold

Features Available:
- Set date options for polling
- Set minimum participant threshold
- Show "We need X people" messaging
- Allow interest indication before date commitment
- Progress tracking toward threshold
```

#### B. **Polling + Threshold Workflow**
```
State: :polling_with_threshold  
Phase: :polling_with_threshold

Features Available:
- Active date voting
- Real-time threshold monitoring
- "X people needed for Y date" messaging
- Conditional confirmation logic
```

### 4. **UI/UX Improvements**

#### A. **Clean Event Page**
- Move date polling to dedicated Planning tab
- Keep main event page focused on confirmed details
- Reduce cognitive load and clutter

#### B. **Consistent Mental Model**
- All planning activities in one location
- Similar UX patterns for all polling types
- Clear separation between planning and confirmed details

#### C. **Progressive Disclosure**
```
Main Event Page (Clean):
├── Confirmed event details
├── Registration (if open)
└── "Planning in Progress" banner (links to Planning tab)

Planning Tab (Comprehensive):
├── Date Selection
├── Threshold Progress  
├── Interest Polls
├── Venue Polls
└── Custom Polls
```

## Implementation Strategy

### Phase 1: **State Machine Enhancement**
1. Add support for combination states (`polling_with_threshold`)
2. Update phase computation logic
3. Add database fields for hybrid configurations
4. Update validation logic

### Phase 2: **UI Reorganization**  
1. Create Planning tab component
2. Move date polling to Planning tab
3. Update public event page layout
4. Implement consistent polling UI patterns

### Phase 3: **Threshold Integration**
1. Add threshold progress to Planning tab
2. Implement hybrid confirmation logic
3. Update messaging for combined workflows
4. Add organizer controls for threshold management

### Phase 4: **Enhanced Features**
1. Smart threshold suggestions based on polling data
2. Conditional date confirmation (if threshold met)
3. Advanced analytics in Planning tab
4. Participant communication improvements

## Database Schema Changes

### New Fields for Event Model
```elixir
# Add to events table migration
add :planning_features, {:array, :string}, default: []  # ["date_polling", "threshold", "interest_tracking"]
add :threshold_per_date, :boolean, default: false       # Threshold applies per date option
add :auto_confirm_threshold, :boolean, default: false   # Auto-confirm when threshold met
```

### Enhanced State Constraints
```elixir
# Update status enum to include hybrid states
create constraint(:events, :status_check, 
  check: "status IN ('draft', 'polling', 'threshold', 'polling_with_threshold', 'confirmed', 'canceled')")
```

## Benefits

### 1. **Increased Flexibility**
- Organizers can combine planning features as needed
- More natural event planning workflows
- Better matches real-world event organization needs

### 2. **Improved UX**
- Cleaner event pages with less clutter
- Consistent organization patterns
- Reduced cognitive load for users

### 3. **Better Organization**
- All planning activities in one logical location
- Clear separation between planning and confirmed details
- Scalable architecture for future planning features

### 4. **Enhanced Capability**
- "Need 10 people, which date works?" workflows
- Threshold progress tracking during polling
- Conditional confirmation based on multiple criteria

## Migration Strategy

### 1. **Backward Compatibility**
- Existing events continue working unchanged
- New features opt-in only
- Graceful degradation for legacy states

### 2. **Gradual Rollout**
- Phase 1: New state machine (behind feature flag)
- Phase 2: UI reorganization (optional tab)
- Phase 3: Full hybrid workflows
- Phase 4: Enhanced features

### 3. **Testing Strategy**
- Comprehensive state machine tests
- UI integration tests for tab switching
- End-to-end workflow tests
- Performance testing for complex state calculations

## Success Metrics

### 1. **Feature Adoption**
- % of events using hybrid states
- Planning tab usage analytics
- Feature combination patterns

### 2. **User Experience**
- Time spent in event creation
- Event page bounce rates
- User feedback on planning workflows

### 3. **Technical Metrics**
- State transition performance
- UI component load times
- Error rates in hybrid workflows

---

This reorganization addresses the core issues of rigid state separation while providing a cleaner, more flexible architecture that can grow with user needs and support complex real-world event planning scenarios.