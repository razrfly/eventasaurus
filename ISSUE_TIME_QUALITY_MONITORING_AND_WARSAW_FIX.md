# Issue: Add Time Quality Monitoring & Fix Warsaw Scraper Time Parsing

## Problem Statement

The Warsaw scraper (waw4free) is loading events with suspicious times - many events are showing up at midnight (00:00) or have 99% of events at exactly the same time. This indicates a systemic time parsing failure.

### Example Evidence

**Event URL**: http://localhost:4000/activities/wieczor-operowy-w-wykonaniu-choru-ul-carla-goldoniego-1-251104

**Source Data**:
```
📅 Data: środa, 5 listopada 2025
⌚ Godzina rozpoczęcia: 18:00
📌 Miejsce: Warszawa - Bielany, Bielański Ośrodek Kultury, ul. Carla Goldoniego 1
```

**Problem**: Event clearly shows `18:00` start time, but system is likely loading it as `00:00` (midnight).

## Root Cause Analysis

After investigating the code:

1. **Time Extraction Works** (`lib/eventasaurus_discovery/sources/waw4free/detail_extractor.ex:186-205`):
   - `extract_time_text/1` successfully extracts "⌚ Godzina rozpoczęcia: 18:00"
   - Text is combined with date: `"środa, 5 listopada 2025 ⌚ Godzina rozpoczęcia: 18:00"`

2. **Time Parsing Fails** (`lib/eventasaurus_discovery/sources/shared/parsers/multilingual_date_parser.ex:388-411`):
   - `MultilingualDateParser` only parses **DATES**, not **TIMES**
   - Line 393: Defaults to `~T[00:00:00]` for start_of_day
   - The combined date+time text has time information stripped/ignored
   - Result: All events default to midnight (00:00)

3. **Polish Date Pattern Missing Time Parsing**:
   - `DatePatterns.Polish` module needs time pattern support
   - Currently only handles date components (day, month, year)
   - No regex patterns for "Godzina:", "18:00", or HH:MM formats

## Two-Phase Solution

### Phase 1: Time Quality Monitoring (Quality Dashboard)

**Goal**: Surface this issue automatically so we can detect time parsing failures across all scrapers.

**Implementation**: Add time quality metrics to `occurrence_metrics` in `DataQualityChecker`.

#### New Metrics to Track

```elixir
# Add to occurrence_metrics map:
time_quality: %{
  score: 0-100,                    # Overall time quality score
  midnight_percentage: 0-100,      # % of events at 00:00
  same_time_percentage: 0-100,     # % of events at most common time
  most_common_time: "HH:MM",       # What time appears most often
  hour_distribution: %{},          # Count of events per hour (0-23)
  time_diversity_score: 0-100      # Shannon entropy of hour distribution
}
```

#### Quality Score Calculation

```elixir
# Weighted components:
# - midnight_penalty: High % at 00:00 suggests parsing failure (40% weight)
# - diversity_score: Low diversity suggests hardcoded times (40% weight)
# - same_time_penalty: >80% at same time is suspicious (20% weight)

midnight_penalty = if midnight_percentage > 30, do: 0, else: 100
diversity_component = time_diversity_score
same_time_penalty = if same_time_percentage > 80, do: 0, else: 100

time_quality = round(
  midnight_penalty * 0.4 +
  diversity_component * 0.4 +
  same_time_penalty * 0.2
)
```

#### Suspicious Patterns to Detect

1. **Midnight Dominance**: >30% of events at 00:00 (likely parsing failure)
2. **Time Monoculture**: >80% of events at same time (likely hardcoded default)
3. **Low Diversity**: Hour distribution entropy < 50 (limited time variety)

#### Recommendation Messages

```elixir
recommendations =
  if quality.occurrence_metrics.time_quality.score < 70 do
    msg = "⚠️ Time parsing issues detected: "

    details = cond do
      quality.occurrence_metrics.time_quality.midnight_percentage > 50 ->
        "#{quality.occurrence_metrics.time_quality.midnight_percentage}% of events at midnight (00:00) - likely missing time parsing"

      quality.occurrence_metrics.time_quality.same_time_percentage > 80 ->
        "#{quality.occurrence_metrics.time_quality.same_time_percentage}% of events at #{quality.occurrence_metrics.time_quality.most_common_time} - check for hardcoded times"

      quality.occurrence_metrics.time_quality.time_diversity_score < 50 ->
        "Low time diversity (score: #{quality.occurrence_metrics.time_quality.time_diversity_score}) - verify time extraction"

      true ->
        "Review time parsing implementation"
    end

    [msg <> details | recommendations]
  else
    recommendations
  end
```

