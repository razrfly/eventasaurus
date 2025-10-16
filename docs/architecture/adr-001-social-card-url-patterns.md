# ADR-001: Social Card URL Patterns and Hash-Based Cache Busting

**Status**: Accepted
**Date**: 2025-10-16
**Authors**: Social Card Remediation Team
**Context**: Issue #1781 - Social card functionality broken due to URL pattern mismatches

## Context and Problem Statement

The social card system was experiencing critical issues:

1. **URL Pattern Mismatch**: HashGenerator produced URLs like `/event-slug/social-card-hash.png` but router expected `/events/event-slug/social-card-hash.png`
2. **Localhost URLs**: Social media platforms couldn't access `http://localhost:4000` URLs during development
3. **Architectural Fragmentation**: Two separate hash generators (HashGenerator, PollHashGenerator) with no unified interface
4. **Lack of Documentation**: No clear guidelines for adding new social card types

## Decision Drivers

- **User Experience**: Social cards must work reliably for event and poll sharing
- **Developer Experience**: Simple, consistent patterns for adding new entity types
- **Performance**: Efficient cache busting without database queries
- **Maintainability**: Centralized logic to reduce duplication
- **Extensibility**: Easy to add new entity types (groups, activities, etc.)

## Considered Options

### Option 1: Database-Based URLs (Rejected)
**Pattern**: `/events/:id/social-card.png`

**Pros**:
- Simple URL structure
- No hash generation needed

**Cons**:
- Requires database lookup for every social card request
- No automatic cache invalidation when content changes
- Performance bottleneck at scale

### Option 2: Timestamp-Based Cache Busting (Rejected)
**Pattern**: `/event-slug/social-card.png?t=1234567890`

**Pros**:
- Simple implementation
- Works with query parameters

**Cons**:
- Query parameters often ignored by social media crawlers
- No content-based invalidation (cache breaks even if content unchanged)
- Race conditions during rapid updates

### Option 3: Hash-Based URL Patterns (Accepted)
**Pattern**:
- Events: `/:event-slug/social-card-:hash.png`
- Polls: `/:event-slug/polls/:poll-number/social-card-:hash.png`

**Pros**:
- Content-based cache busting (hash changes only when content changes)
- No database queries needed in router
- Social media platforms cache correctly
- Clean, predictable URLs

**Cons**:
- Requires hash generation logic
- Slightly more complex URL patterns

## Decision Outcome

**Chosen Option**: Hash-Based URL Patterns (Option 3)

### Implementation Details

#### Phase 1: Fix URL Pattern Mismatch (Completed)
- Modified HashGenerator to remove `/events/` prefix
- Updated router to match new pattern: `get "/:slug/social-card-:hash/*rest"`
- Ensured all existing functionality remains intact

#### Phase 2: Fix External URL Generation (Completed)
- Created `EventasaurusWeb.UrlHelper` module for centralized URL building
- Respects `BASE_URL` environment variable for development (ngrok support)
- Falls back to config `:base_url` then `Endpoint.url()`
- Updated `public_event_live.ex` and `poll_helpers.ex` to use UrlHelper

#### Phase 3: Architectural Unification (Completed)
- Created `Eventasaurus.SocialCards.UrlBuilder` module
- Unified interface for all entity types using entity-type atoms (`:event`, `:poll`)
- Utility functions: `detect_entity_type/1`, `parse_path/1`, `extract_hash/1`, `validate_hash/4`
- Comprehensive test coverage (26 tests)
- Updated all integrations to use UrlBuilder

#### Phase 4: Documentation and Safeguards (Current)
- Architecture Decision Record (this document)
- Integration tests for route reachability
- Developer guide for adding new entity types
- CI/CD validation checks

### Hash Generation Strategy

**Algorithm**: SHA-256 with truncated 8-character hex output

**Event Hash Inputs**:
```elixir
"#{event.slug}-#{event.title}-#{event.updated_at}"
```

**Poll Hash Inputs**:
```elixir
"#{poll.number}-#{poll.title}-#{poll.updated_at}"
```

**Why This Works**:
- Content changes → hash changes → new URL → cache invalidation
- No content changes → same hash → same URL → cache hits
- Collisions extremely unlikely (2^32 possibilities per entity)

### URL Patterns

#### Events
**Pattern**: `/:event-slug/social-card-:hash.png`

**Example**: `/tech-meetup/social-card-abc12345.png`

