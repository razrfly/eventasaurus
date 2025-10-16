# Database Integration Plan: Trivia Advisor → Eventasaurus

## Executive Summary

This document outlines the strategy for migrating Trivia Advisor to use Eventasaurus's centralized database, eliminating duplicate scraper infrastructure and data storage. Both systems currently maintain separate Postgres databases with overlapping event data from the same sources (Geeks Who Drink, Inquizition, PubQuiz, Question One, Quizmeisters, Speed Quizzing).

**Recommendation:** Direct Postgres read-only access with transformation layer (simplest to implement, leverages Ecto, no API overhead).

---

## Current State Analysis

### Trivia Advisor
- **Database:** Direct Postgres connection via `TriviaAdvisor.Repo`
- **Scrapers:** 6 trivia event scrapers (now ported to Eventasaurus)
- **Data Model:** Recurring event model (day_of_week, start_time, frequency)
- **Key Tables:** events, venues, sources, event_sources
- **Job System:** Oban with scraper queues

### Eventasaurus
- **Database:** Supabase (Postgres) via `EventasaurusApp.Repo`
- **Scrapers:** All trivia scrapers + additional sources (Karnet, Ticketmaster, Cinema City, etc.)
- **Data Model:** Date-specific events with occurrences map
- **Key Tables:** public_events, public_event_sources, venues, cities, countries, sources, categories
- **Job System:** Oban with discovery queues
- **Additional Features:** PostGIS support, i18n translations, category system

---

## Data Model Comparison

### Events

| Field | Trivia Advisor | Eventasaurus | Compatibility |
|-------|---------------|--------------|---------------|
| **Identification** | `id`, `name` | `id`, `title`, `slug` | ✅ Name → Title |
| **Timing** | `day_of_week`, `start_time`, `frequency` | `starts_at`, `ends_at`, `occurrences` | ⚠️ Requires transformation |
| **Location** | `venue_id` | `venue_id` | ✅ Direct mapping |
| **Pricing** | `entry_fee_cents` (on event) | `min_price`, `max_price`, `currency` (in source) | ⚠️ Different storage location |
| **Content** | `description`, `hero_image` | Descriptions in `public_event_sources` | ⚠️ Different location |
| **Categorization** | None | `category_id`, many-to-many categories | ❌ Missing in TA |
| **Performers** | `performer_id` | Many-to-many via `public_event_performers` | ⚠️ Different relationship |
| **Translations** | None | `title_translations`, `description_translations` | ❌ TA doesn't support i18n |

### Venues

| Field | Trivia Advisor | Eventasaurus | Compatibility |
|-------|---------------|--------------|---------------|
| **Core** | `name`, `slug`, `address`, `postcode` | Same + `city_id` | ✅ Compatible |
| **Coordinates** | `latitude`, `longitude` | Same (with PostGIS support) | ✅ Compatible |
| **Identifiers** | `place_id` | Same | ✅ Compatible |
| **Social** | `phone`, `website`, `facebook`, `instagram` | Same | ✅ Compatible |
| **Metadata** | `metadata`, `google_place_images` | Same | ✅ Compatible |
| **Location Hierarchy** | Direct `city_id` | `city_id` → `cities.country_id` | ⚠️ EA has full hierarchy |

### Sources

| Field | Trivia Advisor | Eventasaurus | Compatibility |
|-------|---------------|--------------|---------------|
| **Identification** | `name`, `slug`, `website_url` | Similar structure | ✅ Compatible |
| **Relationships** | `has_many :event_sources` | Similar | ✅ Compatible |

### Event-Source Join Table

