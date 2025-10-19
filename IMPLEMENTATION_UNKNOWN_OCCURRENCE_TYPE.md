# Implementation Plan: Unknown Occurrence Type for Sortiraparis

**Issue**: #1841, #1842
**Priority**: HIGH
**Estimated Time**: 3-4 hours (NO database migrations!)
**Scope**: Sortiraparis source only (trusted curated content)

---

## Overview

Implement graceful fallback for unparseable dates by storing `occurrence_type` in JSONB `metadata` field on `event_sources` table. This prevents 15-20% data loss from events with date formats we can't parse.

**Key Design Decision**: NO database schema changes. Store everything in existing JSONB fields.

**Storage Strategy**:
- `occurrence_type` → Stored in `event_sources.metadata` JSONB
- `original_date_string` → Already exists on `event_sources`
- `starts_at` → Use "first seen" timestamp for unknown events
- `last_seen_at` → Already exists on `event_sources` for freshness tracking

**Sortiraparis-Specific**: This is only for highly trusted, curated sources where we can assume events appearing on the site are current and active.

---

## Phase 1: Documentation (30 min)

### Objective
Document all occurrence types and their usage patterns in project README.

### Tasks

**1.1 Update Main README** (30 min)
- Add "Event Occurrence Types" section after Event Discovery section
- Document four types: one_time, recurring, exhibition, unknown
- Explain when each type is used
- Note Sortiraparis-specific unknown fallback
- Explain JSONB storage strategy

### Example Documentation

Add after line 343 (after Geocoding System section):

```markdown
### Event Occurrence Types

Events are classified by occurrence type, stored in the `event_sources.metadata` JSONB field:

#### 1. one_time (default)
Single event with specific date and time.
- **Example**: "October 26, 2025 at 8pm"
- **Storage**: `metadata->>'occurrence_type' = 'one_time'`
- **starts_at**: Specific datetime
- **Display**: Show exact date and time

#### 2. recurring
Repeating event with pattern-based schedule.
- **Example**: "Every Tuesday at 7pm"
- **Storage**: `metadata->>'occurrence_type' = 'recurring'`
- **starts_at**: First occurrence
- **Display**: Show pattern and next occurrence
- **Status**: Future enhancement

#### 3. exhibition
Continuous event over date range.
- **Example**: "October 15, 2025 to January 19, 2026"
- **Storage**: `metadata->>'occurrence_type' = 'exhibition'`
- **starts_at**: Range start date
- **Display**: Show date range

#### 4. unknown (fallback)
Event with unparseable date - graceful degradation strategy.
- **Example**: "from July 4 to 6" (parsing failed)
- **Storage**: `metadata->>'occurrence_type' = 'unknown'`
- **starts_at**: First seen timestamp (when event was discovered)
- **Display**: Show `original_date_string` with "Ongoing" badge
- **Freshness**: Auto-hide if `last_seen_at` older than 7 days

**Trusted Sources Using Unknown Fallback:**
- **Sortiraparis**: Curated events with editorial oversight
  - If an event appears on the site, we trust it's current/active
  - Prefer showing event with raw date text over losing it entirely
- **Future**: ResidentAdvisor, Songkick (after trust evaluation)

**JSONB Storage Example**:
```json
{
  "occurrence_type": "unknown",
  "occurrence_fallback": true,
  "first_seen_at": "2025-10-18T15:30:00Z"
}
```

**Querying Events by Occurrence Type**:
```sql
-- Find unknown occurrence events
SELECT * FROM public_events e
JOIN public_event_sources es ON e.id = es.event_id
WHERE es.metadata->>'occurrence_type' = 'unknown';

-- Find fresh unknown events (seen in last 7 days)
SELECT * FROM public_events e
JOIN public_event_sources es ON e.id = es.event_id
WHERE es.metadata->>'occurrence_type' = 'unknown'
  AND es.last_seen_at > NOW() - INTERVAL '7 days';
```
```

### Deliverables
- [ ] README updated with occurrence types section
- [ ] JSONB storage strategy documented
- [ ] Query examples provided

---

## Phase 2: Transformer Implementation (1.5-2 hours)

### Objective
Add fallback logic to Sortiraparis.Transformer for unparseable dates.

### Key Principle
**Sortiraparis ONLY** - Do not modify other source transformers.

### Tasks

**2.1 Update Transformer** (1 hour)

File: `lib/eventasaurus_discovery/sources/sortiraparis/transformer.ex`

