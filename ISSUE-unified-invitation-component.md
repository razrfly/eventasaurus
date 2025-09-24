# Issue: Unify Public Event Invitation UX with Existing Private Event Interface

## Problem Statement

**After audit:** The solution we need ALREADY EXISTS in the private event guest management system!

**Current Inconsistency:**
- **Public Event "Plan with Friends" Modal**: Uses two separate, confusing components:
  1. `UserSelectorComponent` - Searches for existing Eventasaurus users
  2. `EmailInputComponent` - Adds new email addresses for invitation

- **Private Event Guest Management**: Uses unified, elegant interface:
  1. `HistoricalParticipantsComponent` - Past event participants (works great!)
  2. `IndividualEmailInput` - Smart unified email input that handles both existing users AND new emails seamlessly

**The Real Problem**: UX inconsistency between public and private event invitation flows. Users get a confusing dual-component interface for public events but a clean unified interface for private events.

## Current Architecture Analysis

### Public Event Components (PROBLEMATIC)
- `UserSelectorComponent` (`lib/eventasaurus_web/components/invitations/user_selector_component.ex`)
  - Provides autocomplete search for existing users
  - Shows user avatars, names, and email addresses
  - Sends `{:user_selected, user}` message to parent

- `EmailInputComponent` (`lib/eventasaurus_web/components/invitations/email_input_component.ex`)
  - Accepts raw email addresses (single or comma-separated)
  - Validates email format
  - Sends `{:email_added, email}` messages to parent

### Private Event Components (SOLUTION ALREADY EXISTS!)
- `HistoricalParticipantsComponent` - Past event participants (keep as-is, works perfectly)
- `IndividualEmailInput` (`lib/eventasaurus_web/components/individual_email_input.ex`)
  - ✅ Smart unified email input that handles both existing users AND new emails
  - ✅ Real-time email validation with visual feedback
  - ✅ Email chips/tags with individual removal
  - ✅ Bulk paste support for comma-separated emails
  - ✅ Clean, modern interface similar to Luma/Linear

### Usage Comparison
- **Public Modal (`PublicPlanWithFriendsModal`)**: Uses TWO separate components, creating cognitive overhead
- **Private Modal (`GuestInvitationModal`)**: Uses ONE unified component, clean UX

## Proposed Solution: Apply Existing Private Event UX to Public Events

**Simple Solution:** Replace the two separate components in `PublicPlanWithFriendsModal` with the existing `IndividualEmailInput` component that already works perfectly in the private event system.

### Proposed Changes

#### 1. Keep Historical Participants (No Changes)
- `HistoricalParticipantsComponent` stays exactly as-is
- This part works perfectly and users love it

#### 2. Replace Dual Components with Single Unified Input
- **Remove**: `UserSelectorComponent` (search for users)
- **Remove**: `EmailInputComponent` (manual email entry)
- **Add**: `IndividualEmailInput` (the component that already works great in private events)

#### 3. Technical Implementation
```elixir
# In PublicPlanWithFriendsModal, replace this:

<!-- User Search -->
<.live_component
  module={UserSelectorComponent}
  id={@id <> "_user_selector"}
  selected_users={@selected_users}
/>

<!-- Email Input -->
<.live_component
  module={EmailInputComponent}
  id={@id <> "_email_input"}
  selected_emails={@selected_emails}
/>

# With this:
<.individual_email_input
  id="unified-email-input"
  emails={@selected_emails}
  current_input={@current_email_input}
  bulk_input={@bulk_email_input}
  on_add_email="add_email"
  on_remove_email="remove_email"
  on_input_change="email_input_change"
  placeholder="Enter email address or search for users"
/>
```

### How It Works (Like Private Events)
1. **Historical participants section** - unchanged, works great
2. **Single email input field** - type anything (email or name)
3. **Smart handling** - automatically determines if it's an existing user or new email
4. **Visual chips** - shows selected people as removable chips
5. **Bulk support** - paste multiple emails separated by commas