| Field | Trivia Advisor (`event_sources`) | Eventasaurus (`public_event_sources`) | Compatibility |
|-------|----------------------------------|---------------------------------------|---------------|
| **Core** | `event_id`, `source_id`, `source_url` | Same | ✅ Compatible |
| **Tracking** | `last_seen_at`, `status`, `metadata` | `last_seen_at`, `metadata` | ✅ Compatible |
| **Content** | Stored on event | `description_translations`, `image_url` | ⚠️ Different location |
| **Pricing** | Stored on event | `min_price`, `max_price`, `currency`, `is_free` | ⚠️ Different location |
| **External ID** | None | `external_id` | ⚠️ Missing in TA |

---

## Integration Approaches

### Option 1: Direct Postgres Read-Only Access ⭐ RECOMMENDED

**Implementation:**
1. Add Eventasaurus Supabase connection to Trivia Advisor config (read-only credentials)
2. Create read-only Ecto schemas in TA for EA tables
3. Build transformation layer to convert EA data → TA format
4. Keep TA's own DB for TA-specific features

**Pros:**
- ✅ Simplest to implement (no API layer needed)
- ✅ Leverages existing Ecto knowledge
- ✅ Type-safe with Ecto schemas
- ✅ No serialization overhead
- ✅ Can use Ecto queries, preloads, associations
- ✅ Immediate data access
- ✅ Read-only reduces risk of conflicts

**Cons:**
- ⚠️ Requires Supabase connection string in TA
- ⚠️ Tight coupling to EA database schema
- ⚠️ Schema changes in EA require updates in TA
- ⚠️ Need to manage two database connections in TA

**Complexity:** LOW (1-2 days)

---

### Option 2: GraphQL API Layer

**Implementation:**
1. Add Absinthe GraphQL to Eventasaurus
2. Create API authentication (API keys)
3. Build GraphQL schema and resolvers for public_events, venues, sources
4. Implement GraphQL client in Trivia Advisor
5. Create transformation layer for API responses

**Pros:**
- ✅ Clean separation of concerns
- ✅ Versioned API contract
- ✅ Better for future microservices
- ✅ Can rate limit and monitor usage
- ✅ Easy to mock for testing

**Cons:**
- ⚠️ More complex to build and maintain
- ⚠️ Network/serialization overhead (though minimal on localhost)
- ⚠️ Additional dependency (Absinthe)
- ⚠️ Need to build both API and client

**Complexity:** MEDIUM (3-5 days)

---

## Obstacles & Missing Pieces

### 🚧 Data Model Incompatibilities

#### 1. Event Time Representation
**Problem:** TA uses recurring model (`day_of_week`, `start_time`, `frequency`), EA uses specific dates (`starts_at`, `ends_at`, `occurrences`)

**Solution:**
- Create adapter that generates next N occurrences from EA data
- Transform EA's date-specific events into TA's display format
- For recurring patterns in EA, extract pattern from occurrences

**Code Location:** `lib/trivia_advisor/adapters/eventasaurus_adapter.ex`

#### 2. Price Storage Location
**Problem:** TA stores `entry_fee_cents` on event, EA stores pricing in `public_event_sources`

**Solution:**
- Adapter fetches pricing from sources join table
- Use first source's pricing or average across sources
- Handle currency conversion if needed

**Code Location:** Same adapter module

#### 3. Category System
**Problem:** EA has categories, TA doesn't

**Solution:**
- Filter EA events to "Trivia" category only
- Or: Add category support to TA (future enhancement)
- Default all events to trivia category in queries

#### 4. Performers Relationship
**Problem:** TA has single `performer_id`, EA has many-to-many

**Solution:**
- Take first performer from EA's association
- Or: Display all performers in TA UI
- Adapter handles association loading

### 🔧 Missing in Eventasaurus

#### 1. Trivia Category
**Status:** ✅ EA has category system, just need "Trivia" category created

**Action Required:**
```elixir
# Run in Eventasaurus
EventasaurusDiscovery.Categories.create_category(%{
  name: "Trivia",
  slug: "trivia",
  icon: "🧠"
})
```

#### 2. API Authentication System (if using GraphQL)
**Status:** ❌ Not implemented