#### Files to Modify

1. `lib/eventasaurus_discovery/admin/data_quality_checker.ex`:
   - Add `calculate_time_quality/1` function (similar to `calculate_occurrence_richness/1`)
   - Query occurrences JSONB to extract times from dates array
   - Calculate midnight %, same_time %, hour distribution
   - Add to `occurrence_metrics` map
   - Update `get_recommendations/1` with time quality checks

2. `lib/eventasaurus_web/live/admin/discovery_stats_live/source_detail.ex`:
   - Display time_quality metrics in occurrence section
   - Show hour distribution chart/table
   - Highlight suspicious patterns with warnings

#### Query Strategy

```elixir
defp calculate_time_quality(source_id) do
  # Query events with occurrence dates
  query =
    from(e in PublicEvent,
      join: pes in PublicEventSource,
      on: pes.event_id == e.id,
      where: pes.source_id == ^source_id,
      where: not is_nil(e.occurrences),
      where: fragment("jsonb_typeof(?) = 'object'", e.occurrences),
      where: fragment("? ->> 'dates' IS NOT NULL", e.occurrences),
      select: %{
        event_id: e.id,
        dates: fragment("? -> 'dates'", e.occurrences)
      }
    )

  events = Repo.all(query)

  # Extract times from dates JSON arrays
  times =
    events
    |> Enum.flat_map(fn event ->
      case Jason.decode(event.dates) do
        {:ok, dates_array} when is_list(dates_array) ->
          Enum.map(dates_array, fn date_obj ->
            case date_obj do
              %{"start_time" => time} when is_binary(time) -> time
              _ -> "00:00"  # Default for missing times
            end
          end)
        _ -> []
      end
    end)

  # Analyze time distribution
  analyze_time_distribution(times)
end
```

### Phase 2: Fix Warsaw Scraper Time Parsing

**Goal**: Actually parse and store the time information that's being extracted.

#### Option A: Extend Polish Date Pattern (Recommended)

Add time parsing support to `DatePatterns.Polish` module:

```elixir
# lib/eventasaurus_discovery/sources/shared/parsers/date_patterns/polish.ex

# Add time patterns
@time_patterns [
  # "Godzina rozpoczęcia: 18:00"
  ~r/godzina\s+rozpoczęcia:\s*(\d{1,2}):(\d{2})/iu,

  # "18:00" or "18.00"
  ~r/(\d{1,2})[:\.](\d{2})/,

  # "o godz. 18:00"
  ~r/o\s+godz\.?\s*(\d{1,2}):(\d{2})/iu
]

def extract_time(text) do
  Enum.find_value(@time_patterns, fn pattern ->
    case Regex.run(pattern, text) do
      [_, hour, minute] ->
        with {h, _} <- Integer.parse(hour),
             {m, _} <- Integer.parse(minute),
             true <- h >= 0 and h <= 23,
             true <- m >= 0 and m <= 59 do
          {:ok, %{hour: h, minute: m}}
        else
          _ -> nil
        end
      _ -> nil
    end
  end) || {:error, :no_time_found}
end
```

Update `MultilingualDateParser` to handle time components:

```elixir
# lib/eventasaurus_discovery/sources/shared/parsers/multilingual_date_parser.ex

defp parse_iso_to_datetime(iso_date, timezone, time_of_day, time_components \\ nil) do
  case Date.from_iso8601(iso_date) do
    {:ok, date} ->
      # Use extracted time if available, otherwise default
      time = case time_components do
        %{hour: h, minute: m} -> Time.new!(h, m, 0)
        nil -> if time_of_day == :start_of_day, do: ~T[00:00:00], else: ~T[23:59:59]
      end

      # Create NaiveDateTime
      naive_datetime = NaiveDateTime.new!(date, time)

      # Convert to DateTime with timezone, then to UTC
      case DateTime.from_naive(naive_datetime, timezone) do
        {:ok, datetime} ->
          {:ok, DateTime.shift_zone!(datetime, "Etc/UTC")}
        {:error, _} ->
          {:ok, DateTime.from_naive!(naive_datetime, "Etc/UTC")}
      end

    {:error, _} ->
      {:error, :invalid_date}
  end
end
```

