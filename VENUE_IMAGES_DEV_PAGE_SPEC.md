# Venue Images Dev Page - Specification

**GitHub Issue**: Follow-up to #1915
**Purpose**: Development testing page for venue image aggregation system
**Route**: `/dev/venue-images` (dev environment only)
**Pattern**: Similar to `/dev/unsplash`

---

## Overview

Create a comprehensive development page to visualize, test, and debug the venue image aggregation system implemented in #1915. This page provides real-time insights into provider performance, enrichment status, cost tracking, and allows manual testing of the enrichment workflow.

---

## Page Sections

### 1. System Status (Header)

**Purpose**: Quick overview of system configuration and health

**Display**:
- API Key Status (checkmarks for each provider)
  - ✅/❌ Google Places API
  - ✅/❌ Foursquare API
  - ✅/❌ HERE API
  - ✅/❌ Geoapify API
  - ✅/❌ Unsplash API
- Rate Limiter Status: Running/Stopped
- Oban Queue Status: Active jobs in `venue_enrichment` queue
- Last Cron Run: When EnrichmentJob last ran

**Implementation**:
```elixir
%{
  api_keys: %{
    google_places: System.get_env("GOOGLE_PLACES_API_KEY") != nil,
    foursquare: System.get_env("FOURSQUARE_API_KEY") != nil,
    here: System.get_env("HERE_API_KEY") != nil,
    geoapify: System.get_env("GEOAPIFY_API_KEY") != nil,
    unsplash: System.get_env("UNSPLASH_ACCESS_KEY") != nil
  },
  rate_limiter_running: Process.whereis(EventasaurusDiscovery.VenueImages.RateLimiter) != nil,
  oban_queue_depth: get_oban_queue_depth("venue_enrichment"),
  last_cron_run: get_last_cron_run_time()
}
```

---

### 2. Global Statistics

**Purpose**: High-level metrics across all venues

**Display**:
- **Total Venues**: Count of all venues
- **Enriched Venues**: Count with `venue_images` populated
- **Needs Enrichment**: Count where `needs_enrichment?/2` returns true
- **Total Images Fetched**: Sum of all images across venues
- **Total Cost**: Cumulative cost from all enrichments
- **Average Images per Venue**: Total images / enriched venues
- **Average Cost per Venue**: Total cost / enriched venues

**Implementation**:
```elixir
alias EventasaurusApp.{Repo, Venues.Venue}
import Ecto.Query

total_venues = Repo.aggregate(Venue, :count, :id)

enriched_venues =
  from(v in Venue,
    where: fragment("jsonb_array_length(?) > 0", v.venue_images),
    select: count(v.id)
  ) |> Repo.one()

needs_enrichment_count =
  Venue
  |> Repo.all()
  |> Enum.count(&Orchestrator.needs_enrichment?/1)

total_images =
  from(v in Venue,
    where: fragment("jsonb_array_length(?) > 0", v.venue_images),
    select: fragment("SUM(jsonb_array_length(?))", v.venue_images)
  ) |> Repo.one() || 0

total_cost =
  from(v in Venue,
    where: fragment("? IS NOT NULL", v.image_enrichment_metadata),
    select: fragment("SUM(CAST(? ->> 'total_cost' AS FLOAT))", v.image_enrichment_metadata)
  ) |> Repo.one() || 0.0
```

---

### 3. Provider Statistics Table

**Purpose**: Show performance and contribution of each provider

**Columns**:
- Provider Name (Google Places, Foursquare, HERE, etc.)
- Active Status (✅/❌)
- Priority (1-99)
- Images Contributed (count across all venues)
- Success Rate (% of enrichments where provider succeeded)
- Average Cost per Image
- Total Cost
- Rate Limit Usage (current second/minute/hour)
- Last Used (timestamp)

**Implementation**:
```elixir
alias EventasaurusDiscovery.VenueImages.{Monitor, RateLimiter}
alias EventasaurusDiscovery.Geocoding.Schema.GeocodingProvider

providers =
  from(p in GeocodingProvider,
    where: fragment("? @> ?", p.capabilities, ^%{"images" => true}),
    order_by: [asc: fragment("CAST(? -> 'images' AS INTEGER)", p.priorities)]
  ) |> Repo.all()

Enum.map(providers, fn provider ->
  rate_stats = RateLimiter.get_stats(provider.name)

  # Count images contributed by this provider
  images_count =
    from(v in Venue,
      where: fragment(
        "EXISTS (SELECT 1 FROM jsonb_array_elements(?) AS img WHERE img ->> 'provider' = ?)",
        v.venue_images,
        ^provider.name
      ),
      select: fragment(
        "SUM((SELECT COUNT(*) FROM jsonb_array_elements(?) AS img WHERE img ->> 'provider' = ?))",
        v.venue_images,
        ^provider.name
      )
    ) |> Repo.one() || 0

  # Calculate success rate
  {successes, attempts} = calculate_provider_success_rate(provider.name)

  %{
    name: provider.name,
    is_active: provider.is_active,
    priority: provider.priorities["images"],
    images_contributed: images_count,
    success_rate: if(attempts > 0, do: successes / attempts * 100, else: 0),
    cost_per_image: provider.metadata["cost_per_image"] || 0.0,
    total_cost: calculate_provider_total_cost(provider.name),
    rate_limit_stats: rate_stats,
    last_used: get_last_provider_usage(provider.name)
  }
end)
```

