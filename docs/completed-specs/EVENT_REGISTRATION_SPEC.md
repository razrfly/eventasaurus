# Event Registration Flow Specification

## Overview
Allow anonymous users to register for events with just their name and email address, creating Supabase Auth users and EventParticipant records without requiring immediate verification or sign-in.

## User Flow

### 1. Event Discovery
- User visits public event page
- Sees "Register for this event" button with "Register Now - Limited spots available" text
- Button is prominently displayed and clearly actionable

### 2. Registration Form
- Clicking "Register" shows a registration form modal/page
- Form matches the design language of existing public event pages
- Simple form with:
  - **Name** (required text input)
  - **Email** (required email input with validation)
  - **Register** button (disabled during submission)
- Form uses the same styling as the existing public event layout

### 3. Backend Processing
When form is submitted:

#### Step 1: User Management
- Check if user exists in Supabase Auth by email
- If user doesn't exist:
  - Create new user with `supabase.auth.admin.createUser()`
  - Set `email_confirm: true` (bypasses verification requirement)
  - Store name in `user_metadata`
  - Generate a temporary password (user will set their own later)

#### Step 2: Event Registration Check
- Check if user is already registered for this event
- Query EventParticipant table for existing registration

#### Step 3: Create Participation Record
- If not already registered:
  - Create new EventParticipant record with:
    - `role: :invitee`
    - `status: :pending`
    - `source: "public_registration"`
    - `metadata: {registration_date: timestamp}`

### 4. Response Handling

#### Success Cases:
- **New registration**: "Thanks! You're registered for [Event Name]. Check your email for account verification instructions."
- **Existing user, new registration**: "Welcome back! You're now registered for [Event Name]."

#### Edge Cases:
- **Already registered**: "You have already registered for this event. Check your email for details or contact the organizer."
- **Event full**: "Sorry, this event is currently full. You've been added to the waitlist."
- **Event past**: "Registration for this event has closed."

#### Error Cases:
- **Invalid email**: Show inline validation error
- **Server error**: "Something went wrong. Please try again or contact support."

## Technical Implementation

### Frontend Components
1. **Registration Button** - Existing button that triggers the form
2. **Registration Form Modal/Page** - New form component
3. **Success/Error Messages** - Toast notifications or inline messages

### Backend Endpoints
1. **POST /events/:slug/register** - Handle registration submission
2. Input validation and sanitization
3. Supabase Auth user creation
4. EventParticipant record creation
5. Error handling and appropriate responses

### Database Operations
1. Check user existence in `auth.users`
2. Check existing registration in `event_participants`
3. Create user (if needed) via Supabase Admin API
4. Create EventParticipant record
5. All operations in a transaction for data consistency

### Security Considerations
- Rate limiting on registration endpoint
- Email validation and sanitization
- Prevent multiple rapid submissions
- CSRF protection
- Input validation on both client and server

### Follow-up Actions
- Email sent to user with:
  - Event confirmation details
  - Account verification link (if new user)
  - Instructions for setting password/logging in
  - Event details and calendar invite

## Files to Create/Modify

### Frontend (Phoenix LiveView)
- `lib/eventasaurus_web/live/event_registration_live.ex` - Registration form LiveView
- `lib/eventasaurus_web/live/event_registration_live.html.heex` - Form template
- Add registration button/modal to existing public event page

### Backend
- Add registration route to router
- Add registration functions to Events context
- Handle user creation and event participation logic

### Styling
- Use existing public event page CSS classes
- Ensure mobile responsiveness
- Match current design system

## Success Metrics
- User can register with just name/email
- No duplicate registrations allowed
- Clear feedback for all scenarios
- Consistent with existing UI/UX patterns
- Works on mobile and desktop
- Fast and reliable registration process

## Future Enhancements
- Waitlist functionality for full events
- Social sharing after registration
- Calendar integration
- SMS notifications (if phone collected)
- Custom registration questions per event 