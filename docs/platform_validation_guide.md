# Platform Validation Guide

**Purpose:** Validate social cards across major platforms (Facebook, Twitter, LinkedIn, WhatsApp, Slack, Discord)

**Last Updated:** 2025-01-29

---

## Quick Start

```bash
# 1. Start development server
mix phx.server

# 2. Use ngrok to expose local server (if testing locally)
ngrok http 4000

# 3. Get a social card URL
# Event: https://your-domain.com/event-slug/social-card-abc12345.png
# Poll: https://your-domain.com/event-slug/polls/1/social-card-def67890.png
# City: https://your-domain.com/social-cards/city/warsaw/ghi11111.png

# 4. Test on platforms using validators below
```

---

## Platform Validators

### 1. Facebook Sharing Debugger

**URL:** https://developers.facebook.com/tools/debug/

**What It Tests:**
- Open Graph meta tags (`og:title`, `og:description`, `og:image`)
- Image dimensions (recommended: 1200x630px)
- Image format (PNG, JPG, GIF, WebP)
- Image accessibility (URL must be publicly accessible)

**Testing Steps:**
1. Navigate to Facebook Sharing Debugger
2. Enter your page URL (e.g., `https://wombie.com/summer-fest`)
3. Click "Debug"
4. Verify:
   - ✅ Title appears correctly
   - ✅ Description appears correctly
   - ✅ Social card image loads (1200x630px)
   - ✅ No errors or warnings
5. Click "Scrape Again" to refresh cache

**Common Issues:**
- **Image not loading:** Check image URL is absolute and publicly accessible
- **Old image showing:** Click "Scrape Again" to clear Facebook's cache
- **Wrong dimensions warning:** Verify image is 1200x630px
- **Missing tags:** Ensure `og:image`, `og:title`, `og:description` are present

**Expected Output:**
```
Preview:
  [Social Card Image: 1200x630]
  Summer Music Festival
  Join us for an amazing night of music in Warsaw...

Properties:
  og:title: Summer Music Festival
  og:description: Join us for an amazing night of...
  og:image: https://wombie.com/summer-fest/social-card-abc12345.png
  og:type: event
  og:url: https://wombie.com/summer-fest
```

---

### 2. Twitter Card Validator

**URL:** https://cards-dev.twitter.com/validator

**What It Tests:**
- Twitter Card meta tags (`twitter:card`, `twitter:title`, `twitter:image`)
- Image dimensions (recommended: 1200x675px for summary_large_image)
- Image size (max 5MB for mobile, 20MB for web)
- Card type (summary, summary_large_image)

**Testing Steps:**
1. Navigate to Twitter Card Validator
2. Enter your page URL
3. Click "Preview card"
4. Verify:
   - ✅ Card type is "summary_large_image"
   - ✅ Image renders correctly
   - ✅ Title and description appear
   - ✅ No errors

**Common Issues:**
- **Card not showing:** Ensure `twitter:card` is set to "summary_large_image"
- **Image cut off:** Verify image is 1200x675px (or 1200x630 works too)
- **Missing attribution:** Add `twitter:site` for site attribution

**Expected Output:**
```
Card Preview:
  [Social Card Image]
  Summer Music Festival
  Join us for an amazing night of music in Warsaw...

Card Type: summary_large_image
Image: https://wombie.com/summer-fest/social-card-abc12345.png
Title: Summer Music Festival
Description: Join us for an amazing night of...
```

---

### 3. LinkedIn Post Inspector

**URL:** https://www.linkedin.com/post-inspector/

**What It Tests:**
- Open Graph meta tags (LinkedIn uses OG protocol)
- Image dimensions (recommended: 1200x627px)
- Image quality and loading speed

**Testing Steps:**
1. Navigate to LinkedIn Post Inspector
2. Enter your page URL
3. Click "Inspect"
4. Verify:
   - ✅ Preview shows correct image
   - ✅ Title and description appear
   - ✅ No errors or warnings
5. Click "Refresh" to clear LinkedIn's cache

**Common Issues:**
- **Image not displaying:** Ensure URL is HTTPS and publicly accessible
- **Cached old image:** Click "Refresh" to clear cache
- **Blurry image:** Verify image is at least 1200x627px

**Expected Output:**
```
Post Preview:
  [Social Card Image: 1200x627]
  Summer Music Festival
  Join us for an amazing night of music in Warsaw...

Status: Success
Image URL: https://wombie.com/summer-fest/social-card-abc12345.png
```