**Action Required:**
- Add API key generation system
- Implement authentication plug
- Create keys for Trivia Advisor

### 🔧 Missing in Trivia Advisor

#### 1. Supabase Connection Configuration
**Status:** ❌ Not configured

**Action Required:**
```elixir
# config/runtime.exs
config :trivia_advisor, TriviaAdvisor.EventasaurusRepo,
  url: System.get_env("EVENTASAURUS_DATABASE_URL"),
  pool_size: 2,  # Read-only, small pool
  ssl: true,
  ssl_opts: [verify: :verify_none]
```

#### 2. Read-Only Ecto Schemas for EA Tables
**Status:** ❌ Not created

**Action Required:**
Create schemas in `lib/trivia_advisor/eventasaurus/` for:
- `PublicEvent`
- `PublicEventSource`
- `Venue`
- `City`
- `Source`

#### 3. Transformation/Adapter Layer
**Status:** ❌ Not created

**Action Required:**
Create `lib/trivia_advisor/adapters/eventasaurus_adapter.ex` with functions:
- `list_events_for_city(city_id, opts \\ [])`
- `get_event_details(event_id)`
- `search_events(query, opts \\ [])`
- Transform EA events to TA format

#### 4. Caching Layer
**Status:** ❌ Not implemented

**Action Required:**
- Add Cachex or similar for caching EA data
- Implement cache invalidation strategy
- Cache venue lookups, event queries

---

## Phased Implementation Plan

### Phase 1: Preparation (Eventasaurus)
**Duration:** 1 day

**Tasks:**
1. ✅ Verify all trivia scrapers are running in EA
2. ✅ Ensure venues from scrapers are properly stored
3. ✅ Create "Trivia" category in EA
4. ✅ Tag all trivia events with trivia category
5. ✅ Set up read-only database user in Supabase
6. ✅ Document Supabase connection string

**Deliverables:**
- Supabase read-only connection string
- Trivia category created
- All trivia events tagged

**Validation:**
```sql
-- Verify trivia events exist
SELECT COUNT(*) FROM public_events
WHERE category_id = (SELECT id FROM categories WHERE slug = 'trivia');

-- Verify sources
SELECT * FROM sources WHERE slug IN ('geeks-who-drink', 'pubquiz', 'inquizition', 'question-one', 'quizmeisters', 'speed-quizzing');
```

---

### Phase 2: Schema Setup (Trivia Advisor)
**Duration:** 1 day

**Tasks:**
1. ✅ Add Eventasaurus Supabase connection to config
2. ✅ Create `TriviaAdvisor.EventasaurusRepo` module
3. ✅ Create read-only Ecto schemas in `lib/trivia_advisor/eventasaurus/`:
   - `PublicEvent`
   - `PublicEventSource`
   - `Venue` (EA version)
   - `City`
   - `Source`
4. ✅ Set up schemas with proper associations
5. ✅ Test connection and basic queries

**Deliverables:**
- Working EventasaurusRepo connection
- Read-only schemas defined
- Basic query tests passing

**Validation:**
```elixir
# Test in iex
alias TriviaAdvisor.EventasaurusRepo, as: EARepo
alias TriviaAdvisor.Eventasaurus.PublicEvent

# Should return events
EARepo.all(PublicEvent) |> length()

# Should preload associations
EARepo.all(PublicEvent) |> EARepo.preload([:venue, :sources])
```

---

### Phase 3: Adapter Layer (Trivia Advisor)
**Duration:** 2-3 days

**Tasks:**
1. ✅ Create `TriviaAdvisor.Adapters.EventasaurusAdapter` module
2. ✅ Implement data transformation functions:
   - `transform_event/1` - PublicEvent → TA Event format
   - `transform_venue/1` - EA Venue → TA Venue format
   - `extract_pricing/1` - Get pricing from sources
   - `generate_display_time/1` - Format event time for display
