# Social Cards Development Guide

## Testing Social Cards with External Services

Social media platforms (Facebook, Twitter, LinkedIn) cannot access `localhost` URLs to fetch Open Graph images. To test social card generation during development, you need to expose your local server to the internet.

### Using ngrok (Recommended)

1. **Install ngrok** (if not already installed):
   ```bash
   brew install ngrok
   # or download from https://ngrok.com/download
   ```

2. **Start your Phoenix server**:
   ```bash
   mix phx.server
   ```

3. **In a separate terminal, start ngrok**:
   ```bash
   ngrok http 4000
   ```

4. **Set the BASE_URL environment variable** with your ngrok URL:
   ```bash
   export BASE_URL="https://your-subdomain.ngrok.io"
   ```

5. **Restart your Phoenix server** with the new BASE_URL:
   ```bash
   BASE_URL="https://your-subdomain.ngrok.io" mix phx.server
   ```

### Testing Social Cards

Once ngrok is running and BASE_URL is set:

1. **Visit your event page** using the ngrok URL:
   ```
   https://your-subdomain.ngrok.io/your-event-slug
   ```

2. **Verify the og:image meta tag** uses the external domain:
   ```html
   <meta property="og:image" content="https://your-subdomain.ngrok.io/your-event-slug/social-card-abc123.png">
   ```

3. **Test with social media debuggers**:
   - Facebook: https://developers.facebook.com/tools/debug/
   - Twitter: https://cards-dev.twitter.com/validator
   - LinkedIn: https://www.linkedin.com/post-inspector/

### Troubleshooting

#### Social card URLs return 404
- Check that `HashGenerator.generate_url_path` returns URLs without `/events/` prefix
- Verify router has pattern: `get "/:slug/social-card-:hash/*rest"`
- See Phase 1 fixes in GitHub issue #1781

#### Social card meta tags use localhost

**Root Cause:** LiveView not capturing and passing `request_uri` to `SEOHelpers.assign_meta_tags/2`

**Fix:**

Step 1: Capture `request_uri` in LiveView's `mount/3`:
```elixir
def mount(_params, _session, socket) do
  # Capture request URI for correct URL generation (ngrok support)
  raw_uri = get_connect_info(socket, :uri)
  request_uri =
    cond do
      match?(%URI{}, raw_uri) -> raw_uri
      is_binary(raw_uri) -> URI.parse(raw_uri)
      true -> nil
    end

  # ... rest of mount logic
end
```

Step 2: Pass `request_uri` to `SEOHelpers.assign_meta_tags/2`:
```elixir
socket
|> SEOHelpers.assign_meta_tags(
  title: title,
  description: description,
  image: social_card_url,
  type: "website",
  canonical_path: "/path",
  json_ld: json_ld,
  request_uri: request_uri  # CRITICAL: Must pass this
)
```

**Why this works:**
- Without `request_uri`: URLs fall back to endpoint config (returns localhost in dev)
- With `request_uri`: URLs use actual request host (ngrok URL, production domain)

**Reference:** See `lib/eventasaurus_web/live/public_event_show_live.ex:27-34` for the canonical implementation

**Alternative (Legacy):** Setting BASE_URL environment variable (not recommended)
- Ensure `BASE_URL` environment variable is set
- Restart Phoenix server after setting BASE_URL
- Verify `UrlHelper.get_base_url()` returns external domain

#### Images not loading in social card
- Check `EventasaurusWeb.SocialCardView` image processing logic
- Verify external images can be downloaded by the server
- Check server logs for image optimization errors

## Architecture

### URL Generation Flow

```
Event Page Request
    ↓
public_event_live.ex:social_card_url/2
    ↓
UrlHelper.get_base_url()  ← Returns external domain
    ↓
HashGenerator.generate_url_path(event)  ← Returns path without /events/
    ↓
UrlHelper.build_url(path)  ← Combines to full URL
    ↓
Meta tag rendered with external URL
```

### Configuration Priority

`UrlHelper.get_base_url()` checks in this order:

1. `BASE_URL` environment variable (for development overrides)
2. `Application.get_env(:eventasaurus, :base_url)` (from config files)
3. `EventasaurusWeb.Endpoint.url()` (fallback, returns localhost in dev)

### Files Modified in Phase 2

- **Created**: `lib/eventasaurus_web/url_helper.ex` - Centralized external URL generation
- **Updated**: `lib/eventasaurus_web/live/public_event_live.ex:2089-2093` - Use UrlHelper
- **Updated**: `lib/eventasaurus_web/poll_helpers.ex:261-294` - Use UrlHelper for polls

## Related Issues

- #1781 - Social card remediation plan (4 phases)
- #1778 - Original social card issues
- #1780 - Previous refactoring attempts

## Next Steps (Phase 3)

Phase 3 will unify the architecture across event and poll social cards:
- Create `SocialCards.UrlBuilder` module
- Consolidate HashGenerator and PollHashGenerator logic
- Create unified test suite for all social card types