---

### 4. Sample Enriched Venues

**Purpose**: Visual verification of enrichment results

**Display**:
- Show 10-20 recently enriched venues
- For each venue:
  - Venue name and location
  - Enrichment status badge (Fresh <30 days / Stale >30 days)
  - Image count (e.g., "15 images from 3 providers")
  - Primary image (first by position)
  - Provider breakdown (e.g., "Google: 8, Foursquare: 5, HERE: 2")
  - Attribution display
  - Last enriched timestamp
  - Total cost for this venue
  - "View Details" button → expands metadata

**Implementation**:
```elixir
enriched_venues =
  from(v in Venue,
    where: fragment("jsonb_array_length(?) > 0", v.venue_images),
    order_by: [desc: fragment("? ->> 'last_enriched_at'", v.image_enrichment_metadata)],
    limit: 20,
    preload: [:city]
  ) |> Repo.all()
  |> Enum.map(fn venue ->
    metadata = venue.image_enrichment_metadata || %{}
    images = venue.venue_images || []

    provider_breakdown =
      images
      |> Enum.group_by(& &1["provider"])
      |> Enum.map(fn {provider, imgs} -> {provider, length(imgs)} end)
      |> Enum.into(%{})

    %{
      venue: venue,
      image_count: length(images),
      primary_image: List.first(images),
      provider_breakdown: provider_breakdown,
      is_stale: Orchestrator.needs_enrichment?(venue),
      last_enriched: metadata["last_enriched_at"],
      total_cost: metadata["total_cost"] || 0.0,
      metadata: metadata
    }
  end)
```

---

### 5. Test Controls

**Purpose**: Manual testing and debugging tools

**Controls**:

1. **Enrich Specific Venue**
   - Input: Venue ID or name search
   - Button: "🖼️ Enrich Now"
   - Shows: Real-time enrichment progress and results

2. **Enrich Random Sample**
   - Button: "🎲 Enrich 5 Random Venues"
   - Shows: Progress bar and results

3. **Test Provider**
   - Dropdown: Select provider
   - Input: Place ID
   - Button: "🔍 Test Provider"
   - Shows: Raw API response from provider

4. **Check Enrichment Status**
   - Input: Venue ID
   - Button: "📊 Check Status"
   - Shows: needs_enrichment? result + metadata

5. **Reset Rate Limits**
   - Dropdown: Select provider
   - Button: "🔄 Reset Limits"
   - Shows: Confirmation + new limits

**Implementation**:
```elixir
# handle_event callbacks
def handle_event("enrich_venue", %{"venue_id" => id}, socket) do
  venue = Repo.get!(Venue, id) |> Repo.preload(:city)

  case Orchestrator.enrich_venue(venue) do
    {:ok, enriched_venue} ->
      socket
      |> put_flash(:info, "✅ Enriched #{enriched_venue.name}")
      |> push_patch(to: ~p"/dev/venue-images")

    {:error, reason} ->
      socket
      |> put_flash(:error, "❌ Enrichment failed: #{inspect(reason)}")
  end

  {:noreply, socket}
end

def handle_event("test_provider", %{"provider" => provider, "place_id" => place_id}, socket) do
  # Direct provider API call
  result = test_provider_api_call(provider, place_id)

  socket
  |> assign(:test_result, result)
  |> assign(:show_test_modal, true)

  {:noreply, socket}
end
```

---

### 6. Enrichment Workflow Visualization

**Purpose**: Show the complete enrichment pipeline

**Display**:
- Flow diagram showing:
  1. Venue → Check needs_enrichment?
  2. Get enabled providers (sorted by priority)
  3. Parallel provider queries (Task.async_stream)
  4. Rate limit checks
  5. Image deduplication
  6. Metadata aggregation
  7. Database update
  8. Cost tracking

