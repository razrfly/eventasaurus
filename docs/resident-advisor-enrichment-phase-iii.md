# Resident Advisor Artist Enrichment - Phase III

**Status:** ✅ Complete
**Date:** 2025-10-07

## Overview

Phase III implements a background job system for enriching performer records with Resident Advisor artist data. This completes the three-phase implementation of comprehensive RA artist support.

## Architecture

### Core Components

1. **ArtistEnrichmentJob** (`lib/eventasaurus_discovery/sources/resident_advisor/jobs/artist_enrichment_job.ex`)
   - Oban background worker for asynchronous enrichment
   - Handles individual performer enrichment
   - Includes batch processing and rate limiting
   - Retry logic with 3 max attempts

2. **Enrichment Helper** (`lib/eventasaurus_discovery/sources/resident_advisor/enrichment.ex`)
   - Convenience functions for enrichment management
   - Status checking and reporting
   - Queue prioritization
   - Batch scheduling utilities

### Data Flow

```
RA Event Import (Phase I & II)
    ↓
Performers created with RA metadata
    ↓
Enrichment job scheduled (Phase III)
    ↓
Performer record updated with enriched data
    ↓
Completeness tracking and timestamps
```

## Usage

### Enrich a Single Performer

```elixir
# By performer ID
{:ok, :scheduled} = Enrichment.enrich_performer(123)
```

### Enrich All Performers from an Event

```elixir
# After importing an RA event, enrich all its performers
{:ok, count} = Enrichment.enrich_event_performers(event_id)
```

### Batch Enrichment with Rate Limiting

```elixir
# Enrich 50 performers with 60-second intervals
{:ok, count} = ArtistEnrichmentJob.enrich_batch(
  batch_size: 50,
  delay_seconds: 60
)
```

### High-Priority Enrichment

```elixir
# Enrich performers missing images (highest priority)
{:ok, count} = Enrichment.enrich_high_priority(50)
```

### Enrich All Pending

```elixir
# Schedule enrichment for all performers needing it
{:ok, count} = ArtistEnrichmentJob.enrich_all_pending()
```

## Monitoring & Reporting

### Get Enrichment Statistics

```elixir
stats = ArtistEnrichmentJob.enrichment_stats()
# Returns:
# %{
#   total_ra_performers: 150,
#   enriched_performers: 120,
#   performers_with_images: 110,
#   pending_enrichment: 30,
#   enrichment_percentage: 80.0
# }
```

### Check Individual Performer Status

```elixir
# Get detailed enrichment report
{:ok, report} = Enrichment.enrichment_report(performer_id)
# Returns:
# %{
#   performer_id: 123,
#   performer_name: "Carl Cox",
#   has_ra_artist_id: true,
#   has_image: true,
#   has_ra_url: true,
#   country: "United Kingdom",
#   enriched: true,
#   enriched_at: "2025-01-15T10:30:00Z",
#   completeness_score: 100.0
# }
```

### Check Enrichment Queue

```elixir
queue = Enrichment.get_enrichment_queue()
# Returns:
# %{
#   high_priority: [performers without images],
#   medium_priority: [performers without URLs],
#   low_priority: [other unenriched performers]
# }
```

### Check Performer Status

```elixir
# Check if performer has RA artist ID
Enrichment.has_ra_artist_id?(performer)  # true/false

# Check if performer has been enriched
Enrichment.enriched?(performer)  # true/false
```

## Enrichment Process

### What Gets Enriched

Phase III enrichment adds or updates:

1. **Image URL** - If missing, populated from metadata
2. **RA Artist URL** - Full profile URL (e.g., `https://ra.co/dj/carlcox`)
3. **Country Information** - Name and ISO code
4. **Source Attribution** - Marks as "resident_advisor"
5. **Enrichment Timestamp** - Tracks when enrichment occurred
6. **Completeness Score** - Percentage of available data fields populated

### Enrichment Priority

**High Priority** (Priority: 1)
- Performers missing profile images
- Most visible user-facing data

**Medium Priority** (Priority: 2)
- Performers with images but missing RA URLs
- Important for linking to RA profiles

**Low Priority** (Priority: 3)
- Other metadata enrichment
- Completeness improvements

## Data Structure

### Performer Metadata After Enrichment

```elixir
%Performer{
  id: 123,
  name: "Carl Cox",
  image_url: "https://static.ra.co/images/profiles/square/carlcox.jpg",
  metadata: %{
    "ra_artist_id" => "1",
    "ra_artist_url" => "https://ra.co/dj/carlcox",
    "country" => "United Kingdom",
    "country_code" => "GB",
    "source" => "resident_advisor",
    "enriched_at" => "2025-01-15T10:30:00Z"
  }
}
```

