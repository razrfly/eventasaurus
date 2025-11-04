# Recurring Event Patterns

**Version:** 1.0
**Last Updated:** 2025-10-10
**Purpose:** Standardized pattern for scrapers handling recurring events with predictable schedules

---

## 🎯 Overview

Many event sources have recurring schedules (weekly trivia nights, monthly book clubs, daily movie showtimes). Instead of storing each occurrence as a separate event, we use **recurrence patterns** to generate future dates dynamically.

**Key Benefit:** One database record can represent hundreds of future occurrences, improving:
- Storage efficiency (one event vs. 50+ explicit occurrences)
- User experience (shows next 4+ upcoming dates)
- Data freshness (always shows future dates, no stale past events)
- Maintenance (update one pattern vs. regenerating all occurrences)

---

## 📐 Data Structure

### The `recurrence_rule` Field

Events with recurring schedules should include a `recurrence_rule` field in the event map passed to `Processor.process_single_event()`:

```elixir
%{
  title: "Weekly Trivia Night - The Local Pub",
  starts_at: ~U[2025-10-15 19:00:00Z],  # Next occurrence
  ends_at: ~U[2025-10-15 21:00:00Z],

  # Recurrence pattern (REQUIRED for recurring events)
  recurrence_rule: %{
    "frequency" => "weekly",              # "weekly" | "monthly"
    "days_of_week" => ["monday"],         # List of day names
    "time" => "19:00",                    # 24-hour format HH:MM
    "timezone" => "Europe/London"         # IANA timezone
  },

  # ... other event fields
}
```

### Field Specifications

#### `frequency` (required)
- **Type:** String
- **Values:** `"weekly"`, `"monthly"`
- **Description:** How often the event recurs

**Weekly Events** (~95% of recurring events):
```elixir
"frequency" => "weekly"
"days_of_week" => ["tuesday"]  # Every Tuesday
```

**Monthly Events** (~5% of recurring events):
```elixir
"frequency" => "monthly"
"days_of_week" => ["first_monday", "third_friday"]  # 1st Monday, 3rd Friday of month
```

#### `days_of_week` (required)
- **Type:** List of strings
- **Values:** `["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]`
- **For Monthly:** `["first_monday", "second_tuesday", "last_friday", ...]`
- **Description:** Which day(s) of the week the event occurs

**Examples:**
```elixir
# Single day
"days_of_week" => ["wednesday"]

# Multiple days (rare)
"days_of_week" => ["monday", "thursday"]

# Monthly pattern
"days_of_week" => ["first_saturday", "third_saturday"]
```

#### `time` (required)
- **Type:** String
- **Format:** `"HH:MM"` (24-hour format, zero-padded)
- **Description:** Time when event starts in the specified timezone

**Examples:**
```elixir
"time" => "19:00"  # 7:00 PM
"time" => "14:30"  # 2:30 PM
"time" => "09:00"  # 9:00 AM
```

#### `timezone` (required)
- **Type:** String
- **Format:** IANA timezone identifier
- **Description:** Timezone for the event (critical for accurate scheduling)

**Common Timezones:**
```elixir
"timezone" => "Europe/London"      # UK
"timezone" => "Europe/Warsaw"      # Poland
"timezone" => "America/New_York"   # US East
"timezone" => "America/Chicago"    # US Central
"timezone" => "America/Los_Angeles" # US West
"timezone" => "Australia/Sydney"   # Australia
```

---

## 🔄 How It Works

### EventProcessor Behavior

When `Processor.process_single_event()` receives an event with `recurrence_rule`:

```elixir
# lib/eventasaurus_discovery/scraping/processors/event_processor.ex
def initialize_occurrence_with_source(data, source) do
  if data.recurrence_rule do
    # Pattern-based: Frontend generates future dates
    %{
      "type" => "pattern",
      "pattern" => data.recurrence_rule
    }
  else
    # Explicit: Only shows stored dates
    %{
      "type" => "explicit",
      "dates" => [%{"date" => ..., "time" => ...}]
    }
  end
end
```

### Database Storage

The `recurrence_rule` is stored in the `public_events.occurrences` JSONB field:

```elixir
# With recurrence_rule
occurrences: %{
  "type" => "pattern",
  "pattern" => %{
    "frequency" => "weekly",
    "days_of_week" => ["monday"],
    "time" => "19:00",
    "timezone" => "Europe/London"
  }
}

# Without recurrence_rule (explicit dates only)
occurrences: %{
  "type" => "explicit",
  "dates" => [
    %{"date" => "2025-10-15", "time" => "19:00"}
  ]
}
```

### Frontend Display

