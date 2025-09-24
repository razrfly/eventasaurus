# Phase II: Refactor and Enhance Plan with Friends Modal System

## Overview
Refactor the invitation modal system to create reusable components shared between the public "Plan with Friends" modal and the admin invitation system. Add missing features including existing user selection with smart recommendations.

## Context
Phase I successfully implemented the basic "Plan with Friends" functionality on public event pages, allowing users to create private events and invite friends via email. Phase II will enhance this with:
1. Ability to select existing Eventasaurus users (not just email addresses)
2. Smart recommendations based on past event attendees
3. Shared component architecture between admin and public modals
4. Complete email sending implementation

## Current State

### Working Features (Phase I)
- ✅ SimplePlanWithFriendsModal on public event pages
- ✅ Private event creation from public events
- ✅ Email address input for invitations
- ✅ Custom invitation message
- ✅ Authentication and form submission

### Missing Features
- ❌ Selection of existing Eventasaurus users
- ❌ "People from your past events" recommendations
- ❌ Email sending (TODO stub in send_invitations/3)
- ❌ Shared components between modals

### Existing Infrastructure
- `GuestInvitationModal` - Advanced modal with user selection (admin area)
- `SimplePlanWithFriendsModal` - Basic modal (public events)
- `get_historical_participants/2` - Backend function for participant recommendations
- `GuestInvitations` module - Participant scoring logic
- `Emails` module - Complete email templates
- `EmailInvitationJob` - Oban job for email delivery

## Phase II Implementation Plan

### 1. Create Shared Components

#### A. `UserSelectorComponent`
**Location**: `lib/eventasaurus_web/components/invitations/user_selector.ex`
- Search existing users by name/email
- Autocomplete functionality
- User avatar display
- Selection/deselection handlers
- Exclude already-selected users

#### B. `HistoricalParticipantsComponent`
**Location**: `lib/eventasaurus_web/components/invitations/historical_participants.ex`
- "People from your past events" section
- Smart recommendations using `get_historical_participants/2`
- Participant scoring and ranking
- Avatar grid display
- Quick selection interface
- Show event history context (e.g., "Attended 3 of your events")

#### C. `EmailInputComponent`
**Location**: `lib/eventasaurus_web/components/invitations/email_input.ex`
- Single email input with validation
- Bulk email input (comma-separated)
- Email format validation
- Duplicate detection
- Add to list functionality

#### D. `SelectedParticipantsComponent`
**Location**: `lib/eventasaurus_web/components/invitations/selected_participants.ex`
- Display selected users and emails
- Avatar/initial display
- Remove functionality
- Count display
- Categorize by type (existing users vs new emails)

#### E. `InvitationMessageComponent`
**Location**: `lib/eventasaurus_web/components/invitations/invitation_message.ex`
- Text area for personal message
- Character count
- Message preview
- Template suggestions

### 2. Refactor Existing Modals

#### A. `PublicPlanWithFriendsModal` (replacement for SimplePlanWithFriendsModal)
**Location**: `lib/eventasaurus_web/components/public_plan_with_friends_modal.ex`

**Features**:
- Use all shared components
- NO direct add functionality (invitation only)
- User selection with recommendations
- Email input for non-users
- Custom message
- Preview selected participants

**Component Usage**:
```elixir
<.live_component module={UserSelectorComponent} />
<.live_component module={HistoricalParticipantsComponent} />
<.live_component module={EmailInputComponent} />
<.live_component module={SelectedParticipantsComponent} />
<.live_component module={InvitationMessageComponent} />
```

#### B. `AdminInvitationModal` (refactored GuestInvitationModal)
**Location**: `lib/eventasaurus_web/components/admin_invitation_modal.ex`

**Features**:
- Use all shared components
- INCLUDES direct add functionality
- Toggle between "Invite" and "Add Directly" modes
- User selection with recommendations
- Email input for non-users
- Custom message (for invite mode)
- Immediate participant addition (for direct mode)

### 3. Implement Email Sending

