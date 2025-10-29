# SEO & Social Cards Testing Checklist

**Purpose:** Comprehensive testing checklist for SEO and social card features

**Last Updated:** 2025-01-29

---

## Pre-Deployment Checklist

Use this checklist before deploying any SEO or social card changes to production.

### Code Quality Checks

- [ ] All tests pass: `mix test`
- [ ] No compilation warnings: `mix compile --warnings-as-errors`
- [ ] Credo checks pass: `mix credo --strict`
- [ ] Dialyzer type checks pass: `mix dialyzer`
- [ ] Code formatted: `mix format --check-formatted`

### Social Card Implementation Checks

#### Event Social Cards

- [ ] Event social card generates successfully
- [ ] Hash is generated from event content
- [ ] URL pattern matches: `/event-slug/social-card-[hash].png`
- [ ] Image is exactly 1200x630px
- [ ] PNG format with proper compression
- [ ] File size < 200KB (optimal) or < 500KB (acceptable)
- [ ] Generation time < 500ms (first request)
- [ ] Cached response time < 50ms
- [ ] Hash mismatch redirects to correct URL (301)
- [ ] SVG template renders all event data correctly
- [ ] Special characters are escaped in SVG
- [ ] Theme colors apply correctly

#### Poll Social Cards

- [ ] Poll social card generates successfully
- [ ] Hash includes poll options and event theme
- [ ] URL pattern matches: `/event-slug/polls/[number]/social-card-[hash].png`
- [ ] Image is exactly 1200x630px
- [ ] PNG format with proper compression
- [ ] File size < 200KB (optimal) or < 500KB (acceptable)
- [ ] Generation time < 500ms (first request)
- [ ] Poll question renders correctly
- [ ] Poll options display properly
- [ ] Event theme is inherited
- [ ] Poll phase indicator shows correctly

#### City Social Cards

- [ ] City social card generates successfully
- [ ] Hash includes city stats (events, venues, categories)
- [ ] URL pattern matches: `/social-cards/city/[slug]/[hash].png`
- [ ] Image is exactly 1200x630px
- [ ] PNG format with proper compression
- [ ] File size < 200KB (optimal) or < 500KB (acceptable)
- [ ] Generation time < 500ms (first request)
- [ ] City name renders correctly
- [ ] Stats display properly (events count, venues count, categories count)
- [ ] City image/background renders if present

### Meta Tags & SEO Checks

#### Open Graph Tags

- [ ] `og:title` is present and accurate
- [ ] `og:description` is present and 150-160 characters
- [ ] `og:image` is absolute URL to social card
- [ ] `og:type` is set correctly (event, website, etc.)
- [ ] `og:url` is canonical URL
- [ ] `og:site_name` is set to "Wombie" or site name
- [ ] `og:locale` is set appropriately

#### Twitter Card Tags

- [ ] `twitter:card` is "summary_large_image"
- [ ] `twitter:title` matches og:title
- [ ] `twitter:description` matches og:description
- [ ] `twitter:image` matches og:image
- [ ] `twitter:site` is set (if applicable)

#### JSON-LD Structured Data

- [ ] Event schema includes all required fields
- [ ] Event schema validates in Google Rich Results Test
- [ ] LocalBusiness schema for venues (if applicable)
- [ ] BreadcrumbList schema for navigation
- [ ] Schema types are correct (@type)
- [ ] Dates are in ISO 8601 format
- [ ] URLs are absolute
- [ ] Images are absolute URLs

#### Canonical URLs

