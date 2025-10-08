# Image Proxy/CDN Service for External Event Images

## Issue Summary

Implement an image proxy/CDN service to cache and deliver external event images from third-party sources (Resident Advisor, Bandsintown, Ticketmaster, etc.) without storing images on our infrastructure. This will improve reliability, performance, and enable image transformations while reducing dependency on external hosts.

## Problem Statement

### Current Situation
- Event images are sourced from multiple third-party providers (RA, Bandsintown, Ticketmaster)
- Direct linking to external URLs in JSON-LD schema and UI
- No control over image availability, performance, or formatting
- Vulnerable to broken links if providers change URLs or remove images
- No ability to optimize/transform images (resize, format conversion, quality adjustment)

### Example Current Implementation
```elixir
# lib/eventasaurus_web/json_ld/public_event_schema.ex:414
source.image_url  # Direct URL to RA, Bandsintown, etc.
# e.g., "https://ra.co/images/123456.jpg"
```

### Risks
1. **Availability**: Third-party hosts may go down or remove images
2. **Performance**: No CDN, images loaded from origin servers
3. **Consistency**: Different image sizes/formats from different providers
4. **SEO Impact**: Broken images hurt search rankings and social sharing
5. **No Control**: Can't optimize for mobile, retina displays, or bandwidth

## Requirements

### Must Have
- ✅ Proxy/cache external images without uploading to our storage
- ✅ Automatic caching with CDN delivery
- ✅ Support for all major image formats (JPEG, PNG, WebP, AVIF)
- ✅ Simple URL-based integration
- ✅ Security features (domain whitelisting, signed URLs)

### Nice to Have
- ⭐ Real-time image transformations (resize, crop, format conversion)
- ⭐ Responsive images (srcset generation)
- ⭐ Automatic format optimization (WebP/AVIF for modern browsers)
- ⭐ Quality/compression controls
- ⭐ Lazy loading support
- ⭐ Analytics/usage tracking

## Research Findings

### Service Comparison

#### 1. ImageKit (Recommended - Best Overall)

**Web Proxy Feature**: ✅ Available on all plans
- **URL Format**: `https://ik.imagekit.io/your_id/https://external.com/image.jpg`
- **Transformations**: `tr:w-300,h-300/https://external.com/image.jpg`
- **Caching**: Automatic (persistent caching on Enterprise plans)
- **CDN**: 6 global processing regions

**Pricing**:
- Free tier available
- Bandwidth: $0.45-$0.50/GB beyond free tier
- Cache purge: $9 per 1,500 requests
- No storage charges for external images

**Setup**:
```
1. Dashboard → External Storage → Web Proxy
2. Configure origin name
3. Start using: https://ik.imagekit.io/{id}/{external_url}
```

**Pros**:
- ✅ Simple setup and URL structure
- ✅ Available on free plan
- ✅ Comprehensive documentation
- ✅ Real-time transformations
- ✅ Competitive pricing

**Cons**:
- ⚠️ Persistent caching requires Enterprise plan
- ⚠️ Should use signed URLs to prevent abuse

**Documentation**: https://imagekit.io/docs/integration/web-proxy

---

#### 2. Cloudinary (Industry Standard)

**Fetch Feature**: ✅ Full support
- **URL Format**: `https://res.cloudinary.com/{cloud}/fetch/{external_url}`
- **Transformations**: Built into URL path
- **Caching**: Automatic with CDN delivery
- **Domain Whitelist**: Security feature to restrict fetch domains

**Pricing**:
- Free tier: 25 credits/month (includes transformations & bandwidth)
- Pay-as-you-go after free tier
- Contact sales for pricing details

**Setup**:
```
1. Security tab → Allowed fetch domains
2. Whitelist your source domains
3. Use: https://res.cloudinary.com/{cloud}/fetch/{url}
```

**Pros**:
- ✅ Industry leader with extensive features
- ✅ Mature product with excellent docs
- ✅ Advanced transformation capabilities
- ✅ Domain whitelisting for security
- ✅ Automatic format optimization

**Cons**:
- ⚠️ More expensive than alternatives
- ⚠️ Complex pricing structure
- ⚠️ Requires domain whitelisting setup

**Documentation**: https://cloudinary.com/documentation/fetch_remote_images

---

#### 3. Cloudflare Images (Budget-Friendly)

**Transform via URL**: ✅ Free plan available
- **URL Format**: Use Cloudflare Workers or URL transformations
- **Transformations**: Via query parameters or Workers API
- **Caching**: Automatic (minimum 1 hour)
- **Integration**: Can use Workers for advanced control

**Pricing**:
- Free tier with limited usage
- Very competitive pay-as-you-go pricing
- Part of Cloudflare ecosystem (if already using CF)

**Setup**:
```
1. Enable Cloudflare Images
2. Use URL transformation or Workers binding
3. Implement transform-via-url or Workers proxy
```

**Pros**:
- ✅ Very cost-effective
- ✅ Free tier available
- ✅ Good if already using Cloudflare
- ✅ Workers integration for flexibility
- ✅ Excellent CDN performance