3. ✅ Implement query functions:
   - `list_events(city_id, opts)`
   - `get_event(event_id)`
   - `search_events(query, opts)`
   - `list_venues(city_id)`
4. ✅ Add caching layer (Cachex)
5. ✅ Write unit tests for transformations

**Deliverables:**
- Complete adapter module
- Transformation functions tested
- Caching implemented

**Code Structure:**
```elixir
defmodule TriviaAdvisor.Adapters.EventasaurusAdapter do
  alias TriviaAdvisor.EventasaurusRepo, as: EARepo
  alias TriviaAdvisor.Eventasaurus.PublicEvent

  def list_events(city_id, opts \\ []) do
    # Query EA database
    # Transform results
    # Cache results
  end

  def transform_event(%PublicEvent{} = ea_event) do
    # Transform to TA format
    %{
      id: ea_event.id,
      name: ea_event.title,
      venue_id: ea_event.venue_id,
      # Generate display time from starts_at
      day_of_week: extract_day_of_week(ea_event.starts_at),
      start_time: extract_time(ea_event.starts_at),
      frequency: detect_frequency(ea_event.occurrences),
      entry_fee_cents: extract_pricing(ea_event),
      description: extract_description(ea_event),
      # ... other fields
    }
  end

  defp extract_pricing(%PublicEvent{sources: sources}) do
    # Get first source with pricing
    case Enum.find(sources, & &1.min_price) do
      nil -> nil
      source -> Decimal.to_integer(Decimal.mult(source.min_price, 100))
    end
  end
end
```

---

### Phase 4: Integration (Trivia Advisor)
**Duration:** 2 days

**Tasks:**
1. ✅ Update TA contexts to use adapter:
   - `TriviaAdvisor.Events.list_events/1` → Use adapter
   - `TriviaAdvisor.Events.get_event/1` → Use adapter
   - Keep TA-specific features using local DB
2. ✅ Update controllers to work with adapter data
3. ✅ Update views/templates for any display changes
4. ✅ Add fallback handling for EA unavailability
5. ✅ Implement error handling and logging

**Deliverables:**
- TA reads from EA database successfully
- UI displays EA data correctly
- Error handling in place

**Code Changes:**
```elixir
# lib/trivia_advisor/events.ex
defmodule TriviaAdvisor.Events do
  alias TriviaAdvisor.Adapters.EventasaurusAdapter

  def list_events(city_id) do
    # Use adapter instead of local DB
    EventasaurusAdapter.list_events(city_id)
  rescue
    error ->
      Logger.error("Failed to fetch from Eventasaurus: #{inspect(error)}")
      # Fallback to cached data or empty list
      []
  end
end
```

---

### Phase 5: Testing & Validation
**Duration:** 2 days

**Tasks:**
1. ✅ Data consistency validation:
   - Compare event counts between TA and EA
   - Verify venue data matches
   - Check pricing calculations
2. ✅ Performance testing:
   - Query response times
   - Cache hit rates
   - Database connection pool usage
3. ✅ UI testing:
   - All pages display correctly
   - Search works
   - Filters work
4. ✅ Error scenarios:
   - EA database unavailable
   - Network timeouts
   - Invalid data handling
5. ✅ Load testing (if applicable)

**Deliverables:**
- Test report with metrics
- Performance baseline established
- All critical paths validated

**Test Checklist:**
```
□ List events by city works
□ Event detail page displays correctly
□ Search returns relevant results
□ Venue pages show correct events
□ Pricing displays correctly
□ Date/time formatting correct
□ Images display (if applicable)
□ Performer information shows
□ Source attribution visible
□ Error pages work when EA unavailable
```

---

### Phase 6: Migration & Cleanup
**Duration:** 1 day

**Tasks:**
1. ✅ Disable Trivia Advisor scrapers (turn off Oban cron jobs)
2. ✅ Archive TA scraper code (move to `archived/` folder)
3. ✅ Keep TA's `events` and `event_sources` tables for historical data
4. ✅ Add migration note to README
5. ✅ Update deployment docs
6. ✅ Monitor for issues