- [ ] Canonical URL is set on all pages
- [ ] Canonical URL is absolute (https://domain.com/path)
- [ ] Canonical URL points to correct version (no trailing slash issues)
- [ ] Canonical URL matches current page (no redirect chains)

### Cache & Performance Checks

#### Cache Headers

- [ ] `Cache-Control` includes `public, max-age=31536000` (1 year)
- [ ] `ETag` matches content hash
- [ ] No `no-cache` or `private` directives (should be public)
- [ ] `Vary` header set appropriately (if needed)

#### Performance Benchmarks

- [ ] Event card generation < 500ms
- [ ] Poll card generation < 500ms
- [ ] City card generation < 500ms
- [ ] Cached requests < 50ms
- [ ] Hash generation < 5ms
- [ ] Hash validation < 10ms
- [ ] 404 responses < 50ms
- [ ] Hash mismatch redirects < 100ms

#### Memory & Resource Usage

- [ ] No memory leaks after 100+ generations
- [ ] Memory increase < 50MB per 100 cards
- [ ] Temp files are cleaned up properly
- [ ] No orphaned processes
- [ ] CPU usage returns to baseline after generation

### Error Handling Checks

- [ ] 404 returned for missing events
- [ ] 404 returned for missing polls
- [ ] 404 returned for missing cities
- [ ] 503 returned if rsvg-convert unavailable
- [ ] 500 errors logged with context
- [ ] Hash mismatch redirects (301) to correct URL
- [ ] Invalid hash formats handled gracefully
- [ ] SVG rendering errors logged
- [ ] PNG conversion errors logged

### Hash Generator Checks

- [ ] Event hash changes when title changes
- [ ] Event hash changes when description changes
- [ ] Event hash changes when theme changes
- [ ] Event hash changes when cover image changes
- [ ] Poll hash changes when title changes
- [ ] Poll hash changes when options change
- [ ] Poll hash changes when poll type changes
- [ ] City hash changes when stats change
- [ ] Same content produces same hash (deterministic)
- [ ] Hash is 8 characters lowercase hex
- [ ] Hash extraction from URL works for all patterns

---

## Platform Validation Checklist

Test on all major platforms before announcing new features.

### Facebook

- [ ] Test with [Facebook Sharing Debugger](https://developers.facebook.com/tools/debug/)
- [ ] Image loads and displays correctly
- [ ] Title appears correctly
- [ ] Description appears correctly (first ~300 characters)
- [ ] No errors or warnings
- [ ] Image is 1200x630px (verify in debugger)
- [ ] Scraped successfully
- [ ] Cache cleared with "Scrape Again"
- [ ] Test actual share in Facebook post

### Twitter/X

- [ ] Test with [Twitter Card Validator](https://cards-dev.twitter.com/validator)
- [ ] Card type is "summary_large_image"
- [ ] Image renders correctly
- [ ] Title appears correctly
- [ ] Description appears correctly
- [ ] No errors or warnings
- [ ] Test actual tweet with URL

### LinkedIn

- [ ] Test with [LinkedIn Post Inspector](https://www.linkedin.com/post-inspector/)
- [ ] Preview shows correct image
- [ ] Title appears correctly
- [ ] Description appears correctly
- [ ] No errors or warnings
- [ ] Cache cleared with "Refresh"
- [ ] Test actual LinkedIn post

### Google Search

- [ ] Test with [Google Rich Results Test](https://search.google.com/test/rich-results)
- [ ] Event schema detected and valid
- [ ] All required fields present
- [ ] No structured data errors
- [ ] Preview looks correct
- [ ] Test with [Google Search Console](https://search.google.com/search-console) (production only)
- [ ] No mobile usability issues

### Messaging Apps

- [ ] WhatsApp: Share link and verify preview loads
- [ ] Slack: Share link and verify unfurling works
- [ ] Discord: Share link and verify embed appears
- [ ] Telegram: Share link and verify preview (if applicable)
- [ ] iMessage: Share link and verify preview (if applicable)

---

## Automated Testing Checklist

Run automated tests to ensure everything works.

### Unit Tests

```bash
# Run all tests
mix test

# Run social card tests only
mix test test/eventasaurus_web/controllers/*_social_card_controller_test.exs

# Run performance tests
mix test test/eventasaurus_web/controllers/social_card_performance_test.exs

# Run with coverage
mix test --cover
```

**Expected Results:**
- [ ] All unit tests pass
- [ ] Test coverage > 80% for social card modules
- [ ] No flaky tests (run 3 times to verify)

### Integration Tests

```bash
# Run validation script
APP_URL=http://localhost:4000 elixir test/validation/social_card_validator.exs

# Run with production URL (if deployed)
APP_URL=https://wombie.com elixir test/validation/social_card_validator.exs
```

**Expected Results:**
- [ ] All validation checks pass
- [ ] Performance benchmarks within targets
- [ ] No HTTP errors
- [ ] Images load correctly

### Performance Tests

```bash
# Run performance benchmark
mix test test/eventasaurus_web/controllers/social_card_performance_test.exs

# Run stress test (1000 requests)
mix test --only stress test/eventasaurus_web/controllers/social_card_performance_test.exs

# Generate performance report
mix test --only performance_summary test/eventasaurus_web/controllers/social_card_performance_test.exs
```

**Expected Results:**
- [ ] Generation time < 500ms
- [ ] Cached time < 50ms
- [ ] Image sizes within limits
- [ ] No memory leaks
- [ ] Stress test shows no degradation

---

## Manual Testing Checklist

Perform manual tests to verify user-facing functionality.

### Event Pages

- [ ] Visit event page: `/activities/[slug]`
- [ ] Verify page title in browser tab
- [ ] View page source and verify meta tags
- [ ] Copy social card URL and open in new tab
- [ ] Verify image loads (1200x630px PNG)
- [ ] Check network tab for cache headers
- [ ] Update event title and verify new hash generated
- [ ] Old hash URL redirects to new hash (301)
- [ ] Share on one social platform and verify preview

### Poll Pages

- [ ] Visit poll page: `/activities/[slug]/polls/[number]`
- [ ] Verify page title in browser tab
- [ ] View page source and verify meta tags
- [ ] Copy social card URL and open in new tab
- [ ] Verify image loads with poll data
- [ ] Update poll title and verify new hash
- [ ] Share on one social platform and verify preview

### City Pages

- [ ] Visit city page: `/c/[slug]`
- [ ] Verify page title in browser tab
- [ ] View page source and verify meta tags
- [ ] Copy social card URL and open in new tab
- [ ] Verify image loads with city stats
- [ ] Stats update should trigger new hash
- [ ] Share on one social platform and verify preview

### Mobile Testing

- [ ] Open event page on mobile device
- [ ] Verify meta tags present (view source)
- [ ] Share link via mobile app (WhatsApp, iMessage, etc.)
- [ ] Verify preview loads on mobile
- [ ] Image displays correctly on small screen
- [ ] Page is mobile-friendly (Google test)

### Browser Testing

Test on major browsers:

- [ ] Chrome (latest)
- [ ] Firefox (latest)
- [ ] Safari (latest)
- [ ] Edge (latest)
- [ ] Mobile Safari (iOS)
- [ ] Mobile Chrome (Android)

---

## Regression Testing Checklist

Run when making changes to social card system.

### After Code Changes

- [ ] All existing tests still pass
- [ ] Performance benchmarks still meet targets
- [ ] No new compilation warnings
- [ ] Hash algorithm still produces correct results
- [ ] Cache headers unchanged (or intentionally changed)
- [ ] Meta tags still render correctly
- [ ] JSON-LD schemas still validate

### After Dependency Updates

- [ ] `rsvg-convert` still available and working
- [ ] Image generation still works
- [ ] Performance hasn't degraded
- [ ] No new errors in logs
- [ ] All tests pass

### After Infrastructure Changes

- [ ] Social cards accessible via CDN (if using)
- [ ] Cache behavior still correct
- [ ] CORS headers correct (if needed)
- [ ] Performance hasn't degraded
- [ ] Load balancing works correctly

---

## Production Deployment Checklist

Final checks before deploying to production.

### Pre-Deployment

- [ ] All tests pass in CI/CD
- [ ] Code review completed and approved
- [ ] Performance benchmarks meet targets
- [ ] Database migrations tested (if applicable)
- [ ] Rollback plan documented
- [ ] Monitoring alerts configured

### Deployment Steps

- [ ] Deploy to staging environment first
- [ ] Run full test suite on staging
- [ ] Manual testing on staging
- [ ] Platform validation on staging URLs
- [ ] Performance testing on staging
- [ ] Get stakeholder approval
- [ ] Deploy to production
- [ ] Monitor deployment logs
- [ ] Verify health checks pass

### Post-Deployment

- [ ] Smoke test production URLs
- [ ] Verify social cards generate successfully
- [ ] Test hash mismatch redirects
- [ ] Check error rates in monitoring
- [ ] Verify cache hit rates
- [ ] Monitor performance metrics
- [ ] Test on at least 3 platforms
- [ ] Clear CDN cache if needed
- [ ] Update platform caches (Facebook, Twitter, LinkedIn)

### Rollback Checklist (if needed)

- [ ] Identify root cause of issue
- [ ] Decide if rollback necessary
- [ ] Communicate to stakeholders
- [ ] Execute rollback procedure
- [ ] Verify rollback successful
- [ ] Monitor system after rollback
- [ ] Document incident
- [ ] Plan fix for next deployment

---

## Monitoring Checklist

Set up monitoring for production.

### Metrics to Monitor

- [ ] Social card generation time (p50, p95, p99)
- [ ] Cache hit rate (target: >95%)
- [ ] Error rate (target: <0.1%)
- [ ] 404 rate for social cards
- [ ] 503 rate (rsvg-convert unavailable)
- [ ] Image file sizes (average, max)
- [ ] Hash mismatch redirect rate
- [ ] Memory usage during generation
- [ ] Concurrent request handling

### Alerts to Configure

- [ ] Alert if p95 generation time > 1s
- [ ] Alert if error rate > 1%
- [ ] Alert if 503 rate > 0.1% (rsvg-convert issues)
- [ ] Alert if cache hit rate < 90%
- [ ] Alert if memory usage > 80%
- [ ] Alert if hash mismatch rate > 10% (unusual)

### Logs to Collect

- [ ] Social card generation requests
- [ ] Hash mismatch redirects
- [ ] SVG rendering errors
- [ ] PNG conversion errors
- [ ] 404 errors for missing entities
- [ ] Performance metrics (generation time)
- [ ] Cache hits vs misses

---

## Troubleshooting Checklist

Use when issues arise.

### Social Card Not Generating

- [ ] Check if `rsvg-convert` is installed: `rsvg-convert --version`
- [ ] Check server logs for errors
- [ ] Verify entity exists in database
- [ ] Test SVG template rendering manually
- [ ] Check file system permissions
- [ ] Verify temp directory exists and writable
- [ ] Check memory usage (may be exhausted)

### Image Not Loading on Platforms

- [ ] Verify URL is absolute (https://domain.com/path)
- [ ] Check HTTPS is enabled
- [ ] Test URL directly in browser
- [ ] Verify no authentication required
- [ ] Check CORS headers (if needed)
- [ ] Test image file size < 8MB
- [ ] Clear platform cache

### Performance Issues

- [ ] Check `rsvg-convert` performance: `time rsvg-convert test.svg -o test.png`
- [ ] Review SVG template complexity
- [ ] Check for memory leaks
- [ ] Monitor concurrent requests
- [ ] Verify caching is working
- [ ] Check database query performance
- [ ] Review server resources (CPU, memory)

### Hash Mismatch Issues

- [ ] Verify hash generation logic hasn't changed
- [ ] Check if entity data changed
- [ ] Review fingerprint fields included in hash
- [ ] Test hash generation manually
- [ ] Check for timezone issues in timestamps
- [ ] Verify JSON encoding is deterministic

---

## Documentation Checklist

Ensure documentation is up to date.

### Technical Documentation

- [ ] ADRs reflect current implementation
- [ ] API documentation updated
- [ ] Code comments accurate
- [ ] README updated with new features
- [ ] CHANGELOG updated
- [ ] Migration guides written (if needed)

### User Documentation

- [ ] SEO best practices guide updated
- [ ] Testing checklists current
- [ ] Platform validation guide current
- [ ] Troubleshooting guide complete
- [ ] Examples tested and working

---

## Continuous Improvement Checklist

Regularly review and improve the system.

### Monthly Reviews

- [ ] Review error logs for patterns
- [ ] Analyze performance metrics
- [ ] Check cache hit rates
- [ ] Review user feedback
- [ ] Identify optimization opportunities
- [ ] Update documentation as needed

### Quarterly Reviews

- [ ] Platform validator changes (Facebook, Twitter, etc.)
- [ ] Schema.org updates
- [ ] Open Graph protocol changes
- [ ] Performance benchmark review
- [ ] Security audit
- [ ] Dependency updates

---

## Quick Reference

### Run All Checks

```bash
# Code quality
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer

# Tests
mix test
mix test --cover

# Validation
APP_URL=http://localhost:4000 elixir test/validation/social_card_validator.exs

# Performance
mix test test/eventasaurus_web/controllers/social_card_performance_test.exs
```

### Platform Validators

- **Facebook:** https://developers.facebook.com/tools/debug/
- **Twitter:** https://cards-dev.twitter.com/validator
- **LinkedIn:** https://www.linkedin.com/post-inspector/
- **Google:** https://search.google.com/test/rich-results

### Target Metrics

- Generation time: < 500ms
- Cached time: < 50ms
- Image size: < 200KB (optimal), < 500KB (acceptable)
- Error rate: < 0.1%
- Cache hit rate: > 95%

---

**Last Updated:** 2025-01-29
**Related Documents:**
- [SEO Best Practices Guide](seo_best_practices.md)
- [Platform Validation Guide](platform_validation_guide.md)
- [ADR 002: Social Card Architecture](adr/002-social-card-architecture.md)