**Cons**:
- ⚠️ Limited transformation options vs competitors
- ⚠️ May require Workers implementation for best results
- ⚠️ Less mature than ImageKit/Cloudinary

**Documentation**: https://developers.cloudflare.com/images/

---

#### 4. imgix (Premium Option)

**Web Proxy**: ✅ Premium accounts only
- **URL Format**: Pass full external URLs to imgix
- **Transformations**: Extensive query parameter options
- **Requirements**: Premium account required

**Pricing**:
- Contact sales (not publicly listed)
- Premium account required for Web Proxy
- Likely more expensive than alternatives

**Pros**:
- ✅ Excellent image quality and transformations
- ✅ Fast performance
- ✅ Good documentation

**Cons**:
- ⚠️ Premium account required
- ⚠️ No public pricing
- ⚠️ Likely most expensive option

**Documentation**: https://docs.imgix.com/setup/creating-sources

---

#### 5. Alternative Options

**Gumlet**: Top ImageKit alternative with similar features
**Uploadcare**: Free alternative with comprehensive file API
**Bunny.net**: Budget-friendly CDN with image optimization
**Sirv**: Real-time optimization, good for 360-degree spins

## Recommendations

### Primary Recommendation: ImageKit

**Why ImageKit?**
1. ✅ **Best Value**: Web Proxy on free plan, competitive pricing
2. ✅ **Ease of Use**: Simple URL structure, easy integration
3. ✅ **Complete Solution**: Transformations, caching, CDN all included
4. ✅ **Phoenix/Elixir Friendly**: URL-based, no SDK required
5. ✅ **Growth Path**: Can scale from free to enterprise

**Estimated Costs** (assuming 10K events, avg 1 image each):
- Initial load: ~10GB bandwidth = ~$5/month
- Cached delivery: Minimal additional costs
- Free tier might cover initial usage

### Alternative Recommendation: Cloudflare Images

**If already using Cloudflare:**
- Leverage existing infrastructure
- More cost-effective if already on CF
- Workers integration provides flexibility

### Not Recommended: imgix

- Premium account requirement
- No public pricing
- Overkill for our needs

## Implementation Plan

### Phase 1: Setup & Basic Integration (1-2 days)

1. **Create ImageKit Account**
   - Sign up for free tier
   - Configure web proxy origin
   - Test with sample external URLs

2. **Update PublicEventSchema**
   ```elixir
   # lib/eventasaurus_web/json_ld/public_event_schema.ex

   defp proxy_image_url(external_url) do
     # ImageKit web proxy URL format
     base_url = "https://ik.imagekit.io/#{Application.get_env(:eventasaurus, :imagekit_id)}"
     "#{base_url}/#{external_url}"
   end

   defp add_event_images(images, event) do
     source_images =
       event.sources
       |> extract_images()
       |> Enum.map(&proxy_image_url/1)  # Proxy through ImageKit
   end
   ```

3. **Configuration**
   ```elixir
   # config/runtime.exs
   config :eventasaurus,
     imagekit_id: System.get_env("IMAGEKIT_ID"),
     imagekit_private_key: System.get_env("IMAGEKIT_PRIVATE_KEY")
   ```

### Phase 2: Image Transformations (2-3 days)

1. **Create Image Helper Module**
   ```elixir
   defmodule EventasaurusWeb.Images do
     def event_thumbnail(url, width, height) do
       proxy_image_url(url, "tr:w-#{width},h-#{height},fo-auto")
     end

     def responsive_srcset(url) do
       [300, 600, 900, 1200]
       |> Enum.map(fn w ->
         "#{proxy_image_url(url, "tr:w-#{w}")} #{w}w"
       end)
       |> Enum.join(", ")
     end
   end
   ```

2. **Implement in Templates**
   ```heex
   <img
     src={Images.event_thumbnail(@event.image_url, 600, 400)}
     srcset={Images.responsive_srcset(@event.image_url)}
     sizes="(max-width: 768px) 100vw, 600px"
     alt={@event.title}
   />
   ```

### Phase 3: Security & Optimization (1-2 days)

1. **Implement Signed URLs** (prevent hotlinking abuse)
   ```elixir
   defp signed_image_url(external_url, transformations) do
     # Generate HMAC signature for ImageKit
     # Prevents unauthorized access
   end
   ```

2. **Add Monitoring**
   - Track bandwidth usage
   - Monitor cache hit rates
   - Alert on cost thresholds

3. **Fallback Strategy**
   ```elixir
   defp get_image_url(event) do
     with {:ok, proxied_url} <- proxy_image_url(event.image_url),
          true <- image_accessible?(proxied_url) do
       proxied_url
     else
       _ -> event.image_url  # Fallback to original
     end
   end
   ```

## Security Considerations

### ImageKit Security
1. **Signed URLs**: Implement to prevent abuse
2. **Domain Restrictions**: Configure in ImageKit dashboard
3. **Rate Limiting**: Monitor usage, set up alerts
4. **URL Validation**: Sanitize external URLs before proxying

