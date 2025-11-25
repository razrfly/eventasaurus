# Social Card Routing Conflict Issue

## Problem Summary

Social card generation is broken due to a route ordering conflict in the Phoenix router. Social card URLs like `https://wombie.com/fuzbklq14z/social-card-7f2e0693.png` are being intercepted by the aggregated content LiveView route before reaching the social card controller.

## Root Cause

The aggregated content route pattern `/:content_type/:identifier` (router.ex:669) is a catch-all that matches social card URLs before they can reach the dedicated social card controllers (router.ex:697-713).

### Route Processing Order

1. **Line 669** - Aggregated content route (in `live_session :public`):
   ```elixir
   live "/:content_type/:identifier", AggregatedContentLive, :multi_city
   ```

2. **Lines 697-713** - Social card routes (in separate scope):
   ```elixir
   scope "/", EventasaurusWeb do
     pipe_through :image

     get "/:slug/social-card-:hash/*rest", EventSocialCardController, :generate_card_by_slug
     get "/:slug/polls/:number/social-card-:hash/*rest", PollSocialCardController, :generate_card_by_number
   end
   ```

### Why It Breaks

When a request comes in for `/fuzbklq14z/social-card-7f2e0693.png`:

1. Phoenix processes routes in order
2. The aggregated content route `/:content_type/:identifier` matches first:
   - `content_type` = `fuzbklq14z`
   - `identifier` = `social-card-7f2e0693.png`
3. The request is sent to `AggregatedContentLive` instead of `EventSocialCardController`
4. The LiveView tries to handle it as aggregated content, which fails
5. Social card never gets generated

## Impact

- **All event social cards are broken** - OpenGraph images won't load for social media sharing
- **Poll social cards may also be affected** - Similar routing pattern
- **City social cards likely work** - They use `/social-cards/city/:slug/:hash/*rest` pattern which doesn't conflict
- **SEO impact** - Missing social card images hurt social media presence and click-through rates

## Evidence

Recent changes in `public_movie_screenings_live.ex` and other files show we've been working on aggregated content routes, which likely introduced this conflict.

Git diff shows:
- `MovieDetailsCard` component integration
- Language switcher additions
- Breadcrumb navigation updates
- Plan with friends modal integration

These changes don't directly affect routing, but the aggregated content route was likely added recently and is now catching social card URLs.

## Solutions

### Option 1: Move Social Card Routes Before Aggregated Content (RECOMMENDED)

Move the social card scope to appear BEFORE the `live_session :public` block.

**Pros:**
- Simple, clear fix
- No performance impact
- Maintains existing route patterns
- Explicit route precedence

**Cons:**
- Splits social card routes from related public routes

**Implementation:**
```elixir
# Around line 650, BEFORE live_session :public
scope "/", EventasaurusWeb do
  pipe_through :image

  # City social card generation
  get "/social-cards/city/:slug/:hash/*rest", CitySocialCardController, :generate_card_by_slug,
    as: :city_social_card_cached

  # Event social card generation (must be before aggregated content)
  get "/:slug/social-card-:hash/*rest", EventSocialCardController, :generate_card_by_slug,
    as: :social_card_cached

  # Poll social card generation (must be before aggregated content)
  get "/:slug/polls/:number/social-card-:hash/*rest",
      PollSocialCardController,
      :generate_card_by_number,
      as: :poll_social_card_cached
end

# Then have live_session :public with aggregated content route
```

### Option 2: Add Route Constraints to Aggregated Content

Add a constraint to prevent the aggregated content route from matching social card patterns.

**Pros:**
- Keeps routes logically grouped
- Self-documenting via constraints

**Cons:**
- More complex
- Requires custom constraint module
- Slightly slower due to constraint checking

**Implementation:**
```elixir
# In router.ex
live "/:content_type/:identifier", AggregatedContentLive, :multi_city,
  constraints: %{identifier: ~r/^(?!social-card-)/}
```

Or create a custom constraint module:
```elixir
defmodule EventasaurusWeb.Constraints do
  def not_social_card(identifier) do
    not String.contains?(identifier, "social-card-")
  end
end

# In router
live "/:content_type/:identifier", AggregatedContentLive, :multi_city,
  constraints: [identifier: &EventasaurusWeb.Constraints.not_social_card/1]
```

### Option 3: Restructure Aggregated Content Routes

Use a more specific pattern for aggregated content that doesn't conflict.

**Pros:**
- Clearer URL structure
- No route ordering dependencies

**Cons:**
- Breaking change to existing URLs
- Requires redirects for old URLs
- More work

**Implementation:**
```elixir
# Use /browse/ prefix for aggregated content
live "/browse/:content_type/:identifier", AggregatedContentLive, :multi_city
```

## Recommended Fix

**Option 1** is recommended because it:
- Is the simplest and most reliable solution
- Has zero performance impact
- Maintains all existing URL patterns
- Makes route precedence explicit and clear
- Follows Phoenix best practices (specific routes before catch-alls)

## Testing Checklist

After implementing the fix:

1. **Event Social Cards**
   - [ ] Visit an event page and check meta tags
   - [ ] Verify social card URL in `<meta property="og:image">`
   - [ ] Test social card URL directly in browser
   - [ ] Verify hash validation works

2. **Poll Social Cards**
   - [ ] Visit a poll page and check meta tags
   - [ ] Test poll social card URL generation
   - [ ] Verify correct image returned

3. **City Social Cards**
   - [ ] Verify city social cards still work
   - [ ] Test hash validation for cities

4. **Aggregated Content Routes**
   - [ ] Verify `/trivia/pubquiz-pl` still works
   - [ ] Test `/movies/:slug` routes
   - [ ] Verify query parameters work (`?scope=all&city=krakow`)

5. **Social Media Preview**
   - [ ] Test with Facebook Debugger: https://developers.facebook.com/tools/debug/
   - [ ] Test with Twitter Card Validator: https://cards-dev.twitter.com/validator
   - [ ] Test with LinkedIn Post Inspector

## References

- Router file: `lib/eventasaurus_web/router.ex`
- Event social card controller: `lib/eventasaurus_web/controllers/event_social_card_controller.ex`
- Poll social card controller: `lib/eventasaurus_web/controllers/poll_social_card_controller.ex`
- City social card controller: `lib/eventasaurus_web/controllers/city_social_card_controller.ex`
- Social card documentation: `SOCIAL_CARDS_DEV.md`
- ADR 002: `docs/adr/002-social-card-architecture.md`

## Related Issues

- This may affect other catch-all routes in the future
- Consider adding route ordering documentation to prevent similar issues
- Review all catch-all routes for potential conflicts

---

**Created:** 2025-01-25
**Severity:** High (breaks social media sharing)
**Priority:** Immediate fix required
