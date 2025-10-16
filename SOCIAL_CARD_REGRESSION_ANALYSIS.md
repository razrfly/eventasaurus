# Social Card Regression Analysis - Meta Tag Issue

**Date**: 2025-10-16
**Issue**: Social card images not displaying in Messenger and Signal after Issue #1781 fixes
**Status**: Root cause identified

---

## Executive Summary

The handle_params() callback added to fix ngrok URL issues is **unconditionally overriding ALL meta_image values**, including movie backdrop images from TMDB that were working correctly before. This breaks social sharing for movie events.

---

## Root Cause Analysis

### What Changed in Issue #1781

**Commit**: `aa2996f6` ("social cards")

**Before Changes**:
```elixir
# public_event_live.ex - NO handle_params callback
def mount(_params, _session, socket) do
  # ...
  social_image_url = if has_movie_backdrop do
    "https://image.tmdb.org/t/p/w1280/movie-backdrop.jpg"  # TMDB URL
  else
    social_card_url(socket, event)  # Uses Endpoint.url() + hash path
  end

  socket |> assign(:meta_image, social_image_url)
  # Meta image stays as set in mount()
end
```

**After Changes**:
```elixir
# public_event_live.ex:180 - mount() sets initial value
def mount(_params, _session, socket) do
  # ...
  social_image_url = if has_movie_backdrop do
    "https://image.tmdb.org/t/p/w1280/movie-backdrop.jpg"  # TMDB URL
  else
    social_card_url(socket, event)
  end

  socket |> assign(:meta_image, social_image_url)
end

# public_event_live.ex:205-224 - handle_params() OVERRIDES the value
@impl true
def handle_params(_params, uri, socket) do
  base_url = get_base_url_from_uri(uri)

  socket = if socket.assigns[:event] do
    event = socket.assigns.event
    hash_path = EventasaurusWeb.SocialCardView.social_card_url(event)

    socket
    |> assign(:meta_image, "#{base_url}#{hash_path}")  # ❌ OVERWRITES TMDB URL!
    |> assign(:canonical_url, "#{base_url}/#{event.slug}")
  else
    socket
  end

  {:noreply, assign(socket, :current_uri, uri)}
end
```

### The Problem

**Line 219**: `|> assign(:meta_image, "#{base_url}#{hash_path}")`

This line ALWAYS generates a social card URL and overwrites meta_image, regardless of whether the event should be using a movie backdrop image or a social card.

### URL Format Differences

**TMDB Backdrop URLs** (external, already working):
```
https://image.tmdb.org/t/p/w1280/abc123xyz.jpg
```

**Social Card URLs** (internal, need base URL):
```
/4xgm6g6x9e/social-card-233a8a92.png
```

### Impact

1. **Movie Events**: Previously used TMDB backdrop images → Now forced to use social card URLs
2. **Regular Events**: Previously used social card URLs with wrong base URL → Now use social card URLs with correct base URL ✅

**Result**: Movie events lost their beautiful backdrop images and are showing generic social cards instead.

---

## Why It Works in Facebook Linter But Not Messenger/Signal

**Facebook Linter** (Link Debugger):
- Independent scraper that fetches pages
- More lenient about image formats
- May have cached the OLD working URLs

**Messenger & Signal**:
- Stricter image validation requirements:
  - Must be HTTPS (✓)
  - Must be directly accessible (✓)
  - Must return proper Content-Type headers (✓)
  - Must meet minimum dimensions (✓)
  - **Must be the CORRECT image for the content** ❌

For movie events, users EXPECT to see the movie backdrop, not a generic social card. The social card URL works technically, but it's the wrong image semantically.

---

## The Fix

### Strategy

`handle_params()` should **conditionally** update meta_image based on the current value:

1. **If meta_image is a full HTTPS URL** (TMDB backdrop) → Leave it alone
2. **If meta_image is a relative path** (social card) → Update with correct base URL

### Implementation Approach

```elixir
@impl true
def handle_params(_params, uri, socket) do
  base_url = get_base_url_from_uri(uri)

  socket = if socket.assigns[:event] do
    event = socket.assigns.event
    current_meta_image = socket.assigns[:meta_image]

    # Only update meta_image if it's a relative path (social card URL)
    # Leave external URLs (TMDB backdrops) untouched
    updated_meta_image = if is_binary(current_meta_image) &&
                             String.starts_with?(current_meta_image, "/") do
      # It's a relative social card URL - update with correct base URL
      hash_path = EventasaurusWeb.SocialCardView.social_card_url(event)
      "#{base_url}#{hash_path}"
    else
      # It's already a full URL (TMDB backdrop) - keep it
      current_meta_image
    end

    socket
    |> assign(:meta_image, updated_meta_image)
    |> assign(:canonical_url, "#{base_url}/#{event.slug}")
  else
    socket
  end

  {:noreply, assign(socket, :current_uri, uri)}
end
```

### Alternative Approach

Check if the event has a movie backdrop and skip the override:

