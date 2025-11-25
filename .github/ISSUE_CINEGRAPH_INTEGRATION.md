# Cinegraph Integration: Cross-Project Movie Linking

## Overview

Enable bidirectional linking between Eventasaurus and Cinegraph using TMDB IDs as the common reference point. This allows users to seamlessly navigate between event screenings and detailed movie information.

## Background

**Eventasaurus**: Event discovery platform with cinema screenings
**Cinegraph**: Movie discovery platform with detailed film data, cast/crew, and relationships

Both projects store TMDB (The Movie Database) IDs, providing a reliable common identifier for movies.

## Technical Analysis

### Current State

#### Eventasaurus
- **TMDB Storage**: `event.rich_external_data["tmdb"]["id"]`
- **Helper Functions**: `Event.get_tmdb_data/1`, `Event.has_tmdb_data?/1`
- **Location**: `lib/eventasaurus_app/events/event.ex:688-743`

#### Cinegraph
- **TMDB Storage**: `movie.tmdb_id` (integer field)
- **Routing**: `/movies/:id_or_slug` accepts both TMDB IDs and slugs
- **Slug Format**: `{title}-{year}` (e.g., "the-matrix-1999")
- **Production URL**: `https://cinegraph.org`
- **Location**: `lib/cinegraph_web/router.ex:30`

## Proposed Solution

### Phase 1: Eventasaurus → Cinegraph Links

Add "View on Cinegraph" links from movie events to Cinegraph movie pages.

#### Implementation

**1. Configuration Module**
```elixir
# lib/eventasaurus/integrations/cinegraph.ex
defmodule Eventasaurus.Integrations.Cinegraph do
  @moduledoc """
  Helper functions for generating Cinegraph URLs and integration.
  """

  @doc """
  Returns the Cinegraph base URL based on environment.

  Reads from CINEGRAPH_URL env variable, defaults to production.
  """
  def base_url do
    System.get_env("CINEGRAPH_URL") || "https://cinegraph.org"
  end

  @doc """
  Generates Cinegraph movie URL from event's TMDB data.

  Returns nil if event has no TMDB data.

  ## Examples

      iex> event = %Event{rich_external_data: %{"tmdb" => %{"id" => 603}}}
      iex> Cinegraph.movie_url(event)
      "https://cinegraph.org/movies/603"

      iex> event = %Event{rich_external_data: %{}}
      iex> Cinegraph.movie_url(event)
      nil
  """
  def movie_url(event) do
    case EventasaurusApp.Events.Event.get_tmdb_data(event) do
      %{"id" => tmdb_id} when is_integer(tmdb_id) ->
        "#{base_url()}/movies/#{tmdb_id}"

      _ ->
        nil
    end
  end

  @doc """
  Checks if event can link to Cinegraph (has TMDB data).
  """
  def linkable?(event) do
    EventasaurusApp.Events.Event.has_tmdb_data?(event)
  end
end
```

**2. UI Component Enhancement**

Add link to existing movie detail views:
- `lib/eventasaurus_web/components/movie_details_card.ex`
- `lib/eventasaurus_web/live/public_movie_screenings_live.ex`
- `lib/eventasaurus_web/live/public_event_show_live.ex`

Example placement (next to "View on TMDB" link):

```heex
<%= if Eventasaurus.Integrations.Cinegraph.linkable?(@event) do %>
  <a
    href={Eventasaurus.Integrations.Cinegraph.movie_url(@event)}
    target="_blank"
    rel="noopener noreferrer"
    class="inline-flex items-center gap-2 text-sm text-blue-600 hover:text-blue-800"
  >
    <span>View on Cinegraph</span>
    <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
  </a>
<% end %>
```

**3. Environment Configuration**

```bash
# .env.dev
CINEGRAPH_URL=http://localhost:4001

# .env.prod
CINEGRAPH_URL=https://cinegraph.org

# .env.test
CINEGRAPH_URL=https://cinegraph.org
```

### Phase 2: Cinegraph → Eventasaurus Links (Future)

Add "View Screenings" links from Cinegraph movie pages to Eventasaurus events.

#### Implementation Plan

**1. New Route in Eventasaurus**
```elixir
# router.ex
get "/movies/:tmdb_id/screenings", EventController, :movie_screenings
```

**2. Query Events by TMDB ID**
```elixir
# lib/eventasaurus_app/events.ex
def list_events_by_tmdb_id(tmdb_id) do
  from(e in Event,
    where: fragment("?->>'tmdb'->>'id' = ?", e.rich_external_data, ^to_string(tmdb_id)),
    where: e.start_at >= ^DateTime.utc_now(),
    order_by: [asc: e.start_at]
  )
  |> Repo.all()
end
```

**3. Cinegraph Integration Module**
```elixir
# lib/cinegraph/integrations/eventasaurus.ex
defmodule Cinegraph.Integrations.Eventasaurus do
  def screenings_url(movie) do
    base_url = System.get_env("EVENTASAURUS_URL") || "https://eventasaurus.com"
    "#{base_url}/movies/#{movie.tmdb_id}/screenings"
  end
end
```

## URL Format Options

### Option A: Simple TMDB ID (Recommended for Phase 1)
```
https://cinegraph.org/movies/603
```
**Pros**: Guaranteed to work, simple implementation
**Cons**: Less SEO-friendly

### Option B: Hybrid ID + Slug (Future Enhancement)
```
https://cinegraph.org/movies/603/the-matrix-1999
```
**Pros**: SEO-friendly, human-readable, still guaranteed resolution
**Cons**: More complex, requires slug lookup

