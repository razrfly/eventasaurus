# Phase 1: Time Polling Enhancement
**Add time granularity to existing date polling feature**

## Overview
Extend our existing date polling functionality to optionally include time selection. This enhancement maintains the current date-only polling as the default behavior while adding an optional time specification mode that allows organizers to specify start and end times for each selected date.

## Current State Analysis

### Existing Date Polling Feature
Our current implementation provides a robust date-only polling system:

**Data Structure:**
- `event_date_polls` - Main poll entity (one per event)
- `event_date_options` - Individual date choices (`date` field only - no time)
- `event_date_votes` - User votes with 3 types (yes/if_need_be/no)

**Current UI Flow:**
1. Event organizer enables date polling during event creation
2. Calendar component allows multi-date selection
3. Poll is created with date-only options
4. Participants vote on full-day date options
5. Results show vote tallies for each date

**Current Limitations:**
- `EventDateOption.date` is Date type (no time component)
- Calendar component only handles date selection
- UI assumes all-day events
- Database constraints designed for unique dates per poll

## Proposed Enhancement

### User Experience Flow

**Step 1: Date Selection (Existing)**
- User selects multiple dates using the existing calendar component
- This remains unchanged from current implementation

**Step 2: Time Selection Toggle (New)**
- Below the calendar, add a toggle/checkbox: "Specify times for selected dates"
- When disabled (default): behaves exactly like current system
- When enabled: reveals time specification interface

**Step 3: Time Specification Interface (New)**
- Shows selected dates in a vertical list
- Each date row contains:
  - Date label (e.g., "Jul 17", "Jul 18", "Jul 24")
  - Start time dropdown/picker
  - End time dropdown/picker 
  - "Add time option" button to add multiple time slots per date
  - Delete button to remove time slots

**Step 4: Multiple Time Slots Per Date (New)**
- Each date can have multiple time options (e.g., "Morning" and "Afternoon" slots)
- Each time slot becomes a separate poll option
- Users can add/remove time slots dynamically

### Technical Implementation

#### Database Schema Changes
```sql
-- Add optional time fields to event_date_options
ALTER TABLE event_date_options 
ADD COLUMN start_time TIME,
ADD COLUMN end_time TIME,
ADD COLUMN time_description VARCHAR(255); -- Optional label like "Morning Session"

-- Update unique constraint to allow multiple time slots per date
DROP CONSTRAINT event_date_options_event_date_poll_id_date_index;
CREATE UNIQUE INDEX event_date_options_unique_datetime 
ON event_date_options (event_date_poll_id, date, start_time, end_time);
```

#### Data Model Updates
- **EventDateOption**: Add `start_time`, `end_time`, and `time_description` fields
- **EventDatePoll**: Add `include_times` boolean field to track poll type
- Update validation to ensure time consistency (start_time < end_time)
- Update display methods to show time ranges when present

#### UI Components
- **Calendar Component**: No changes needed (remains date-only)
- **New TimeSpecificationComponent**: 
  - Renders selected dates with time pickers
  - Handles adding/removing time slots
  - Validates time ranges
- **Poll Creation Form**: Add time specification toggle
- **Voting Interface**: Update to display date+time options

#### API Changes
- `create_event_date_poll/3`: Accept optional time data
- `create_date_options_with_times/3`: New function for time-enabled options
- Update vote display functions to handle time formatting

### Design Inspiration
Based on Rallly.co's approach (screenshots provided):
- Clean toggle to enable time specification
- Selected dates displayed as individual cards/rows
- Time pickers for start/end times
- "Add time option" buttons for multiple slots per date
- Consistent with existing calendar aesthetic

### User Interface Mockup Description

**Initial State (Time Toggle OFF):**
```
┌─────────────────────────────────────┐
│ [Calendar Component - Existing]     │
│ Select dates: Jul 17, 18, 24       │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ ☐ Specify times for selected dates  │
└─────────────────────────────────────┘
```

**Time Specification Enabled:**
```
┌─────────────────────────────────────┐
│ [Calendar Component - Existing]     │
│ Select dates: Jul 17, 18, 24       │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ ☑ Specify times for selected dates  │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ Jul 17                              │
│ [12:00 PM ▼] to [1:00 PM ▼] [✕]   │
│ + Add time option                   │
├─────────────────────────────────────┤
│ Jul 18                              │
│ [12:00 PM ▼] to [1:00 PM ▼] [✕]   │
│ + Add time option                   │
├─────────────────────────────────────┤
│ Jul 24                              │
│ [12:00 PM ▼] to [1:00 PM ▼] [✕]   │
│ + Add time option                   │
└─────────────────────────────────────┘
```

## Implementation Requirements

### Phase 1 Scope (This Issue)
1. **Database Migration**: Add time fields to `event_date_options`
2. **Data Model Updates**: Extend `EventDateOption` with time fields
3. **Time Specification UI**: Create new component for time selection
4. **Poll Creation Flow**: Add time toggle to existing form
5. **API Updates**: Modify poll creation to handle time data
6. **Display Updates**: Update voting interface to show times

### Acceptance Criteria
- [ ] Toggle appears below calendar during poll creation
- [ ] When toggle is OFF, system behaves exactly like current implementation
- [ ] When toggle is ON, selected dates appear with time pickers
- [ ] Users can add multiple time slots per date
- [ ] Time slots can be removed individually
- [ ] Database correctly stores date+time combinations
- [ ] Poll voting interface displays time ranges when present
- [ ] Full-day and time-specific polls can coexist in the system

### Technical Considerations
- **Backward Compatibility**: Existing date-only polls continue to work
- **Performance**: Time specification UI should load quickly
- **Validation**: Ensure end time is after start time
- **Time Zones**: Consider future time zone support (out of scope for Phase 1)
- **Mobile Responsiveness**: Time pickers work well on mobile devices

### Out of Scope (Future Phases)
- Time zone conversion and display
- Recurring time patterns
- Calendar integration (ICS export with times)
- Advanced time conflict detection
- Time-based poll analytics

## Estimated Effort
- **Database Migration**: 2 hours
- **Data Model Updates**: 4 hours  
- **Time Specification UI Component**: 8 hours
- **Poll Creation Integration**: 4 hours
- **API Updates**: 6 hours
- **Display Updates**: 6 hours
- **Testing & QA**: 8 hours
- **Total**: ~38 hours

## Dependencies
- Existing calendar component functionality
- Current poll creation flow
- Event date polling database schema

## Related Issues
- Extracted from: #392 (Phase 1: Time Polling Enhancement)
- Future: Time zone support enhancement
- Future: Calendar integration with time export

---

**Priority**: High
**Labels**: enhancement, polling, ui-enhancement, phase-1
**Assignee**: TBD
**Milestone**: Time Polling Enhancement - Phase 1