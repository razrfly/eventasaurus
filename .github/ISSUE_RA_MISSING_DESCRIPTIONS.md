# Resident Advisor Events Missing Descriptions in JSON-LD

## Issue Summary

Resident Advisor events are missing descriptions in the JSON-LD schema output, resulting in incomplete SEO metadata. This affects Google's ability to display rich event results and reduces the quality of search engine listings.

## Example

**Event:** "Unsound Kraków 2025: LATTICE - Moin / Abdullah Miniawy / Artur Rumiński"
**URL:** https://event.ngrok.io/activities/unsound-krakow-2025-lattice-moin-laznia-nowa-theatre-251008
**Issue:** JSON-LD schema shows "Missing field 'description' (optional)"

## Root Cause Analysis

### 1. GraphQL API Limitation

The Resident Advisor GraphQL event listings API **only provides descriptions for editorial picks** (featured events):

**Location:** `lib/eventasaurus_discovery/sources/resident_advisor/client.ex:131-187`

```graphql
query GET_EVENT_LISTINGS {
  eventListings {
    data {
      event {
        # ... other fields ...
        pick {
          id
          blurb  # ← Only available for featured events
        }
      }
    }
  }
}
```

**Supporting Documentation:** `docs/resident-advisor-phase1-research.md:144`
> **Editorial:**
> - `pick.blurb` - Editorial description (if featured)

### 2. Transformer Only Extracts Pick Blurb

**Location:** `lib/eventasaurus_discovery/sources/resident_advisor/transformer.ex:236-245`

```elixir
defp extract_description(event) do
  # Use editorial pick blurb if available
  pick_blurb = get_in(event, ["pick", "blurb"])

  if pick_blurb && pick_blurb != "" do
    pick_blurb
  else
    nil  # ← Most events have no description
  end
end
```

**Result:** ~90% of RA events have `nil` description because they're not editorial picks.

### 3. JSON-LD Schema Generation

**Location:** `lib/eventasaurus_web/json_ld/public_event_schema.ex`

The schema correctly checks for description from sources, but since the RA transformer returns `nil`, no description is included in the JSON-LD output.

## Impact

### SEO Impact
- **Severity:** Medium-High
- Missing descriptions reduce click-through rates in search results
- Google may not display event as a rich result
- Event pages appear less informative in search listings
- Competitor events with descriptions rank better

### User Experience Impact
- Users see less information when sharing RA events on social media
- Event previews lack context and appeal

## Investigation: Potential Solutions

### Solution 1: Event Detail Page Scraping (Recommended)

**Pattern:** Follow the Karnet scraper's two-phase approach:
- Phase 1: Fetch event listings from GraphQL (current)
- Phase 2: Scrape individual event pages for full descriptions

**Example:** `lib/eventasaurus_discovery/sources/karnet/jobs/event_detail_job.ex:61-74`

```elixir
case Client.fetch_page(url) do
  {:ok, html} ->
    process_event_html(html, url, source_id, event_metadata)
end
```

**RA Event URL:** Available in `event.contentUrl` (e.g., "events/2234469")
**Full URL:** `https://ra.co/events/2234469`

**Pros:**
- Guaranteed to get description (visible on event page)
- Can extract additional metadata (genres, full lineup, etc.)
- Proven pattern in our codebase

**Cons:**
- Requires HTML parsing
- Slower than GraphQL-only approach
- More requests to RA (rate limiting considerations)

### Solution 2: GraphQL Event Detail Query

**Status:** Needs Research

Investigate if RA's GraphQL API supports querying individual events with more fields:

```graphql
query GET_EVENT_DETAIL($eventId: ID!) {
  event(id: $eventId) {
    id
    title
    description  # ← Check if this field exists
    # ... other fields
  }
}
```

**Pros:**
- Faster than HTML scraping
- Cleaner implementation
- Better error handling

**Cons:**
- May not exist in RA's GraphQL schema
- Requires API research/testing

### Solution 3: Fallback to Generated Description

**Pattern:** Generate description from available data if none exists:

```elixir
def generate_fallback_description(event) do
  performers = event.performers |> Enum.map(& &1.name) |> Enum.join(", ")
  venue_name = event.venue.name

  "#{performers} at #{venue_name}"
end
```

**Pros:**
- Simple implementation
- Works immediately
- Better than no description

**Cons:**
- Generic descriptions
- Not as SEO-effective as real descriptions
- May not be accurate for all event types

## Recommendation

**Phase 1:** Implement Solution 3 (Fallback Description) immediately for better-than-nothing SEO.

**Phase 2:** Research Solution 2 (GraphQL Event Detail Query) to determine if it's viable.

**Phase 3:** If GraphQL doesn't provide descriptions, implement Solution 1 (Event Detail Scraping) following the Karnet pattern.

## Testing

To verify the fix:

1. Run scraper for RA events
2. Check public_event_sources table for description_translations
3. Visit event page and check JSON-LD schema in HTML source
4. Verify description appears in `<script type="application/ld+json">`
5. Test with Google's Rich Results Test: https://search.google.com/test/rich-results

## Related Files

- `lib/eventasaurus_discovery/sources/resident_advisor/client.ex` - GraphQL queries
- `lib/eventasaurus_discovery/sources/resident_advisor/transformer.ex` - Data transformation
- `lib/eventasaurus_web/json_ld/public_event_schema.ex` - JSON-LD generation
- `lib/eventasaurus_discovery/sources/karnet/jobs/event_detail_job.ex` - Reference implementation
- `docs/resident-advisor-phase1-research.md` - API research

## Priority

**Medium-High** - SEO impact is significant but not breaking functionality.

## Labels

- `scraper:resident-advisor`
- `seo`
- `enhancement`
- `needs-research`