#### Update `send_invitations/3` in `PublicEventShowLive`
Replace TODO stub with actual implementation:
```elixir
defp send_invitations(socket, emails, message) do
  event = socket.assigns.private_event
  organizer = get_authenticated_user(socket)

  # Parse emails and create participants
  email_list = parse_email_list(emails)

  Enum.each(email_list, fn email ->
    # Create or find user
    user = find_or_create_guest_user(email)

    # Add as participant
    Events.add_participant_to_event(event, user, "invited")

    # Queue email job
    %{
      user_id: user.id,
      event_id: event.id,
      invitation_message: message,
      organizer_id: organizer.id
    }
    |> EmailInvitationJob.new()
    |> Oban.insert()
  end)
end
```

### 4. Backend Enhancements

#### A. User Search API
- Add `search_users/2` function to Accounts context
- Support search by name, username, email
- Exclude blocked users
- Return paginated results

#### B. Guest User Creation
- Implement `find_or_create_guest_user/1`
- Create placeholder users for email-only invites
- Mark as "pending" until they register

### 5. LiveView Integration

#### Update `PublicEventShowLive`
- Replace SimplePlanWithFriendsModal with PublicPlanWithFriendsModal
- Add handle_event for user search
- Add handle_event for loading historical participants
- Update submit handler to support both users and emails

#### Update Event Admin Pages
- Replace GuestInvitationModal with AdminInvitationModal
- Ensure backward compatibility
- Add proper permission checks

## Technical Specifications

### Data Flow
1. User opens modal → Load historical participants
2. User searches → Query existing users
3. User selects participants → Update selected list
4. User adds emails → Validate and add to list
5. User submits → Create event, add participants, queue emails

### State Management
```elixir
assigns:
  selected_users: [%User{}, ...]
  selected_emails: ["email@example.com", ...]
  historical_participants: [%{user: %User{}, score: float}, ...]
  search_results: [%User{}, ...]
  invitation_message: String
  modal_mode: :invite | :direct (admin only)
```

### Performance Considerations
- Lazy load historical participants
- Debounce user search (300ms)
- Limit historical participants to top 20
- Cache search results in socket assigns
- Batch email job creation

## Acceptance Criteria

### Functional Requirements
- [ ] Users can select existing Eventasaurus users for invitations
- [ ] "People from your past events" shows relevant recommendations
- [ ] Both user selection and email input work seamlessly
- [ ] Emails are actually sent via the queued job system
- [ ] Admin modal retains all existing functionality
- [ ] Public modal excludes direct-add functionality

### User Experience
- [ ] Selected participants show avatars/initials
- [ ] Clear distinction between users and email-only invites
- [ ] Search is responsive (<300ms)
- [ ] Recommendations are relevant and scored properly
- [ ] Modal remains performant with many selections

### Technical Requirements
- [ ] All components are properly isolated and reusable
- [ ] No code duplication between modals
- [ ] Proper error handling for email sending
- [ ] Database transactions for invitation creation
- [ ] Tests for all new components

### Backward Compatibility
- [ ] Existing admin invitation flow continues to work
- [ ] Database migrations are non-breaking
- [ ] API changes are additive only

## Testing Plan

### Unit Tests
- Component isolation tests
- User search functionality
- Email validation
- Participant scoring

### Integration Tests
- Modal interaction flow
- Email job queuing
- Event creation with invitations
- Historical participant loading

### E2E Tests (Playwright)
- Complete invitation flow
- User selection and search
- Email sending verification
- Modal state management

## Migration Path

1. **Step 1**: Create shared components (non-breaking)
2. **Step 2**: Update public modal to use new components
3. **Step 3**: Implement email sending
4. **Step 4**: Refactor admin modal (careful testing)
5. **Step 5**: Remove old components
6. **Step 6**: Performance optimization

## Dependencies
- Existing `get_historical_participants/2` function
- `GuestInvitations` scoring module
- Oban job queue for emails
- Swoosh email system

## Notes
- Consider adding invitation tracking (opened, clicked, accepted)
- Future: Add invitation reminder functionality
- Future: Calendar integration for event invites
- Ensure mobile responsiveness for all components

## Related Issues
- #1223 - Phase I: Basic Plan with Friends
- #1224 - Phase I Completion Review
- #1219 - Guest Management System Reference