```elixir
@impl true
def handle_params(_params, uri, socket) do
  base_url = get_base_url_from_uri(uri)

  socket = if socket.assigns[:event] do
    event = socket.assigns.event

    # Check if event has movie backdrop
    has_movie_backdrop = event.rich_external_data &&
                        event.rich_external_data["metadata"] &&
                        event.rich_external_data["metadata"]["backdrop_path"]

    # Only update meta_image for events without movie backdrops
    socket = if !has_movie_backdrop do
      hash_path = EventasaurusWeb.SocialCardView.social_card_url(event)
      assign(socket, :meta_image, "#{base_url}#{hash_path}")
    else
      socket
    end

    assign(socket, :canonical_url, "#{base_url}/#{event.slug}")
  else
    socket
  end

  {:noreply, assign(socket, :current_uri, uri)}
end
```

---

## Recommended Solution

**Option 1** (Check URL format) is preferred because:
- More robust - works regardless of how meta_image was set
- Doesn't require duplicating the movie backdrop logic
- Follows the principle: "If it's already a full URL, leave it alone"
- Simpler to understand: relative paths need base URL, absolute URLs don't

---

## Testing Strategy

After implementing the fix:

1. **Test Movie Event** (with TMDB backdrop):
   - Visit event page via localhost → Should show TMDB backdrop
   - Visit event page via ngrok → Should STILL show TMDB backdrop (not social card)
   - Check og:image meta tag → Should contain `https://image.tmdb.org/t/p/...`

2. **Test Regular Event** (without movie data):
   - Visit event page via localhost → Should show social card with correct base URL
   - Visit event page via ngrok → Should show social card with ngrok base URL
   - Check og:image meta tag → Should contain social card URL with correct base

3. **Test Social Sharing**:
   - Share movie event link in Facebook Messenger → Should show movie backdrop
   - Share movie event link in Signal → Should show movie backdrop
   - Share regular event link in Messenger → Should show social card
   - Share regular event link in Signal → Should show social card

---

## Files to Modify

- `lib/eventasaurus_web/live/public_event_live.ex` (lines 205-224)
  - Update handle_params() to conditionally update meta_image

---

## Related Files

- `lib/eventasaurus_web/live/public_poll_live.ex` (reference implementation for polls)
- `lib/eventasaurus_web/components/layouts/root.html.heex` (lines 48-79, meta tag rendering)
- `lib/eventasaurus_web/views/social_card_view.ex` (social card URL generation)
- `lib/eventasaurus/social_cards/hash_generator.ex` (hash-based cache busting)

---

## Lessons Learned

1. **Lifecycle Callbacks**: handle_params() runs AFTER mount(), so assignments made in mount() can be overridden
2. **Conditional Updates**: When updating assigns in handle_params(), check if the current value should be preserved
3. **URL Semantics**: Distinguish between relative paths (need base URL) and absolute URLs (already complete)
4. **Testing Scope**: Test both technical correctness (URL works) and semantic correctness (right image for content)

---

## Additional Critical Finding: Hash Not Regenerating on Theme Changes

**User Report**: "For one thing the images are no longer changing eg https://wombie.com/79yy52il0u/social-card-d2d1f3af.png They are not getting rehashed. When I change the theme, nothing happens. The hash stays exactly the same as before."

### Root Cause

The hash generator (`lib/eventasaurus/social_cards/hash_generator.ex:110-129`) includes theme data in the fingerprint:

```elixir
defp build_fingerprint(event) do
  %{
    slug: slug,
    title: Map.get(event, :title, ""),
    description: Map.get(event, :description, ""),
    cover_image_url: Map.get(event, :cover_image_url, ""),
    theme: Map.get(event, :theme, :minimal),              # ← Theme included
    theme_customizations: Map.get(event, :theme_customizations, %{}),  # ← Customizations included
    updated_at: format_timestamp(Map.get(event, :updated_at)),
    version: @social_card_version
  }
end
```

**However**, when the hash is generated in `handle_params()` (line 216), it uses the **event from socket.assigns.event**, which was loaded in `mount()` BEFORE any theme changes were made on the page.

### The Problem

1. User visits event page → `mount()` loads event with theme `:minimal`
2. User changes theme to `:cosmic` using UI controls
3. `handle_params()` runs → Generates hash using OLD theme (`:minimal` from socket.assigns.event)
4. Hash doesn't change because the event record in memory still has the old theme
5. Social card URL stays the same → No cache busting

### Why This Matters

- Social media platforms cache images based on URL
- If the hash doesn't change when theme changes, platforms serve stale images
- Users see the wrong social card design when sharing
- Defeats the purpose of hash-based cache busting

### The Solution

**Option A**: Don't include theme in hash generation
- **Pros**: Hash only changes when content changes, not when appearance changes
- **Cons**: Same social card appearance across all themes

**Option B**: Update event theme in socket before regenerating hash
- **Pros**: Hash correctly reflects current theme
- **Cons**: Requires theme change events to update socket.assigns.event

**Option C**: Pass current theme explicitly to hash generation
- **Pros**: Hash always reflects current page theme
- **Cons**: Requires refactoring hash generator to accept theme parameter

**Recommended**: Option A - Remove theme from hash generation. Social cards should reflect content, not appearance. Theme changes are user preferences, not content changes.

---

**Prepared by**: Claude Code Sequential Thinking Analysis
**Date**: 2025-10-16
**Next Steps**:
1. Implement fix for movie backdrop override issue (Option 1 approach)
2. Remove theme from hash generation to fix cache busting issue
3. Test both fixes together
