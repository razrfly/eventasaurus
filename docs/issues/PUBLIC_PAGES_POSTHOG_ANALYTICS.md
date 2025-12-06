# Public Pages Analytics Dashboard - PostHog Implementation

**Issue Reference**: Extends [#2542](https://github.com/razrfly/eventasaurus/issues/2542)

## Overview

Build comprehensive PostHog analytics for all public-facing pages on wombie.com to understand user behavior, traffic patterns, and engagement across cities, activities, and venues.

## Current State

### What's Tracked
- Basic `$pageview` events with minimal properties (title, privacy_consent, user_type)
- Private event tracking: `event_page_viewed`, `event_registration_completed`, `poll_viewed`, `poll_vote`
- One default dashboard with sample insights (DAU, WAU, Retention)

### What's NOT Tracked (Gap Analysis)
- **No differentiation** between page types (city vs activity vs venue)
- **No rich context** (city name, category, venue, dates)
- **No user interaction tracking** (searches, filters, date selections)
- **No external link click tracking**
- **No funnels** for public discovery flow

## Public Pages to Track

### From Sitemap (lib/eventasaurus/sitemap.ex)

| Route Pattern | Page Type | LiveView Module | Priority |
|--------------|-----------|-----------------|----------|
| `/activities` | home | PublicEventsHomeLive | High |
| `/activities/:slug` | activity | PublicEventShowLive | High |
| `/activities/:slug/:date_slug` | activity_date | PublicEventShowLive | High |
| `/c/:city_slug` | city | CityLive.Index | High |
| `/c/:city_slug/events` | city_events | CityLive.Events | High |
| `/c/:city_slug/events/today\|weekend\|week` | city_events_filter | CityLive.Events | Medium |
| `/c/:city_slug/venues` | city_venues | CityLive.Venues | Medium |
| `/c/:city_slug/venues/:venue_slug` | venue | VenueLive.Show | High |
| `/c/:city_slug/search` | city_search | CityLive.Search | Medium |
| `/c/:city_slug/festivals\|conferences\|...` | container_list | CityLive.Events | Medium |
| `/c/:city_slug/:type/:slug` | container_detail | ContainerDetailLive | Medium |
| `/c/:city_slug/movies/:movie_slug` | movie | PublicMovieScreeningsLive | Medium |
| `/c/:city_slug/:content_type/:identifier` | aggregated | AggregatedContentLive | Medium |
| `/social\|food\|movies\|.../:identifier` | multi_city | AggregatedContentLive | Low |

### Static Pages
- `/` (homepage)
- `/about`
- `/our-story`
- `/privacy`
- `/terms`
- `/your-data`

---

## Implementation Phases

### Phase 1: Enhanced Pageview Tracking (Foundation)
**Estimated Effort**: 1-2 days
**Goal**: Add rich context properties to all public page views

#### 1.1 Create Analytics Hook Module

Create a new hook for public pages that enriches pageviews:

```elixir
# lib/eventasaurus_web/live/hooks/public_analytics_hook.ex
defmodule EventasaurusWeb.Live.Hooks.PublicAnalyticsHook do
  @moduledoc """
  LiveView hook for tracking public page analytics with PostHog.
  Enriches pageviews with contextual data about cities, activities, venues, etc.
  """

  import Phoenix.LiveView

  def on_mount(:default, params, _session, socket) do
    socket = attach_hook(socket, :track_pageview, :handle_params, &track_pageview/3)
    {:cont, socket}
  end

  defp track_pageview(params, url, socket) do
    # Build analytics context based on assigns
    context = build_analytics_context(socket.assigns, params)

    # Push event to client-side PostHog via hook
    socket = push_event(socket, "posthog:track", %{
      event: "public_page_viewed",
      properties: context
    })

    {:cont, socket}
  end

  defp build_analytics_context(assigns, params) do
    %{
      page_type: determine_page_type(assigns),
      city_slug: assigns[:city][:slug],
      city_name: assigns[:city][:name],
      city_country: assigns[:city][:country][:name],
      venue_slug: assigns[:venue][:slug],
      venue_name: assigns[:venue][:name],
      activity_slug: assigns[:event][:slug],
      activity_title: assigns[:event][:title],
      activity_category: get_primary_category(assigns[:event]),
      container_type: assigns[:container_type],
      language: assigns[:language],
      view_mode: assigns[:view_mode],
      filter_count: count_active_filters(assigns[:filters]),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end
end
```

#### 1.2 Update Client-Side PostHog Manager

Add event listener in `posthog-manager.js`:

```javascript
// Add to PostHogManager class
setupLiveViewHooks() {
  window.addEventListener('phx:posthog:track', (event) => {
    const { event: eventName, properties } = event.detail;
    this.capture(eventName, properties);
  });
}
```

#### 1.3 Properties to Track with Every Pageview

| Property | Type | Description | Example |
|----------|------|-------------|---------|
| `page_type` | string | Type of public page | "city", "activity", "venue" |
| `city_slug` | string | City URL slug | "krakow" |
| `city_name` | string | City display name | "Kraków" |
| `city_country` | string | Country name | "Poland" |
| `venue_slug` | string | Venue URL slug | "ice-krakow" |
| `venue_name` | string | Venue display name | "ICE Kraków" |
| `activity_slug` | string | Activity/event slug | "kwiat-jaboni..." |
| `activity_title` | string | Activity display title | "Kwiat Jabłoni..." |
| `activity_category` | string | Primary category | "Concerts" |
| `container_type` | string | Container type | "festival", "conference" |
| `language` | string | User's selected language | "en", "pl" |
| `view_mode` | string | Grid/list view selection | "grid", "list" |
| `filter_count` | integer | Number of active filters | 3 |
| `date_range` | string | Selected date range | "next_7_days" |

---

### Phase 2: Custom Event Tracking (User Interactions)
**Estimated Effort**: 2-3 days
**Goal**: Track meaningful user interactions on public pages

#### 2.1 Events to Track

| Event Name | Trigger | Properties |
|------------|---------|------------|
| `city_search_performed` | User submits search | city_slug, query, results_count |
| `city_filter_applied` | Filter selection changes | city_slug, filter_type, filter_value |
| `date_range_selected` | Quick date filter clicked | city_slug, range (today/weekend/etc), previous_range |
| `activity_external_link_clicked` | External ticket/info link | activity_slug, link_type, destination_domain |
| `venue_directions_clicked` | Map/directions interaction | venue_slug, city_slug |
| `language_changed` | Language switcher used | from_lang, to_lang, page_type |
| `view_mode_changed` | Grid/list toggle | page_type, from_mode, to_mode |
| `pagination_used` | Page navigation | page_type, page_number, total_pages |
| `category_selected` | Category filter applied | city_slug, category_name, category_id |
| `nearby_event_clicked` | "Nearby events" card click | source_activity, target_activity |

#### 2.2 Implementation Pattern

Add to each LiveView's `handle_event`:

```elixir
def handle_event("search", %{"search" => query}, socket) do
  # ... existing logic ...

  # Track search event
  socket = push_event(socket, "posthog:track", %{
    event: "city_search_performed",
    properties: %{
      city_slug: socket.assigns.city.slug,
      query: query,
      results_count: length(socket.assigns.events)
    }
  })

  {:noreply, socket}
end
```

#### 2.3 Track External Link Clicks (Client-Side)

```javascript
// In app.js or dedicated hook
document.addEventListener('click', (e) => {
  const link = e.target.closest('a[data-external]');
  if (link) {
    window.posthogManager?.capture('activity_external_link_clicked', {
      activity_slug: link.dataset.activitySlug,
      link_type: link.dataset.linkType, // 'tickets', 'info', 'venue'
      destination_domain: new URL(link.href).hostname
    });
  }
});
```

---

### Phase 3: PostHog Dashboards
**Estimated Effort**: 1-2 days
**Goal**: Create actionable dashboards for public page analytics

#### 3.1 Dashboard: Public Events Overview

**Insights to Create:**

1. **Top Activities by Views** (last 30 days)
   - Trend: `public_page_viewed` where `page_type = 'activity'`
   - Breakdown by: `activity_title`
   - Display: Bar chart, top 20

2. **Top Cities by Traffic** (last 30 days)
   - Trend: `public_page_viewed` where `page_type = 'city'`
   - Breakdown by: `city_name`
   - Display: Bar chart with country grouping

3. **Traffic Over Time** (last 90 days)
   - Trend: `public_page_viewed`
   - Breakdown by: `page_type`
   - Display: Stacked area chart

4. **Top Venues by Traffic** (last 30 days)
   - Trend: `public_page_viewed` where `page_type = 'venue'`
   - Breakdown by: `venue_name`
   - Display: Bar chart, top 15

5. **Category Distribution** (last 30 days)
   - Trend: `public_page_viewed` where `activity_category IS NOT NULL`
   - Breakdown by: `activity_category`
   - Display: Pie chart

#### 3.2 Dashboard: User Behavior

**Insights to Create:**

1. **Search Patterns** (last 14 days)
   - Trend: `city_search_performed`
   - Breakdown by: `city_slug`
   - Include: Average results_count

2. **Popular Date Ranges** (last 30 days)
   - Trend: `date_range_selected`
   - Breakdown by: `range`
   - Display: Horizontal bar

3. **External Link Engagement** (last 30 days)
   - Trend: `activity_external_link_clicked`
   - Breakdown by: `link_type`
   - Display: Funnel (view → click)

4. **Language Preferences** (last 30 days)
   - Trend: `public_page_viewed`
   - Breakdown by: `language`
   - Display: Pie chart

5. **Device & Browser** (last 30 days)
   - Trend: `$pageview`
   - Breakdown by: `$browser`, `$device_type`
   - Display: Table

#### 3.3 Dashboard: Geographic Insights

**Insights to Create:**

1. **City-Country Heatmap**
   - World map visualization of traffic by city

2. **Top Countries by Visitors**
   - Trend: `public_page_viewed`
   - Breakdown by: `city_country`

3. **City Comparison** (selected cities)
   - Multiple trends: Compare krakow, warsaw, paris
   - Display: Line chart overlay

---

### Phase 4: Advanced Funnels & Retention
**Estimated Effort**: 1-2 days
**Goal**: Understand user journeys and retention

#### 4.1 Funnels to Create

1. **City → Activity Funnel**
   ```
   Step 1: public_page_viewed (page_type = 'city')
   Step 2: public_page_viewed (page_type = 'activity')
   Step 3: activity_external_link_clicked
   ```
   Breakdown by: `city_slug`

2. **Search → Discovery Funnel**
   ```
   Step 1: city_search_performed
   Step 2: public_page_viewed (page_type = 'activity')
   Step 3: activity_external_link_clicked
   ```

3. **Homepage → Engagement Funnel**
   ```
   Step 1: public_page_viewed (page_type = 'home')
   Step 2: public_page_viewed (page_type = 'city' OR 'activity')
   Step 3: Any interaction event
   ```

#### 4.2 Retention Analysis

1. **City Return Visitors**
   - Retention: Users who return to same city within 7 days
   - Breakdown by: `city_slug`

2. **Weekly Active Discovery Users**
   - Lifecycle: New vs returning vs dormant
   - Based on: `public_page_viewed` events

---

## Technical Implementation Details

### Files to Modify

1. **New Files**:
   - `lib/eventasaurus_web/live/hooks/public_analytics_hook.ex`
   - `assets/js/analytics/public-page-tracker.js`

2. **Modify Existing**:
   - `lib/eventasaurus_web/router.ex` - Add analytics hook to public live_session
   - `assets/js/analytics/posthog-manager.js` - Add LiveView event listener
   - `lib/eventasaurus_web/live/city_live/index.ex` - Add interaction tracking
   - `lib/eventasaurus_web/live/public_event_show_live.ex` - Add interaction tracking
   - `lib/eventasaurus_web/live/venue_live/show.ex` - Add interaction tracking

### Router Changes

```elixir
# In router.ex, update the public live_session
live_session :public,
  on_mount: [
    {EventasaurusWeb.Live.AuthHooks, :assign_auth_user_and_theme},
    {EventasaurusWeb.Live.Hooks.PublicAnalyticsHook, :default}  # Add this
  ] do
```

### Privacy Considerations

- All tracking respects existing privacy consent mechanism
- No PII is tracked (no emails, names, etc.)
- User IDs are hashed when consent is given
- Analytics can be disabled via existing privacy settings

---

## Success Metrics

After implementation, we should be able to answer:

1. **Traffic Questions**
   - Which cities drive the most traffic?
   - Which activities are most viewed?
   - What's the traffic trend over time?

2. **User Behavior Questions**
   - How do users discover events? (search vs browse)
   - What date ranges are most popular?
   - Do users click external ticket links?

3. **Engagement Questions**
   - What's the city → activity conversion rate?
   - How many return visitors do we have per city?
   - Which categories perform best?

---

## Rollout Plan

| Phase | Deliverable | Dependencies | Estimated Days |
|-------|-------------|--------------|----------------|
| 1 | Enhanced pageview tracking | None | 1-2 |
| 2 | Custom interaction events | Phase 1 | 2-3 |
| 3 | PostHog dashboards | Phase 1 & 2 | 1-2 |
| 4 | Funnels & retention | Phase 3 | 1-2 |

**Total Estimated Effort**: 5-9 days

---

## Acceptance Criteria

### Phase 1
- [ ] All public pages send `public_page_viewed` event with rich properties
- [ ] Properties include page_type, city info, venue info, activity info (where applicable)
- [ ] Privacy consent is respected

### Phase 2
- [ ] Search, filter, and date selection events are tracked
- [ ] External link clicks are tracked
- [ ] Language and view mode changes are tracked

### Phase 3
- [ ] "Public Events Overview" dashboard created with 5+ insights
- [ ] "User Behavior" dashboard created with 5+ insights
- [ ] "Geographic Insights" dashboard created

### Phase 4
- [ ] City → Activity funnel created and functioning
- [ ] Return visitor retention tracking working
- [ ] Weekly active user lifecycle visible

---

## References

- [PostHog Event Tracking Docs](https://posthog.com/docs/product-analytics/events)
- [PostHog Dashboards](https://posthog.com/docs/product-analytics/dashboards)
- [Current Sitemap Implementation](lib/eventasaurus/sitemap.ex)
- [Current PostHog Manager](assets/js/analytics/posthog-manager.js)
- [Current PostHog Service](lib/eventasaurus/services/posthog_service.ex)
