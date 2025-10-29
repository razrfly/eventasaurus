# CDN Best Practices

## Overview

This guide covers best practices for using the Cloudflare CDN helper (`Eventasaurus.CDN`) to optimize image delivery across the platform. All external images should be wrapped with `CDN.url/2` to leverage Cloudflare's edge caching and image transformation capabilities.

## Quick Reference

```elixir
# Basic usage
CDN.url(image_url)

# With transformations
CDN.url(image_url, width: 800, quality: 85)

# Full options
CDN.url(image_url,
  width: 800,
  height: 600,
  fit: "cover",
  quality: 85
)
```

## Why Use CDN for Images?

1. **Performance**: Images are served from Cloudflare's global edge network, reducing latency
2. **Cost Savings**: Reduced bandwidth usage on origin servers
3. **Optimization**: Automatic image transformations (resize, quality, format)
4. **Caching**: Cloudflare caches transformed images at the edge
5. **Responsive**: Generate multiple sizes for different devices/screens

## The CDN Module

**Location**: `lib/eventasaurus/cdn.ex`

**Primary Function**: `CDN.url/2`

```elixir
@spec url(String.t() | nil, keyword()) :: String.t() | nil
def url(source_url, opts \\ [])
```

**Returns**:
- Cloudflare CDN URL with transformations when source is external
- Original URL when source is nil or already a CDN URL
- nil when source is nil

## Supported Options

| Option | Type | Description | Example |
|--------|------|-------------|---------|
| `width` | integer | Target width in pixels | `width: 800` |
| `height` | integer | Target height in pixels | `height: 600` |
| `quality` | integer | JPEG/WebP quality (1-100) | `quality: 85` |
| `fit` | string | Resize behavior | `fit: "cover"` |
| `format` | string | Output format | `format: "webp"` |
| `dpr` | integer | Device pixel ratio | `dpr: 2` |

### Fit Options

- `"scale-down"` - Shrink to fit, never enlarge (default)
- `"contain"` - Fit within bounds, preserve aspect ratio
- `"cover"` - Fill bounds, crop if needed
- `"crop"` - Crop to exact dimensions
- `"pad"` - Fit within bounds, pad to exact dimensions

## Usage Patterns

### Pattern 1: Event Cover Images

**Display Size**: Full width cards, approximately 800-1200px wide

```elixir
<img
  src={CDN.url(event.cover_image_url, width: 1200, quality: 90)}
  alt={event.title}
  class="w-full h-auto object-cover"
/>
```

**Why These Settings**:
- `width: 1200` - Covers most desktop displays including retina
- `quality: 90` - High quality for hero images
- No `fit` specified - Uses default "scale-down"

### Pattern 2: Movie Backdrops

**Display Size**: Wide hero images, 16:9 aspect ratio

```elixir
<img
  src={CDN.url(movie.backdrop_url, width: 1200, quality: 90)}
  alt={movie.title}
  class="w-full h-auto object-cover"
/>
```

**Why These Settings**:
- `width: 1200` - High resolution for hero sections
- `quality: 90` - Maintain visual quality for large displays

### Pattern 3: Movie Posters

**Display Size**: Vertical thumbnails, typically 200-300px wide

```elixir
<img
  src={CDN.url(movie.poster_url, width: 200, height: 300, fit: "cover", quality: 90)}
  alt={movie.title}
  class="w-48 h-72 object-cover"
/>
```

**Why These Settings**:
- `width: 200, height: 300` - Matches poster aspect ratio
- `fit: "cover"` - Ensures consistent dimensions
- `quality: 90` - Sharp text on posters

### Pattern 4: Event Card Thumbnails

**Display Size**: Small cards, 96-192px (w-24 or doubled for retina)

```elixir
<img
  src={CDN.url(event.cover_image_url, width: 192, height: 192, fit: "cover", quality: 85)}
  alt={event.title}
  class="w-24 h-24 object-cover rounded-lg"
/>
```

**Why These Settings**:
- `width: 192, height: 192` - 2x size for retina displays (w-24 = 96px)
- `fit: "cover"` - Square aspect ratio, crop if needed
- `quality: 85` - Good balance for thumbnails

### Pattern 5: Grid View Cards

**Display Size**: Responsive grid, approximately 400-800px wide

```elixir
<img
  src={CDN.url(event.cover_image_url, width: 800, height: 450, fit: "cover", quality: 85)}
  alt={event.title}
  class="w-full h-48 object-cover"
/>
```

**Why These Settings**:
- `width: 800` - Covers most grid column widths
- `height: 450` - Maintains 16:9 aspect ratio
- `fit: "cover"` - Consistent card heights
- `quality: 85` - Optimized for fast loading

### Pattern 6: Nearby Events Component

**Display Size**: Medium thumbnails, approximately 400px wide

