# Feature Spec: Add Existing Users to Events

## Overview
Implement a user search and selection interface to allow event organizers to add existing registered users as co-organizers, improving upon the current guest invitation system which only handles email-based invitations.

## Current System Analysis
- **Events support multiple organizers** via `EventUser` table with `role` field
- **Existing guest invitation system** handles email-based invitations for participants
- **No user search functionality** exists for finding existing registered users
- **Historical suggestions** only show users from organizer's past events
- **User profiles** include searchable fields: `name`, `email`, `username`, `bio`

## User Story
**As an event organizer**, I want to search for and add existing registered users as co-organizers to my event, so that multiple people can collaboratively manage the same event.

## Requirements

### Core Functionality
1. **Search existing users only** - no email invitation for non-existent users
2. **Search by multiple fields**: username, email, display name
3. **Add users as co-organizers** with same permissions as event creator
4. **Real-time search** with debounced input
5. **User profile previews** showing username, name, and bio
6. **Duplicate prevention** - don't show users already added as organizers

### Technical Requirements
- **Reuse existing patterns** from current guest invitation system
- **Extend EventUser model** if needed for role clarity
- **Add user search API endpoint** under `/api/search/users`
- **Integrate with existing event management interface**
- **Follow current LiveView component patterns**

## User Interface Design

### 1. Entry Point
- **Location**: Event Management page → "Organizers" section
- **Trigger**: "Add Organizer" button (similar to current "Add Guests" button)
- **Modal/Panel**: Full-screen overlay matching current guest invitation UI

### 2. Search Interface
```
┌─────────────────────────────────────────────────────┐
│  Add Organizers                                   ✕ │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Search for existing users to add as organizers    │
│                                                     │
│  ┌─────────────────────────────────────────────────┐ │
│  │ 🔍 Search by username, email, or name...       │ │
│  └─────────────────────────────────────────────────┘ │
│                                                     │
│  Search Results:                                    │
│  ┌─────────────────────────────────────────────────┐ │
│  │ 👤 @johnsmith                             [Add] │ │
│  │    John Smith • john@example.com                │ │
│  │    Photography enthusiast and event planner    │ │
│  ├─────────────────────────────────────────────────┤ │
│  │ 👤 @sarah_events                          [Add] │ │
│  │    Sarah Johnson • sarah@events.com            │ │
│  │    Professional event coordinator              │ │
│  └─────────────────────────────────────────────────┘ │
│                                                     │
│  Selected Organizers (2):                          │
│  ┌─────────────────────────────────────────────────┐ │
│  │ 👤 @johnsmith                          [Remove] │ │
│  │ 👤 @sarah_events                       [Remove] │ │
│  └─────────────────────────────────────────────────┘ │
│                                                     │
│                            [Cancel]  [Add 2 Users] │
└─────────────────────────────────────────────────────┘
```

### 3. Search Results Display
- **User avatar** (profile picture or initials)
- **Primary identifier**: @username (bold)
- **Secondary info**: Full name • email
- **Bio preview**: First 50 characters of bio
- **Add/Remove buttons** with immediate feedback
- **Empty state**: "No users found" with search tips

### 4. Confirmation State
- **Selected users counter** in bottom bar
- **Add button** shows count: "Add 2 Users"
- **Success message** after adding users
- **Update organizers list** in main event management view

## Technical Implementation

### 1. Database Schema
**Current EventUser table is sufficient:**
```sql
-- No changes needed to existing schema
-- EventUser table already supports:
-- - event_id (references events)
-- - user_id (references users)  
-- - role (currently used, may expand in future)
```

### 2. API Endpoints
**New endpoint for user search:**
```elixir
# /api/search/users
GET /api/search/users?q=search_term&event_id=123

# Response format:
{
  "users": [
    {
      "id": 456,
      "username": "johnsmith",
      "name": "John Smith",
      "email": "john@example.com",
      "bio": "Photography enthusiast and event planner",
      "profile_picture_url": "https://...",
      "already_organizer": false
    }
  ]
}
```

### 3. Context Functions
**Add to Events context:**
```elixir
# lib/eventasaurus_app/events.ex
def search_users_for_event(query, event_id, opts \\ [])
def add_user_as_organizer(event, user)
def remove_user_as_organizer(event, user)
def get_event_organizers(event)
```