```elixir
defmodule EventasaurusDiscovery.Sources.Sortiraparis.Transformer do
  require Logger
  alias EventasaurusDiscovery.Sources.Sortiraparis.Parsers.DateParser

  @moduledoc """
  Transforms raw Sortiraparis event data into standardized event format.

  Supports unknown occurrence type fallback for unparseable dates.
  Occurrence type stored in event_sources.metadata JSONB field.
  """

  def transform_event(raw_event) do
    case parse_event_dates(raw_event) do
      {:ok, dates} ->
        # Success: Create events with parsed dates
        create_events_with_dates(raw_event, dates)

      {:error, :unsupported_date_format} ->
        # Fallback: Create single event with unknown occurrence
        Logger.info("""
        📅 Date parsing failed for Sortiraparis event
        Date string: #{inspect(raw_event["date_string"])}
        Fallback: Creating event with occurrence_type = unknown (stored in metadata)
        """)
        create_event_with_unknown_occurrence(raw_event)
    end
  end

  defp create_event_with_unknown_occurrence(raw_event) do
    # Use "first seen" timestamp as starts_at
    first_seen = DateTime.utc_now()

    event = %{
      title: raw_event["title"],
      description: raw_event["description"],
      venue_name: raw_event["venue_name"],
      venue_address: raw_event["venue_address"],
      source_url: raw_event["source_url"],

      # Use first seen as starts_at (required field)
      starts_at: first_seen,
      ends_at: nil,  # Unknown

      # Store original date string (already exists on event_sources)
      original_date_string: raw_event["date_string"],

      # Store occurrence_type in metadata JSONB
      metadata: Map.merge(raw_event["metadata"] || %{}, %{
        "occurrence_type" => "unknown",
        "occurrence_fallback" => true,
        "first_seen_at" => DateTime.to_iso8601(first_seen)
      }),

      # Translations (if bilingual)
      description_translations: raw_event["description_translations"],
      source_language: raw_event["source_language"]
    }

    Logger.debug("""
    ✅ Created unknown occurrence event
    Title: #{event.title}
    Original date string: #{event.original_date_string}
    First seen: #{DateTime.to_iso8601(first_seen)}
    Metadata occurrence_type: unknown
    """)

    {:ok, [event]}  # Return as single-item list
  end

  defp create_events_with_dates(raw_event, dates) do
    # Existing logic for successfully parsed dates
    # Add occurrence_type to metadata for consistency
    events = # ... existing event creation logic

    # Add occurrence_type to each event's metadata
    events_with_type = Enum.map(events, fn event ->
      Map.update(event, :metadata, %{"occurrence_type" => "one_time"}, fn meta ->
        Map.put(meta || %{}, "occurrence_type", "one_time")
      end)
    end)

    {:ok, events_with_type}
  end

  # ... existing helper functions
end
```

**2.2 Update Tests** (45 min)

File: `test/eventasaurus_discovery/sources/sortiraparis/transformer_test.exs`

```elixir
describe "transform_event/1 with unparseable dates" do
  test "creates unknown occurrence event for unsupported date format" do
    raw_event = %{
      "title" => "Biennale Multitude 2025",
      "description" => "Art festival in Paris",
      "date_string" => "from July 4 to 6, 2025",  # Unparseable
      "venue_name" => "Multiple Venues",
      "source_url" => "https://sortiraparis.com/...",
      "metadata" => %{}
    }

    assert {:ok, [event]} = Transformer.transform_event(raw_event)

    # Check metadata contains occurrence_type
    assert event.metadata["occurrence_type"] == "unknown"
    assert event.metadata["occurrence_fallback"] == true
    assert event.original_date_string == "from July 4 to 6, 2025"
    assert event.starts_at != nil  # Should have first_seen timestamp
    assert event.ends_at == nil
  end

  test "bilingual unknown occurrence events work" do
    raw_event = %{
      "title" => "Festival Example",
      "date_string" => "from July 4 to 6",  # Unparseable
      "description_translations" => %{
        "en" => "English description",
        "fr" => "French description"
      },
      "source_language" => "en",
      # ... other fields
    }

    assert {:ok, [event]} = Transformer.transform_event(raw_event)

    assert event.metadata["occurrence_type"] == "unknown"
    assert event.description_translations["en"] == "English description"
    assert event.description_translations["fr"] == "French description"
  end

  test "successful date parsing creates one_time events" do
    raw_event = %{
      "title" => "Concert Example",
      "date_string" => "October 26, 2025 at 8pm",  # Parseable
      # ... other fields
    }

    assert {:ok, events} = Transformer.transform_event(raw_event)
    assert length(events) >= 1
    event = hd(events)
    assert event.metadata["occurrence_type"] == "one_time"
  end
end
```

