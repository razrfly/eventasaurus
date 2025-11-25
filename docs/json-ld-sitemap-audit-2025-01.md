# JSON-LD & Sitemap Audit - January 2025

**Audit Date:** 2025-01-25
**Issue:** https://github.com/razrfly/eventasaurus/issues/2421
**Auditor:** Claude Code

## Executive Summary

This audit assessed JSON-LD structured data and sitemap coverage for all aggregation pages in Eventasaurus (Wombie). The audit identified significant gaps in both sitemap inclusion and schema.org markup for movie pages and content aggregation types.

### Key Findings

- ✅ **Strong Foundation**: JSON-LD infrastructure exists with well-structured schema modules
- ✅ **Good Coverage**: Individual events, cities, venues, and containers have JSON-LD
- ❌ **Critical Gap**: Movie aggregation pages missing from sitemap AND lacking JSON-LD
- ❌ **Missing Aggregations**: Content aggregation pages (trivia, food, social, etc.) missing from sitemap
- ⚠️  **Open Graph**: Component exists but implementation coverage unclear

---

## 1. Aggregation Page Types Inventory

### Current Aggregation Types (URL Format)

Based on `AggregationTypeSlug` module and routing analysis:

| Type | URL Pattern | Schema.org Type | Example |
|------|-------------|-----------------|---------|
| Movies | `/c/:city/movies/:slug` | ScreeningEvent | `/c/krakow/movies/dune-part-two` |
| Social | `/:city/social/:id` | SocialEvent | `/krakow/social/trivia-night` |
| Food | `/:city/food/:id` | FoodEvent | `/krakow/food/wine-tasting` |
| Music | `/:city/music/:id` | MusicEvent | `/krakow/music/jazz-fest` |
| Comedy | `/:city/comedy/:id` | ComedyEvent | `/krakow/comedy/standup` |
| Dance | `/:city/dance/:id` | DanceEvent | `/krakow/dance/ballet` |
| Classes | `/:city/classes/:id` | EducationEvent | `/krakow/classes/cooking` |
| Sports | `/:city/sports/:id` | SportsEvent | `/krakow/sports/football` |
| Theater | `/:city/theater/:id` | TheaterEvent | `/krakow/theater/hamlet` |
| Festivals | `/c/:city/festivals/:slug` | Festival | `/c/krakow/festivals/krakow-film-festival` |

**Note**: Festivals also exist as "containers" with their own sitemap inclusion logic.

### Additional Aggregation Sources

The following specialized content sources exist but their aggregation pages need verification:

- **Trivia/Quiz Events**: Multiple sources (pubquiz, inquizition, speed_quizzing, geeks_who_drink, quizmeisters)
  - Schema.org type: `SocialEvent` (per PublicEventSchema.ex line 167)
  - Likely aggregated under `/social/` routes

- **Restaurant/Dining**: Not yet identified as separate aggregation
  - Would fall under `FoodEvent` type if implemented

---

## 2. Sitemap Coverage Audit

### Currently Included in Sitemap ✅

From `lib/eventasaurus/sitemap.ex`:

1. **Static Pages** (lines 93-140)
   - Home `/`
   - Activities listing `/activities`
   - About, privacy, terms, etc.

2. **Individual Activities** (lines 144-186)
   - `/activities/:slug` for all public events
   - Dynamic priority based on event date
   - Weekly changefreq for future events

3. **Cities** (lines 189-270)
   - Main city page `/c/:city`
   - City venues listing `/c/:city/venues`
   - City events `/c/:city/events`
   - City search `/c/:city/search`
   - City containers `/c/:city/festivals`, `/c/:city/conferences`, etc.

4. **Venues** (lines 273-299)
   - Individual venue pages `/c/:city/venues/:slug`

5. **Containers** (lines 302-346)
   - Festivals, conferences, tours, series, exhibitions, tournaments
   - City-scoped: `/c/:city/:container_type/:slug`

### Missing from Sitemap ❌

1. **Movie Aggregation Pages**
   - Route exists: `/c/:city/movies/:movie_slug`
   - LiveView: `PublicMovieScreeningsLive`
   - **NOT in sitemap generation logic**