**Recommendation**: Start with Option A for simplicity, consider Option B in future iteration.

## Testing Strategy

### Unit Tests
```elixir
# test/eventasaurus/integrations/cinegraph_test.exs
defmodule Eventasaurus.Integrations.CinegraphTest do
  use Eventasaurus.DataCase

  alias Eventasaurus.Integrations.Cinegraph
  alias EventasaurusApp.Events.Event

  describe "movie_url/1" do
    test "returns URL when event has TMDB data" do
      event = %Event{
        rich_external_data: %{"tmdb" => %{"id" => 603}}
      }

      assert Cinegraph.movie_url(event) ==
        "https://cinegraph.org/movies/603"
    end

    test "returns nil when event has no TMDB data" do
      event = %Event{rich_external_data: %{}}

      assert Cinegraph.movie_url(event) == nil
    end
  end

  describe "linkable?/1" do
    test "returns true when event has TMDB data" do
      event = %Event{
        rich_external_data: %{"tmdb" => %{"id" => 603}}
      }

      assert Cinegraph.linkable?(event)
    end

    test "returns false when event has no TMDB data" do
      event = %Event{rich_external_data: %{}}

      refute Cinegraph.linkable?(event)
    end
  end
end
```

### Integration Tests
1. Verify links appear on movie event pages
2. Test link generation with various TMDB IDs
3. Verify external links open in new tab
4. Test fallback behavior when TMDB data missing

## Benefits

### User Experience
- **Seamless Navigation**: Users can easily jump between screening times and movie details
- **Enhanced Discovery**: Event attendees discover more about films they're interested in
- **Unified Ecosystem**: Creates a cohesive experience across both platforms

### SEO Benefits
- **Cross-linking**: Bidirectional links improve SEO for both sites
- **Content Enrichment**: More contextual links increase page value
- **User Engagement**: Lower bounce rates from enhanced navigation

### Technical Benefits
- **Loose Coupling**: Independent deployment, no tight integration
- **TMDB as Source of Truth**: Reliable, stable identifiers
- **Environment Flexibility**: Easy to configure for dev/staging/prod
- **Future-Proof**: Foundation for more advanced integrations

## Future Enhancements

### Short Term
1. Add Cinegraph logo/icon to links
2. Track click-through analytics
3. Add hover previews (movie poster, rating)

### Medium Term
1. Implement Phase 2 (Cinegraph → Eventasaurus)
2. Add "View Screenings" widget on Cinegraph movie pages
3. Show screening counts on Cinegraph

### Long Term
1. Consider API integration for real-time data
2. Shared authentication (optional)
3. Cross-platform user lists (movies + events)
4. Embedded widgets (Cinegraph movie cards in Eventasaurus)

## Implementation Checklist

### Phase 1: Eventasaurus → Cinegraph
- [ ] Create `Eventasaurus.Integrations.Cinegraph` module
- [ ] Add `CINEGRAPH_URL` environment variable
- [ ] Update movie detail components with Cinegraph links
- [ ] Add unit tests for URL generation
- [ ] Add integration tests for UI links
- [ ] Update documentation
- [ ] Test in dev environment
- [ ] Deploy to staging
- [ ] Test in production
- [ ] Monitor analytics

### Phase 2: Cinegraph → Eventasaurus (Future)
- [ ] Create `/movies/:tmdb_id/screenings` route
- [ ] Implement TMDB ID query in Events context
- [ ] Create screenings list LiveView
- [ ] Add Cinegraph integration module
- [ ] Update Cinegraph movie pages with screening links
- [ ] Add tests
- [ ] Deploy and monitor

## Security Considerations

1. **External Links**: Use `rel="noopener noreferrer"` for security
2. **URL Validation**: Validate environment variables on app start
3. **Error Handling**: Graceful fallback when links fail
4. **Rate Limiting**: Consider rate limits if API integration added later

## Performance Considerations

1. **No Additional Queries**: URL generation is pure computation
2. **Caching**: Consider caching Cinegraph URLs if needed
3. **Async Loading**: Links don't block page rendering
4. **Minimal Dependencies**: No external API calls required

## Questions to Resolve

1. **Branding**: Should we use Cinegraph logo or text link?
2. **Placement**: Exact placement in UI (near TMDB link?)
3. **Analytics**: What metrics do we want to track?
4. **Feature Flag**: Should this be behind a feature flag initially?
5. **Phase 2 Timeline**: When to implement reverse linking?

## References

- **Eventasaurus Event Model**: `lib/eventasaurus_app/events/event.ex:688-743`
- **Cinegraph Movie Model**: `lib/cinegraph/movies/movie.ex:54`
- **Cinegraph Router**: `lib/cinegraph_web/router.ex:30`
- **Cinegraph Slug Module**: `lib/cinegraph/movies/movie_slug.ex`
- **TMDB Documentation**: https://developers.themoviedb.org/

## Success Metrics

1. **Click-through Rate**: % of users clicking Cinegraph links
2. **User Engagement**: Time spent on Cinegraph after clicking
3. **Return Rate**: % of users returning to Eventasaurus
4. **Error Rate**: % of broken/404 links
5. **SEO Impact**: Change in search rankings and organic traffic

---

**Priority**: Medium
**Effort**: Small (Phase 1), Medium (Phase 2)
**Impact**: High (user experience, SEO, ecosystem growth)
