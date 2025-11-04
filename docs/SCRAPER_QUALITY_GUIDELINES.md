# Scraper Quality Guidelines

**Purpose**: Best practices for building high-quality event scrapers, extracted from production scrapers and quality improvement projects.

**Target Audience**: Developers implementing new event source scrapers

**Quality Target**: 95%+ overall quality score on quality dashboard

---

## Table of Contents

1. [Quality Metrics Overview](#quality-metrics-overview)
2. [Data Pipeline Quality](#data-pipeline-quality)
3. [Recurring Events Best Practices](#recurring-events-best-practices)
4. [Performer Data Guidelines](#performer-data-guidelines)
5. [Timezone Handling](#timezone-handling)
6. [Quality Validation](#quality-validation)
7. [Common Pitfalls](#common-pitfalls)
8. [Reference Implementations](#reference-implementations)

---

## Quality Metrics Overview

### Quality Dashboard Metrics

The quality checker (`lib/eventasaurus_discovery/admin/data_quality_checker.ex`) measures:

**Core Metrics (Weighted):**
- **Venue Completeness** (20%): Percentage of events with complete venue information
- **Image Quality** (20%): Percentage of events with valid images
- **Category Data** (15%): Percentage of events with proper categorization
- **Performer Data** (15%): Percentage of events with performer information
- **Description Quality** (10%): Percentage of events with descriptions
- **Occurrence Validity** (10%): Percentage of events with valid occurrence data
- **Time Quality** (5%): Percentage of events with properly formatted times
- **Ticket Info** (5%): Percentage of events with ticket information

**Overall Quality Score**: Weighted average of all metrics (target: 95%+)

### Quality Score Interpretation

- **95%+**: Excellent - Production ready
- **85-94%**: Good - Minor improvements needed
- **75-84%**: Fair - Significant improvements recommended
- **Below 75%**: Poor - Major issues to address

---

## Data Pipeline Quality

### 1. Scraper Layer (Data Collection)

**Best Practices:**
- ✅ Extract all available data from source (don't filter prematurely)
- ✅ Store raw data in meaningful structure (maps with atom keys)
- ✅ Include source URLs for debugging and verification
- ✅ Handle pagination correctly (don't miss events)
- ✅ Respect rate limits and implement backoff strategies
- ✅ Log warnings for missing or malformed data

**Anti-Patterns:**
- ❌ Filtering data based on assumptions (let transformer decide)
- ❌ Hardcoding values that should come from source
- ❌ Ignoring errors silently (always log and handle)
- ❌ Making multiple requests for data available in single response

**Example** (Geeks Who Drink VenueListJob):
```elixir
# ✅ GOOD: Extract all available data
venue_data = %{
  venue_id: venue_id,
  title: venue_name,
  address: address,
  latitude: lat,
  longitude: lng,
  time_text: time_text,
  start_time: start_time,
  performer: performer_data,
  brand: brand,
  fee_text: fee_text,
  source_url: "https://www.geekswhodrink.com/venue/#{venue_id}"
}

# ❌ BAD: Filtering or transforming too early
venue_data = %{
  venue_id: venue_id,
  title: String.upcase(venue_name),  # Don't transform here
  # Missing optional fields like fee_text
}
```

### 2. Transformer Layer (Data Transformation)

**Best Practices:**
- ✅ Normalize data to standard formats (dates, times, addresses)
- ✅ Create recurrence_rule for recurring events (see Recurring Events section)
- ✅ Extract categories from source-specific data
- ✅ Build proper metadata structure (preserve source-specific details)
- ✅ Validate transformed data before returning
- ✅ Provide fallback values for optional fields

**Anti-Patterns:**
- ❌ Losing data during transformation (always preserve in metadata)
- ❌ Assuming data format without validation
- ❌ Hardcoding values that vary by venue/event
- ❌ Skipping validation of transformed output

**Example** (Geeks Who Drink Transformer):
```elixir
# ✅ GOOD: Comprehensive transformation with validation
def transform_event(venue_data) do
  %{
    title: build_title(venue_data),
    description: build_description(venue_data),
    venue: build_venue(venue_data),
    categories: ["Trivia", "Nightlife"],
    image_url: get_image_url(venue_data),
    starts_at: venue_data[:starts_at],
    recurrence_rule: build_recurrence_rule(venue_data),
    metadata: build_metadata(venue_data),
    source_url: venue_data[:source_url]
  }
  |> validate_required_fields()
end

# ❌ BAD: Minimal transformation, missing fields
def transform_event(venue_data) do
  %{
    title: venue_data.title,
    venue: %{name: venue_data.title}
    # Missing: description, categories, recurrence_rule, metadata
  }
end
```

### 3. EventProcessor Layer (Storage)

**Best Practices:**
- ✅ Use EventProcessor for all event storage (don't bypass)
- ✅ Let EventProcessor handle occurrence structure generation
- ✅ Provide complete event_data to processor
- ✅ Trust EventProcessor for pattern vs explicit detection
- ✅ Monitor EventProcessor warnings for data quality issues

**Anti-Patterns:**
- ❌ Bypassing EventProcessor and writing directly to database
- ❌ Manually constructing occurrence structures
- ❌ Ignoring EventProcessor validation errors
- ❌ Overriding EventProcessor defaults without good reason

---

## Recurring Events Best Practices

### When to Use Pattern-Type Occurrences

**Use Pattern-Type When:**
- ✅ Events happen on consistent schedule (weekly/monthly)
- ✅ Same venue, same day of week, same time
- ✅ Schedule text indicates recurring pattern ("Every Tuesday", "Weekly trivia")
- ✅ Source provides schedule information (not just next occurrence)

**Use Explicit-Type When:**
- ✅ Events are one-time or irregular
- ✅ Schedule varies (different times each week)
- ✅ Only specific dates are known (concerts, festivals)
- ✅ Source only provides next occurrence date

### Recurrence Rule Construction

**Method 1: Extract from DateTime (Recommended for Multi-Timezone Sources)**

Use when VenueDetailJob calculates `starts_at` with correct timezone.

```elixir
def parse_schedule_to_recurrence(time_text, starts_at, venue_data) do
  # Extract from starts_at DateTime (most reliable for multi-timezone)
  case extract_from_datetime(starts_at, venue_data) do
    {:ok, {day_of_week, time_string, timezone}} ->
      recurrence_rule = %{
        "frequency" => "weekly",
        "days_of_week" => [day_of_week],
        "time" => time_string,
        "timezone" => timezone
      }
      {:ok, recurrence_rule}

    {:error, _reason} ->
      # Fallback to text parsing if needed
      parse_time_text(time_text, venue_data)
  end
end

defp extract_from_datetime(%DateTime{} = dt, venue_data) do
  timezone = venue_data[:timezone] || "America/New_York"
  local_dt = DateTime.shift_zone!(dt, timezone)

  day_num = Date.day_of_week(DateTime.to_date(local_dt), :monday)
  day_of_week = number_to_day(day_num)

  time_string = local_dt
    |> DateTime.to_time()
    |> Time.to_string()
    |> String.slice(0, 5)

  {:ok, {day_of_week, time_string, timezone}}
rescue
  error -> {:error, "DateTime extraction failed: #{inspect(error)}"}
end
```

**Benefits:**
- Most reliable for multi-timezone sources
- No parsing errors from ambiguous text
- Timezone accuracy guaranteed
- Works when schedule text lacks timezone

**When to Use:**
- Multi-timezone sources (US, Canada, Europe-wide)
- Schedule text doesn't include timezone
- VenueDetailJob already calculates correct starts_at
- Higher reliability required

**Method 2: Parse Schedule Text (Single Timezone Sources)**

Use when source operates in single timezone and provides schedule text.

```elixir
def parse_schedule_to_recurrence(time_text, _starts_at, venue_data) do
  # Example: "Tuesdays at 7:30pm" or "Tuesday 19:30"
  case TimeParser.parse_recurring_schedule(time_text) do
    {:ok, {day_of_week, time}} ->
      recurrence_rule = %{
        "frequency" => "weekly",
        "days_of_week" => [day_of_week],
        "time" => format_time(time),
        "timezone" => venue_data[:timezone] || "Europe/Warsaw"
      }
      {:ok, recurrence_rule}

    {:error, _reason} ->
      {:error, "Could not parse schedule"}
  end
end
```

**Benefits:**
- Simpler implementation for single-timezone sources
- Works when DateTime not available
- Good for sources with consistent text format

**When to Use:**
- Single-timezone sources (Poland, UK, specific city)
- Reliable schedule text format
- Timezone is known and consistent

### Recurrence Rule Validation

Always validate recurrence_rule before including in event:

```elixir
defp validate_recurrence_rule(nil), do: {:ok, nil}

defp validate_recurrence_rule(rule) do
  required_fields = ["frequency", "days_of_week", "time", "timezone"]

  cond do
    not is_map(rule) ->
      {:error, "recurrence_rule must be a map"}

    Enum.any?(required_fields, fn field -> is_nil(rule[field]) end) ->
      {:error, "recurrence_rule missing required fields"}

    rule["frequency"] not in ["weekly", "monthly"] ->
      {:error, "invalid frequency"}

    not valid_time_format?(rule["time"]) ->
      {:error, "invalid time format (expected HH:MM)"}

    true ->
      {:ok, rule}
  end
end

defp valid_time_format?(time) do
  Regex.match?(~r/^\d{2}:\d{2}$/, time)
end
```

---

## Performer Data Guidelines

### Choosing Storage Method

**Decision Matrix:**

| Criteria | Use Metadata | Use Performers Table |
|----------|--------------|---------------------|
| **Number of performers** | Single | Multiple |
| **Performer info needed** | Name only | Name + bio + image + links |
| **Cross-event tracking** | No | Yes |
| **Search/filter by performer** | No | Yes |
| **Example use cases** | Quizmasters, DJs, hosts | Bands, comedians, speakers |

### Metadata Storage Pattern

**When to Use:**
- Single, simple performer per event
- Performer name is sufficient
- No cross-event performer tracking needed
- Source doesn't provide detailed performer info

**Implementation:**
```elixir
defp build_metadata(venue_data) do
  %{
    "quizmaster" => venue_data[:performer][:name],
    "brand" => venue_data[:brand],
    "fee_text" => venue_data[:fee_text],
    "timezone" => venue_data[:timezone]
  }
  |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  |> Map.new()
end
```

**Quality Checker Consideration:**

If using metadata pattern, ensure quality checker recognizes it (see `data_quality_checker.ex` lines 1116-1204 for example).

### Performers Table Pattern

**When to Use:**
- Multiple performers per event
- Detailed performer information available
- Cross-event performer tracking needed
- Performer-based search/filtering required

**Implementation:**
```elixir
def build_performers(event_data) do
  event_data[:performers]
  |> Enum.map(fn performer_data ->
    %{
      name: performer_data[:name],
      bio: performer_data[:bio],
      image_url: performer_data[:image_url],
      social_links: performer_data[:social_links],
      role: performer_data[:role] || "performer"
    }
  end)
end
```

**Database Storage:**

EventProcessor automatically handles performer storage in `public_event_performers` table.

---

## Timezone Handling

### Critical Principle

**Always store times in event's local timezone, never in UTC.**

Storing UTC times causes:
- ❌ Incorrect time display (01:00 instead of 19:00)
- ❌ False quality warnings
- ❌ Broken recurrence rules
- ❌ User confusion

### Timezone Extraction Hierarchy

**Priority Order:**
1. **Recurrence rule timezone** (most specific for pattern events)
2. **Metadata timezone** (event-specific)
3. **Venue timezone** (venue-level default)
4. **Source default timezone** (scraper-level fallback)

**Implementation:**
```elixir
defp extract_timezone(event_data) do
  cond do
    # Priority 1: recurrence_rule timezone
    event_data[:recurrence_rule] && event_data[:recurrence_rule]["timezone"] ->
      event_data[:recurrence_rule]["timezone"]

    # Priority 2: metadata timezone
    event_data[:metadata] && event_data[:metadata]["timezone"] ->
      event_data[:metadata]["timezone"]

    # Priority 3: venue timezone
    event_data[:venue] && event_data[:venue][:timezone] ->
      event_data[:venue][:timezone]

    # Priority 4: source default
    true ->
      "America/New_York"  # Replace with source-specific default
  end
end
```

### Single-Timezone Sources

**Simple Approach:**

If source operates entirely in one timezone (e.g., PubQuiz in Poland, Question One in UK):

```elixir
# In transformer
defp build_metadata(venue_data) do
  %{
    "timezone" => "Europe/Warsaw",  # Hardcode source timezone
    # ... other metadata
  }
end
```

### Multi-Timezone Sources

**Complex Approach:**

If source spans multiple timezones (e.g., Geeks Who Drink across US):

```elixir
# In VenueDetailJob
defp enrich_venue_data(venue_data, details, next_occurrence) do
  venue_data
  |> Map.put(:starts_at, next_occurrence)
  |> Map.put(:timezone, determine_venue_timezone(venue_data))
end

defp determine_venue_timezone(venue_data) do
  # Option 1: Use geocoding service
  Geocoder.timezone(venue_data[:latitude], venue_data[:longitude])

  # Option 2: Use state/region mapping
  state_to_timezone(venue_data[:state])

  # Option 3: Extract from source data if available
  venue_data[:timezone] || "America/New_York"
end
```

### Timezone Validation

```elixir
defp validate_timezone(timezone) do
  case Tzdata.zone_exists?(timezone) do
    true -> {:ok, timezone}
    false -> {:error, "Invalid timezone: #{timezone}"}
  end
end
```

---

## Quality Validation

### Pre-Deployment Checklist

Before deploying a new scraper, validate:

**1. Code Quality:**
- [ ] All functions have documentation
- [ ] Error handling for all external calls
- [ ] Logging for warnings and errors
- [ ] Test coverage for critical paths
- [ ] Code review completed

**2. Data Quality:**
- [ ] Run scraper on test environment
- [ ] Check quality dashboard metrics (target: 95%+)
- [ ] Verify recurring events show as pattern-type
- [ ] Confirm timezone handling (times show in local, not UTC)
- [ ] Validate performer data storage (metadata or table)

**3. Production Readiness:**
- [ ] Rate limiting implemented
- [ ] Monitoring and alerting configured
- [ ] Error recovery mechanisms in place
- [ ] Documentation updated (README, patterns guide)
- [ ] Deployment plan documented

### Quality Validation Script

Create test script to validate quality improvements:

```elixir
# /tmp/test_scraper_quality.exs
alias EventasaurusDiscovery.Admin.DataQualityChecker

source_id = "your-source-id"

IO.puts("\n🧪 SCRAPER QUALITY VALIDATION\n")

quality = DataQualityChecker.check_quality(source_id)

IO.puts("📊 Quality Metrics:")
IO.puts("   Overall Quality Score: #{quality.quality_score}%")
IO.puts("   Venue Completeness: #{quality.venue_completeness}%")
IO.puts("   Image Quality: #{quality.image_quality}%")
IO.puts("   Performer Completeness: #{quality.performer_completeness}%")
IO.puts("   Occurrence Validity: #{quality.occurrence_validity}%")
IO.puts("")

recommendations = DataQualityChecker.get_recommendations(source_id)

IO.puts("💡 Quality Recommendations:")
if Enum.empty?(recommendations) do
  IO.puts("   ✨ No recommendations - quality is excellent!")
else
  Enum.each(recommendations, fn rec ->
    IO.puts("   - #{rec}")
  end)
end

success = quality.quality_score >= 95

IO.puts("")
if success do
  IO.puts("✅ QUALITY TARGET ACHIEVED!")
  IO.puts("   Ready for production deployment")
else
  IO.puts("⚠️  Quality below 95% target")
  IO.puts("   Review recommendations above")
end
```

Run with:
```bash
MIX_ENV=test mix run /tmp/test_scraper_quality.exs
```

### Quality Dashboard Analysis

Navigate to: `http://localhost:4000/admin/sources/{source_id}/quality`

**Review:**
- Overall quality score (target: 95%+)
- Individual metric scores
- Quality recommendations
- Sample events with issues

**Common Issues:**

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Low time quality | UTC times instead of local | Add timezone conversion |
| Low performer data | Missing metadata or table entries | Implement performer storage |
| Low occurrence validity | Missing recurrence_rule | Implement pattern detection |
| Low image quality | Missing or invalid URLs | Validate image URLs |
| Low venue completeness | Missing address/coordinates | Extract full venue data |

---

## Common Pitfalls

### 1. Timezone Mistakes

**Pitfall**: Storing times in UTC
```elixir
# ❌ BAD
starts_at: DateTime.utc_now()  # Will show wrong time
```

**Solution**: Store in local timezone
```elixir
# ✅ GOOD
{:ok, local_dt} = DateTime.from_naive(~N[2025-11-05 19:00:00], "America/New_York")
starts_at: local_dt
```

### 2. Missing Recurrence Rules

**Pitfall**: Storing recurring events as explicit-type
```elixir
# ❌ BAD: No recurrence_rule for weekly event
%{
  title: "Weekly Trivia",
  starts_at: next_tuesday,
  recurrence_rule: nil  # Missing!
}
```

**Solution**: Extract and include recurrence_rule
```elixir
# ✅ GOOD
%{
  title: "Weekly Trivia",
  starts_at: next_tuesday,
  recurrence_rule: %{
    "frequency" => "weekly",
    "days_of_week" => ["tuesday"],
    "time" => "19:00",
    "timezone" => "America/New_York"
  }
}
```

### 3. Incomplete Metadata

**Pitfall**: Losing source-specific data
```elixir
# ❌ BAD: Missing important source data
metadata: %{
  "brand" => venue_data[:brand]
  # Missing: quizmaster, fee_text, original_url
}
```

**Solution**: Preserve all source-specific details
```elixir
# ✅ GOOD
metadata: %{
  "brand" => venue_data[:brand],
  "quizmaster" => venue_data[:performer][:name],
  "fee_text" => venue_data[:fee_text],
  "original_url" => venue_data[:source_url]
}
```

### 4. Quality Checker Misalignment

**Pitfall**: Using metadata storage but quality checker only checks performers table
```elixir
# ❌ BAD: Quality checker won't find performers
metadata: %{"host" => "John Doe"}  # Quality checker doesn't check this key
```

**Solution**: Either use standard metadata key or update quality checker
```elixir
# ✅ GOOD: Use key quality checker recognizes
metadata: %{"quizmaster" => "John Doe"}  # Quality checker checks this

# OR update quality checker to recognize new key
fragment(
  "CASE WHEN jsonb_exists(?, 'host') OR jsonb_exists(?, 'quizmaster') THEN 1 ELSE 0 END",
  pes.metadata,
  pes.metadata
)
```

### 5. Hardcoded Values

**Pitfall**: Hardcoding data that should come from source
```elixir
# ❌ BAD: Hardcoded timezone for multi-timezone source
timezone: "America/New_York"  # Wrong for California venues!
```

**Solution**: Determine timezone from venue location
```elixir
# ✅ GOOD: Calculate timezone from coordinates
timezone: Geocoder.timezone(venue_data[:latitude], venue_data[:longitude])
```

### 6. Silent Failures

**Pitfall**: Ignoring errors without logging
```elixir
# ❌ BAD: Silent failure
case parse_time(time_text) do
  {:ok, time} -> time
  {:error, _} -> nil  # No logging!
end
```

**Solution**: Log warnings for debugging
```elixir
# ✅ GOOD: Log failure for investigation
case parse_time(time_text) do
  {:ok, time} ->
    time
  {:error, reason} ->
    Logger.warning("Failed to parse time '#{time_text}': #{reason}")
    nil
end
```

---

## Reference Implementations

### Excellent Examples (95%+ Quality)

**1. PubQuiz (Poland)**
- **Location**: `lib/eventasaurus_discovery/sources/pubquiz/`
- **Strengths**: Clean recurrence rule extraction, single-timezone handling
- **Pattern**: Text parsing for schedule (reliable format)
- **Quality Score**: 95%+

**2. Geeks Who Drink (US/Canada)**
- **Location**: `lib/eventasaurus_discovery/sources/geeks_who_drink/`
- **Strengths**: Multi-timezone support, DateTime extraction, hybrid performer storage
- **Pattern**: DateTime-based recurrence rule extraction
- **Quality Score**: 95%+ (after Phase 1-2 fixes)
- **Documentation**:
  - `GEEKS_WHO_DRINK_QUALITY_AUDIT.md`
  - `GEEKS_WHO_DRINK_PHASE1_COMPLETE.md`
  - `GEEKS_WHO_DRINK_PHASE2_COMPLETE.md`

### Quality Improvement Case Studies

**Geeks Who Drink: 52% → 95%+ Quality**

**Before:**
- Time Quality: 40% (UTC times instead of local)
- Performer Data: 0% (quality checker didn't recognize metadata)
- Occurrence Validity: 5% (explicit instead of pattern)

**Fixes:**
- Phase 1: Timezone-aware time formatting, DateTime-based recurrence extraction
- Phase 2: Quality checker updated to recognize metadata performers
- Phase 3: Documentation and guidelines

**After:**
- Time Quality: 95%+ (correct local times)
- Performer Data: 100% (metadata performers recognized)
- Occurrence Validity: 95%+ (pattern-type occurrences)

**Lessons**: See `docs/RECURRING_EVENT_PATTERNS.md` - "Lessons Learned from Geeks Who Drink Implementation"

---

## Quick Reference

### Quality Targets by Metric

| Metric | Target | Critical? |
|--------|--------|-----------|
| Venue Completeness | 95%+ | Yes |
| Image Quality | 90%+ | No |
| Category Data | 95%+ | Yes |
| Performer Data | 90%+ | No |
| Description Quality | 85%+ | No |
| Occurrence Validity | 95%+ | Yes |
| Time Quality | 95%+ | Yes |
| Ticket Info | 80%+ | No |

### Essential Files

- **Quality Checker**: `lib/eventasaurus_discovery/admin/data_quality_checker.ex`
- **Event Processor**: `lib/eventasaurus_discovery/scraping/processors/event_processor.ex`
- **Recurring Patterns**: `docs/RECURRING_EVENT_PATTERNS.md`
- **Reference Scrapers**:
  - `lib/eventasaurus_discovery/sources/pubquiz/`
  - `lib/eventasaurus_discovery/sources/geeks_who_drink/`

### Key Commands

```bash
# Run scraper
mix scraper.run source-id

# Check quality
mix scraper.quality source-id

# Run quality test script
MIX_ENV=test mix run /tmp/test_scraper_quality.exs

# View quality dashboard
# Navigate to: http://localhost:4000/admin/sources/{source_id}/quality
```

---

**Questions?** Review reference implementations or consult `docs/RECURRING_EVENT_PATTERNS.md` for detailed patterns.