2. **Content Aggregation Pages**
   - Routes exist: `/:city/:content_type/:identifier`
   - LiveView: `AggregatedContentLive`
   - Types: social, food, music, comedy, dance, classes, sports, theater
   - **NOT in sitemap generation logic**

### Impact Assessment

**SEO Impact**: HIGH
- Movie pages are user-facing content with significant traffic potential
- Missing from Google's crawl prioritization
- Lost rich result opportunities for movie screenings

**Discoverability**: MEDIUM
- Content aggregation pages likely low traffic currently
- But critical for vertical search (e.g., "comedy events in Krakow")

---

## 3. JSON-LD Implementation Audit

### Existing JSON-LD Modules ✅

Located in `lib/eventasaurus_web/json_ld/`:

1. **`PublicEventSchema`** - Individual event pages
   - Supports 21 schema.org Event subtypes
   - Includes: location, performers, images, offers, organizer
   - Special handling for ScreeningEvent with `workPresented` (Movie)
   - ✅ **Excellent implementation**

2. **`CitySchema`** - City pages
   - Implementation details not audited
   - ✅ **Exists**

3. **`LocalBusinessSchema`** - Venue pages
   - Presumably for venue detail pages
   - ✅ **Exists**

4. **`BreadcrumbListSchema`** - Breadcrumb navigation
   - For navigation breadcrumbs
   - ✅ **Exists**

### JSON-LD Rendering Infrastructure ✅

From `lib/eventasaurus_web/components/layouts/root.html.heex` (lines 41-46):

```heex
<!-- JSON-LD Structured Data -->
<%= if assigns[:json_ld] do %>
  <script type="application/ld+json">
    <%= Phoenix.HTML.raw(assigns[:json_ld]) %>
  </script>
<% end %>
```

**Status**: ✅ Infrastructure in place, just needs assigns

### Missing JSON-LD Implementations ❌

#### 1. Movie Aggregation Pages

**File**: `lib/eventasaurus_web/live/public_movie_screenings_live.ex`

**Current State**:
- ❌ No JSON-LD schema generation
- ❌ No assigns[:json_ld] assignment
- ❌ Missing schema.org Movie type markup

**Required Properties** (per schema.org/Movie):
- `@context`: https://schema.org
- `@type`: Movie
- `name`: Movie title (✅ available: `@movie.title`)
- `description`: Movie description
- `image`: Movie poster (TODO in PublicEventSchema line 476-478)
- `url`: Canonical page URL
- `datePublished`: Release date (if available)
- `genre`: Movie genres (if available)
- `actor`: Cast list (if available in metadata)
- `director`: Director (if available in metadata)

**Recommended Properties**:
- `aggregateRating`: If ratings data available
- `trailer`: Movie trailer URL
- `duration`: Runtime (if available)
- `inLanguage`: Movie language

**Also Consider**: `ItemList` schema for the list of screenings/venues

#### 2. Content Aggregation Pages

**File**: `lib/eventasaurus_web/live/aggregated_content_live.ex`

**Current State**:
- ❌ No JSON-LD schema generation
- ❌ No assigns[:json_ld] assignment

**Required Implementation**:
- `ItemList` schema for list of events
- Individual items should reference appropriate Event subtype
- Include: numberOfItems, itemListElement array

**Example Structure**:
```json
{
  "@context": "https://schema.org",
  "@type": "ItemList",
  "name": "Comedy Events in Krakow",
  "description": "Upcoming comedy shows and events in Krakow",
  "numberOfItems": 15,
  "itemListElement": [
    {
      "@type": "ListItem",
      "position": 1,
      "item": {
        "@type": "ComedyEvent",
        "@id": "https://wombie.com/activities/standup-night-123",
        "name": "Standup Comedy Night",
        "...": "..."
      }
    }
  ]
}
```

---

## 4. Open Graph Meta Tags Audit

### Open Graph Infrastructure ✅

**Component**: `lib/eventasaurus_web/components/open_graph_component.ex`

**Features**:
- ✅ Comprehensive OG tags (type, title, description, image, url, site_name, locale)
- ✅ Twitter Card support
- ✅ Image dimension attributes
- ✅ Automatic absolute URL conversion

