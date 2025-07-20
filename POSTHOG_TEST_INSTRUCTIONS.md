# PostHog Analytics Testing Instructions

## How to Test PostHog Integration

### 1. Run the Test Module in IEx Console

Open a new terminal in the project directory and run:

```bash
iex -S mix
```

Then in the IEx console, run:

```elixir
Eventasaurus.TestPosthog.run_tests()
```

This will:
- Send a test event to PostHog
- Test guest invitation tracking
- Test analytics querying

### 2. Manual Browser Testing

1. Open http://localhost:4000 in your browser
2. Open the browser's Developer Console (F12)
3. Check for PostHog initialization messages
4. Look for any errors related to PostHog

### 3. Verify in PostHog Dashboard

1. Go to https://eu.i.posthog.com
2. Log in with your PostHog account
3. Navigate to the "Events" section
4. Look for recent events:
   - `test_analytics_event` - from the test module
   - `$pageview` - from browser visits
   - `guest_invitation_modal_opened` - from the test module

### 4. Check Network Activity

In the browser Developer Tools:
1. Go to the Network tab
2. Filter by "posthog" or "eu.i.posthog.com"
3. You should see requests to:
   - `/decide/` - for feature flags and settings
   - `/capture/` or `/batch/` - for event tracking

### Expected Results

✅ **Success indicators:**
- PostHog loads without errors in browser console
- Events appear in PostHog dashboard within 1-2 minutes
- Network requests to eu.i.posthog.com return 200 status

❌ **Common issues:**
- No PostHog API key set - check .env file
- CORS errors - verify PostHog host configuration
- Events not appearing - check project ID and API keys

### Environment Variables

Ensure these are set in your `.env` file:
```
POSTHOG_PUBLIC_API_KEY=phc_...
POSTHOG_PRIVATE_API_KEY=phx_...
POSTHOG_PROJECT_ID=50216
```