**Router Match**:
```elixir
get "/:slug/social-card-:hash/*rest", SocialCardController, :show
```

#### Polls
**Pattern**: `/:event-slug/polls/:poll-number/social-card-:hash.png`

**Example**: `/tech-meetup/polls/1/social-card-def67890.png`

**Router Match**:
```elixir
get "/:event_slug/polls/:poll_number/social-card-:hash/*rest",
    PollSocialCardController, :show
```

## Consequences

### Positive

1. **Reliable Cache Busting**: Social media platforms cache correctly and invalidate automatically
2. **No Database Queries**: Router doesn't need to hit database for every social card request
3. **Unified Architecture**: Single UrlBuilder interface for all entity types
4. **Extensible**: Adding new entity types (groups, activities) follows the same pattern
5. **Developer Experience**: Clear patterns documented in developer guide
6. **Testable**: Hash validation ensures URL integrity

### Negative

1. **URL Complexity**: Slightly more complex than simple `/events/:id/social-card.png`
2. **Hash Maintenance**: Need to ensure hash inputs include all cache-relevant fields
3. **Migration**: Existing social card URLs needed updating (one-time cost, now complete)

### Neutral

1. **Learning Curve**: New developers need to understand hash-based cache busting
2. **Documentation**: Requires maintaining ADR and developer guide (minimal overhead)

## Validation and Testing

### Automated Tests
- 26 UrlBuilder unit tests covering all functionality
- Integration tests for route reachability
- CI/CD validation checks

### Manual Testing
- Social media debuggers (Facebook, Twitter, LinkedIn)
- ngrok for localhost testing during development
- Playwright end-to-end tests for actual URL access

### Monitoring
- Track 404 errors for social card routes
- Monitor cache hit/miss ratios
- Alert on hash generation failures

## Developer Workflow

### Development Environment
```bash
# Start Phoenix server
mix phx.server

# In separate terminal, start ngrok
ngrok http 4000

# Set BASE_URL environment variable
export BASE_URL="https://your-subdomain.ngrok.io"

# Restart Phoenix server with BASE_URL
BASE_URL="https://your-subdomain.ngrok.io" mix phx.server
```

### Testing Social Cards
```bash
# Test with social media debuggers
# Facebook: https://developers.facebook.com/tools/debug/
# Twitter: https://cards-dev.twitter.com/validator
# LinkedIn: https://www.linkedin.com/post-inspector/
```

### Adding New Entity Types

See developer guide: `docs/guides/adding-social-card-types.md`

Basic steps:
1. Create hash generator module (follow existing patterns)
2. Add entity type to UrlBuilder
3. Add router routes
4. Create controller
5. Add tests

## Related Documentation

- [Social Cards Development Guide](../../SOCIAL_CARDS_DEV.md) - ngrok setup and testing
- [Developer Guide: Adding Social Card Types](../guides/adding-social-card-types.md) - Implementation guide
- [UrlBuilder API Documentation](../../lib/eventasaurus/social_cards/url_builder.ex) - Module documentation

## References

- Issue #1781: Social card remediation plan (4 phases)
- Issue #1778: Original social card issues
- Issue #1780: Previous refactoring attempts
- Phoenix Router Documentation: https://hexdocs.pm/phoenix/routing.html
- Open Graph Protocol: https://ogp.me/

## Future Considerations

### Potential Enhancements

1. **Group Social Cards**: Following the same pattern
   - Pattern: `/:group-slug/social-card-:hash.png`
   - Hash inputs: slug, name, updated_at

2. **Activity Social Cards**: For specific event activities
   - Pattern: `/:event-slug/activities/:activity-id/social-card-:hash.png`
   - Hash inputs: activity_id, title, updated_at

3. **Dynamic Themes**: Allow theme-specific social card variants
   - Pattern: `/:event-slug/social-card-:hash-:theme.png`
   - Hash inputs: event data + theme

4. **CDN Integration**: Serve social cards from CDN
   - Use UrlBuilder to generate CDN URLs
   - Maintain same hash-based cache busting

### Monitoring Metrics

- Social card 404 rate (target: <0.1%)
- Cache hit rate (target: >90%)
- Hash generation time (target: <1ms)
- Social media crawler success rate (target: >99%)

## Revision History

- 2025-10-16: Initial ADR created after Phase 3 completion
- Future revisions will be tracked here
