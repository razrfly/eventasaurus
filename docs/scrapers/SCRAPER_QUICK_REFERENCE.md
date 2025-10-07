# Scraper Quick Reference Card

> **Quick lookup** for common scraper tasks and patterns

---

## 🚀 Quick Start

### Adding a New Scraper

```bash
# 1. Create directory
mkdir -p lib/eventasaurus_discovery/sources/my_source

# 2. Copy reference implementation
cp -r lib/eventasaurus_discovery/sources/resident_advisor/* \
      lib/eventasaurus_discovery/sources/my_source/

# 3. Update module names and configuration
# 4. Implement transformer.ex
# 5. Add tests
# 6. Create README
```

### Testing Daily Idempotency

```bash
# Run scraper twice in a row
iex -S mix
iex> MySource.Jobs.SyncJob.new(%{city_id: 1}) |> Oban.insert!()
# Wait for completion
iex> MySource.Jobs.SyncJob.new(%{city_id: 1}) |> Oban.insert!()

# Check for duplicates
iex> EventasaurusApp.Repo.all(
  from e in Event,
  where: e.source_id == ^source_id,
  group_by: e.external_id,
  having: count(e.id) > 1
)
# Should return []
```

---

## 📁 File Structure Template

```
sources/my_source/
├── source.ex              # ✅ REQUIRED: Configuration
├── config.ex              # ✅ REQUIRED: Runtime settings
├── transformer.ex         # ✅ REQUIRED: Unified format
├── client.ex              # ⚠️  For APIs/scrapers
├── dedup_handler.ex      # ⚠️  Recommended
├── jobs/
│   ├── sync_job.ex       # ✅ REQUIRED
│   └── detail_job.ex     # ⚠️  If multi-stage
├── extractors/           # ⚠️  For HTML scrapers
│   └── event_extractor.ex
└── README.md             # ✅ REQUIRED
```

---

## 🎯 Transformer Checklist

```elixir
def transform_event(raw_event) do
  %{
    # ✅ REQUIRED
    external_id: "source_#{raw_event.id}",  # Must be stable! Used for freshness checking
    title: raw_event.title,
    starts_at: parse_datetime(raw_event.date),  # DateTime, not NaiveDateTime

    # ✅ REQUIRED venue (even if GPS missing)
    venue_data: %{
      name: raw_event.venue.name,
      address: raw_event.venue.address,
      city: raw_event.venue.city,
      country: "Poland",  # Or from data
      latitude: nil,  # OK! VenueProcessor geocodes
      longitude: nil
    },

    # ⚠️  RECOMMENDED
    ends_at: calculate_end_time(raw_event),
    description: raw_event.description,
    source_url: raw_event.url,
    image_url: raw_event.image,

    # ⚠️  OPTIONAL
    performers: transform_performers(raw_event.artists),
    is_ticketed: raw_event.has_tickets,
    is_free: raw_event.price == 0,
    min_price: raw_event.price,
    currency: "PLN"
  }
end
```

---

## 🔄 Freshness Checking Pattern (REQUIRED)

**Add to IndexPageJob or SyncJob before scheduling detail jobs:**

```elixir
defp schedule_detail_jobs(events, source_id) do
  alias EventasaurusDiscovery.Services.EventFreshnessChecker

  # 1. Ensure external_id on all events
  events_with_ids = Enum.map(events, fn event ->
    Map.put(event, :external_id, "source_#{event.id}")
  end)

  # 2. Filter stale events (not seen in last 7 days)
  events_to_process = EventFreshnessChecker.filter_events_needing_processing(
    events_with_ids,
    source_id
  )

  # 3. Log efficiency
  skipped = length(events) - length(events_to_process)
  Logger.info("Processing #{length(events_to_process)}/#{length(events)} events (#{skipped} fresh)")

  # 4. Schedule only stale events
  Enum.each(events_to_process, &schedule_job/1)
end
```

**Why?** Prevents re-scraping events updated within threshold window (default 7 days, configurable per source). Saves 80-90% API calls for recurring events.

**Source-Specific Thresholds**: Some sources need different scraping frequencies:

```elixir
# config/dev.exs, config/test.exs, config/runtime.exs
config :eventasaurus, :event_discovery,
  freshness_threshold_hours: 168,  # Default: 7 days
  source_freshness_overrides: %{
    "kino-krakow" => 24,    # Daily scraping
    "cinema-city" => 48      # Every 2 days
  }
```

EventFreshnessChecker automatically uses source-specific thresholds when available. No code changes needed in scrapers - just add override to config.

---

## 🔄 Common Patterns

### Pattern: API Source

```elixir
# client.ex
def fetch_events(city_id, page \\ 1) do
  url = "#{Config.base_url()}/events"
  params = %{city: city_id, page: page}

  case HTTPoison.get(url, [], params: params) do
    {:ok, %{status_code: 200, body: body}} ->
      {:ok, Jason.decode!(body)}
    {:error, reason} ->
      {:error, reason}
  end
end

# jobs/sync_job.ex
def fetch_events(city, _limit, _options) do
  Client.fetch_events(city.id)
end

def transform_events(raw_events) do
  Enum.map(raw_events, &Transformer.transform_event/1)
end
```

### Pattern: HTML Scraper

```elixir
# client.ex
def fetch_page(url) do
  case HTTPoison.get(url, Config.headers()) do
    {:ok, %{status_code: 200, body: html}} ->
      {:ok, html}
    error ->
      error
  end
end

# extractors/event_extractor.ex
def extract_events(html) do
  html
  |> Floki.parse_document!()
  |> Floki.find(".event-card")
  |> Enum.map(&extract_event_data/1)
end

defp extract_event_data(element) do
  %{
    title: Floki.find(element, "h2") |> Floki.text(),
    url: Floki.find(element, "a") |> Floki.attribute("href") |> List.first(),
    date: Floki.find(element, ".date") |> Floki.text()
  }
end
```