### 4. LiveView Integration
**Add to EventManageLive:**
```elixir
# lib/eventasaurus_web/live/event_manage_live.ex
def handle_event("open_add_organizers", _, socket)
def handle_event("search_users", %{"query" => query}, socket)
def handle_event("add_organizer", %{"user_id" => user_id}, socket)
def handle_event("remove_selected_organizer", %{"user_id" => user_id}, socket)
def handle_event("confirm_add_organizers", _, socket)
```

### 5. Component Structure
**Create new components:**
- `AddOrganizersModal` - Main modal container
- `UserSearchInput` - Search input with debouncing
- `UserSearchResults` - Search results list
- `SelectedOrganizersList` - Selected users preview
- `UserSearchCard` - Individual user result card

## User Experience Flow

### 1. Discovery
- Organizer clicks "Add Organizers" button in event management
- Modal opens with search interface focus on search input

### 2. Search
- User types search query (debounced after 300ms)
- Results appear below search input
- Results filtered to exclude current organizers
- Empty state shown if no results

### 3. Selection
- Click "Add" button on user result
- User moves to "Selected Organizers" section
- Button changes to "Remove" for easy deselection
- Counter updates in bottom action bar

### 4. Confirmation
- Click "Add X Users" button
- Loading state during database updates
- Success message confirmation
- Modal closes and organizers list updates
- New organizers immediately have full event access

## Security Considerations

### 1. Authorization
- **Only event organizers** can add other organizers
- **Verify event ownership** before allowing user additions
- **Rate limiting** on search API to prevent abuse

### 2. Privacy
- **Respect user privacy settings** (`profile_public` field)
- **Don't expose private information** in search results
- **Audit trail** of who added which organizers

### 3. Data Protection
- **Minimal data exposure** in search results
- **No password or sensitive data** in API responses
- **Proper error handling** for non-existent users

## Performance Considerations

### 1. Search Optimization
- **Database indexes** on searchable fields (`username`, `email`, `name`)
- **Limit search results** to 20 users maximum
- **Debounced search** to reduce API calls
- **Cache frequently searched users** (future enhancement)

### 2. User Experience
- **Loading states** during search and addition
- **Optimistic updates** where possible
- **Error recovery** for failed additions
- **Responsive design** for mobile devices

## Future Enhancements

### 1. Advanced Search
- **Filter by location** or timezone
- **Search by social media handles**
- **Advanced filtering** (verified users, mutual connections)

### 2. User Roles
- **Differentiate organizer roles** (admin, editor, viewer)
- **Permission levels** for different aspects of event management
- **Role-based access control**

### 3. Invitation System
- **Send notification** to newly added organizers
- **Pending organizer invitations** requiring acceptance
- **Integration with email system**

### 4. Social Features
- **Suggest organizers** based on past collaborations
- **Mutual connections** display
- **Organizer recommendations** based on event type

## Acceptance Criteria

### ✅ Core Functionality
- [ ] Event organizers can search for existing users
- [ ] Search works by username, email, and name
- [ ] Users can be added as co-organizers
- [ ] Added users have full event management access
- [ ] Interface prevents adding duplicate organizers
- [ ] Search results exclude current organizers

### ✅ User Interface
- [ ] Modal interface matches current design system
- [ ] Search input with real-time results
- [ ] User profile previews in search results
- [ ] Selected users preview before confirmation
- [ ] Success/error feedback for all actions
- [ ] Mobile-responsive design

### ✅ Technical Requirements
- [ ] New API endpoint for user search
- [ ] Integration with existing EventUser model
- [ ] LiveView real-time updates
- [ ] Proper error handling and validation
- [ ] Security measures and authorization checks
- [ ] Performance optimization for search queries

### ✅ Edge Cases
- [ ] Handle empty search results gracefully
- [ ] Prevent adding users to events they already organize
- [ ] Handle network errors during search/addition
- [ ] Validate permissions before allowing additions
- [ ] Handle users with incomplete profiles

## Implementation Priority
**High Priority**: Core search and addition functionality
**Medium Priority**: Enhanced UX and error handling
**Low Priority**: Advanced features and social enhancements

## Testing Strategy
- **Unit tests** for search and addition functions
- **Integration tests** for API endpoints
- **E2E tests** for complete user workflow
- **Performance tests** for search response times
- **Security tests** for authorization and data protection

---

**Estimated Development Time**: 1-2 weeks
**Dependencies**: None (builds on existing system)
**Complexity**: Medium (extends existing patterns)