**Usage Pattern**:
```elixir
# In LiveView mount/handle_params:
assigns =
  socket
  |> assign(:open_graph, OpenGraphComponent.open_graph_tags(%{
      type: "event",
      title: event.title,
      description: description,
      image_url: image_url,
      url: canonical_url
    }))
```

### Current Implementation Status

**Layout Fallback** (root.html.heex lines 48-79):
- ✅ Fallback OG tags if no component used
- ✅ Uses assigns[:meta_title], assigns[:meta_description], assigns[:meta_image]
- ⚠️  Fallback may lack proper typing (always "website")

### Missing Open Graph ❌

**Where to Check**:
1. ❌ Movie aggregation pages (`PublicMovieScreeningsLive`)
2. ❌ Content aggregation pages (`AggregatedContentLive`)
3. ⚠️  Individual event pages - **needs verification**
4. ⚠️  Venue pages - **needs verification**
5. ⚠️  City pages - **needs verification**

**Recommended OG Types**:
- Movie pages: `og:type="video.movie"` (per OG protocol)
- Event aggregations: `og:type="website"` (collections)
- Individual events: `og:type="article"` or custom event type

---

## 5. Validation Testing

### Tools to Use

1. **Google Rich Results Test**
   - https://search.google.com/test/rich-results
   - Test URL: https://wombie.com/c/krakow/movies/dune-part-two
   - Expected: Should show Movie rich result preview

2. **Schema.org Validator**
   - https://validator.schema.org/
   - Validates JSON-LD syntax
   - Checks required/recommended properties

3. **Facebook Sharing Debugger**
   - https://developers.facebook.com/tools/debug/
   - Tests OG tags
   - Shows preview card

4. **Twitter Card Validator**
   - https://cards-dev.twitter.com/validator
   - Tests Twitter Card tags
   - Shows Twitter preview

5. **Google Search Console**
   - Check "Enhancements" → "Unparsed structured data"
   - Monitor for errors after implementation

### Test URLs (Production)

Once implemented, test these URLs:

```
# Movie pages
https://wombie.com/c/krakow/movies/dune-part-two
https://wombie.com/c/warsaw/movies/oppenheimer

# Aggregation pages
https://wombie.com/krakow/social/trivia-nights
https://wombie.com/krakow/food/wine-tastings
https://wombie.com/krakow/comedy/standup-shows

# Existing (should already work)
https://wombie.com/activities/some-event-slug
https://wombie.com/c/krakow/venues/some-venue
```

---

## 6. Gap Analysis

### Critical Gaps (P0 - Fix Immediately)

1. **Movie Pages Missing from Sitemap**
   - Impact: Search engines not discovering movie pages
   - Effort: LOW - Add to `sitemap.ex` stream_urls
   - Files: `lib/eventasaurus/sitemap.ex`

2. **Movie Pages Missing JSON-LD**
   - Impact: No rich results for movie screenings
   - Effort: MEDIUM - Create MovieSchema module or extend PublicEventSchema
   - Files: `lib/eventasaurus_web/json_ld/movie_schema.ex` (new)
   - Update: `lib/eventasaurus_web/live/public_movie_screenings_live.ex`

3. **Movie Pages Missing Open Graph**
   - Impact: Poor social media previews
   - Effort: LOW - Use existing OpenGraphComponent
   - Files: `lib/eventasaurus_web/live/public_movie_screenings_live.ex`

### High Priority Gaps (P1 - Fix Soon)

4. **Content Aggregation Pages Missing from Sitemap**
   - Impact: Aggregation pages not indexed
   - Effort: MEDIUM - Query aggregated_event_groups table
   - Files: `lib/eventasaurus/sitemap.ex`

5. **Content Aggregation Pages Missing JSON-LD**
   - Impact: No ItemList rich results
   - Effort: MEDIUM - Create ItemListSchema module
   - Files: `lib/eventasaurus_web/json_ld/item_list_schema.ex` (new)
   - Update: `lib/eventasaurus_web/live/aggregated_content_live.ex`

6. **Content Aggregation Pages Missing Open Graph**
   - Impact: Poor social sharing
   - Effort: LOW - Use existing OpenGraphComponent
   - Files: `lib/eventasaurus_web/live/aggregated_content_live.ex`

### Medium Priority (P2 - Nice to Have)