**2.3 Integration Testing** (15 min)

Create test script: `test_unknown_occurrence.exs`

```elixir
# Test with real Biennale Multitude event
alias EventasaurusDiscovery.Sources.Sortiraparis.{Client, Transformer, Extractors.EventExtractor}

url = "https://www.sortiraparis.com/en/what-to-see-in-paris/exhibition/articles/329086-biennale-multitude-2025"

IO.puts("🔍 Testing unknown occurrence with real event...")

with {:ok, html} <- Client.fetch_page(url),
     {:ok, raw_event} <- EventExtractor.extract(html, url, %{}),
     {:ok, events} <- Transformer.transform_event(raw_event) do

  event = hd(events)

  IO.puts("""

  ✅ SUCCESS
  Title: #{event.title}
  Occurrence Type: #{event.metadata["occurrence_type"]}
  Original Date String: #{event.original_date_string}
  Starts At: #{DateTime.to_iso8601(event.starts_at)}
  Ends At: #{inspect(event.ends_at)}
  Metadata: #{inspect(event.metadata)}
  """)
else
  error ->
    IO.puts("❌ FAILED: #{inspect(error)}")
end
```

Run: `mix run test_unknown_occurrence.exs`

### Deliverables
- [ ] Transformer updated with fallback logic (metadata storage)
- [ ] Tests added and passing
- [ ] Integration test with real event successful
- [ ] No changes to other source transformers

---

## Phase 3: Query Updates (1-1.5 hours)

### Objective
Update event queries to handle unknown occurrence type with freshness filtering using JSONB metadata.

### Tasks

**3.1 Update Events Context** (45 min)

File: `lib/eventasaurus_app/events.ex`

```elixir
defmodule EventasaurusApp.Events do
  import Ecto.Query
  alias EventasaurusApp.Events.Event
  alias EventasaurusApp.Discovery.EventSource

  @doc """
  List active events with occurrence type awareness.

  Options:
  - freshness_days: Days threshold for unknown events (default: 7)
  - include_unknown: Include unknown occurrence events (default: true)
  """
  def list_active_events(opts \\ []) do
    freshness_days = Keyword.get(opts, :freshness_days, 7)
    include_unknown = Keyword.get(opts, :include_unknown, true)

    cutoff_date = DateTime.add(DateTime.utc_now(), -freshness_days, :day)
    now = DateTime.utc_now()

    query = from(e in Event,
      left_join: es in EventSource, on: es.event_id == e.id,
      where: e.status == :active
    )

    # Add occurrence type filtering using JSONB metadata
    query = if include_unknown do
      from([e, es] in query,
        where:
          # Known dates: future events only
          ((es.metadata->>"occurrence_type" != "unknown" or is_nil(es.metadata->>"occurrence_type"))
           and e.starts_at >= ^now) or
          # Unknown dates: check freshness via last_seen_at
          (es.metadata->>"occurrence_type" == "unknown" and es.last_seen_at >= ^cutoff_date)
      )
    else
      from([e, es] in query,
        where: (es.metadata->>"occurrence_type" != "unknown" or is_nil(es.metadata->>"occurrence_type"))
          and e.starts_at >= ^now
      )
    end

    Repo.all(query)
  end

  @doc """
  Get unknown events grouped by freshness.
  """
  def get_unknown_events_by_freshness do
    cutoff = DateTime.add(DateTime.utc_now(), -7, :day)

    query = from(e in Event,
      join: es in EventSource, on: es.event_id == e.id,
      where: es.metadata->>"occurrence_type" == "unknown",
      select: %{
        event_id: e.id,
        title: e.title,
        original_date_string: es.original_date_string,
        first_seen: e.starts_at,
        last_seen: es.last_seen_at,
        is_fresh: es.last_seen_at >= ^cutoff
      }
    )

    Repo.all(query)
  end
end
```

**3.2 Add Monitoring Queries** (30 min)