### Pattern: Deduplication Handler

```elixir
# dedup_handler.ex
def validate_event_quality(event_data) do
  cond do
    is_nil(event_data[:title]) ->
      {:error, "Missing title"}

    is_nil(event_data[:starts_at]) ->
      {:error, "Missing start date"}

    not is_date_sane?(event_data[:starts_at]) ->
      {:error, "Date is not sane"}

    true ->
      {:ok, event_data}
  end
end

def check_duplicate(event_data) do
  case find_by_external_id(event_data[:external_id]) do
    nil -> {:unique, event_data}
    existing -> {:duplicate, existing}
  end
end
```

---

## 🐛 Debugging

### Check Job Status

```elixir
# See recent jobs
Oban.Job |> where([j], j.queue == "scraper_index") |> order_by(desc: :inserted_at) |> limit(10) |> Repo.all()

# See failed jobs
Oban.Job |> where([j], j.state == "discarded" and j.queue == "scraper_index") |> Repo.all()

# Retry failed job
Oban.Job |> Repo.get!(job_id) |> Oban.retry_job()
```

### Check Deduplication

```elixir
# Find duplicate venues (shouldn't exist)
from(v in Venue,
  group_by: [v.place_id],
  having: count(v.id) > 1,
  select: {v.place_id, count(v.id)}
) |> Repo.all()

# Find events without last_seen_at updates (stale)
from(e in Event,
  where: e.last_seen_at < ago(7, "day"),
  where: e.starts_at > ^DateTime.utc_now()
) |> Repo.all()
```

### Test Geocoding

```elixir
# Manually geocode venue
venue_data = %{
  name: "Jazz Club",
  address: "ul. Floriańska 3",
  city: "Kraków",
  country: "Poland"
}

VenueProcessor.process_venue(venue_data, source)
```

---

## ⚠️ Common Mistakes

### ❌ DON'T: Manual Geocoding

```elixir
# BAD
def transform_event(event) do
  coords = GooglePlaces.geocode(event.venue.address)  # ❌
  %{venue_data: Map.merge(event.venue, coords)}
end
```

```elixir
# GOOD
def transform_event(event) do
  %{
    venue_data: %{
      name: event.venue.name,
      address: event.venue.address,
      latitude: nil,  # Let VenueProcessor handle it ✅
      longitude: nil
    }
  }
end
```

### ❌ DON'T: Unstable External IDs

```elixir
# BAD - changes every run
external_id: "event_#{DateTime.utc_now() |> DateTime.to_unix()}"

# GOOD - stable across runs
external_id: "source_event_#{event.id}"
```

### ❌ DON'T: NaiveDateTime

```elixir
# BAD
starts_at: ~N[2025-10-08 18:00:00]

# GOOD
starts_at: TimezoneConverter.convert_local_to_utc(
  ~N[2025-10-08 18:00:00],
  "Europe/Warsaw"
)
```

---

## 📊 Priority Levels

```
90-100: Premium APIs (Ticketmaster)
70-89:  International trusted (Resident Advisor, Bandsintown)
50-69:  Regional reliable
30-49:  Local/niche (Karnet, PubQuiz)
0-29:   Experimental
```

**Higher priority = wins deduplication conflicts**

---

## 🧪 Testing Snippets

### Test Transformer

```elixir
test "transforms event correctly" do
  raw = %{
    "id" => "123",
    "title" => "Concert",
    "date" => "2025-10-08T18:00:00Z",
    "venue" => %{"name" => "Club", "city" => "Kraków"}
  }

  {:ok, transformed} = Transformer.transform_event(raw)

  assert transformed.external_id == "source_event_123"
  assert transformed.title == "Concert"
  assert transformed.venue_data.name == "Club"
end
```

### Test Deduplication

```elixir
test "does not create duplicates on second run" do
  # First run
  {:ok, _} = SyncJob.perform(%{city_id: city.id})
  first_count = Repo.aggregate(Event, :count)

  # Second run
  {:ok, _} = SyncJob.perform(%{city_id: city.id})
  second_count = Repo.aggregate(Event, :count)

  assert first_count == second_count
end
```

---

## 📝 Logging Standards

```elixir
# Success
Logger.info("✅ Successfully processed #{count} events")

# In Progress
Logger.info("🔄 Processing page #{page} of #{total_pages}")

# Warning
Logger.warning("⚠️ Partial failure: #{failed}/#{total}")

# Error
Logger.error("❌ Failed to fetch: #{reason}")

# Critical
Logger.error("🚫 CRITICAL: Missing GPS coordinates")
```

---

## 🔗 Quick Links

- [Full Specification](./SCRAPER_SPECIFICATION.md)
- [Audit Report](./SCRAPER_AUDIT_REPORT.md)
- [Summary](./SCRAPER_DOCUMENTATION_SUMMARY.md)
- [Issue Template](./.github/ISSUE_TEMPLATE/scraper_improvements.md)

---

## 💡 Pro Tips

1. **Start with Resident Advisor** - Best reference implementation
2. **Test idempotency early** - Run twice immediately
3. **Let VenueProcessor geocode** - Don't do it yourself
4. **Stable external_ids** - Use source's stable identifier
5. **Log with emojis** - Makes monitoring easier (✅❌⚠️)
6. **Use BaseJob** - Handles common patterns
7. **Document as you go** - README prevents future confusion