## Configuration

### Oban Queue

Enrichment jobs run in the `:enrichment` queue:

```elixir
# config/config.exs
config :eventasaurus, Oban,
  queues: [
    enrichment: 2,  # 2 concurrent enrichment jobs
    # ...
  ]
```

### Job Settings

```elixir
# In ArtistEnrichmentJob module
use Oban.Worker,
  queue: :enrichment,
  max_attempts: 3,      # Retry failed jobs 3 times
  priority: 2           # Medium priority
```

## Integration with Other Phases

### Phase I: Multi-Artist Support
- Phase III enriches ALL artists from events (not just the first)
- Each performer gets individual enrichment

### Phase II: Basic Enrichment
- Phase III uses data collected by Phase II
- No additional API calls required
- Works with existing event import workflow

### Automatic Enrichment

To automatically enrich performers after RA event imports:

```elixir
# In RA event processor or job
defp after_event_import(event) do
  # Schedule enrichment for all event performers
  Enrichment.enrich_event_performers(event.id)
end
```

## Completeness Scoring

Performers are scored based on available data:

| Field | Weight |
|-------|--------|
| RA Artist ID | 20% |
| Profile Image | 20% |
| RA Artist URL | 20% |
| Country | 20% |
| Country Code | 20% |

**Score Calculation:**
```
completeness = (completed_fields / total_fields) * 100
```

## Future Enhancements

### Potential Phase IV Features

1. **Web Scraping** (if needed)
   - Scrape artist pages for bios, social links
   - Requires careful rate limiting and ToS compliance

2. **Genre Extraction**
   - Parse genre information from RA pages
   - Auto-tag performers with music styles

3. **Social Media Links**
   - Extract SoundCloud, Spotify, Instagram links
   - Enable cross-platform discovery

4. **Historical Enrichment**
   - Backfill enrichment for existing performers
   - Scheduled periodic updates

5. **Deduplication**
   - Match RA artists to existing performers from other sources
   - Merge duplicate performer records

## Monitoring

### Check Job Status

```bash
# In IEx console
iex> Oban.check_queue(:enrichment)
```

### View Failed Jobs

```elixir
# Find failed enrichment jobs
Oban.Job
|> where([j], j.queue == "enrichment" and j.state == "discarded")
|> Repo.all()
```

### Reset Failed Enrichment

```elixir
# Reset enrichment timestamp to retry
{:ok, _} = Enrichment.reset_enrichment(performer_id)
```

## Error Handling

### Automatic Retries

Jobs automatically retry up to 3 times with exponential backoff:
- 1st retry: after 15 seconds
- 2nd retry: after 60 seconds
- 3rd retry: after 300 seconds

### Graceful Degradation

- Missing data fields are handled gracefully (stored as nil)
- Failed enrichment doesn't block performer creation
- Partial enrichment is preserved

### Logging

All enrichment operations are logged:
```
[info] Starting RA artist enrichment for performer_id=123
[info] Successfully enriched performer 123: Carl Cox
[error] Failed to enrich performer 456: update_failed
```

## Testing

### Run Phase III Tests

```bash
mix run test/one_off_scripts/test_phase_iii_enrichment.exs
```

### Manual Testing

```elixir
# In IEx console
alias EventasaurusDiscovery.Sources.ResidentAdvisor.{ArtistEnrichmentJob, Enrichment}

# Get statistics
stats = ArtistEnrichmentJob.enrichment_stats()

# Find performers needing enrichment
pending = ArtistEnrichmentJob.find_performers_needing_enrichment(5)

# Schedule one for enrichment (dry run - won't commit)
%{performer_id: List.first(pending).id}
|> ArtistEnrichmentJob.new()
|> Oban.insert()
```

## Performance Considerations

### Rate Limiting

- Default batch delay: 60 seconds between jobs
- Prevents overwhelming the system
- Configurable per batch

### Database Impact

- Uses efficient queries with indexes on `metadata` JSONB field
- Batch processing limits concurrent database connections
- Queries scoped to RA performers only

### Memory Usage

- Jobs process one performer at a time
- Minimal memory footprint
- No data caching required

## Summary

Phase III provides:
- ✅ Background job infrastructure for enrichment
- ✅ Batch processing with rate limiting
- ✅ Priority queue system
- ✅ Comprehensive monitoring and reporting
- ✅ Graceful error handling
- ✅ Completeness tracking
- ✅ Integration with Phases I & II

All three phases work together to provide complete RA artist support from event import through enrichment!
