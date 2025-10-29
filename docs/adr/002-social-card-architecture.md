# ADR 002: Social Card Architecture

**Status:** Accepted
**Date:** 2025-01-29
**Decision Makers:** Development Team
**Context:** Phase 1-2 of SEO & Social Cards Code Consolidation (#2058)

## Context

Social media platforms (Facebook, Twitter, LinkedIn, WhatsApp, Slack, Discord) display preview cards when users share links. These previews significantly impact click-through rates and user engagement. We need a scalable, maintainable architecture for generating dynamic social cards that:

1. Reflect current content (no stale cards)
2. Support multiple entity types (events, polls, cities, etc.)
3. Cache efficiently on social platforms
4. Generate quickly without blocking requests
5. Maintain consistency across card types

### Current Social Card Implementations

We have three social card types:
- **Event Cards**: Display event title, date, venue, theme
- **Poll Cards**: Show poll question, options, event context
- **City Cards**: Feature city name, stats (events, venues, categories)

Each card is generated dynamically from SVG templates and converted to PNG on-demand.

## Decision

We will implement a **unified social card architecture** with the following components:

### 1. Content-Based Hash Cache Busting

**Pattern:**
```
/:entity-path/social-card-:hash.png
```

**Rationale:**
- Hash is generated from card content (title, description, images, stats, timestamps)
- When content changes, hash changes automatically
- Old URLs become invalid, forcing re-fetch
- Unchanged content = same hash = maximum caching (1 year)
- No manual cache invalidation needed

**Implementation:**
```elixir
# Hash includes all fields that affect visual appearance
hash = HashGenerator.generate_hash(entity, :entity_type)
# => "a1b2c3d4" (8-character hex from SHA-256)

# Full URL includes hash
"/event-slug/social-card-a1b2c3d4.png"
```

**Benefits:**
- Social platforms can cache aggressively (1 year max-age)
- Content updates automatically invalidate cache
- CDN-friendly (safe to cache at edge)
- No database lookups for cache invalidation
- Deterministic (same content = same hash)

### 2. SVG-to-PNG On-Demand Generation

**Pattern:**
```
Request → Validate Hash → Render SVG → Convert PNG → Serve + Cache Headers
```

**Rationale:**
- SVG templates allow dynamic content insertion
- PNG is universally supported by social platforms
- On-demand generation (no pre-generation needed)
- Stateless (no database of generated images)
- Self-cleaning (temporary files deleted after serving)

**Implementation:**
```elixir
# 1. Render SVG template with entity data
svg_content = render_svg_template(entity)

# 2. Convert SVG to PNG using rsvg-convert
{:ok, png_path} = SvgConverter.svg_to_png(svg_content, entity_id, entity)

# 3. Read PNG binary
{:ok, png_data} = File.read(png_path)

# 4. Serve with cache headers
conn
|> put_resp_content_type("image/png")
|> put_resp_header("cache-control", "public, max-age=31536000")  # 1 year
|> put_resp_header("etag", "\"#{hash}\"")
|> send_resp(200, png_data)

# 5. Cleanup temporary file
SvgConverter.cleanup_temp_file(png_path)
```

**Benefits:**
- No image storage required
- Always up-to-date content
- No cleanup jobs needed
- Scales horizontally (stateless)
- Easy to modify templates

### 3. Shared Controller Logic Pattern

**Pattern:** Extract common logic to `SocialCardHelpers` module, keep entity-specific logic in controllers.

**Common Logic** (in `SocialCardHelpers`):
- Hash parameter parsing
- Hash validation
- SVG-to-PNG conversion
- PNG response with cache headers
- Error responses (503, 500)
- Hash mismatch redirects (301)

**Entity-Specific Logic** (in controllers):
- Entity lookup by slug/ID
- Permission checks
- SVG template rendering
- Entity-specific sanitization

**Implementation:**
```elixir
# lib/eventasaurus_web/controllers/event_social_card_controller.ex
def generate_card_by_slug(conn, %{"slug" => slug, "hash" => hash, "rest" => rest}) do
  final_hash = SocialCardHelpers.parse_hash(hash, rest)

  case Events.get_event_by_slug(slug) do
    nil ->
      send_resp(conn, 404, "Event not found")

    event ->
      if SocialCardHelpers.validate_hash(event, final_hash, :event) do
        # Entity-specific: Render SVG template
        svg_content = render_svg_template(event)

        # Common: Generate PNG and serve
        case SocialCardHelpers.generate_png(svg_content, slug, event) do
          {:ok, png_data} ->
            SocialCardHelpers.send_png_response(conn, png_data, final_hash)

          {:error, error} ->
            SocialCardHelpers.send_error_response(conn, error)
        end
      else
        # Common: Handle hash mismatch
        expected_hash = HashGenerator.generate_hash(event, :event)
        SocialCardHelpers.send_hash_mismatch_redirect(
          conn, event, slug, expected_hash, final_hash, :event
        )
      end
  end
end
```

**Benefits:**
- ~80% code reduction in controllers
- Consistent error handling
- Single source of truth for cache headers
- Easy to add new entity types
- Testable common logic

### 4. Type-Based Polymorphism

**Pattern:** Use type atoms (`:event`, `:poll`, `:city`) for polymorphic behavior.

**Rationale:**
- Single `HashGenerator` module supports all types
- Single `UrlBuilder` module supports all types
- Single `SocialCardHelpers` module supports all types
- Type parameter determines behavior
- Easy to extend with new types

**Implementation:**
```elixir
# Hash generation
HashGenerator.generate_hash(event, :event)
HashGenerator.generate_hash(poll, :poll)
HashGenerator.generate_hash(city, :city)

# URL building
HashGenerator.generate_url_path(event, :event)
# => "/summer-fest/social-card-a1b2c3d4.png"

HashGenerator.generate_url_path(poll, :poll)
# => "/summer-fest/polls/1/social-card-e5f6g7h8.png"

HashGenerator.generate_url_path(city, :city)
# => "/social-cards/city/warsaw/b2c3d4e5.png"

# Hash validation
HashGenerator.validate_hash(entity, hash, :event)
HashGenerator.validate_hash(entity, hash, :poll)
HashGenerator.validate_hash(entity, hash, :city)
```

**Benefits:**
- No duplicate code for each entity type
- Consistent API across types
- Easy to add new types (add one fingerprint function)
- Type-safe with dialyzer
- Clear intent in code

## Alternatives Considered

### Alternative 1: Pre-Generated Static Images

**Approach:** Generate social cards when entity is created/updated, store as static files.

**Rejected Because:**
- ❌ Requires image storage (S3, CDN)
- ❌ Requires cleanup jobs for old images
- ❌ Stale cards if generation fails
- ❌ Complex deployment (asset sync)
- ❌ Not stateless (harder to scale)

### Alternative 2: Separate Controllers per Entity

**Approach:** Keep all logic in individual controllers, no shared helpers.

**Rejected Because:**
- ❌ Massive code duplication (~80%)
- ❌ Inconsistent error handling
- ❌ Harder to maintain (change in 3+ places)
- ❌ More tests needed
- ❌ Violates DRY principle

### Alternative 3: Timestamp-Based Cache Busting

**Approach:** Use `updated_at` timestamp in URL instead of content hash.

**Rejected Because:**
- ❌ Timestamp changes don't always mean visual changes
- ❌ Can't detect when related data changes (event theme, poll options)
- ❌ Forces unnecessary re-generation
- ❌ Less precise than content-based hashing
- ❌ Timezone issues with timestamp formatting

### Alternative 4: External Image Generation Service

**Approach:** Use service like Cloudinary, Imgix, or custom microservice.

**Rejected Because:**
- ❌ Additional infrastructure cost
- ❌ External dependency
- ❌ Network latency
- ❌ Vendor lock-in
- ❌ More complex setup
- ✅ Could be reconsidered at scale (>10M cards/month)

## Implementation Details

### Hash Generation Algorithm

```elixir
defmodule Eventasaurus.SocialCards.HashGenerator do
  @social_card_version "v2.0.0"

  def generate_hash(data, type) do
    data
    |> build_fingerprint(type)
    |> Jason.encode!(pretty: false, sort_keys: true)  # Deterministic JSON
    |> then(&:crypto.hash(:sha256, &1))               # SHA-256 hash
    |> Base.encode16(case: :lower)                    # Hex encoding
    |> String.slice(0, 8)                             # First 8 characters
  end

  # Event fingerprint includes:
  # - slug, title, description, cover_image_url
  # - theme, theme_customizations
  # - updated_at timestamp
  # - version tag
  defp build_fingerprint(event, :event) do
    %{
      type: :event,
      slug: event.slug,
      title: event.title,
      description: event.description,
      cover_image_url: event.cover_image_url,
      theme: event.theme,
      theme_customizations: event.theme_customizations,
      updated_at: format_timestamp(event.updated_at),
      version: @social_card_version
    }
  end

  # Poll fingerprint includes:
  # - poll_id, title, poll_type, phase
  # - event theme (inherited)
  # - poll_options (IDs, titles, timestamps)
  # - updated_at timestamp
  # - version tag
  defp build_fingerprint(poll, :poll) do
    %{
      type: :poll,
      poll_id: poll.id,
      title: poll.title,
      poll_type: poll.poll_type,
      phase: poll.phase,
      theme: get_in(poll, [:event, :theme]) || :minimal,
      updated_at: format_timestamp(poll.updated_at),
      options: build_options_fingerprint(poll.poll_options),
      version: @social_card_version
    }
  end

  # City fingerprint includes:
  # - slug, name
  # - stats (events_count, venues_count, categories_count)
  # - updated_at timestamp
  # - version tag
  defp build_fingerprint(city, :city) do
    stats = city.stats || %{}
    %{
      type: :city,
      slug: city.slug,
      name: city.name,
      events_count: stats.events_count || 0,
      venues_count: stats.venues_count || 0,
      categories_count: stats.categories_count || 0,
      updated_at: format_timestamp(city.updated_at),
      version: @social_card_version
    }
  end
end
```

### SVG Template Guidelines

**Dimensions:**
- Canvas: 1200x630px (Open Graph standard)
- Safe zone: 1140x570px (30px margin all sides)
- Text minimum: 24px font size

**Best Practices:**
- High contrast for mobile readability
- Escape all XML special characters
- Use web-safe fonts or embed fonts
- Handle missing data gracefully
- Test on actual devices

**Example:**
```elixir
def render_event_card_svg(event) do
  """
  <svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630">
    <!-- Background -->
    <rect width="1200" height="630" fill="#{theme_color(event.theme)}"/>

    <!-- Safe zone (30px margins) -->
    <!-- Content must stay within x:30-1170, y:30-600 -->

    <!-- Event Title -->
    <text x="60" y="100" font-size="48" fill="#ffffff" font-weight="bold">
      #{escape_xml(event.title)}
    </text>

    <!-- Event Date -->
    <text x="60" y="160" font-size="24" fill="#cccccc">
      #{escape_xml(format_date(event.start_date))}
    </text>

    <!-- Branding -->
    <text x="60" y="580" font-size="20" fill="#666666">
      Wombie
    </text>
  </svg>
  """
end
```

### System Dependencies

**Required:**
- **librsvg2-bin** (provides `rsvg-convert` command)
  - Ubuntu/Debian: `apt-get install librsvg2-bin`
  - macOS: `brew install librsvg`
  - Verify: `rsvg-convert --version`

**Graceful Degradation:**
```elixir
case SvgConverter.verify_rsvg_available() do
  :ok ->
    # Generate card normally

  {:error, :command_not_found} ->
    # Return 503 with helpful error message
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(503, "Social card generation unavailable - missing system dependency")
end
```

## Consequences

### Positive

- ✅ **Consistent Architecture**: All entity types follow same pattern
- ✅ **Efficient Caching**: Content-based hashing enables aggressive caching
- ✅ **Low Maintenance**: Shared logic reduces code duplication by ~80%
- ✅ **Scalable**: Stateless, horizontally scalable architecture
- ✅ **Flexible**: Easy to add new entity types or modify templates
- ✅ **Self-Cleaning**: No storage management or cleanup jobs needed
- ✅ **CDN-Friendly**: Long cache headers safe with hash-based URLs

### Negative

- ⚠️ **System Dependency**: Requires librsvg2-bin installation
- ⚠️ **Generation Latency**: First request generates PNG (~200-500ms)
- ⚠️ **No Offline Fallback**: If generation fails, no backup image
- ⚠️ **Memory Usage**: SVG conversion can use significant memory for complex cards

### Neutral

- ➖ **On-Demand Generation**: Not pre-generated (first request slower, subsequent instant)
- ➖ **Hash Mismatch Redirects**: Clients receive 301 redirects when content changes
- ➖ **Template in Code**: SVG templates in Elixir files (could move to external files)

## Migration Path

### For New Entity Types

1. Add fingerprint function to `HashGenerator`
2. Add URL pattern to `HashGenerator.generate_url_path/2`
3. Create SVG template in `SocialCardView`
4. Create controller using `SocialCardHelpers`
5. Add route to router
6. Use in LiveView with `SEOHelpers.build_social_card_url/3`

### For Existing Social Cards

This architecture is already implemented for:
- ✅ Event cards
- ✅ Poll cards
- ✅ City cards

Future entity types follow the same pattern.

## Monitoring & Metrics

**Key Metrics:**
- Social card generation time (target: <500ms first request)
- Cache hit rate (target: >95% after first request)
- Hash mismatch rate (indicates content volatility)
- 503 errors (indicates rsvg-convert unavailable)
- Social share click-through rates

**Alerts:**
- Alert if generation time >1s (p95)
- Alert if 503 rate >1%
- Alert if hash mismatch rate >10% (unusual content changes)

## Related Decisions

- **ADR 001**: Meta Tag Pattern Standardization
- **ADR 003**: Hash Generator Unification (forthcoming)

## References

- Issue #2058: SEO & Social Cards Code Consolidation
- Open Graph Protocol: https://ogp.me/
- Twitter Card Documentation: https://developer.twitter.com/en/docs/twitter-for-websites/cards
- librsvg Documentation: https://wiki.gnome.org/Projects/LibRsvg

## Review and Approval

**Reviewed by:** Development Team
**Approved by:** Tech Lead
**Implementation:** Completed (Phase 1-2 of Issue #2058)