7. **Verify Existing Page Open Graph**
   - Audit: Events, venues, cities
   - Ensure using OpenGraphComponent vs fallback
   - Verify og:type correctness

8. **Enhanced Movie Metadata**
   - Add: director, actors, genre, duration
   - Requires: Movie metadata enrichment
   - Dependencies: External API integration (TMDb, OMDb)

9. **AggregateRating for Movies**
   - Add: rating data if available
   - Source: TMDb, IMDb, Rotten Tomatoes
   - Dependencies: Rating data integration

---

## 7. Recommendations

### Immediate Actions (Week 1)

1. **Add Movie Pages to Sitemap**

```elixir
# In lib/eventasaurus/sitemap.ex
# Add after container_urls/1

defp movie_urls(opts) do
  base_url = get_base_url(opts)

  from(m in Movie,
    join: em in "event_movies", on: em.movie_id == m.id,
    join: pe in PublicEvent, on: pe.id == em.event_id,
    join: v in Venue, on: v.id == pe.venue_id,
    join: c in City, on: c.id == v.city_id,
    select: %{
      movie_slug: m.slug,
      city_slug: c.slug,
      updated_at: m.updated_at
    },
    where: c.discovery_enabled == true and not is_nil(m.slug),
    distinct: [m.id, c.id]
  )
  |> Repo.stream()
  |> Stream.map(fn movie ->
    lastmod = if movie.updated_at,
      do: NaiveDateTime.to_date(movie.updated_at),
      else: Date.utc_today()

    %Sitemapper.URL{
      loc: "#{base_url}/c/#{movie.city_slug}/movies/#{movie.movie_slug}",
      changefreq: :weekly,
      priority: 0.8,
      lastmod: lastmod
    }
  end)
end

# Update stream_urls/1 to include movie_urls
def stream_urls(opts \\ []) do
  [
    static_urls(opts),
    activity_urls(opts),
    city_urls(opts),
    venue_urls(opts),
    container_urls(opts),
    movie_urls(opts)  # ADD THIS LINE
  ]
  |> Enum.reduce(Stream.concat([]), fn stream, acc ->
    Stream.concat(acc, stream)
  end)
end
```

2. **Create MovieSchema Module**

```elixir
# Create lib/eventasaurus_web/json_ld/movie_schema.ex

defmodule EventasaurusWeb.JsonLd.MovieSchema do
  @moduledoc """
  Generates JSON-LD structured data for movie aggregation pages.
  """

  def generate(movie, city, venues_with_screenings) do
    %{
      "@context" => "https://schema.org",
      "@type" => "Movie",
      "name" => movie.title,
      "description" => generate_description(movie, venues_with_screenings),
      "url" => build_canonical_url(movie, city)
    }
    |> add_image(movie)
    |> add_screening_list(venues_with_screenings, city)
    |> Jason.encode!()
  end

  defp generate_description(movie, venues) do
    venue_count = length(venues)
    screening_count = Enum.sum(Enum.map(venues, fn {_v, info} -> info.count end))

    "Watch #{movie.title} at #{venue_count} cinemas in the city. " <>
    "#{screening_count} showtimes available."
  end

  # ... more implementation
end
```

3. **Add JSON-LD to PublicMovieScreeningsLive**

```elixir
# In handle_params/3, after assigns
socket =
  socket
  |> assign(:json_ld, EventasaurusWeb.JsonLd.MovieSchema.generate(
      movie, city, venues_with_info
    ))
  |> assign(:open_graph, build_movie_og_tags(movie, city))
```

### Short-term Actions (Week 2-3)

4. **Add Aggregation Pages to Sitemap**
   - Query PublicEventAggregatedGroup table
   - Generate URLs for each content_type + identifier
   - Include all cities where aggregation has events

5. **Create ItemListSchema for Aggregations**
   - Reusable module for any event list
   - Used by aggregation pages
   - Include proper Event subtype nesting

6. **Add Open Graph to All Aggregation Pages**
   - Movie pages
   - Content aggregation pages
   - Verify existing pages

### Long-term Enhancements (Month 2+)

7. **Enhanced Movie Metadata**
   - Integrate TMDb/OMDb API
   - Enrich movie records with: genre, director, actors, runtime
   - Add to JSON-LD output

