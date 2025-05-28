# User Assignment Refactor Specification

## Overview
Clarify and improve the dual user assignment pattern in our Phoenix LiveView application by renaming assigns and establishing clear usage rules. This refactor addresses confusion around `@current_user` vs `@local_user` without changing the underlying architecture.

## Current State Problems

1. **Naming Confusion**: `@current_user` and `@local_user` don't clearly indicate their different purposes
2. **Inconsistent Usage**: Some code checks `@current_user`, others use `@local_user`
3. **Template Complexity**: Templates need to know which user assign to use
4. **Documentation Gap**: No clear rules about when to use each assign

## Proposed Changes

### 1. Rename Assigns for Clarity

**Before:**
```elixir
@current_user  # Raw Supabase auth data or nil
@local_user    # Local database User struct or nil
```

**After:**
```elixir
@auth_user     # Raw authentication data from Supabase
@user          # Local database User struct (processed)
```

### 2. Establish Clear Usage Rules

#### `@auth_user` (formerly `@current_user`)
- **Purpose**: Raw authentication state from Supabase
- **Type**: `nil | %{"id" => string, "email" => string, "user_metadata" => map}`
- **Usage**: 
  - Authentication checks in AuthHooks
  - User creation/sync operations
  - Internal processing only
- **Never used in**: Templates, business logic

#### `@user` (formerly `@local_user`)
- **Purpose**: Processed, database-synchronized user
- **Type**: `nil | %User{}`
- **Usage**:
  - All template rendering
  - Business logic operations
  - Event registration functions
  - User display and interactions

### 3. Processing Pattern

Always use this pattern in LiveViews:
```elixir
def mount(_params, _session, socket) do
  {registration_status, user} = case ensure_user_struct(socket.assigns.auth_user) do
    {:ok, user} -> {:authenticated, user}
    {:error, _} -> {:not_authenticated, nil}
  end
  
  socket = socket
    |> assign(:user, user)
    |> assign(:registration_status, registration_status)
end
```

### 4. Template Simplification

Templates should only reference `@user`:
```heex
<%= if @user do %>
  <div class="user-info">
    <span><%= @user.name %></span>
    <span><%= @user.email %></span>
  </div>
<% end %>
```

## Files to Modify

### 1. AuthHooks (`lib/eventasaurus_web/live/auth_hooks.ex`)
- Rename `assign_current_user` to `assign_auth_user`
- Update documentation
- Keep assigning to `:auth_user` instead of `:current_user`

### 2. PublicEventLive (`lib/eventasaurus_web/live/public_event_live.ex`)
- Update mount function to use `@auth_user`
- Rename `@local_user` to `@user` throughout
- Update all event handlers
- Update template references

### 3. Other LiveViews
- `lib/eventasaurus_web/live/event_live/edit.ex`
- `lib/eventasaurus_web/live/event_live/new.ex`
- Update to use `@auth_user` for processing, `@user` for business logic

### 4. Controllers
- `lib/eventasaurus_web/controllers/auth/auth_controller.ex`
- `lib/eventasaurus_web/controllers/dashboard_controller.ex`
- `lib/eventasaurus_web/controllers/event_controller.ex`
- Update to use `:auth_user` assign name

### 5. Plugs (`lib/eventasaurus_web/plugs/auth_plug.ex`)
- Rename `fetch_current_user` to `fetch_auth_user`
- Update assign name to `:auth_user`

### 6. Router (`lib/eventasaurus_web/router.ex`)
- Update plug references

### 7. Tests
- Update test helper functions
- Update assertions to use new assign names
- Ensure test patterns follow new conventions

## Implementation Steps

### Phase 1: Core Infrastructure
1. Update AuthHooks to assign `:auth_user`
2. Update AuthPlug to assign `:auth_user`
3. Update router plug references

### Phase 2: LiveViews
1. Update PublicEventLive (main focus)
2. Update other LiveViews
3. Update templates to use `@user`

### Phase 3: Controllers
1. Update auth controllers
2. Update other controllers using user assigns

### Phase 4: Tests
1. Update test helpers
2. Update test assertions
3. Verify all tests pass

### Phase 5: Documentation
1. Add inline documentation
2. Update any README or docs
3. Add code comments explaining the pattern

## Benefits After Refactor

1. **Clear Separation**: `@auth_user` for auth, `@user` for everything else
2. **Template Simplicity**: Only `@user` in templates
3. **Consistent Processing**: Always `ensure_user_struct(@auth_user) -> @user`
4. **Better Documentation**: Clear rules and examples
5. **Easier Onboarding**: New developers understand the pattern immediately

## Backward Compatibility

This is a breaking change for:
- Any custom code referencing `@current_user` or `@local_user`
- Tests that assert on these assign names
- Any external integrations expecting these assigns

All changes will be made atomically to ensure the application continues working.

## Testing Strategy

1. **Unit Tests**: Update all test assertions
2. **Integration Tests**: Verify LiveView interactions work
3. **Authentication Flow**: Test login/logout/registration
4. **User Display**: Verify templates render correctly
5. **Edge Cases**: Anonymous users, new users, existing users

## Success Criteria

- [x] All tests pass with new assign names
- [x] Templates only reference `@user`
- [x] Clear documentation of usage patterns
- [x] No references to old assign names remain
- [x] Authentication flow works end-to-end
- [x] User registration flow works end-to-end 