### Example Signed URL Implementation
```elixir
defmodule EventasaurusWeb.Images.ImageKit do
  @expiry_seconds 3600  # 1 hour

  def signed_url(path, transformations \\ "") do
    expires = DateTime.utc_now() |> DateTime.add(@expiry_seconds) |> DateTime.to_unix()

    signature =
      :crypto.mac(:hmac, :sha256, private_key(), "#{path}#{expires}")
      |> Base.encode16(case: :lower)

    "#{base_url()}/#{transformations}/#{path}?expires=#{expires}&signature=#{signature}"
  end
end
```

## Performance Optimization

### CDN Caching Strategy
- **Cache Headers**: Rely on ImageKit's CDN caching (automatic)
- **Purge Strategy**: Rarely needed for event images (immutable)
- **Preload Critical Images**: Consider preloading for above-the-fold images

### Format Optimization
```elixir
# Automatic format selection based on browser support
def optimized_image(url) do
  # ImageKit auto-detects browser capabilities
  proxy_image_url(url, "tr:f-auto,q-auto")
end
```

### Responsive Images
```elixir
def responsive_image(url, sizes \\ [300, 600, 900, 1200]) do
  sizes
  |> Enum.map(fn width ->
    {proxy_image_url(url, "tr:w-#{width},f-auto"), width}
  end)
end
```

## Cost Estimation

### Monthly Estimates (ImageKit)

**Scenario 1: Small Scale** (1,000 events/month)
- Storage: $0 (external URLs)
- Bandwidth: ~1GB = **$0** (within free tier)
- Transformations: Unlimited on free tier

**Scenario 2: Medium Scale** (10,000 events/month)
- Storage: $0 (external URLs)
- Bandwidth: ~10GB = **~$5/month** ($0.50/GB)
- First load: 10GB
- Cached delivery: Minimal additional cost

**Scenario 3: Large Scale** (100,000 events/month)
- Storage: $0 (external URLs)
- Bandwidth: ~100GB = **~$45-50/month** ($0.45-0.50/GB)
- Consider Enterprise plan for persistent caching
- Better cache hit ratios reduce costs

### Comparison to Alternatives
- **Cloudinary**: ~$99/month for 25GB+ usage
- **Cloudflare Images**: Very competitive, ~$5/million requests
- **imgix**: Contact sales (likely $200+/month)

## Testing Strategy

1. **Unit Tests**: Image URL generation
2. **Integration Tests**: ImageKit API availability
3. **Visual Regression**: Ensure image quality
4. **Performance Tests**: Load times with/without proxy
5. **Fallback Tests**: Verify graceful degradation

## Monitoring & Alerts

### Key Metrics
- Bandwidth usage (daily/monthly)
- Cache hit ratio
- Image load times
- Error rates (4xx, 5xx from ImageKit)
- Cost tracking

### Alert Thresholds
- Bandwidth: >80% of budget
- Errors: >1% of requests
- Load time: >2 seconds

## Migration Strategy

### Phase 1: New Events Only
- Implement proxy for newly scraped events
- Test with production data
- Monitor performance and costs

### Phase 2: Gradual Backfill
- Update existing events in batches
- Start with most viewed events
- Monitor cache warming

### Phase 3: Full Rollout
- All event images proxied
- Original URLs as fallback
- Deprecate direct linking

## Documentation Needed

1. **Developer Docs**: How to use image helpers
2. **Operations Docs**: Cost monitoring, troubleshooting
3. **Architecture Docs**: Image flow diagrams
4. **Runbook**: Common issues and resolutions

## Related Issues

- #1592: Resident Advisor Events Missing Descriptions
- Improves SEO with reliable image delivery
- Enhances social media sharing with optimized images

## Next Steps

1. ✅ Research complete (this issue)
2. ⏭️ **Decision**: Choose service (recommend ImageKit)
3. ⏭️ Create ImageKit account and configure
4. ⏭️ Implement Phase 1 (basic proxy integration)
5. ⏭️ Test with sample events
6. ⏭️ Implement Phase 2 (transformations)
7. ⏭️ Implement Phase 3 (security & monitoring)
8. ⏭️ Deploy and monitor

## References

- [ImageKit Web Proxy Documentation](https://imagekit.io/docs/integration/web-proxy)
- [Cloudinary Fetch Documentation](https://cloudinary.com/documentation/fetch_remote_images)
- [Cloudflare Images Documentation](https://developers.cloudflare.com/images/)
- [Image Optimization Best Practices](https://web.dev/fast/#optimize-your-images)

## Priority

**High** - Improves reliability, performance, and SEO for all event images

## Labels

- `enhancement`
- `infrastructure`
- `seo`
- `performance`
- `images`
- `cdn`
- `needs-decision`

---

**Estimated Implementation Time**: 5-7 days total (across 3 phases)
**Estimated Monthly Cost**: $0-50 depending on scale (ImageKit free tier → paid)
