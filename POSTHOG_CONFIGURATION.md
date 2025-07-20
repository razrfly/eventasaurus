# PostHog Analytics Configuration Guide

## Overview

This document describes the PostHog analytics configuration for Eventasaurus, including autocapture settings and custom event tracking strategy.

## Current Configuration

### Frontend (app.js)

```javascript
posthog.init(posthogApiKey, {
  api_host: 'https://eu.i.posthog.com',
  
  // Privacy settings
  disable_session_recording: !privacyConsent.analytics,
  disable_cookie: !privacyConsent.cookies,
  respect_dnt: true,
  opt_out_capturing_by_default: !privacyConsent.analytics,
  
  // Performance settings
  capture_pageview: privacyConsent.analytics,
  capture_pageleave: privacyConsent.analytics,
  
  // Disable autocapture to prevent duplicate tracking
  autocapture: false,
  
  // Batch settings for performance
  batch_requests: true,
  batch_size: 10,
  batch_flush_interval_ms: 5000
});
```

### Backend (PosthogService)

- Supports both authenticated and anonymous user tracking
- Anonymous users get a temporary ID: `anonymous_<hash>`
- All events include `is_anonymous` property when tracked anonymously

## Autocapture vs. Custom Events Strategy

### Why Autocapture is Disabled

1. **Precision Control**: We track specific poll interactions with meaningful event names
2. **Data Quality**: Avoid noise from generic click events
3. **Performance**: Reduce unnecessary event volume
4. **Privacy**: Better control over what data is collected

### Custom Events We Track

Instead of autocapture, we track these specific events:

#### Page Navigation
- `$pageview` - Automatic page view tracking (enabled)
- `$pageleave` - Automatic page leave tracking (enabled)

#### Poll Engagement
- `poll_created` - When a new poll is created
- `poll_viewed` - When a poll is displayed to a user
- `poll_vote` - When a user casts a vote
- `poll_suggestion_created` - When a user suggests an option
- `poll_suggestion_approved` - When a suggestion is approved
- `poll_results_viewed` - When results are viewed
- `poll_phase_changed` - When poll phase transitions
- `poll_votes_cleared` - When user clears their votes
- `poll_deleted` - When a poll is deleted
- `poll_guest_invited` - When a guest is invited

#### Guest Management (Already Implemented)
- `guest_invitation_modal_opened` - Modal opened
- `historical_participant_selected` - Historical guest selected
- `guest_added_directly` - Guest added directly

## Event Property Standards

### Common Properties
- `timestamp` - ISO 8601 timestamp
- `event_id` - Associated event ID
- `poll_id` - Poll identifier (when applicable)
- `is_anonymous` - Boolean flag for anonymous actions

### User Identification
- Authenticated users: Tracked with their user ID
- Anonymous users: Tracked with temporary anonymous ID
- PostHog automatically links anonymous → authenticated sessions

## Privacy Compliance

### Consent-Based Tracking
- Analytics only enabled when `privacyConsent.analytics` is true
- Cookies only used when `privacyConsent.cookies` is true
- Text masking enabled when analytics consent is not given
- DNT (Do Not Track) header is respected

### Data Minimization
- No autocapture of all interactions
- Only track necessary events for product analytics
- No session recording by default
- No personal data in event properties

## Testing Analytics

### Verify Event Tracking
1. Open browser DevTools → Network tab
2. Filter by "posthog" or "eu.i.posthog.com"
3. Look for `/capture/` or `/batch/` requests
4. Check request payload for correct event data

### Debug Mode
Add to browser console:
```javascript
posthog.debug()
```

### Check Current Configuration
```javascript
console.log(posthog.config)
```

## Best Practices

1. **Event Naming**: Use snake_case for consistency
2. **Property Names**: Use descriptive, consistent property names
3. **User Privacy**: Never include PII in event properties
4. **Event Volume**: Batch similar events when possible
5. **Testing**: Always test new events in development first

## Troubleshooting

### Events Not Appearing
1. Check if PostHog is initialized: `window.posthog !== undefined`
2. Verify API key is set: Check `.env` file
3. Check privacy consent: `window.privacyConsent.analytics === true`
4. Look for errors in console or network tab

### Duplicate Events
1. Ensure autocapture is disabled
2. Check for multiple event triggers in code
3. Verify component lifecycle (especially with LiveView)

### Anonymous User Tracking
1. Anonymous users get consistent session IDs from PostHog
2. Backend generates `anonymous_<hash>` for server-side events
3. Sessions link automatically when user authenticates