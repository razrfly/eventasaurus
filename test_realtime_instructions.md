# Test Real-Time Updates

## Server is starting with debug logging

### How to Test:
1. Open a poll in 2 browser tabs (normal + private/incognito)
2. Vote in one tab
3. Watch the server logs for these messages:
   - "DEBUG: Casting vote for poll X"
   - "DEBUG: Vote created successfully"
   - "DEBUG: Getting poll voting stats"
   - "DEBUG: Broadcasted poll stats update"
   - "DEBUG: VotingInterfaceComponent received poll_stats_updated"

### What to Look For:
- Are votes being saved? (look for "Vote created successfully")
- Are broadcasts being sent? (look for "Broadcasted poll stats update")
- Are components receiving updates? (look for "received poll_stats_updated")

### If Nothing in Logs:
- The voting event might not be reaching the server
- Check browser console for JavaScript errors
- Ensure you're logged in or using anonymous voting correctly

### Server Command:
```bash
mix phx.server
```

Watch the terminal output when you vote!