#### Option B: Add Separate Time Parsing in waw4free Transformer

If multilingual time parsing is too complex, handle it specifically in the waw4free transformer:

```elixir
# lib/eventasaurus_discovery/sources/waw4free/transformer.ex

defp parse_polish_time(time_text) when is_binary(time_text) do
  # Extract HH:MM from "⌚ Godzina rozpoczęcia: 18:00"
  case Regex.run(~r/(\d{1,2})[:\.](\d{2})/, time_text) do
    [_, hour, minute] ->
      with {h, _} <- Integer.parse(hour),
           {m, _} <- Integer.parse(minute),
           true <- h >= 0 and h <= 23,
           true <- m >= 0 and m <= 59 do
        {:ok, Time.new!(h, m, 0)}
      else
        _ -> {:error, :invalid_time}
      end
    _ -> {:error, :no_time_found}
  end
end

# Then merge time into starts_at DateTime
defp merge_time_into_datetime(datetime, time) do
  date = DateTime.to_date(datetime)
  naive = NaiveDateTime.new!(date, time)

  case DateTime.from_naive(naive, "Europe/Warsaw") do
    {:ok, dt} -> DateTime.shift_zone!(dt, "Etc/UTC")
    {:error, _} -> datetime  # Fallback to original
  end
end
```

#### Testing Strategy

1. **Unit Tests**: Test Polish time pattern extraction
2. **Integration Tests**: Test full waw4free detail extraction with times
3. **Manual Verification**: Check events in dashboard after fix
4. **Compare**: Before/after screenshots of event times

## Files to Create/Modify

### Phase 1: Quality Monitoring
- `lib/eventasaurus_discovery/admin/data_quality_checker.ex` - Add `calculate_time_quality/1`
- `lib/eventasaurus_web/live/admin/discovery_stats_live/source_detail.ex` - Display time metrics

### Phase 2: Time Parsing Fix (Option A - Recommended)
- `lib/eventasaurus_discovery/sources/shared/parsers/date_patterns/polish.ex` - Add time patterns
- `lib/eventasaurus_discovery/sources/shared/parsers/multilingual_date_parser.ex` - Handle time components
- `test/eventasaurus_discovery/sources/shared/parsers/date_patterns/polish_test.exs` - Test time extraction

### Phase 2: Time Parsing Fix (Option B - Fallback)
- `lib/eventasaurus_discovery/sources/waw4free/transformer.ex` - Add Polish time parsing
- `test/eventasaurus_discovery/sources/waw4free/transformer_test.exs` - Test time parsing

## Success Criteria

### Phase 1
- [ ] Time quality metric appears in admin dashboard for all sources
- [ ] Warsaw scraper shows low time_quality score (<70)
- [ ] Recommendation appears: "⚠️ Time parsing issues detected: X% of events at midnight (00:00)"
- [ ] Hour distribution visible in UI

### Phase 2
- [ ] Warsaw scraper events show correct times (18:00, not 00:00)
- [ ] Time quality score improves to >90
- [ ] No more midnight dominance warning
- [ ] Manual verification: http://localhost:4000/activities/wieczor-operowy-w-wykonaniu-choru-ul-carla-goldoniego-1-251104 shows 18:00

## Related Code References

- `lib/eventasaurus_discovery/admin/data_quality_checker.ex:1141-1361` - Occurrence richness calculation (template for time quality)
- `lib/eventasaurus_discovery/sources/waw4free/detail_extractor.ex:186-205` - Time text extraction
- `lib/eventasaurus_discovery/sources/shared/parsers/multilingual_date_parser.ex:388-411` - Date parsing (needs time support)
- `lib/eventasaurus_discovery/sources/shared/parsers/date_patterns/polish.ex` - Polish date patterns (needs time patterns)

## Priority

**High** - This affects user experience as event times are critical information. Quality monitoring will help us detect similar issues in other scrapers.