**Implementation**:
```elixir
# Static SVG/HTML visualization
# Or interactive mermaid diagram
"""
graph TD
    A[Venue] --> B{needs_enrichment?}
    B -->|Yes| C[Get Enabled Providers]
    B -->|No| D[Skip]
    C --> E[Sort by Priority]
    E --> F[Parallel Fetch]
    F --> G[Google Places]
    F --> H[Foursquare]
    F --> I[HERE]
    G --> J[Deduplicate]
    H --> J
    I --> J
    J --> K[Aggregate Metadata]
    K --> L[Update Database]
    L --> M[Track Costs]
"""
```

---

### 7. Cost Analysis Dashboard

**Purpose**: Financial tracking and budgeting

**Display**:
- **Daily Cost Chart**: Last 30 days (if data available)
- **Cost Breakdown Pie Chart**: By provider
- **Projected Monthly Cost**: Based on current usage
- **Cost per Venue Histogram**: Distribution of costs
- **Budget Alert**: If approaching cost threshold

**Implementation**:
```elixir
# Aggregate costs by date
daily_costs =
  from(v in Venue,
    where: fragment("? IS NOT NULL", v.image_enrichment_metadata),
    select: %{
      date: fragment("DATE(? ->> 'last_enriched_at')", v.image_enrichment_metadata),
      cost: fragment("SUM(CAST(? ->> 'total_cost' AS FLOAT))", v.image_enrichment_metadata)
    },
    group_by: fragment("DATE(? ->> 'last_enriched_at')", v.image_enrichment_metadata),
    order_by: [desc: fragment("DATE(? ->> 'last_enriched_at')", v.image_enrichment_metadata)],
    limit: 30
  ) |> Repo.all()

# Provider cost breakdown
provider_costs =
  from(v in Venue,
    where: fragment("? IS NOT NULL", v.image_enrichment_metadata),
    select: fragment(
      "jsonb_each_text(? -> 'cost_breakdown')",
      v.image_enrichment_metadata
    )
  ) |> Repo.all()
  |> aggregate_provider_costs()
```

---

### 8. Staleness Monitor

**Purpose**: Track venues needing re-enrichment

**Display**:
- **Stale Venues Count**: >30 days old
- **Upcoming Stale**: 25-30 days old (warning zone)
- **Never Enriched**: Venues with provider_ids but no images
- **Next Cron Run**: Countdown to 4 AM UTC
- **Estimated Enrichment Time**: Based on batch size and rate limits

**Implementation**:
```elixir
now = DateTime.utc_now()
thirty_days_ago = DateTime.add(now, -30, :day)
twenty_five_days_ago = DateTime.add(now, -25, :day)

stale_venues =
  Venue
  |> Repo.all()
  |> Enum.filter(&Orchestrator.needs_enrichment?/1)
  |> length()

upcoming_stale =
  from(v in Venue,
    where:
      fragment("? ->> 'last_enriched_at' < ?", v.image_enrichment_metadata, ^DateTime.to_iso8601(twenty_five_days_ago)) and
      fragment("? ->> 'last_enriched_at' >= ?", v.image_enrichment_metadata, ^DateTime.to_iso8601(thirty_days_ago)),
    select: count(v.id)
  ) |> Repo.one() || 0

never_enriched =
  from(v in Venue,
    where:
      fragment("? IS NOT NULL", v.provider_ids) and
      (fragment("jsonb_array_length(?) = 0", v.venue_images) or is_nil(v.venue_images)),
    select: count(v.id)
  ) |> Repo.one() || 0
```

---

### 9. Testing Instructions

**Purpose**: Guide developers on how to test the system

**Content**:
```markdown
### Manual Enrichment Tests

1. **Single Venue Enrichment**:
   ```elixir
   iex> alias EventasaurusDiscovery.VenueImages.Orchestrator
   iex> venue = Repo.get(Venue, 1) |> Repo.preload(:city)
   iex> {:ok, enriched} = Orchestrator.enrich_venue(venue)
   iex> enriched.venue_images  # Should have images
   ```

2. **Provider Testing**:
   ```elixir
   iex> alias EventasaurusDiscovery.Geocoding.Providers.GooglePlaces
   iex> GooglePlaces.get_images("ChIJ...")  # Test with place_id
   ```

3. **Rate Limit Testing**:
   ```elixir
   iex> alias EventasaurusDiscovery.VenueImages.RateLimiter
   iex> RateLimiter.get_stats("google_places")
   iex> RateLimiter.reset_limits("google_places")
   ```

4. **Background Job Testing**:
   ```elixir
   iex> EventasaurusDiscovery.VenueImages.EnrichmentJob.enqueue()
   # Monitor at /admin/oban
   ```

### Load Testing

See: `test/eventasaurus_discovery/venue_images/LOAD_TESTING.md`

### Cost Monitoring

- Check `/admin/venue-images/stats` for real-time provider costs
- Review metadata: `venue.image_enrichment_metadata.cost_breakdown`
```

---

### 10. API Reference