**Pattern-Based Events** (with `recurrence_rule`):
- Generates next 4+ upcoming dates dynamically
- Shows "Every Monday at 7:00 PM" description
- Updates automatically (no stale dates)

**Explicit Events** (without `recurrence_rule`):
- Shows only stored dates (typically 1 date)
- Cannot generate future occurrences
- Requires re-scraping to add new dates

---

## 🛠️ Implementation Pattern

### Step 1: Parse Schedule Text to recurrence_rule

Create a parser function in your `Transformer` module:

```elixir
defmodule EventasaurusDiscovery.Sources.YourSource.Transformer do
  @doc """
  Parses schedule text into recurrence_rule JSON.

  ## Examples

      iex> parse_schedule_to_recurrence("Every Monday at 7:00 PM")
      {:ok, %{
        "frequency" => "weekly",
        "days_of_week" => ["monday"],
        "time" => "19:00",
        "timezone" => "Europe/London"
      }}
  """
  def parse_schedule_to_recurrence(schedule_text) do
    with {:ok, day_of_week} <- extract_day_of_week(schedule_text),
         {:ok, time} <- extract_time(schedule_text) do
      recurrence_rule = %{
        "frequency" => "weekly",
        "days_of_week" => [day_of_week],
        "time" => time,
        "timezone" => determine_timezone()  # Based on source location
      }

      {:ok, recurrence_rule}
    end
  end

  defp extract_day_of_week(text) do
    # Parse day names from schedule text
    # Map to lowercase English: "monday", "tuesday", etc.
  end

  defp extract_time(text) do
    # Extract time in HH:MM format
    case Regex.run(~r/(\d{1,2}):(\d{2})/, text) do
      [_, hour, minute] ->
        hour_padded = String.pad_leading(hour, 2, "0")
        {:ok, "#{hour_padded}:#{minute}"}

      nil ->
        {:error, :no_time_found}
    end
  end
end
```

### Step 2: Calculate Next Occurrence

Create a function to calculate the next upcoming event date:

```elixir
@doc """
Calculates the next occurrence datetime based on recurrence_rule.

Returns the next upcoming date/time when this event will occur.
"""
def calculate_next_occurrence(recurrence_rule) do
  timezone = recurrence_rule["timezone"]
  [day_of_week] = recurrence_rule["days_of_week"]
  time_str = recurrence_rule["time"]

  # Parse time
  [hour, minute] = String.split(time_str, ":") |> Enum.map(&String.to_integer/1)

  # Get current time in event timezone
  now = DateTime.now!(timezone)
  today = DateTime.to_date(now)

  # Map day names to numbers (1 = Monday, 7 = Sunday)
  day_numbers = %{
    "monday" => 1, "tuesday" => 2, "wednesday" => 3,
    "thursday" => 4, "friday" => 5, "saturday" => 6, "sunday" => 7
  }

  target_day_num = day_numbers[day_of_week]
  current_day_num = Date.day_of_week(today)

  # Calculate days until next occurrence
  days_until =
    if target_day_num >= current_day_num do
      target_day_num - current_day_num
    else
      7 - current_day_num + target_day_num
    end

  target_date = Date.add(today, days_until)

  # If it's today but time has passed, move to next week
  target_date =
    if days_until == 0 do
      event_time = Time.new!(hour, minute, 0)
      current_time = DateTime.to_time(now)

      if Time.compare(current_time, event_time) == :gt do
        Date.add(target_date, 7)
      else
        target_date
      end
    else
      target_date
    end

  # Create DateTime for next occurrence
  {:ok, naive_dt} = NaiveDateTime.new(target_date, Time.new!(hour, minute, 0))
  {:ok, dt} = DateTime.from_naive(naive_dt, timezone)

  {:ok, dt}
end
```

### Step 3: Include in Event Map

In your `VenueDetailJob` or similar processing job:

```elixir
defmodule EventasaurusDiscovery.Sources.YourSource.Jobs.VenueDetailJob do
  def perform(%Oban.Job{args: args}) do
    # ... fetch venue data

    # Build base event map
    event_map = %{
      title: venue_data.title,
      external_id: "yoursource_#{venue_data.id}",
      venue_data: venue_data.venue,
      # ... other fields
    }

    # Try to add recurrence pattern
    event_map =
      case Transformer.parse_schedule_to_recurrence(venue_data.schedule) do
        {:ok, recurrence_rule} ->
          case Transformer.calculate_next_occurrence(recurrence_rule) do
            {:ok, next_occurrence} ->
              %{event_map |
                recurrence_rule: recurrence_rule,
                starts_at: next_occurrence,
                ends_at: DateTime.add(next_occurrence, 2 * 3600, :second)
              }

            {:error, reason} ->
              Logger.warning("Could not calculate next occurrence: #{inspect(reason)}")
              event_map
          end

        {:error, reason} ->
          Logger.warning("Could not parse schedule: #{inspect(reason)}")
          event_map
      end

    # Only process if we have dates
    if event_map.starts_at do
      Processor.process_single_event(event_map, source)
    else
      {:discard, :no_valid_schedule}
    end
  end
end
```