**Deliverables:**
- TA running purely on EA data
- Old scrapers disabled
- Documentation updated

**Config Changes:**
```elixir
# config/config.exs - Remove scraper cron jobs
config :trivia_advisor, Oban,
  queues: [
    default: 20,
    # Remove: scraper: [limit: 10]
  ],
  plugins: [
    # Remove scraper cron jobs
  ]
```

---

## Local Development Setup

### Eventasaurus
1. Ensure Supabase is running and accessible
2. Create read-only database user:
```sql
CREATE USER trivia_advisor_readonly WITH PASSWORD 'secure_password';
GRANT CONNECT ON DATABASE postgres TO trivia_advisor_readonly;
GRANT USAGE ON SCHEMA public TO trivia_advisor_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO trivia_advisor_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO trivia_advisor_readonly;
```

3. Get connection string:
```bash
# Format: postgresql://user:password@host:port/database
EVENTASAURUS_DATABASE_URL="postgresql://trivia_advisor_readonly:secure_password@db.PROJECT_REF.supabase.co:5432/postgres"
```

### Trivia Advisor
1. Add to `.env`:
```bash
EVENTASAURUS_DATABASE_URL="postgresql://trivia_advisor_readonly:secure_password@localhost:54322/postgres"
```

2. Add to `config/dev.exs`:
```elixir
config :trivia_advisor, TriviaAdvisor.EventasaurusRepo,
  url: System.get_env("EVENTASAURUS_DATABASE_URL"),
  pool_size: 2,
  show_sensitive_data_on_connection_error: true
```

3. Test connection:
```bash
mix ecto.query -r TriviaAdvisor.EventasaurusRepo "SELECT COUNT(*) FROM public_events"
```

---

## Risk Assessment & Mitigation

### Risk 1: Schema Changes in Eventasaurus
**Impact:** High - Could break Trivia Advisor queries

**Mitigation:**
- Create database views in EA that provide stable schema
- Version the read schemas in TA
- Add integration tests that run against EA schema
- Document schema change process

### Risk 2: Performance Issues
**Impact:** Medium - Slow queries could affect TA UX

**Mitigation:**
- Implement aggressive caching in TA
- Add database indexes in EA for common TA queries
- Monitor query performance
- Set up read replicas if needed

### Risk 3: Eventasaurus Unavailability
**Impact:** Medium - TA would have no event data

**Mitigation:**
- Implement fallback to cached data
- Add health check endpoint
- Set up monitoring and alerts
- Keep last-good data in TA cache (TTL: 24h)

### Risk 4: Data Transformation Errors
**Impact:** Medium - Incorrect data display in TA

**Mitigation:**
- Comprehensive unit tests for transformations
- Validation in adapter layer
- Logging of transformation errors
- Graceful degradation (show raw data if transform fails)

---

## Success Criteria

### Technical
- ✅ Trivia Advisor successfully reads from Eventasaurus database
- ✅ All TA features work with EA data
- ✅ Query performance meets requirements (<200ms p95)
- ✅ Cache hit rate >80%
- ✅ Zero data loss during migration
- ✅ All tests passing

### Business
- ✅ Single source of truth for event data
- ✅ No duplicate scraping infrastructure
- ✅ Reduced maintenance overhead
- ✅ TA displays current, accurate event data
- ✅ No user-facing issues during migration

---

## Next Steps

### Immediate (Week 1)
1. Review and approve this plan
2. Set up read-only Supabase user for TA
3. Begin Phase 1: Preparation in Eventasaurus
4. Create "Trivia" category and tag events

### Short-term (Week 2-3)
1. Complete Phase 2: Schema setup in TA
2. Complete Phase 3: Build adapter layer
3. Begin Phase 4: Integration