8. **Rating Integration**
   - Source ratings from TMDb, IMDb
   - Add aggregateRating to Movie schema
   - Display on pages

9. **Automated Testing**
   - CI/CD validation of JSON-LD
   - Schema.org validator in test suite
   - Prevent regressions

---

## 8. Implementation Priority Matrix

| Task | Impact | Effort | Priority | Timeline |
|------|--------|--------|----------|----------|
| Add movie pages to sitemap | HIGH | LOW | P0 | Week 1 |
| Movie JSON-LD schema | HIGH | MEDIUM | P0 | Week 1 |
| Movie Open Graph tags | MEDIUM | LOW | P0 | Week 1 |
| Aggregation sitemap | MEDIUM | MEDIUM | P1 | Week 2 |
| Aggregation JSON-LD | MEDIUM | MEDIUM | P1 | Week 2 |
| Aggregation Open Graph | MEDIUM | LOW | P1 | Week 2 |
| Verify existing OG tags | LOW | LOW | P2 | Week 3 |
| Enhanced movie metadata | MEDIUM | HIGH | P2 | Month 2 |
| Rating integration | LOW | HIGH | P3 | Month 3 |

---

## 9. Success Metrics

### Immediate (Post-Implementation)

- ✅ All movie pages appear in sitemap.xml
- ✅ All aggregation pages appear in sitemap.xml
- ✅ Movie pages validate in Google Rich Results Test
- ✅ Aggregation pages validate in Schema.org Validator
- ✅ OG tags generate proper previews in FB Sharing Debugger

### 30 Days Post-Implementation

- 📈 Google Search Console shows Movie rich results
- 📈 Increase in organic traffic to movie pages
- 📈 Improved click-through rate from search results
- 📈 Social media shares generate proper preview cards

### 90 Days Post-Implementation

- 📈 Movie pages indexed in Google
- 📈 Aggregation pages indexed in Google
- 📈 Reduced bounce rate on movie/aggregation pages
- 📈 Increased user engagement from organic search

---

## 10. Files Modified (Checklist)

### Sitemap Changes
- [ ] `lib/eventasaurus/sitemap.ex` - Add movie_urls/1 function
- [ ] `lib/eventasaurus/sitemap.ex` - Add aggregation_urls/1 function
- [ ] `lib/eventasaurus/sitemap.ex` - Update stream_urls/1

### New JSON-LD Schemas
- [ ] `lib/eventasaurus_web/json_ld/movie_schema.ex` - NEW
- [ ] `lib/eventasaurus_web/json_ld/item_list_schema.ex` - NEW

### LiveView Updates
- [ ] `lib/eventasaurus_web/live/public_movie_screenings_live.ex` - Add JSON-LD + OG
- [ ] `lib/eventasaurus_web/live/aggregated_content_live.ex` - Add JSON-LD + OG

### Tests
- [ ] `test/eventasaurus/sitemap_test.exs` - Add movie URL tests
- [ ] `test/eventasaurus/sitemap_test.exs` - Add aggregation URL tests
- [ ] `test/eventasaurus_web/json_ld/movie_schema_test.exs` - NEW
- [ ] `test/eventasaurus_web/json_ld/item_list_schema_test.exs` - NEW

---

## 11. References

### Documentation
- [Schema.org Movie](https://schema.org/Movie)
- [Schema.org ItemList](https://schema.org/ItemList)
- [Schema.org ScreeningEvent](https://schema.org/ScreeningEvent)
- [Google Movie Rich Results](https://developers.google.com/search/docs/appearance/structured-data/movie)
- [Open Graph Protocol](https://ogp.me/)
- [Open Graph Movie Type](https://ogp.me/#type_video.movie)

### Tools
- [Google Rich Results Test](https://search.google.com/test/rich-results)
- [Schema.org Validator](https://validator.schema.org/)
- [Facebook Sharing Debugger](https://developers.facebook.com/tools/debug/)
- [Twitter Card Validator](https://cards-dev.twitter.com/validator)

### Internal Documentation
- Source Implementation Guide: `docs/source-implementation-guide.md`
- Scraper Monitoring Guide: `docs/scraper-monitoring-guide.md`

---

**End of Audit Report**

*Generated: 2025-01-25*
*Issue: #2421*
*Status: Recommendations Pending Implementation*