---

### 4. Google Rich Results Test

**URL:** https://search.google.com/test/rich-results

**What It Tests:**
- Structured data (JSON-LD)
- Event schema compliance
- Meta tags for search results
- Mobile-friendliness

**Testing Steps:**
1. Navigate to Google Rich Results Test
2. Enter your page URL
3. Wait for analysis
4. Verify:
   - ✅ Event schema detected and valid
   - ✅ No errors in structured data
   - ✅ All required fields present
   - ✅ Preview looks correct

**Expected Output:**
```
Rich Results:
  ✅ Event (Valid)

Detected Items:
  - Event
    - name: "Summer Music Festival"
    - startDate: "2025-08-15T20:00:00+02:00"
    - location: "Warsaw, Poland"
    - image: [social card URL]
    - description: "Join us for..."
```

---

### 5. WhatsApp Link Preview

**Testing Method:** Share link in WhatsApp

**What It Tests:**
- Open Graph meta tags
- Image loading and display
- Title and description rendering

**Testing Steps:**
1. Share your page URL in a WhatsApp chat (to yourself or test contact)
2. Wait for preview to generate
3. Verify:
   - ✅ Image loads correctly
   - ✅ Title appears
   - ✅ Description appears (first ~50 characters)

**Common Issues:**
- **No preview:** WhatsApp may not support your domain (use production URL)
- **Image not loading:** Check image is HTTPS and < 300KB for best performance
- **Slow loading:** Optimize image size (target < 200KB)

---

### 6. Slack Link Unfurling

**Testing Method:** Share link in Slack channel

**What It Tests:**
- Open Graph meta tags
- Image rendering
- Title and description formatting

**Testing Steps:**
1. Paste your page URL in a Slack channel
2. Wait for unfurl preview
3. Verify:
   - ✅ Image displays correctly
   - ✅ Title and description appear
   - ✅ Link is formatted properly

**Common Issues:**
- **Preview not appearing:** URL must be HTTPS
- **Old preview cached:** Use `/unfurl clear` command in Slack
- **Image too large:** Slack prefers images < 1MB

---

### 7. Discord Link Embed

**Testing Method:** Share link in Discord server

**What It Tests:**
- Open Graph meta tags
- Embed rendering
- Image and text display

**Testing Steps:**
1. Paste your page URL in a Discord channel
2. Wait for embed to generate
3. Verify:
   - ✅ Embed box appears with image
   - ✅ Title is bold and prominent
   - ✅ Description appears below title
   - ✅ Image renders correctly

**Common Issues:**
- **Embed not showing:** Ensure `og:image` is present and valid
- **Image stretched:** Discord prefers 1200x630px images
- **Cached old version:** Discord caches aggressively (wait 24h or contact support)

---

## Platform Comparison Matrix

| Platform | Image Size | Max File Size | Cache TTL | Refresh Method |
|----------|-----------|---------------|-----------|----------------|
| Facebook | 1200x630px | 8MB | 7 days | Sharing Debugger |
| Twitter | 1200x675px | 5MB (mobile) | 7 days | Card Validator |
| LinkedIn | 1200x627px | No limit | 7 days | Post Inspector |
| Google | 1200x630px | No limit | Variable | Search Console |
| WhatsApp | 1200x630px | 300KB* | 30 days | Cannot refresh |
| Slack | 1200x630px | 1MB* | 24 hours | `/unfurl clear` |
| Discord | 1200x630px | 8MB | 24 hours | Contact support |

*Recommended for best performance, not hard limit

---

## Complete Testing Checklist

Use this checklist when deploying new social card features:

### Pre-Deployment Checks

- [ ] Social card URLs generate correctly for all entity types
- [ ] Hash-based cache busting works (hash changes when content changes)
- [ ] Images are exactly 1200x630px
- [ ] PNG format with proper compression
- [ ] All meta tags present (`og:*`, `twitter:*`)
- [ ] JSON-LD structured data valid
- [ ] Canonical URLs are absolute and correct

### Platform Validation Checks

#### Facebook
- [ ] Tested with Sharing Debugger
- [ ] Image loads and displays correctly
- [ ] Title and description accurate
- [ ] No errors or warnings
- [ ] Scraped successfully (no caching issues)

#### Twitter
- [ ] Tested with Card Validator
- [ ] Card type is "summary_large_image"
- [ ] Image renders properly
- [ ] Title and description accurate
- [ ] No errors or warnings