### Medium-term (Week 4)
1. Complete Phase 4: Integration
2. Complete Phase 5: Testing
3. Complete Phase 6: Migration & cleanup

---

## Questions for Discussion

1. **Approach Confirmation:** Do you prefer Direct Postgres (recommended) or GraphQL API?

2. **Supabase Access:** Do you have admin access to create read-only users in Supabase?

3. **Data Scope:** Should TA show only trivia events, or all events from EA?

4. **Backwards Compatibility:** Do we need to preserve TA's existing event data, or can we fully migrate to EA?

5. **Performance SLA:** What are the acceptable response times for event queries in TA?

6. **Deployment:** Will this be deployed to production gradually (feature flag) or all at once?

---

## Appendix: Code Examples

### Example: Read-Only Schema Definition

```elixir
# lib/trivia_advisor/eventasaurus/public_event.ex
defmodule TriviaAdvisor.Eventasaurus.PublicEvent do
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: false}
  @schema_prefix "public"

  schema "public_events" do
    field :title, :string
    field :slug, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :occurrences, :map

    belongs_to :venue, TriviaAdvisor.Eventasaurus.Venue
    belongs_to :category, TriviaAdvisor.Eventasaurus.Category

    has_many :sources, TriviaAdvisor.Eventasaurus.PublicEventSource, foreign_key: :event_id

    timestamps()
  end

  # Read-only schema - no changesets needed
end
```

### Example: Transformation Function

```elixir
defmodule TriviaAdvisor.Adapters.EventasaurusAdapter do
  def transform_event(%PublicEvent{} = ea_event) do
    # Extract day of week from starts_at
    day_of_week = DateTime.to_date(ea_event.starts_at) |> Date.day_of_week() |> normalize_day_of_week()

    # Extract time
    start_time = DateTime.to_time(ea_event.starts_at)

    # Detect frequency from occurrences
    frequency = detect_frequency(ea_event.occurrences)

    # Get pricing from first source
    entry_fee_cents = get_entry_fee_cents(ea_event.sources)

    # Build TA event struct
    %{
      id: ea_event.id,
      name: ea_event.title,
      venue_id: ea_event.venue_id,
      day_of_week: day_of_week,
      start_time: start_time,
      frequency: frequency,
      entry_fee_cents: entry_fee_cents,
      description: get_description(ea_event.sources),
      # Virtual field for display
      source: "Eventasaurus",
      inserted_at: ea_event.inserted_at,
      updated_at: ea_event.updated_at
    }
  end

  defp normalize_day_of_week(7), do: 0  # Sunday: Elixir uses 7, TA uses 0
  defp normalize_day_of_week(day), do: day

  defp detect_frequency(%{"dates" => dates}) when is_list(dates) do
    case length(dates) do
      n when n <= 1 -> :irregular
      n when n >= 4 -> :weekly
      _ -> :irregular
    end
  end
  defp detect_frequency(_), do: :irregular

  defp get_entry_fee_cents(sources) do
    sources
    |> Enum.find_value(fn source ->
      if source.min_price do
        Decimal.to_integer(Decimal.mult(source.min_price, 100))
      end
    end)
  end

  defp get_description(sources) do
    sources
    |> Enum.find_value(fn source ->
      case source.description_translations do
        %{"en" => desc} -> desc
        _ -> nil
      end
    end)
  end
end
```

---

## Conclusion

The recommended approach is **Direct Postgres read-only access with transformation layer** because it:
- ✅ Is simplest to implement (1-2 weeks total)
- ✅ Leverages existing Ecto knowledge
- ✅ Provides type safety and performance
- ✅ Requires minimal infrastructure changes

The main work is in building the transformation layer to handle the data model differences between TA's recurring event model and EA's date-specific model. Once this adapter is in place, Trivia Advisor becomes a read-only consumer of Eventasaurus data, eliminating duplicate scraping infrastructure and ensuring a single source of truth for event data.
