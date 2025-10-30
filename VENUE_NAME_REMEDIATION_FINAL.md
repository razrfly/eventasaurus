# Finalize Venue Name Remediation: Unified Validation System

## 🎯 Overview

**Problem**: Scrapers extract bad venue names (UI elements, image captions, event counts) instead of actual venue names, despite having quality geocoded names available in metadata.

**Root Cause**: No validation layer between scraper output and database insertion.

**Solution**: Implement unified `VenueNameValidator` module that:
1. **Prevents** new bad names during scraping (fixes Issue #2071)
2. **Remediates** existing bad names via Oban job (fixes Issue #2072)
3. **Provides** reusable pattern for future scrapers (closes Issue #2082)

## 🏗️ Architecture

### Single Source of Truth: VenueNameValidator

```elixir
defmodule EventasaurusApp.Venues.VenueNameValidator do
  @moduledoc """
  Unified venue name validation logic used for both prevention and remediation.

  Validates scraped venue names against authoritative geocoded names using
  Jaro distance similarity scoring.

  ## Thresholds
  - >= 0.7: Scraped name is good quality, use it
  - 0.3-0.7: Moderate quality, prefer geocoded name
  - < 0.3: Severe quality issue, use geocoded name

  ## Usage
  - During scraping: VenueProcessor calls this before venue creation
  - During remediation: FixVenueNamesJob uses this to assess and fix existing venues
  """

  @doc """
  Validates a scraped venue name against the authoritative geocoded name.

  Returns:
  - {:ok, :use_scraped, similarity} - Scraped name is good quality
  - {:ok, :use_geocoded, similarity} - Should use geocoded name instead
  - {:ok, :no_geocoded_available} - No geocoded name to compare against
  """
  def validate_venue_name(scraped_name, metadata)

  @doc """
  Extracts the best venue name from geocoding metadata.

  Tries providers in order: google_places, here, mapbox, foursquare
  Falls back to nil if no name available.
  """
  def extract_geocoded_name(metadata)

  @doc """
  Calculates similarity between scraped and geocoded names using Jaro distance.
  """
  def calculate_similarity(name1, name2)
end
```

### Integration Points

**1. VenueProcessor (Prevention - Issue #2071)**

Location: `lib/eventasaurus_discovery/scraping/processors/venue_processor.ex:656`

```elixir
defp create_venue(data, city, _source, source_scraper) do
  # ... geocoding happens ...

  # BEFORE: final_name = data.name
  # AFTER: Validate scraped name against geocoded name
  final_name =
    case VenueNameValidator.validate_venue_name(data.name, final_geocoding_metadata) do
      {:ok, :use_scraped, _similarity} ->
        data.name
      {:ok, :use_geocoded, _similarity} ->
        VenueNameValidator.extract_geocoded_name(final_geocoding_metadata) || data.name
      {:ok, :no_geocoded_available} ->
        data.name
    end

  # ... rest of creation logic ...
end
```

**2. FixVenueNamesJob (Remediation - Issue #2072)**

New file: `lib/eventasaurus_app/venues/fix_venue_names_job.ex`

```elixir
defmodule EventasaurusApp.Venues.FixVenueNamesJob do
  use Oban.Worker,
    queue: :venue_maintenance,
    max_attempts: 3,
    unique: [period: 300, fields: [:args, :worker]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"city_id" => city_id, "severity" => severity}}) do
    # 1. Find venues with metadata
    venues = find_venues_with_metadata(city_id)

    # 2. Assess each venue using VenueNameValidator
    assessments = Enum.map(venues, fn venue ->
      geocoded_name = VenueNameValidator.extract_geocoded_name(venue.metadata)

      case VenueNameValidator.validate_venue_name(venue.name, venue.metadata) do
        {:ok, :use_geocoded, similarity} when similarity < severity_threshold(severity) ->
          {:needs_fix, venue, geocoded_name, similarity}
        _ ->
          {:skip, venue}
      end
    end)

    # 3. Fix venues in batches
    fixed =
      assessments
      |> Enum.filter(&match?({:needs_fix, _, _, _}, &1))
      |> Enum.chunk_every(50)
      |> Enum.map(&fix_venue_batch/1)
      |> Enum.sum()

    {:ok, %{fixed: fixed, total: length(venues)}}
  end

  defp fix_venue_batch(batch) do
    Repo.transaction(fn ->
      Enum.each(batch, fn {:needs_fix, venue, new_name, _similarity} ->
        # Update name AND regenerate slug
        venue
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_change(:name, new_name)
        |> Venue.Slug.maybe_generate_slug()
        |> Repo.update()
      end)
    end)

    length(batch)
  end
end
```

**3. Admin UI Trigger (Simple Button)**

Location: `lib/eventasaurus_web/live/admin/discovery_stats_live/source_detail.ex`

Add button when `venues_with_low_quality_names > 0`:

```elixir
<button phx-click="fix_venue_names" class="...">
  Fix <%= @quality_data.venues_with_low_quality_names %> Venue Names
</button>

# Handler:
def handle_event("fix_venue_names", _, socket) do
  %{city_id: socket.assigns.city.id, severity: "all"}
  |> FixVenueNamesJob.new()
  |> Oban.insert()

  socket
  |> put_flash(:info, "Job enqueued to fix venue names")
  |> {:noreply}
end
```

## 📋 Implementation Checklist

### Phase 1: VenueNameValidator Module
- [ ] Create `lib/eventasaurus_app/venues/venue_name_validator.ex`
- [ ] Implement `validate_venue_name/2` with Jaro distance scoring
- [ ] Implement `extract_geocoded_name/1` with provider priority
- [ ] Add tests for validation logic (unit tests)
- [ ] Document thresholds and rationale

### Phase 2: VenueProcessor Integration (Prevention)
- [ ] Update `VenueProcessor.create_venue/4` to call VenueNameValidator
- [ ] Add validation before final_name assignment (line 656)
- [ ] Log validation decisions for monitoring
- [ ] Test with waw4free scraper data
- [ ] Verify new venues get good names

### Phase 3: Oban Job (Remediation)
- [ ] Create `lib/eventasaurus_app/venues/fix_venue_names_job.ex`
- [ ] Implement batch processing (50 venues per transaction)
- [ ] Add slug regeneration using `Venue.Slug.maybe_generate_slug()`
- [ ] Add severity filtering (all, moderate, severe)
- [ ] Return summary statistics (fixed count, total count)
- [ ] Add to venue_maintenance queue (or create if needed)

### Phase 4: Admin UI Integration
- [ ] Add button to source_detail.ex when quality issues detected
- [ ] Add `handle_event("fix_venue_names")` handler
- [ ] Enqueue FixVenueNamesJob with city_id
- [ ] Show flash notification on job enqueue
- [ ] Test button triggers job correctly

### Phase 5: Cleanup
- [ ] Delete `lib/eventasaurus_web/live/admin/venue_name_fixer_live.ex`
- [ ] Delete `lib/eventasaurus_web/live/admin/venue_name_fixer_live.html.heex`
- [ ] Remove LiveView routes from router.ex
- [ ] Keep CLI tool (`mix venues.fix_names`) for testing
- [ ] Keep VenueNameFixer module for reference (or refactor to use VenueNameValidator)

### Phase 6: Testing & Validation
- [ ] Test VenueNameValidator with sample waw4free data
- [ ] Test VenueProcessor integration with new scrapes
- [ ] Run FixVenueNamesJob on Warsaw (81 venues expected)
- [ ] Verify names AND slugs are updated correctly
- [ ] Check no duplicates created
- [ ] Verify quality metrics improve

## 🔗 Issue Resolution

### Issue #2071 (Prevention)
**Status**: ✅ Resolved by VenueProcessor integration

VenueNameValidator integrated into scraper pipeline prevents new bad names from entering database.

### Issue #2072 (Remediation)
**Status**: ✅ Resolved by FixVenueNamesJob

Oban job uses same VenueNameValidator logic to fix existing bad names.

### Issue #2082 (Tooling)
**Status**: ✅ Resolved by unified architecture

Simple button + Oban job provides easy remediation without complex interface.

## 📊 Current State

**Working Components**:
- ✅ VenueNameFixer module (81 venues found in Warsaw)
- ✅ CLI tool (`mix venues.fix_names`)
- ✅ Duplicate detection (prevents auto-merge)
- ✅ Slug generation logic (from Venue.Slug module)

**Components to Build**:
- ⚠️ VenueNameValidator (core validation logic)
- ⚠️ VenueProcessor integration (prevention)
- ⚠️ FixVenueNamesJob (remediation)
- ⚠️ Admin UI button (trigger)

**Components to Remove**:
- ❌ venue_name_fixer_live.ex (user rejected complex UI)
- ❌ venue_name_fixer_live.html.heex

## 🎓 Pattern for Future Issues

This establishes the pattern for ALL future scraper quality issues:

1. **Create Validator Module**: Single source of truth for validation logic
2. **Integrate in Processor**: Prevent bad data during scraping
3. **Create Oban Job**: Remediate existing data using same validator
4. **Add Simple Trigger**: Button in admin UI to run remediation

**Example**: Future image URL validation would follow same pattern:
- `ImageUrlValidator` module
- Integration in `EventProcessor`
- `FixImageUrlsJob` Oban worker
- Button in admin UI

## 💡 Key Benefits

1. **Single Source of Truth**: One validation module used everywhere
2. **Fix Once, Apply Everywhere**: Fix scraper + remediate existing data
3. **Reusable Pattern**: Template for future quality issues
4. **Simple UI**: Just a button, no complex interface
5. **Background Processing**: Oban handles retries and failures
6. **Testable**: Validation logic isolated and unit testable

## 🚀 Success Metrics

- [ ] Zero new venues with bad names after VenueProcessor integration
- [ ] 81 venues in Warsaw fixed by FixVenueNamesJob
- [ ] Venue name quality metric > 95% for waw4free source
- [ ] Slugs regenerated correctly for all fixed venues
- [ ] No duplicate venues created during remediation
- [ ] Job completes in < 5 minutes for 81 venues

## 📝 Notes

- **Queue Configuration**: Add `venue_maintenance: 2` to Oban queues config
- **CLI Tool**: Keep `mix venues.fix_names` for testing and manual fixes
- **Monitoring**: Log validation decisions for quality monitoring
- **Future Enhancement**: Consider adding venue name quality to source stats dashboard

---

**Related Issues**: #2071, #2072, #2082
**Status**: Ready for implementation
**Priority**: High (blocking venue quality improvements)