```elixir
<img
  src={CDN.url(image_url, width: 400, height: 300, fit: "cover", quality: 85)}
  alt={title}
  class="w-full h-auto object-cover"
/>
```

**Why These Settings**:
- `width: 400, height: 300` - Good size for side panels
- `fit: "cover"` - Consistent aspect ratio
- `quality: 85` - Balanced quality/size

## Implementation Checklist

When adding images to public-facing pages:

### ✅ Required Steps

1. **Import CDN Module** (if not already imported)
   ```elixir
   alias Eventasaurus.CDN
   ```

2. **Identify Display Size**
   - Measure actual rendered size in browser
   - Account for responsive breakpoints
   - Consider retina displays (2x multiplier)

3. **Choose Appropriate Dimensions**
   - Use width/height that match or exceed display size
   - Round to common sizes (192, 400, 800, 1200)
   - Add 2x for retina when needed

4. **Select Fit Mode**
   - Use `"cover"` for fixed aspect ratios
   - Use `"scale-down"` for flexible layouts
   - Use `"contain"` to preserve full image

5. **Set Quality Level**
   - 90-95: Hero images, large displays
   - 85-90: Standard cards and images
   - 75-85: Thumbnails and small images

6. **Wrap Image URL**
   ```elixir
   src={CDN.url(image_url, width: 800, quality: 85)}
   ```

### ⚠️ Important Notes

- **Always use CDN for external images** - Any image from external URLs
- **Skip CDN for local assets** - Static assets served from `/priv/static/`
- **Handle nil gracefully** - `CDN.url(nil)` returns `nil`, safe to use
- **Don't double-wrap** - CDN module checks if URL is already a CDN URL

## Common Mistakes

### ❌ Don't: Use raw URLs

```elixir
<img src={event.cover_image_url} alt={event.title} />
```

**Problems**:
- No edge caching
- Full-size images loaded (wasted bandwidth)
- Slower load times for users

### ✅ Do: Wrap with CDN

```elixir
<img src={CDN.url(event.cover_image_url, width: 800, quality: 85)} alt={event.title} />
```

---

### ❌ Don't: Guess dimensions

```elixir
<img src={CDN.url(event.cover_image_url, width: 500, quality: 75)} />
```

**Problems**:
- May be too small for actual display
- May be too large, wasting bandwidth

### ✅ Do: Match display size

```elixir
<!-- For w-24 h-24 (96px), use 192px for retina -->
<img
  src={CDN.url(event.cover_image_url, width: 192, height: 192, fit: "cover", quality: 85)}
  class="w-24 h-24 object-cover"
/>
```

---

### ❌ Don't: Forget fit mode for fixed sizes

```elixir
<img
  src={CDN.url(event.cover_image_url, width: 192, height: 192)}
  class="w-24 h-24"
/>
```

**Problems**:
- Images with wrong aspect ratio will be distorted
- Inconsistent card heights

### ✅ Do: Use fit: "cover" for fixed dimensions

```elixir
<img
  src={CDN.url(event.cover_image_url, width: 192, height: 192, fit: "cover", quality: 85)}
  class="w-24 h-24 object-cover"
/>
```

---

### ❌ Don't: Use CDN for local static assets

```elixir
<img src={CDN.url("/images/logo.png")} />
```

**Problems**:
- Local paths don't benefit from CDN
- May cause errors or unexpected behavior

### ✅ Do: Use CDN only for external URLs

```elixir
<!-- External images - use CDN -->
<img src={CDN.url(event.cover_image_url, width: 800, quality: 85)} />

<!-- Local static assets - use directly -->
<img src="/images/logo.png" />
```

## Size Guidelines

### Tailwind Class → CDN Dimensions

| Tailwind Class | Actual Size | CDN Width | CDN Height | Notes |
|----------------|-------------|-----------|------------|-------|
| `w-12 h-12` | 48px | 96 | 96 | 2x for retina |
| `w-16 h-16` | 64px | 128 | 128 | 2x for retina |
| `w-24 h-24` | 96px | 192 | 192 | 2x for retina |
| `w-32 h-32` | 128px | 256 | 256 | 2x for retina |
| `w-48 h-auto` | 192px | 384 | - | 2x for retina, auto height |
| `w-full h-48` | 100% | 800 | 192 | Responsive width |
| `w-full h-64` | 100% | 1200 | 256 | Large cards |
| `w-full h-auto` | 100% | 1200 | - | Hero images |

### Responsive Considerations

For responsive images that change size across breakpoints:

```elixir
<!-- Mobile: ~320px, Tablet: ~768px, Desktop: ~1200px -->
<!-- Use largest expected size -->
<img
  src={CDN.url(image_url, width: 1200, quality: 85)}
  class="w-full h-auto object-cover"
/>
```