---

## ⏰ Timezone Handling

### Single Timezone Sources

Most sources operate in a single timezone (e.g., Poland events → `Europe/Warsaw`):

```elixir
def parse_schedule_to_recurrence(schedule_text) do
  # All events in this source use same timezone
  recurrence_rule = %{
    "frequency" => "weekly",
    "days_of_week" => [day_of_week],
    "time" => time,
    "timezone" => "Europe/Warsaw"  # Fixed timezone
  }

  {:ok, recurrence_rule}
end
```

### Multi-Timezone Sources

For sources covering multiple timezones (e.g., US-wide events):

**Option 1: Extract from starts_at DateTime (Recommended - Geeks Who Drink pattern)**
```elixir
def parse_schedule_to_recurrence(time_text, starts_at, venue_data) do
  # starts_at already calculated with correct timezone by VenueDetailJob
  timezone =
    cond do
      # Priority 1: Extract from starts_at DateTime (most accurate)
      match?(%DateTime{}, starts_at) ->
        starts_at.time_zone

      # Priority 2: Use explicit timezone from venue metadata
      is_binary(venue_data[:timezone]) ->
        venue_data[:timezone]

      # Priority 3: Fallback to most common timezone
      true ->
        "America/New_York"
    end

  recurrence_rule = %{
    "frequency" => "weekly",
    "days_of_week" => [day_of_week],
    "time" => time,
    "timezone" => timezone
  }

  {:ok, recurrence_rule}
end
```

**Option 2: Detect from venue location (state-based)**
```elixir
def determine_timezone(venue_data) do
  cond do
    venue_data.state in ["NY", "MA", "PA"] -> "America/New_York"
    venue_data.state in ["IL", "TX", "WI"] -> "America/Chicago"
    venue_data.state in ["CA", "WA", "OR"] -> "America/Los_Angeles"
    true -> "America/New_York"  # Default
  end
end
```

**Option 3: Use venue metadata directly**
```elixir
# If source provides timezone explicitly
def parse_schedule_to_recurrence(schedule_text, venue_data) do
  timezone = venue_data[:timezone] || infer_from_location(venue_data)

  recurrence_rule = %{
    "frequency" => "weekly",
    "days_of_week" => [day_of_week],
    "time" => time,
    "timezone" => timezone
  }

  {:ok, recurrence_rule}
end
```

**Important:** Always store times in the **event's local timezone**, not UTC. The frontend will handle timezone conversions for display.

**Best Practice:** Extract timezone from the already-calculated `starts_at` DateTime (Option 1) to ensure consistency between the next occurrence time and the recurrence pattern timezone.

---

## 📅 Frequency Types

### Weekly Events (~95% of use cases)

**Pattern:**
```elixir
%{
  "frequency" => "weekly",
  "days_of_week" => ["wednesday"],  # Single day
  "time" => "20:00",
  "timezone" => "Europe/London"
}
```

**Examples:**
- Trivia nights (every Tuesday)
- Open mic nights (every Thursday)
- Recurring concerts (every Friday)

### Monthly Events (~5% of use cases)

**Pattern:**
```elixir
%{
  "frequency" => "monthly",
  "days_of_week" => ["first_saturday"],  # 1st Saturday of month
  "time" => "14:00",
  "timezone" => "America/New_York"
}
```

**Day Format for Monthly:**
- `"first_monday"`, `"first_tuesday"`, ..., `"first_sunday"`
- `"second_monday"`, ..., `"second_sunday"`
- `"third_monday"`, ..., `"third_sunday"`
- `"fourth_monday"`, ..., `"fourth_sunday"`
- `"last_monday"`, ..., `"last_sunday"`

**Examples:**
- Monthly book clubs (first Wednesday)
- Community meetups (third Saturday)
- Networking events (last Thursday)

---

## 🚫 Edge Cases & Limitations

### Irregular Events

**Problem:** Events without a consistent pattern (e.g., "Every other Tuesday", "Quarterly meetups")

**Solution:** Store as explicit dates without `recurrence_rule`:

```elixir
# Don't create recurrence_rule for irregular patterns
if irregular_schedule?(schedule_text) do
  Logger.info("Irregular schedule detected, using explicit dates only")

  %{
    starts_at: next_occurrence,
    ends_at: next_occurrence_end
    # NO recurrence_rule field
  }
else
  # Use recurrence_rule for regular patterns
end
```

### Multiple Days per Week

**Supported:**
```elixir
%{
  "frequency" => "weekly",
  "days_of_week" => ["tuesday", "thursday"],  # Both days
  "time" => "19:00",
  "timezone" => "Europe/London"
}
```

**Use Case:** Events that occur multiple times per week (e.g., yoga classes Tuesday & Thursday)

### Special Dates (Holidays, Closures)

**Current Limitation:** `recurrence_rule` doesn't support exceptions (e.g., "Every Monday except Christmas")

**Workaround:**
- Store regular pattern in `recurrence_rule`
- Frontend/backend filters out known holidays
- Manual event deletion/hiding for one-off closures

**Future Enhancement:** Add `exceptions` field to recurrence_rule:
```elixir
# Proposed future feature
%{
  "frequency" => "weekly",
  "days_of_week" => ["monday"],
  "time" => "19:00",
  "timezone" => "Europe/London",
  "exceptions" => ["2025-12-25", "2026-01-01"]  # Skip these dates
}
```

---

## 🎯 When to Use recurrence_rule

### ✅ Use recurrence_rule when:

- Event has a **predictable recurring schedule** (weekly/monthly)
- Schedule text clearly indicates pattern (e.g., "Every Tuesday at 7 PM")
- Source confirms event is ongoing (not a limited series)
- Timezone is known or can be reliably inferred

**Examples:**
- Weekly trivia nights
- Monthly book clubs
- Daily movie showtimes (same time each day)
- Open mic nights (every Thursday)

### ❌ Don't use recurrence_rule when:

- Event is one-time only
- Schedule is irregular ("Every other week", "Quarterly")
- Pattern is complex ("1st and 3rd Tuesday")
- Source doesn't confirm recurrence
- Timezone is unknown

**Examples:**
- One-time concerts
- Festival events (dates vary each year)
- Special events (holiday parties)
- Irregular meetups

---

## 📚 Reference Implementation

See **PubQuiz scraper** for complete implementation:

**Files:**
- `lib/eventasaurus_discovery/sources/pubquiz/transformer.ex`
  - `parse_schedule_to_recurrence/1` - Parsing function
  - `calculate_next_occurrence/1` - Date calculation
- `lib/eventasaurus_discovery/sources/pubquiz/jobs/venue_detail_job.ex`
  - Integration with event processing pipeline

**Key Code:**
```elixir
# In Transformer
def parse_schedule_to_recurrence(schedule_text) do
  # Extract day and time from Polish schedule text
  # Return standardized recurrence_rule map
end

# In VenueDetailJob
case Transformer.parse_schedule_to_recurrence(venue_data[:schedule]) do
  {:ok, recurrence_rule} ->
    case Transformer.calculate_next_occurrence(recurrence_rule) do
      {:ok, next_occurrence} ->
        %{event_map |
          recurrence_rule: recurrence_rule,
          starts_at: next_occurrence
        }
    end
end
```

---

## 🔗 Current Use Cases

### Trivia Events (Primary Use Case)

Sources with recurring trivia patterns:
- **PubQuiz** (Poland) ✅ Implemented
- **Question One** (UK) 🚧 Needs implementation
- **Geeks Who Drink** (US/Canada) ✅ Implemented

**Pattern:** Weekly events on same day/time at fixed venues

### Future Use Cases

Potential applications for other event types:
- 🎬 **Movie Showtimes** - Daily screenings (same times)
- 🎵 **Music Series** - Weekly concerts (same venue)
- 🎭 **Theater Shows** - Multiple performances (weekly/nightly)
- 📚 **Community Events** - Monthly book clubs, meetups
- 🏃 **Recurring Activities** - Yoga classes, fitness events

---

## ✅ Quality Checklist

Before implementing `recurrence_rule` in a scraper:

- [ ] Schedule data is consistently available from source
- [ ] Pattern is truly recurring (weekly or monthly)
- [ ] Can reliably extract day of week from schedule text
- [ ] Can reliably extract time in HH:MM format
- [ ] Timezone is known or can be inferred accurately
- [ ] Implemented `parse_schedule_to_recurrence/1` function
- [ ] Implemented `calculate_next_occurrence/1` function
- [ ] Added `recurrence_rule` to event map in VenueDetailJob
- [ ] Tested with real schedule data from source
- [ ] Handles irregular schedules gracefully (no recurrence_rule)
- [ ] Logs warnings when schedule parsing fails

