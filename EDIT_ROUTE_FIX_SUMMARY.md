# Edit Route Function Clause Error Fix

## Problem Identified

The `/events/:slug/edit` route was completely broken with a `FunctionClauseError`:

```
** (FunctionClauseError) no function clause matching in EventasaurusWeb.EventLive.Edit.mount/3
```

The error occurred because:
- **Router defined**: `/events/:slug/edit` (passing `%{"slug" => "..."}`)
- **Mount function expected**: `%{"id" => id}` 
- **Function clause mismatch**: No matching clause for the actual parameters

## Root Cause Analysis

### 1. Parameter Name Mismatch
```elixir
# Router (correct)
live "/events/:slug/edit", EventLive.Edit

# Mount function (incorrect)
def mount(%{"id" => id}, _session, socket) do
  event = Events.get_event!(id)  # Looking up by ID instead of slug
```

### 2. Wrong Lookup Function
The mount function was using `Events.get_event!(id)` but needed `Events.get_event_by_slug(slug)`.

### 3. Missing Template Assigns
The template expected `@changeset` but the mount function only assigned `:form`.

## Fixes Applied

### 1. Fixed Parameter Matching
```elixir
# Before
def mount(%{"id" => id}, _session, socket) do
  event = Events.get_event!(id)

# After  
def mount(%{"slug" => slug}, _session, socket) do
  event = Events.get_event_by_slug(slug)
```

### 2. Added Null Check
```elixir
if event do
  # ... existing logic
else
  {:ok,
   socket
   |> put_flash(:error, "Event not found")
   |> redirect(to: ~p"/dashboard")
  }
end
```

### 3. Fixed Save Function
```elixir
# Before
defp save_event(socket, event_id, event_params) do
  event = Events.get_event!(event_id)
  # ... redirect to event.id

# After
defp save_event(socket, event_params) do
  event = socket.assigns.event
  # ... redirect to event.slug
```

### 4. Added Missing Template Assign
```elixir
socket =
  socket
  |> assign(:event, event)
  |> assign(:venues, venues)
  |> assign(:form, to_form(changeset))
  |> assign(:changeset, changeset)  # Added this line
  |> assign(:user, user)
  # ... rest of assigns
```

## Verification Results

### Tests
- **80 tests, 0 failures** ✅
- Added integration tests for edit route ✅
- Verified both authenticated and unauthenticated access ✅

### Application Functionality
- **Unauthenticated users**: Properly redirected to login ✅
- **Authenticated users**: Can access edit page without crashes ✅
- **Event lookup**: Works correctly with slug parameter ✅
- **Template rendering**: No missing assign errors ✅

### Route Testing
```bash
# Unauthenticated - redirects to login
curl -s http://localhost:4000/events/tnhtg2b4fz/edit
# Returns: <html><body>You are being <a href="/auth/login">redirected</a>

# No more 500 errors or function clause crashes
```

## Integration Tests Added

```elixir
describe "event edit routes" do
  test "edit route redirects unauthenticated users to login" do
    event = EventasaurusApp.EventsFixtures.event_fixture()
    
    conn = get(conn, ~p"/events/#{event.slug}/edit")
    assert redirected_to(conn) == ~p"/auth/login"
  end

  test "edit route works for authenticated users who can manage the event" do
    user = EventasaurusApp.AccountsFixtures.user_fixture()
    event = EventasaurusApp.EventsFixtures.event_fixture(%{user: user})
    
    {conn, _token} = authenticate_user(conn, user)
    
    conn = get(conn, ~p"/events/#{event.slug}/edit")
    assert html_response(conn, 200) =~ "Edit Event"
  end
end
```

## Key Lessons Learned

1. **Route Parameter Consistency**: Ensure mount function parameters match router definitions
2. **Function Signatures**: Update all related functions when changing parameter types
3. **Template Dependencies**: Verify all template assigns are provided by mount function
4. **Integration Testing**: Test actual routes, not just individual functions
5. **Error Handling**: Add proper null checks for database lookups

## Current State

The edit route is now fully functional:
- ✅ **Parameter matching**: Correctly handles slug parameter
- ✅ **Event lookup**: Uses proper slug-based lookup function  
- ✅ **Template rendering**: All required assigns provided
- ✅ **Error handling**: Graceful handling of missing events
- ✅ **Authentication**: Proper access control and redirects
- ✅ **Testing**: Comprehensive integration test coverage

The application went from completely broken edit functionality to a robust, well-tested feature with proper error handling and user experience. 