## Quality Guidelines

| Use Case | Quality | Reasoning |
|----------|---------|-----------|
| Hero images | 90-95 | Maximum visual quality for large displays |
| Event covers | 85-90 | Good balance of quality and file size |
| Card thumbnails | 85 | Optimized for fast loading |
| List thumbnails | 80-85 | Smaller files, still good quality |
| Background images | 75-85 | Often partially obscured |

## Examples from Codebase

### ✅ Excellent: PublicEventShowLive

```elixir
# lib/eventasaurus_web/live/public_event_show_live.ex
<img
  src={CDN.url(@event.cover_image_url, width: 1200, quality: 90)}
  alt={@event.display_title}
  class="w-full h-full object-cover"
/>
```

**Why It's Good**:
- Appropriate dimensions for hero image
- High quality for focal point
- Uses display_title for accessible alt text
- Clean, readable code

### ✅ Excellent: Event Cards Component

```elixir
# lib/eventasaurus_web/components/event_cards.ex
<img
  src={CDN.url(@event.cover_image_url, width: 400, height: 300, fit: "cover", quality: 85)}
  alt={@event.title}
  class="w-full h-full object-cover"
  loading="lazy"
  referrerpolicy="no-referrer"
/>
```

**Why It's Good**:
- Matches card display size
- Uses fit: "cover" for consistent aspect ratio
- Includes loading="lazy" for performance
- Uses referrerpolicy="no-referrer" for external images
- Balanced quality for card context

### ✅ Excellent: Nearby Events Component

```elixir
# lib/eventasaurus_web/live/components/nearby_events_component.ex
<img
  src={CDN.url(@image_url, width: 400, height: 300, fit: "cover", quality: 85)}
  alt={@display_title}
  class="w-full h-48 object-cover group-hover:opacity-95 transition-opacity"
  loading="lazy"
/>
```

**Why It's Good**:
- Appropriate for sidebar component
- Consistent with card sizing patterns
- Includes loading="lazy" for performance
- Uses display_title for accessible alt text
- Hover effect for better UX
- Good quality/size balance

## Testing CDN URLs

### Manual Testing

1. **Check Generated URL**:
   ```elixir
   iex> CDN.url("https://example.com/image.jpg", width: 800, quality: 85)
   "https://cdn.wombie.com/cdn-cgi/image/width=800,quality=85/https://example.com/image.jpg"
   ```

2. **Verify in Browser**:
   - Open Network tab in DevTools
   - Check image requests show CDN domain
   - Verify cache headers present
   - Check image dimensions match expectations

3. **Test Transformations**:
   - Try different widths/heights
   - Verify quality differences
   - Test fit modes (cover, contain, etc.)

### Automated Testing

```elixir
# Test CDN URL generation
test "generates correct CDN URL with transformations" do
  url = "https://example.com/image.jpg"
  cdn_url = CDN.url(url, width: 800, quality: 85)

  assert cdn_url =~ "cdn.wombie.com"
  assert cdn_url =~ "width=800"
  assert cdn_url =~ "quality=85"
end
```

## Performance Impact

### Before CDN (Direct URLs)

- Image size: ~2-5MB original
- Load time: 2-4 seconds on 3G
- Bandwidth: Full resolution downloaded
- Cache: Browser cache only

### After CDN (Optimized URLs)

- Image size: ~100-500KB optimized
- Load time: 200-500ms on 3G
- Bandwidth: Only requested size downloaded
- Cache: Cloudflare edge + browser cache

**Estimated Savings**:
- 80-90% bandwidth reduction
- 70-85% faster load times
- Better user experience
- Lower server costs

## Migration Checklist

When migrating existing images to CDN:

1. ✅ Add CDN alias to module
2. ✅ Identify all image src attributes
3. ✅ Measure display sizes for each context
4. ✅ Choose appropriate CDN dimensions
5. ✅ Wrap URLs with CDN.url/2
6. ✅ Test in browser (Network tab)
7. ✅ Verify images load correctly
8. ✅ Check responsive behavior
9. ✅ Test on mobile devices
10. ✅ Monitor performance metrics

## Related Documentation

- [SEO Best Practices](./seo_best_practices.md) - Social card images also use CDN
- [Social Cards Development](../SOCIAL_CARDS_DEV.md) - Testing with ngrok
- Architecture Decision Records in `docs/adr/`

## Questions?

If you're unsure about CDN usage for a specific case:

1. Check if the image is external (not in `/priv/static/`)
2. Measure the actual display size in browser
3. Use dimensions 2x the display size for retina
4. Start with `quality: 85` and adjust if needed
5. Use `fit: "cover"` for fixed aspect ratios

When in doubt, follow the patterns in `event_cards.ex` and `public_event_show_live.ex` - they demonstrate best practices.
