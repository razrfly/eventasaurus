# Poll Analytics Events Documentation

## Overview

This document describes all custom PostHog events tracked for poll engagement analytics in Eventasaurus.

## Event Schema

### 1. `poll_created`

Fired when a new poll is created.

**Properties:**
- `poll_id` (string): Unique identifier of the poll
- `event_id` (string): Associated event ID
- `poll_type` (string): Voting system type (binary, approval, ranked, star, date_selection)
- `options_count` (integer): Number of initial options
- `is_anonymous` (boolean): Whether anonymous voting is enabled
- `timestamp` (ISO 8601): When the poll was created

### 2. `poll_vote`

Fired when a user casts a vote in a poll.

**Properties:**
- `poll_id` (string): Unique identifier of the poll
- `option_id` (string): ID of the selected option
- `event_id` (string): Associated event ID
- `voting_system` (string): Type of voting system
- `poll_type` (string): Same as voting_system
- `is_anonymous` (boolean): Whether this was an anonymous vote
- `vote_value` (varies): Vote-specific value (for binary votes)
- `rank` (integer): Rank position (for ranked choice voting)
- `rating` (integer): Star rating (for star voting)
- `timestamp` (ISO 8601): When the vote was cast

### 3. `poll_suggestion_created`

Fired when a user suggests a new option for a poll.

**Properties:**
- `poll_id` (string): Unique identifier of the poll
- `suggestion_id` (string): ID of the created suggestion
- `event_id` (string): Associated event ID
- `poll_type` (string): Voting system type
- `option_title` (string): Title of the suggested option
- `is_anonymous` (boolean): Whether suggested anonymously
- `is_approved` (boolean): Initial approval status
- `timestamp` (ISO 8601): When the suggestion was created

### 4. `poll_suggestion_approved`

Fired when a moderator approves a poll suggestion.

**Properties:**
- `poll_id` (string): Unique identifier of the poll
- `suggestion_id` (string): ID of the approved suggestion
- `approver_id` (string): User ID of the approver
- `event_id` (string): Associated event ID
- `poll_type` (string): Voting system type
- `option_title` (string): Title of the approved option
- `suggested_by_id` (string): Original suggester's user ID
- `timestamp` (ISO 8601): When the suggestion was approved

### 5. `poll_viewed`

Fired when a user views a poll (on initial load).

**Properties:**
- `poll_id` (string): Unique identifier of the poll
- `event_id` (string): Associated event ID
- `poll_type` (string): Voting system type
- `poll_phase` (string): Current phase of the poll
- `is_anonymous` (boolean): Whether viewing anonymously
- `timestamp` (ISO 8601): When the poll was viewed

### 6. `poll_results_viewed`

Fired when a user views poll results.

**Properties:**
- `poll_id` (string): Unique identifier of the poll
- `is_anonymous` (boolean): Whether viewing anonymously
- `timestamp` (ISO 8601): When results were viewed

### 7. `poll_phase_changed`

Fired when a poll transitions between phases.

**Properties:**
- `poll_id` (string): Unique identifier of the poll
- `from_phase` (string): Previous phase
- `to_phase` (string): New phase
- `timestamp` (ISO 8601): When the phase changed

### 8. `poll_votes_cleared`

Fired when a user clears all their votes in a poll.

**Properties:**
- `poll_id` (string): Unique identifier of the poll
- `timestamp` (ISO 8601): When votes were cleared

### 9. `poll_deleted`

Fired when a poll is deleted.

**Properties:**
- `poll_id` (string): Unique identifier of the poll
- `timestamp` (ISO 8601): When the poll was deleted

### 10. `poll_guest_invited`

Fired when a guest is invited to participate in a poll.

**Properties:**
- `poll_id` (string): Unique identifier of the poll
- `event_id` (string): Associated event ID
- `invitation_method` (string): How the guest was invited (default: "email")
- `timestamp` (ISO 8601): When the invitation was sent

## User Identification

- **Authenticated Users**: Events are tracked with the user's actual ID
- **Anonymous Users**: Events are tracked with a temporary anonymous identifier (e.g., `anonymous_123456`)
- PostHog handles session tracking to link anonymous events to authenticated users when they log in

## Implementation Details

All poll analytics events are handled by the `Eventasaurus.Services.PollAnalyticsService` module, which:
- Provides type-safe event tracking functions
- Handles anonymous user identification
- Ensures consistent event property structure
- Integrates with the existing PostHog service

## Funnel Analysis Examples

### Poll Creation to Completion Funnel
1. `poll_created` → Poll is created
2. `poll_viewed` → Users view the poll
3. `poll_vote` → Users cast votes
4. `poll_results_viewed` → Results are viewed

### Suggestion Approval Funnel
1. `poll_suggestion_created` → Suggestion is made
2. `poll_suggestion_approved` → Suggestion is approved
3. `poll_vote` → Users vote on the suggestion

## Best Practices

1. **Avoid Duplicate Events**: Poll view tracking includes a flag to prevent duplicate events on component re-renders
2. **Include Context**: Always include relevant context like `event_id`, `poll_type`, and `poll_phase`
3. **Handle Anonymous Users**: Use consistent anonymous identifiers for session tracking
4. **Track User Journey**: Events are designed to track the complete user journey from poll creation to completion