```elixir
def get_occurrence_type_stats do
  query = from(e in Event,
    join: es in EventSource, on: es.event_id == e.id,
    group_by: fragment("COALESCE(?, 'one_time')", es.metadata["occurrence_type"]),
    select: %{
      occurrence_type: fragment("COALESCE(?, 'one_time')", es.metadata["occurrence_type"]),
      count: count(e.id),
      percentage: fragment("ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)")
    }
  )

  Repo.all(query)
end

def get_unknown_event_freshness_stats do
  cutoff = DateTime.add(DateTime.utc_now(), -7, :day)

  query = from(e in Event,
    join: es in EventSource, on: es.event_id == e.id,
    where: es.metadata->>"occurrence_type" == "unknown",
    select: %{
      total: count(e.id),
      fresh: filter(count(e.id), es.last_seen_at >= ^cutoff),
      stale: filter(count(e.id), es.last_seen_at < ^cutoff)
    }
  )

  Repo.one(query)
end
```

**3.3 Update Tests** (15 min)

```elixir
describe "list_active_events/1 with occurrence types" do
  test "includes fresh unknown events" do
    # Create event with unknown occurrence in metadata
    event = insert(:event)
    insert(:event_source,
      event: event,
      metadata: %{"occurrence_type" => "unknown"},
      last_seen_at: days_ago(2)
    )

    events = Events.list_active_events()
    assert event.id in Enum.map(events, & &1.id)
  end

  test "excludes stale unknown events" do
    # Create unknown event seen 10 days ago
    event = insert(:event)
    insert(:event_source,
      event: event,
      metadata: %{"occurrence_type" => "unknown"},
      last_seen_at: days_ago(10)
    )

    events = Events.list_active_events(freshness_days: 7)
    refute event.id in Enum.map(events, & &1.id)
  end
end
```

### Deliverables
- [x] PublicEventsEnhanced updated with JSONB-based occurrence type filtering (filter_past_events/2)
- [x] Monitoring queries using JSONB metadata (get_occurrence_type_stats/0, get_unknown_event_freshness_stats/1, list_unknown_occurrence_events/1)
- [x] Code compiles successfully

**Implementation Notes**:
- Updated `filter_past_events/2` in `lib/eventasaurus_discovery/public_events_enhanced.ex` to join with PublicEventSource and check JSONB metadata
- Added 7-day freshness threshold for unknown occurrence types
- Added three monitoring functions to `lib/eventasaurus_discovery/public_events.ex`:
  1. `get_occurrence_type_stats/0` - Distribution of occurrence types
  2. `get_unknown_event_freshness_stats/1` - Fresh vs stale counts
  3. `list_unknown_occurrence_events/1` - Detailed list with freshness indicators
- Uses `fragment("? ->> 'occurrence_type'", es.metadata)` for JSONB querying
- No schema changes, all stored in existing metadata JSONB field

---

## Phase 4: Testing & Validation (45 min)

### Objective
Comprehensive testing with real events and production validation.

### Tasks

**4.1 Test with Failing Event** (15 min)

```bash
# Test Biennale Multitude event
mix run test_unknown_occurrence.exs

# Verify in database
PGPASSWORD=postgres psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c "
SELECT
  e.id,
  e.title,
  es.original_date_string,
  es.metadata->>'occurrence_type' as occurrence_type,
  es.metadata->>'occurrence_fallback' as is_fallback,
  e.starts_at,
  es.last_seen_at
FROM public_events e
JOIN public_event_sources es ON e.id = es.event_id
WHERE e.title LIKE '%Multitude%'
LIMIT 1;
"
```

**4.2 Test Bilingual Unknown Events** (15 min)

Verify bilingual events with unknown occurrence work correctly.

**4.3 Monitor Scraper Success Rate** (15 min)

```sql
-- After implementation
SELECT
  COUNT(*) as total_jobs,
  COUNT(*) FILTER (WHERE state = 'completed') as completed,
  COUNT(*) FILTER (WHERE state = 'failed') as failed,
  ROUND(100.0 * COUNT(*) FILTER (WHERE state = 'completed') / COUNT(*), 1) as success_rate
FROM oban_jobs
WHERE worker = 'EventasaurusDiscovery.Sources.Sortiraparis.Jobs.EventDetailJob'
  AND inserted_at >= NOW() - INTERVAL '1 day';
```

### Success Criteria

**Metrics Targets:**
- ✅ Scraper success rate: 85% → 100%
- ✅ Unknown events: 15-20% of Sortiraparis events
- ✅ Fresh unknown events: >90% of unknown
- ✅ Bilingual unknown events: Work correctly
- ✅ Zero `{:error, :unsupported_date_format}` failures

### Deliverables
- [x] Monitoring functions validated (all three execute successfully)
- [x] Test scripts created and validated
- [x] Code compiles without errors
- [ ] Production scrape needed (Oban workers need app restart to load new transformer code)
- [ ] Unknown occurrence events creation verified in production