#### LinkedIn
- [ ] Tested with Post Inspector
- [ ] Preview shows correct image
- [ ] Title and description accurate
- [ ] No errors or warnings
- [ ] Refreshed successfully

#### Google
- [ ] Tested with Rich Results Test
- [ ] Event schema detected and valid
- [ ] All structured data valid
- [ ] Mobile-friendly
- [ ] No schema errors

#### Messaging Apps
- [ ] WhatsApp preview works
- [ ] Slack unfurling works
- [ ] Discord embed works

### Performance Checks

- [ ] Social card generation < 500ms (first request)
- [ ] Cached responses < 50ms (subsequent requests)
- [ ] Image file size < 200KB (optimal)
- [ ] No 500 errors in logs
- [ ] Hash mismatch redirects work (301 to correct URL)

### SEO Checks

- [ ] Page title is descriptive and unique
- [ ] Meta description is 150-160 characters
- [ ] Canonical URL is correct
- [ ] JSON-LD schema includes all required fields
- [ ] Open Graph tags match page content

---

## Automated Testing Script

Run the validation script to test all social card endpoints:

```bash
# Using development server
APP_URL=http://localhost:4000 elixir test/validation/social_card_validator.exs

# Using production server
APP_URL=https://wombie.com elixir test/validation/social_card_validator.exs

# Using ngrok tunnel
APP_URL=https://abc123.ngrok.io elixir test/validation/social_card_validator.exs
```

**Expected Output:**
```
🔍 Social Card Validation Test Suite
============================================================

📅 Testing Event Social Card...
  🌐 Testing: /summer-fest/social-card-abc12345.png
  ✅ Content-Type: image/png
  ✅ Cache-Control: public, max-age=31536000
  ✅ ETag: "abc12345"
  ✅ Valid PNG signature (45678 bytes)
  ✅ All checks passed

📊 Testing Poll Social Card...
  🌐 Testing: /summer-fest/polls/1/social-card-def67890.png
  ✅ All checks passed

🏙️  Testing City Social Card...
  🌐 Testing: /social-cards/city/warsaw/ghi11111.png
  ✅ All checks passed

🔄 Testing Hash Mismatch Redirect...
  ✅ Correctly redirected (301)
  📍 Location: /summer-fest/social-card-abc12345.png

⚡ Performance Benchmarks...
  ⏱️  First request: 342.5ms
  ⏱️  Second request: 12.3ms
  ✅ Performance within target (<500ms)

============================================================
📊 Test Summary

  ✅ Passed: 5/5
  ⚠️  Warnings: 0/5
  ❌ Failed: 0/5

🎉 All tests passed!
```

---

## Troubleshooting Common Issues

### Issue: Social card not updating on platforms

**Symptoms:**
- Old image still showing after content change
- Platform shows cached version

**Solution:**
1. Verify hash has changed: `/event-slug/social-card-[NEW_HASH].png`
2. Use platform refresh tools:
   - Facebook: Sharing Debugger → "Scrape Again"
   - Twitter: No manual refresh (wait 7 days or contact support)
   - LinkedIn: Post Inspector → "Refresh"
3. Check meta tags include new hash URL
4. Clear CDN cache if using one

### Issue: Image not loading on any platform

**Symptoms:**
- Broken image icon
- "Could not load image" error

**Solution:**
1. Verify URL is absolute: `https://domain.com/path`, not `/path`
2. Check HTTPS is enabled (required by most platforms)
3. Test URL directly in browser
4. Verify image file size < 8MB
5. Check server logs for 500 errors during generation
6. Ensure `rsvg-convert` is installed: `rsvg-convert --version`

### Issue: Image dimensions incorrect

**Symptoms:**
- Image appears stretched or cropped
- Platform shows dimension warning

**Solution:**
1. Verify SVG template canvas: `width="1200" height="630"`
2. Check PNG conversion maintains dimensions
3. Test generated PNG: `file social-card.png` should show 1200x630
4. Review SVG template for aspect ratio issues

### Issue: Slow social card generation

**Symptoms:**
- First request > 1 second
- Timeout errors

**Solution:**
1. Check `rsvg-convert` performance: `time rsvg-convert input.svg -o output.png`
2. Simplify SVG template (reduce complexity)
3. Optimize image assets (compress embedded images)
4. Consider pre-warming cache for important pages
5. Monitor server resources (CPU, memory)

### Issue: Hash mismatch redirects not working

**Symptoms:**
- 404 error on old hash
- No redirect to new hash