### Benefits of This Approach
- **No new component needed** - reuse existing, proven component
- **Consistent UX** - same interface across public and private events
- **Reduced complexity** - eliminate duplicate logic and maintenance
- **User familiarity** - users who use both features get consistent experience

### Visual Design Mockup

```
┌─────────────────────────────────────────────────────────────┐
│ Add friends and contacts                                    │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ john@example.com, sarah.smith                          │ │
│ └─────────────────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ 👤 Sarah Smith (sarah@company.com)          [existing] │ │
│ │ ✉️  Invite john@example.com                 [new]      │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Benefits

#### User Experience
- **Simplified Mental Model** - Users don't need to understand the distinction between existing users and new invites
- **Familiar Pattern** - Follows Gmail, Slack, and other modern collaboration tools
- **Reduced Cognitive Load** - Single input interface vs. multiple sections
- **Better Accessibility** - Single focus target with proper keyboard navigation

#### Developer Experience
- **Code Consolidation** - Combine similar functionality into one component
- **Maintainability** - Single component to maintain vs. two separate ones
- **Consistency** - Unified behavior and styling
- **Reusability** - Can be used in other invitation contexts

#### Technical
- **Reduced Bundle Size** - Eliminate duplicate logic
- **Better Performance** - Single search query vs. separate systems
- **Improved Testing** - Test one component vs. integration of two

### Migration Strategy

#### Phase 1: Create UnifiedInvitationComponent
1. Build new component with combined functionality
2. Implement comprehensive tests
3. Ensure API compatibility with existing parent components

#### Phase 2: Update PublicPlanWithFriendsModal
1. Replace UserSelectorComponent and EmailInputComponent with UnifiedInvitationComponent
2. Update any modal-specific logic
3. Test complete invitation flow

#### Phase 3: Update Other Usage Locations
1. Identify other places where invitation components are used
2. Migrate them to use the unified component
3. Consider deprecating old components

#### Phase 4: Cleanup
1. Remove deprecated components once migration is complete
2. Update documentation
3. Clean up any unused imports or references

### Acceptance Criteria

#### Functional Requirements
- [ ] Single input field accepts both usernames/emails and raw email addresses
- [ ] Real-time search shows existing users with avatars and names
- [ ] Email validation shows "Add as invite" option for valid emails
- [ ] Support comma-separated bulk input
- [ ] Maintains existing parent component API (`user_selected` and `email_added` messages)
- [ ] Proper error handling and validation feedback
- [ ] Loading states during search

#### User Experience Requirements
- [ ] Dropdown shows clear distinction between existing users and new invites
- [ ] Keyboard navigation works properly (arrow keys, enter, tab)
- [ ] Mobile-responsive design
- [ ] Accessibility compliance (ARIA labels, screen reader support)
- [ ] Visual feedback for selected items

#### Technical Requirements
- [ ] No performance regression compared to existing components
- [ ] Comprehensive test coverage
- [ ] Proper error boundaries and fallback UI
- [ ] LiveView component best practices followed

### Testing Strategy

#### Unit Tests
- Input validation logic
- Search functionality
- Email parsing and validation
- Event handling

#### Integration Tests
- Parent-child component communication
- LiveView integration
- Form submission flows

#### E2E Tests
- Complete invitation flow from modal
- Bulk email input scenarios
- User search and selection
- Mixed user/email invitation flows

### Implementation Estimate

**Complexity:** Simple (reusing existing component)
**Estimated Effort:** 4-6 hours
- 2 hours: Replace components in PublicPlanWithFriendsModal
- 2 hours: Update event handlers and LiveView logic
- 1-2 hours: Testing and refinement

**Previous Estimate Was Wrong:** We don't need to build anything new - just swap out components!

### Related Issues/Dependencies
- Current nested form issue causing page reload (fixed)
- HistoricalParticipantsComponent remains separate
- Avatar generation service integration

---

## Summary

**The solution already exists!** We just need to apply the same unified invitation UX that works great in private events to the public event modal. This eliminates UX inconsistency across the platform while reducing code complexity.

**Key Insight:** Instead of building new components, we should consolidate around the existing `IndividualEmailInput` component that users already love in private events.