---

---

## 🆔 External ID Patterns for Recurring Events

### Venue-Based External IDs

For pattern-based recurring events, **the venue IS the unique identifier**, not the day of week or time.

#### Core Principle

> **Venue location** = Identity (describes WHICH event it is)
> **Day of week, time, scheduling** = Metadata (describes WHEN event happens)

#### Why Venue-Based?

**Benefits:**
- ✅ EventFreshnessChecker can skip recently-updated venues (80-90% reduction in API calls)
- ✅ Recurring event consolidation via EventProcessor title matching
- ✅ Stable external_ids across scraper runs
- ✅ Automatic handling of edge cases (multiple events at same venue with different titles)

**Pattern-Based Scrapers (use venue-based external_id):**
- Question One: `question_one_royal_oak_twickenham`
- PubQuiz: `pubquiz-pl_warszawa_centrum`
- Inquizition: `inquizition_12345`
- Geeks Who Drink: `geeks_who_drink_12345`
- Speed Quizzing: `speed-quizzing-12345`

#### Implementation

```elixir
# ❌ WRONG: Including day_of_week in external_id
external_id = "question_one_#{venue_slug}_#{day_of_week}"

# ✅ CORRECT: Venue-based external_id only
external_id = "question_one_#{venue_slug}"
```

**In Transformer:**
```elixir
def transform_event(venue_data, _options \\ %{}) do
  # Use venue identifier (NOT day_of_week!)
  venue_slug = slugify(venue_data.name)
  external_id = "question_one_#{venue_slug}"

  %{
    external_id: external_id,
    title: "Quiz Night at #{venue_data.name}",
    recurrence_rule: %{
      "frequency" => "weekly",
      "days_of_week" => ["monday"],  # Metadata, not in external_id
      "time" => "19:00",
      "timezone" => "Europe/London"
    }
  }
end
```

**In IndexJob (for two-stage architecture):**
```elixir
defp schedule_detail_jobs(venues, source_id) do
  # Generate external_ids for venues
  venues_with_ids = Enum.map(venues, fn venue ->
    venue_slug = extract_venue_slug(venue.url)
    Map.put(venue, :external_id, "question_one_#{venue_slug}")
  end)

  # EventFreshnessChecker filters out fresh venues
  venues_to_process = EventFreshnessChecker.filter_events_needing_processing(
    venues_with_ids,
    source_id
  )

  # Schedule detail jobs ONLY for stale venues
  Enum.each(venues_to_process, fn venue ->
    VenueDetailJob.new(%{...}) |> Oban.insert()
  end)
end
```

#### Edge Case: Multiple Events at Same Venue

**Q: What if a venue has multiple different events?**

A: EventProcessor's title-based matching handles this automatically:

**Example:**
- Regular quiz: external_id = `geeks_who_drink_bar_xyz`, title = "General Trivia Night"
- Special event: external_id = `geeks_who_drink_bar_xyz`, title = "Halloween Special Trivia"
- **Result**: EventFreshnessChecker's prediction layer groups by normalized title → different titles processed separately ✅

**Three-Layer Matching:**
1. **Direct external_id match**: Skip if seen within threshold
2. **Existing event_id match**: Skip if belongs to recently-updated recurring event
3. **Predicted event_id match**: Uses title+venue similarity for new events

**Q: What if titles are very similar?**

A: Intentional consolidation (Jaro distance > 0.85):
- "Monday Night Trivia" and "Monday Trivia Night" → merged as recurring event ✅
- This is desired behavior for recurring event detection

#### Reference Documentation

**EventFreshnessChecker Integration:**
- Three-layer matching: `lib/eventasaurus_discovery/services/event_freshness_checker.ex`
- Recurring event consolidation: `lib/eventasaurus_discovery/scraping/processors/event_processor.ex:1132-1391`

**Scraper Examples:**
- Question One: `lib/eventasaurus_discovery/sources/question_one/README.md` (External ID Pattern section)
- PubQuiz: `lib/eventasaurus_discovery/sources/pubquiz/README.md` (External ID Pattern section)
- Speed Quizzing: `lib/eventasaurus_discovery/sources/speed_quizzing/README.md` (External ID Pattern section)
- Inquizition: `lib/eventasaurus_discovery/sources/inquizition/README.md` (External ID Pattern section)
- Geeks Who Drink: `lib/eventasaurus_discovery/sources/geeks_who_drink/README.md` (External ID Pattern section)

**Related Issues:**
- GitHub Issue #1944 - Pattern-based scraper external_id standardization