**Solution:**
1. Verify `SocialCardHelpers.send_hash_mismatch_redirect/6` is called
2. Check hash validation logic in controller
3. Test redirect: `curl -I /event-slug/social-card-wrong123.png`
4. Verify expected hash generation matches
5. Check router has catch-all route for social cards

---

## Performance Targets

### Response Times
- **First Request (Generation):** < 500ms (target), < 1000ms (acceptable)
- **Cached Requests:** < 50ms (target), < 100ms (acceptable)
- **Hash Validation:** < 10ms

### File Sizes
- **Optimal:** < 200KB (best for all platforms)
- **Acceptable:** < 500KB (good for most platforms)
- **Maximum:** < 8MB (platform limits)

### Cache Hit Rates
- **Target:** > 95% cache hits after first request
- **Method:** CDN caching + browser caching (max-age=31536000)

### Error Rates
- **Target:** < 0.1% error rate
- **Monitor:** 500 errors, timeout errors, generation failures

---

## Integration Testing

### Manual Integration Test

1. **Create Test Event:**
   ```bash
   # Create event in development
   mix run priv/repo/seeds.exs
   ```

2. **Generate Social Card:**
   ```bash
   # Visit event page
   open http://localhost:4000/test-event

   # Get social card URL from page source
   curl -I http://localhost:4000/test-event/social-card-abc12345.png
   ```

3. **Test on Platforms:**
   - Use ngrok: `ngrok http 4000`
   - Test on Facebook Sharing Debugger
   - Test on Twitter Card Validator
   - Test on LinkedIn Post Inspector

4. **Update Event Content:**
   ```bash
   # Update event title/description
   # Verify new hash is generated
   # Old URL should 301 redirect to new hash
   ```

5. **Verify Cache Behavior:**
   ```bash
   # First request (generation)
   time curl http://localhost:4000/test-event/social-card-abc12345.png > /dev/null

   # Second request (cached)
   time curl http://localhost:4000/test-event/social-card-abc12345.png > /dev/null
   ```

### Automated Integration Test

Add to `test/eventasaurus_web/controllers/event_social_card_controller_test.exs`:

```elixir
describe "platform validation" do
  test "social card meets platform requirements", %{conn: conn} do
    event = insert(:event, title: "Test Event")
    hash = HashGenerator.generate_hash(event, :event)

    conn = get(conn, "/#{event.slug}/social-card-#{hash}.png")

    # Verify response
    assert response(conn, 200)
    assert get_resp_header(conn, "content-type") == ["image/png"]

    # Verify dimensions (would need image processing library)
    # body = response(conn, 200)
    # assert image_dimensions(body) == {1200, 630}

    # Verify cache headers
    cache_control = get_resp_header(conn, "cache-control")
    assert cache_control |> List.first() |> String.contains?("max-age=31536000")

    # Verify ETag
    etag = get_resp_header(conn, "etag")
    assert etag == ["\"#{hash}\""]
  end
end
```

---

## Best Practices

### 1. Always Use Absolute URLs
```elixir
# ✅ Good
"https://wombie.com/event/social-card-abc123.png"

# ❌ Bad
"/event/social-card-abc123.png"
```

### 2. Include All Required Meta Tags
```html
<!-- Open Graph -->
<meta property="og:title" content="Event Title" />
<meta property="og:description" content="Event description..." />
<meta property="og:image" content="https://..." />
<meta property="og:type" content="event" />
<meta property="og:url" content="https://..." />

<!-- Twitter -->
<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:title" content="Event Title" />
<meta name="twitter:description" content="Event description..." />
<meta name="twitter:image" content="https://..." />
```

### 3. Test Before Deploying
- Validate all social cards with automated script
- Test on at least 3 major platforms
- Verify performance benchmarks
- Check error rates in logs

### 4. Monitor in Production
- Track social card generation times
- Monitor error rates
- Check cache hit rates
- Alert on performance degradation

---

## Additional Resources

- [Open Graph Protocol Documentation](https://ogp.me/)
- [Twitter Cards Documentation](https://developer.twitter.com/en/docs/twitter-for-websites/cards)
- [LinkedIn Post Inspector](https://www.linkedin.com/post-inspector/)
- [Google Rich Results Test](https://search.google.com/test/rich-results)
- [Facebook Sharing Debugger](https://developers.facebook.com/tools/debug/)
- [ADR 002: Social Card Architecture](../adr/002-social-card-architecture.md)
- [SEO Best Practices Guide](../seo_best_practices.md)
