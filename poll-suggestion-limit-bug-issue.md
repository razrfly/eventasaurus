# Bug: Poll Suggestion Limits Not Enforced for Participants

## Summary
The poll suggestion limit feature (`max_options_per_user`) is not working correctly. The limit is only enforced in the UI (showing/hiding buttons) but not when actually saving suggestions. This allows participants to bypass the limit if they manipulate the frontend or if there's any UI state issue.

Additionally, there appears to be a logic issue where administrators/creators might be incorrectly limited in some UI scenarios while participants are not properly restricted.

## Current Behavior
1. When a poll has `max_options_per_user` set (e.g., 3), the UI correctly shows "3/3 suggestions used" for participants
2. The "Add Option" button is hidden when participants reach their limit
3. However, the backend `save_option` function doesn't validate the limit, so submissions can still go through
4. Administrators might see incorrect limit enforcement in the UI

## Expected Behavior
1. Participants should be limited to exactly `max_options_per_user` suggestions
2. The backend should validate and reject suggestions that exceed the limit
3. Administrators/creators should have unlimited suggestions (current behavior is correct)
4. Both frontend and backend should enforce the same rules

## Root Cause Analysis

### Location: `/lib/eventasaurus_web/live/components/option_suggestion_component.ex`

1. **UI Logic (lines 129-136)**: Correctly calculates limits
   ```elixir
   {max_options, can_suggest_more} =
     if assigns.is_creator do
       {nil, suggestions_allowed_by_phase}
     else
       max_opts = assigns.poll.max_options_per_user || 3
       {max_opts, suggestions_allowed_by_phase && user_suggestion_count < max_opts}
     end
   ```

2. **Backend Save (lines 1967-2048)**: The `save_option` function has NO limit validation
   ```elixir
   defp save_option(socket, option_params) do
     # ... data preparation ...
     Events.create_poll_option(final_option_params, [poll_type: socket.assigns.poll.poll_type])
   end
   ```

3. **Event Handler (line 1365)**: `handle_event("submit_suggestion", ...)` doesn't check limits before calling `save_option`

## Proposed Solutions

### Solution 1: Add Backend Validation (Recommended)
Add limit validation in the `save_option` function before calling `Events.create_poll_option`:

```elixir
defp save_option(socket, option_params) do
  # Check suggestion limit for non-creators
  if !socket.assigns.is_creator && socket.assigns.poll.max_options_per_user do
    user_suggestion_count = calculate_user_suggestion_count(socket)
    if user_suggestion_count >= socket.assigns.poll.max_options_per_user do
      {:error, %{suggestion_limit: "You have reached your suggestion limit"}}
    else
      # ... existing save logic ...
    end
  else
    # ... existing save logic for creators or polls without limits ...
  end
end
```

### Solution 2: Add Validation in Event Handler
Alternatively, add the check in `handle_event("submit_suggestion", ...)` before processing:

```elixir
def handle_event("submit_suggestion", params, socket) do
  if can_user_suggest_more?(socket) do
    # ... existing logic ...
  else
    {:noreply, put_flash(socket, :error, "You have reached your suggestion limit")}
  end
end
```

### Solution 3: Database-Level Constraint
Add a custom validation in the Poll context or database trigger to enforce limits, ensuring data integrity even if frontend validation is bypassed.

## Testing Scenarios
1. Create a poll with `max_options_per_user` = 3
2. As a participant, add 3 suggestions (should work)
3. Try to add a 4th suggestion (should be blocked)
4. As an administrator, verify unlimited suggestions work
5. Test edge cases: 
   - Switching between phases
   - Multiple participants reaching limits
   - Editing existing suggestions

## Priority
High - This is a security/integrity issue where users can bypass intended restrictions

## Implementation Notes
- Ensure the fix maintains backward compatibility
- Consider adding logging when limits are exceeded
- Update any relevant tests to cover this scenario
- The UI already has the correct logic; focus on backend enforcement