**Purpose**: Quick reference for developers

**Functions**:
```elixir
# Enrichment
Orchestrator.fetch_venue_images/1    # Fetch images without DB update
Orchestrator.enrich_venue/1          # Fetch and update venue
Orchestrator.enrich_venue/2          # With options (force: true)
Orchestrator.needs_enrichment?/1     # Check if enrichment needed
Orchestrator.needs_enrichment?/2     # With force flag

# Provider Management
Orchestrator.get_enabled_image_providers/0  # List active providers

# Background Jobs
EnrichmentJob.enqueue/0              # Enqueue all stale venues
EnrichmentJob.enqueue_venue/1        # Enqueue specific venue
EnrichmentJob.enqueue_batch/1        # Enqueue list of venue IDs

# Monitoring
Monitor.get_all_stats/0              # All provider statistics
Monitor.get_provider_stats/1         # Specific provider stats
Monitor.check_alerts/0               # Rate limit alerts
Monitor.log_health_check/0           # Log health status

# Rate Limiting
RateLimiter.get_stats/1              # Get rate limit usage
RateLimiter.reset_limits/1           # Reset provider limits
RateLimiter.record_request/1         # Manual request recording
```

---

## Technical Implementation

### Controller Structure

```elixir
defmodule EventasaurusWeb.Dev.VenueImagesTestController do
  use EventasaurusWeb, :controller

  alias EventasaurusDiscovery.VenueImages.{Orchestrator, Monitor, RateLimiter}
  alias EventasaurusApp.{Repo, Venues.Venue}
  import Ecto.Query

  def index(conn, _params) do
    render(conn, :index,
      system_status: get_system_status(),
      global_stats: get_global_statistics(),
      provider_stats: get_provider_statistics(),
      sample_venues: get_sample_enriched_venues(),
      cost_analysis: get_cost_analysis(),
      staleness_monitor: get_staleness_monitor()
    )
  end

  # Private helper functions...
end
```

### HTML Module

```elixir
defmodule EventasaurusWeb.Dev.VenueImagesTestHTML do
  use EventasaurusWeb, :html

  embed_templates "venue_images_test_html/*"

  def format_cost(cost) when is_float(cost) do
    :erlang.float_to_binary(cost, decimals: 4)
  end

  def format_cost(_), do: "0.0000"

  def format_percentage(ratio) when is_float(ratio) do
    "#{Float.round(ratio, 2)}%"
  end

  def format_percentage(_), do: "0%"
end
```

### Route Configuration

```elixir
# lib/eventasaurus_web/router.ex

scope "/dev", EventasaurusWeb.Dev do
  pipe_through :browser

  get "/unsplash", UnsplashTestController, :index
  get "/venue-images", VenueImagesTestController, :index  # NEW
end
```

---

## UI/UX Design

### Color Coding

- **Green**: Active providers, successful operations, fresh data
- **Yellow**: Warning states (approaching rate limits, stale data)
- **Red**: Error states, rate limit exceeded, failed operations
- **Blue**: Informational, neutral statistics
- **Indigo**: Primary actions, featured content

### Layout Sections

1. **Header**: System status + quick stats (full width)
2. **Provider Grid**: 3-column responsive grid
3. **Sample Venues**: 2-column responsive grid with image galleries
4. **Test Controls**: Sidebar or accordion sections
5. **Charts**: Full width visualization sections
6. **Instructions**: Collapsible sections with code examples

---

## Success Criteria

✅ **Complete** when page displays:
- All 10 sections listed above
- Real-time data from database
- Interactive test controls functional
- Provider statistics accurate
- Cost tracking operational
- Similar visual quality to `/dev/unsplash`

✅ **Testing**:
- Loads without errors in dev environment
- Shows accurate statistics
- Test controls work correctly
- Handles edge cases (no enriched venues, missing API keys)
- Responsive on mobile/tablet/desktop

---

## Future Enhancements (Out of Scope)

- Real-time WebSocket updates (currently page refresh)
- Historical cost charts (requires time-series data collection)
- Provider performance comparison graphs
- Automated testing scheduler
- Export to CSV functionality
- Image quality scoring visualization

---

## Implementation Checklist

- [ ] Create `EventasaurusWeb.Dev.VenueImagesTestController`
- [ ] Create `EventasaurusWeb.Dev.VenueImagesTestHTML`
- [ ] Create template `venue_images_test_html/index.html.heex`
- [ ] Add route to `router.ex`
- [ ] Implement all 10 sections
- [ ] Add helper functions for data aggregation
- [ ] Test with sample venues
- [ ] Verify cost calculations accuracy
- [ ] Test all interactive controls
- [ ] Add documentation comments
- [ ] Update `VENUE_IMAGES_IMPLEMENTATION.md` with dev page info