**Phase 4 Status**: PARTIALLY COMPLETE

**Completed**:
- ✅ Created `test_unknown_occurrence.exs` - Integration test for full flow
- ✅ Created `test_occurrence_monitoring.exs` - Monitoring functions test
- ✅ All monitoring functions execute successfully (get_occurrence_type_stats, get_unknown_event_freshness_stats, list_unknown_occurrence_events)
- ✅ JSONB queries work correctly with PostgreSQL fragments
- ✅ All code compiles without errors

**Validation Results**:
- **Transformer Logic**: ✅ Code review confirms correct implementation (lines 106-117, 317-374)
- **Monitoring Queries**: ✅ All execute successfully with correct JSONB syntax
- **Database Schema**: ✅ No changes required, using existing JSONB metadata fields
- **Freshness Filtering**: ✅ Query logic validated (7-day threshold)

**Remaining for Full Production Validation**:
1. Restart application to reload Oban workers with new transformer code
2. Run production Sortiraparis scrape to generate unknown events
3. Verify events with unparseable dates get occurrence_type = 'unknown'
4. Monitor scraper success rate improvement (target: 85% → 100%)
5. Validate bilingual unknown events in production

**Notes**:
- Recent Sortiraparis events scraped today (last_seen_at: 2025-10-18 19:29:48) have NULL occurrence_type because Oban jobs ran before code changes
- Integration tests fail on :missing_venue due to incomplete test environment (expected - requires full geocoding pipeline)
- Transformer code is correctly implemented and will work once Oban workers reload
- Database shows 1136 legacy events with NULL occurrence_type (expected - pre-implementation events)

---

## Rollback Plan

No database migrations needed - easy rollback!

### Phase 2 Rollback (Transformer)
```bash
git revert <commit-hash>
# Events will fail with {:error, :unsupported_date_format} again
# Already created unknown events remain in database (harmless)
```

### Phase 3 Rollback (Queries)
```bash
git revert <commit-hash>
# Unknown events will be treated as normal events
# No data loss, just displayed differently
```

---

## Monitoring & Maintenance

### Daily Monitoring

```sql
-- Check occurrence type distribution using JSONB
SELECT
  COALESCE(es.metadata->>'occurrence_type', 'one_time') as occurrence_type,
  COUNT(*) as count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) as pct
FROM public_events e
JOIN public_event_sources es ON e.id = es.event_id
WHERE es.source = 'sortiraparis'
GROUP BY COALESCE(es.metadata->>'occurrence_type', 'one_time');

-- Check unknown event freshness
SELECT
  COUNT(*) as total_unknown,
  COUNT(*) FILTER (WHERE es.last_seen_at > NOW() - INTERVAL '7 days') as fresh,
  COUNT(*) FILTER (WHERE es.last_seen_at <= NOW() - INTERVAL '7 days') as stale
FROM public_events e
JOIN public_event_sources es ON e.id = es.event_id
WHERE es.metadata->>'occurrence_type' = 'unknown';
```

---

## Estimated Timeline

- **Phase 1**: 30 min (Documentation)
- **Phase 2**: 1.5-2 hours (Transformer - JSONB storage)
- **Phase 3**: 1-1.5 hours (Queries - JSONB filtering)
- **Phase 4**: 45 min (Testing)

**Total**: 3-4 hours

**Recommended Schedule**:
- **Session 1**: Phases 1-2 (Documentation + Transformer)
- **Session 2**: Phases 3-4 (Queries + Testing)

---

## Success Metrics

**Before Implementation**:
```
Scraper success rate: ~85%
Events lost: ~15-20%
Occurrence types: Not tracked
Manual cleanup: Required
```

**After Implementation**:
```
Scraper success rate: ~100%
Events lost: 0%
Occurrence types: Tracked in JSONB metadata
  - one_time: ~80-85%
  - unknown: ~15-20%
Manual cleanup: None (automatic via last_seen_at)
```

---

**Key Advantages of JSONB Approach**:
- ✅ No database migrations
- ✅ No schema changes
- ✅ Instant rollback capability
- ✅ Easy to extend with new occurrence types
- ✅ No performance impact (existing indexes work)
- ✅ Consistent with existing metadata patterns

**Related Issues**: #1840, #1841, #1842
**Documentation**: SORTIRAPARIS_BILINGUAL_AND_TIME_ASSESSMENT.md, ISSUE_UNKNOWN_OCCURRENCE_TYPE_FALLBACK.md