---

## 🎓 Key Takeaways

1. **recurrence_rule enables pattern-based events** - One record, many future dates
2. **Frontend generates upcoming dates** - No need to store 50+ explicit occurrences
3. **Timezone is critical** - Always store in event's local timezone
4. **Weekly is most common** - ~95% of recurring events are weekly
5. **Gracefully handle irregular events** - Don't force patterns on irregular schedules
6. **Follow PubQuiz pattern** - Reference implementation is production-tested
7. **Calculate next occurrence** - Always set `starts_at` to next upcoming date
8. **Store pattern in occurrences field** - EventProcessor handles storage
9. **Use venue-based external_ids** - Venue is identity, schedule is metadata
10. **EventFreshnessChecker integration** - Filters out fresh venues for efficiency

---

## 📚 Lessons Learned from Geeks Who Drink Implementation

### Overview

Geeks Who Drink implementation (GitHub Issue #2149) revealed critical insights about multi-timezone recurring events, hybrid performer storage, and quality measurement. Three-phase project improved quality from 52% → 95%+.

**Project Phases:**
- **Phase 1** (Data Pipeline): Fixed timezone handling and occurrence type storage
- **Phase 2** (Quality Measurement): Fixed quality checker to recognize metadata-stored performers
- **Phase 3** (Documentation): This section and related guidelines

**Documentation:**
- `GEEKS_WHO_DRINK_QUALITY_AUDIT.md` - Initial quality analysis
- `GEEKS_WHO_DRINK_PHASE1_COMPLETE.md` - Data pipeline fixes
- `GEEKS_WHO_DRINK_PHASE2_COMPLETE.md` - Quality checker updates

### Lesson 1: DateTime Extraction for Multi-Timezone Sources

**Challenge**: Geeks Who Drink operates across multiple US timezones. Schedule text like "Tuesdays at" doesn't include timezone, making parsing unreliable.

**Solution**: Extract recurrence_rule from `starts_at` DateTime instead of parsing schedule text.

**Implementation** (`lib/eventasaurus_discovery/sources/geeks_who_drink/transformer.ex`):

```elixir
def parse_schedule_to_recurrence(time_text, starts_at, venue_data) when is_binary(time_text) do
  # Extract from starts_at DateTime (VenueDetailJob calculated correct timezone)
  case extract_from_datetime(starts_at, venue_data) do
    {:ok, {day_of_week, time_string, timezone}} ->
      recurrence_rule = %{
        "frequency" => "weekly",
        "days_of_week" => [day_of_week],
        "time" => time_string,
        "timezone" => timezone
      }
      {:ok, recurrence_rule}

    {:error, reason} ->
      # Fallback to time_text parsing for backward compatibility
      Logger.warning("Failed to extract from starts_at (#{reason}), trying time_text...")
      fallback_parse_time_text(time_text, venue_data)
  end
end

defp extract_from_datetime(%DateTime{} = dt, venue_data) when is_map(venue_data) do
  # Get timezone from venue_data (VenueDetailJob adds this)
  timezone = venue_data[:timezone] || venue_data["timezone"] || "America/New_York"

  # Convert UTC to local timezone
  local_dt = DateTime.shift_zone!(dt, timezone)

  # Extract day of week and time from LOCAL datetime
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

defp number_to_day(1), do: "monday"
defp number_to_day(2), do: "tuesday"
defp number_to_day(3), do: "wednesday"
defp number_to_day(4), do: "thursday"
defp number_to_day(5), do: "friday"
defp number_to_day(6), do: "saturday"
defp number_to_day(7), do: "sunday"
```

**Key Benefits:**
- ✅ **Timezone-accurate**: Uses venue's actual timezone from VenueDetailJob
- ✅ **No parsing errors**: Extracts day/time directly from DateTime
- ✅ **Multi-timezone support**: Works across all US timezones
- ✅ **Backward compatible**: Falls back to text parsing if DateTime method fails

**When to Use This Pattern:**
- Multi-timezone sources (spanning multiple regions)
- Schedule text lacks timezone information
- VenueDetailJob already calculates `starts_at` with correct timezone
- Higher reliability needed over text parsing

### Lesson 2: Timezone-Aware Time Display

**Challenge**: Events showed "01:00" (UTC midnight) instead of local time "19:00-22:00".

**Root Cause**: `format_time_only/1` extracted time from UTC DateTime without converting to local timezone first.

**Solution**: Created timezone-aware version that converts to local before extracting time.

**Implementation** (`lib/eventasaurus_discovery/scraping/processors/event_processor.ex`):

```elixir
defp format_time_only(%DateTime{} = dt, event_data) when is_map(event_data) or is_nil(event_data) do
  # Extract timezone from event data or use UTC as fallback
  timezone = extract_timezone(event_data) || "Etc/UTC"

  # Convert to local timezone before extracting time
  dt
  |> DateTime.shift_zone!(timezone)
  |> DateTime.to_time()
  |> Time.to_string()
  |> String.slice(0..4)
rescue
  # Graceful fallback if timezone shift fails
  ArgumentError ->
    dt
    |> DateTime.to_time()
    |> Time.to_string()
    |> String.slice(0..4)
end

defp extract_timezone(data) when is_map(data) do
  cond do
    # Priority 1: recurrence_rule timezone (for pattern events)
    data[:recurrence_rule] && data[:recurrence_rule]["timezone"] ->
      data[:recurrence_rule]["timezone"]

    # Priority 2: metadata timezone (for all events)
    data[:metadata] && data[:metadata]["timezone"] ->
      data[:metadata]["timezone"]

    # Priority 3: metadata timezone (string key fallback)
    data["metadata"] && data["metadata"]["timezone"] ->
      data["metadata"]["timezone"]

    true -> nil
  end
end
```

**Key Insight**: Universal EventProcessor must be timezone-aware for accurate time display across all scrapers.

**Impact:**
- Time quality: 40% → 95%+
- Correct local times displayed in all views
- Works universally for all scrapers

### Lesson 3: Hybrid Performer Storage Pattern

**Challenge**: Not all events need full performer records. Simple cases (single quizmaster) don't require separate performer entries.

**Pattern**: Geeks Who Drink stores quizmasters in `metadata["quizmaster"]` instead of `public_event_performers` table.

**When to Use Metadata Storage:**
- ✅ Single, simple performer per event (e.g., quizmaster, DJ, host)
- ✅ No detailed performer information needed
- ✅ Performer name is sufficient (no bio, image, links)
- ✅ No cross-event performer tracking required

**When to Use Performers Table:**
- ✅ Multiple performers per event
- ✅ Detailed performer information (bio, social links, images)
- ✅ Cross-event performer tracking and analytics
- ✅ Performer-based search and filtering

**Benefits of Metadata Pattern:**
- Simpler data model for single-performer events
- Avoids creating separate performer records for each event
- Metadata is co-located with event data (better performance)
- Reduces database complexity

**Quality Checker Consideration**: Quality checker must recognize BOTH storage patterns (see Lesson 4).

### Lesson 4: Quality Checker Must Recognize Metadata Performers

**Challenge**: Quality dashboard showed 0% performer completeness despite all events having quizmasters.

**Root Cause**: Quality checker only looked in `public_event_performers` table, didn't check metadata field.

**Solution**: Updated quality checker to recognize both storage patterns.

**Implementation** (`lib/eventasaurus_discovery/admin/data_quality_checker.ex`):

```elixir
defp calculate_performer_completeness(source_id) do
  query =
    from(e in PublicEvent,
      join: pes in PublicEventSource,
      on: pes.event_id == e.id,
      left_join: pep in "public_event_performers",
      on: pep.event_id == e.id,
      where: pes.source_id == ^source_id,
      group_by: [e.id, pes.metadata],
      select: %{
        event_id: e.id,
        # Count performers from performers table
        table_performer_count: count(pep.performer_id),
        # Check if metadata contains quizmaster (Geeks Who Drink pattern)
        # Uses jsonb_exists() to check if 'quizmaster' key exists in metadata
        has_metadata_performer:
          fragment(
            "CASE WHEN jsonb_exists(?, 'quizmaster') THEN 1 ELSE 0 END",
            pes.metadata
          )
      }
    )

  performer_data = Repo.all(query)

  # Calculate metrics combining both performer sources
  performer_data_with_total =
    Enum.map(performer_data, fn d ->
      Map.put(d, :total_performer_count, d.table_performer_count + d.has_metadata_performer)
    end)

  events_with_performers =
    Enum.count(performer_data_with_total, fn d -> d.total_performer_count > 0 end)

  # Completeness = % of events with at least one performer (from either source)
  performer_completeness = round(events_with_performers / total_events * 100)

  # ... return metrics map
end
```

**Key Insight**: Universal quality checker must be flexible enough to recognize source-specific patterns.

**Impact:**
- Performer completeness: 0% → 100%
- Accurate quality scoring across all scrapers
- No false warnings for metadata-stored data

**JSONB Best Practice**: Use `jsonb_exists(column, 'key')` instead of `column ? 'key'` in Ecto fragments to avoid placeholder count issues.

### Lesson 5: Pattern-Type vs Explicit-Type Occurrences

**Challenge**: 82 events stored as "explicit" (individual dates) instead of "pattern" (recurrence rules), causing database bloat.

**Root Cause**: `recurrence_rule` was nil despite events being recurring, so EventProcessor defaulted to explicit type.

**Solution**: Fix transformer to properly extract recurrence_rule (see Lesson 1).

**Database Impact:**
- **Before**: 82 explicit occurrence records per venue (one per week for 2 years)
- **After**: 1 pattern record per venue with recurrence rule

**Benefits:**
- 98% reduction in occurrence records
- Dynamic generation of future dates by frontend
- Single source of truth for recurring schedule
- Easier schedule updates (change one pattern vs 82 records)

**Quality Impact:**
- Occurrence validity: 5% → 95%+
- Structural issues: 82 → 0
- More accurate occurrence type representation

### Lesson 6: Three-Layer Quality System

**Insight**: Quality issues can exist in data pipeline, measurement pipeline, or both.

**Three Layers:**

1. **Data Pipeline** (Scraper → Transformer → EventProcessor → Database)
   - Phase 1 fixed: Timezone conversion, recurrence rule extraction
   - Impact: Correct data storage

2. **Measurement Pipeline** (Quality Checker → Dashboard)
   - Phase 2 fixed: Metadata performer recognition
   - Impact: Accurate quality scoring

3. **Documentation Pipeline** (Code → Docs → Knowledge Transfer)
   - Phase 3 completed: This section and quality guidelines
   - Impact: Future scraper quality

**Key Insight**: Fixing data pipeline alone won't improve dashboard metrics if quality checker doesn't recognize the patterns. Both must align.

**Example from Geeks Who Drink:**
- Data pipeline was 100% correct after Phase 1 (all quizmasters in metadata)
- Quality dashboard still showed 0% until Phase 2 fixed measurement
- Both layers needed updates for accurate quality reporting

### Lesson 7: Quality Metrics Methodology

**Before Geeks Who Drink Project:**
- Overall Quality: 52%
- Time Quality: 40%
- Performer Data: 0%
- Occurrence Validity: 5%

**After Phase 1 (Data Pipeline Fixes):**
- Overall Quality: 75%+ (expected after re-scrape)
- Time Quality: 95%+
- Performer Data: Still 0% (measurement issue)
- Occurrence Validity: 95%+

**After Phase 2 (Quality Checker Updates):**
- Overall Quality: 88% (with test data)
- Time Quality: 95%+
- Performer Data: 100% ✅
- Occurrence Validity: 95%+

**Expected After Production Deployment:**
- Overall Quality: 95%+
- All metrics: 95%+
- Recommendation: "Data quality is excellent! 🎉"

**Key Insight**: Test metrics may differ from production metrics. Always re-scrape and re-measure after deployment.

### Summary: Best Practices Extracted

1. **DateTime Extraction**: For multi-timezone sources, extract recurrence_rule from DateTime instead of parsing text
2. **Timezone Awareness**: Always convert to local timezone before extracting time components
3. **Hybrid Storage**: Use metadata for simple performers, performers table for complex cases
4. **Quality Checker Flexibility**: Design quality checkers to recognize multiple valid patterns
5. **Pattern vs Explicit**: Prefer pattern-type occurrences for recurring events (better efficiency)
6. **Three-Layer Testing**: Test data pipeline, measurement pipeline, and documentation separately
7. **JSONB Operators**: Use `jsonb_exists()` function in Ecto fragments for cleaner code
8. **Graceful Fallbacks**: Always provide fallback mechanisms for robustness
9. **Evidence-Based Quality**: Use test scripts to validate quality improvements before deployment
10. **Documentation First**: Document patterns immediately while context is fresh

### Related Documentation

- **Quality Audit**: `GEEKS_WHO_DRINK_QUALITY_AUDIT.md`
- **Phase 1 Complete**: `GEEKS_WHO_DRINK_PHASE1_COMPLETE.md`
- **Phase 2 Complete**: `GEEKS_WHO_DRINK_PHASE2_COMPLETE.md`
- **Phase 3 Complete**: `GEEKS_WHO_DRINK_PHASE3_COMPLETE.md`
- **Quality Guidelines**: `docs/SCRAPER_QUALITY_GUIDELINES.md`
- **GitHub Issue**: #2149

---

**Questions?** Review PubQuiz implementation in `lib/eventasaurus_discovery/sources/pubquiz/` or Geeks Who Drink implementation in `lib/eventasaurus_discovery/sources/geeks_who_drink/`
