# Resident Advisor (RA) Scraper Implementation

**Status:** 📋 Planning
**Priority:** High
**Source Priority:** 75 (Major international source)
**Estimated Effort:** 3-5 days

---

## 🎯 Overview

Implement a production-ready scraper for Resident Advisor (ra.co), a major international electronic music events platform. RA provides comprehensive event listings for electronic music events worldwide with high-quality data.

**Target Implementation:** GraphQL API-based scraper with Google Places geocoding fallback

**Reference Library:** [djb-gt/resident-advisor-events-scraper](https://github.com/djb-gt/resident-advisor-events-scraper)

---

## 📊 Source Analysis

### Data Source Type

**Type:** API-based (GraphQL)

**Pros:**
- ✅ Structured JSON responses
- ✅ Built-in pagination
- ✅ Reliable data format
- ✅ Less prone to breakage than HTML scraping
- ✅ International coverage
- ✅ High-quality electronic music events

**Cons:**
- ❌ Venue coordinates NOT included in base event query
- ❌ May require separate venue detail queries
- ❌ Possible rate limiting (needs investigation)
- ❌ Unknown if API requires authentication

### Available Data Fields

Based on analysis of the [GraphQL query template](https://github.com/djb-gt/resident-advisor-events-scraper/blob/master/graphql_query_template.json):

**Event Fields:**
- `id` - Unique event ID
- `title` - Event name
- `date` - Event date
- `startTime` - Start time
- `endTime` - End time (if available)
- `contentUrl` - Event detail URL
- `flyerFront` - Event poster/flyer image
- `isTicketed` - Boolean for ticketed events
- `attending` - Number of attendees (social proof)
- `images` - Event images with metadata
- `pick.blurb` - Editorial description (if featured)

**Venue Fields:**
- `id` - Venue ID
- `name` - Venue name ✅
- `contentUrl` - Venue detail URL
- `live` - Venue status
- ❌ **Coordinates NOT provided in base query**

**Artist Fields:**
- Artist information (structure unclear, needs investigation)

**Pagination:**
- `page` - Current page number
- `pageSize` - Results per page (default: 20)
- `totalResults` - Total available results

**Filters:**
- `areas` - Geographic area filter (exact match)
- `listingDate` - Date range filtering
- `genre` - Genre filter (optional)

### Critical Gap: Venue Coordinates

**Problem:** RA's GraphQL API does not provide venue coordinates in the base event listing query.

**Solutions (in priority order):**

1. **Option A: Venue Detail GraphQL Query** (INVESTIGATE FIRST)
   - Check if RA has a separate venue query that includes coordinates
   - Query pattern: `venue(id: $venueId) { latitude, longitude }`
   - **Status:** Needs investigation

2. **Option B: Venue Detail Page Scraping** (FALLBACK)
   - Fetch venue `contentUrl` and parse HTML for embedded coordinates
   - Many venue pages have embedded maps with lat/lng
   - **Status:** Needs HTML structure analysis

3. **Option C: Google Places API Geocoding** (PROVEN PATTERN)
   - Use venue name + city from event data
   - Geocode via Google Places API
   - **Status:** Proven working in Karnet scraper

**Recommended Strategy:** Try Option A, fallback to C (skip B unless A fails and C has low accuracy)

---

## 🏗️ Implementation Plan

### Phase 1: Research & Discovery (Day 1)

**Objectives:**
- [ ] Identify actual GraphQL endpoint URL
- [ ] Test GraphQL queries (events, venues, pagination)
- [ ] Determine if authentication is required
- [ ] Check rate limiting policies (robots.txt, terms of service)
- [ ] Investigate venue coordinate availability
- [ ] Map area codes to our city system

**Deliverables:**
- GraphQL endpoint documentation
- Sample queries with responses
- Rate limit specification
- Venue coordinate strategy decision

**Tasks:**
```bash
# 1. Analyze network requests
# Open https://ra.co/events/pl/warsaw in browser
# Check Network tab for GraphQL requests
# Document endpoint URL, headers, auth requirements

# 2. Test GraphQL queries
# Use Postman/Insomnia to test queries
# Test event listing, venue details, pagination

# 3. Check for venue coordinates
# Query venue details by ID
# Check if coordinates are available

# 4. Map areas to cities
# Document area codes for target cities
# Create mapping in config
```

### Phase 2: Module Setup (Day 1-2)

**Objectives:**
- [ ] Create module structure following manifesto
- [ ] Implement SourceConfig
- [ ] Implement GraphQL client
- [ ] Set up Oban jobs

**Module Structure:**
```
lib/eventasaurus_discovery/sources/resident_advisor/
├── config.ex              # SourceConfig with GraphQL endpoint
├── source.ex              # Source metadata
├── client.ex              # GraphQL client
├── transformer.ex         # Raw GraphQL → Unified format
├── dedup_handler.ex       # Deduplication (optional)
├── venue_enricher.ex      # Coordinate fetching strategy
├── jobs/
│   ├── sync_job.ex        # Orchestration
│   ├── index_page_job.ex  # Paginated event fetching
│   └── event_detail_job.ex # Individual event processing
└── helpers/
    ├── date_parser.ex     # RA date format → DateTime
    ├── area_mapper.ex     # Area codes → cities
    └── graphql_builder.ex # GraphQL query construction
```

**Files to Create:**

1. **config.ex**
```elixir
defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.Config do
  @behaviour EventasaurusDiscovery.Sources.SourceConfig

  @graphql_endpoint "https://ra.co/graphql"  # TO CONFIRM
  @rate_limit 2  # Conservative initial limit

  @impl EventasaurusDiscovery.Sources.SourceConfig
  def source_config do
    EventasaurusDiscovery.Sources.SourceConfig.merge_config(%{
      name: "Resident Advisor",
      slug: "resident_advisor",
      priority: 75,  # Below Ticketmaster, above regional sources
      rate_limit: @rate_limit,
      timeout: 15_000,
      max_retries: 3,
      queue: :discovery,
      base_url: "https://ra.co",
      api_key: nil,
      api_secret: nil,
      metadata: %{
        graphql_endpoint: @graphql_endpoint,
        requires_auth: false,  # TO CONFIRM
        venue_geocoding_strategy: :google_places  # or :detail_query
      }
    })
  end

  def graphql_endpoint, do: @graphql_endpoint
  def rate_limit, do: @rate_limit

  # Area code mapping (to be populated during research)
  def area_for_city(city_name) do
    %{
      "Warsaw" => "pl/warsaw",
      "Kraków" => "pl/krakow",
      "Berlin" => "de/berlin",
      # ... more mappings
    }[city_name]
  end
end
```

2. **client.ex**
```elixir
defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.Client do
  @moduledoc """
  GraphQL client for Resident Advisor API.
  """

  require Logger
  alias EventasaurusDiscovery.Sources.ResidentAdvisor.Config

  def fetch_events(area_code, page \\ 1, page_size \\ 20, date_from \\ nil) do
    query = build_events_query()
    variables = build_variables(area_code, page, page_size, date_from)

    execute_graphql(query, variables)
  end

  def fetch_venue_details(venue_id) do
    # If RA supports venue detail query
    query = build_venue_query()
    variables = %{"venueId" => venue_id}

    execute_graphql(query, variables)
  end

  defp execute_graphql(query, variables) do
    body = Jason.encode!(%{query: query, variables: variables})

    case HTTPoison.post(
      Config.graphql_endpoint(),
      body,
      headers(),
      timeout: 15_000
    ) do
      {:ok, %{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"data" => data}} -> {:ok, data}
          {:ok, %{"errors" => errors}} -> {:error, {:graphql_errors, errors}}
          error -> error
        end

      {:ok, %{status_code: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp headers do
    [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"User-Agent", "EventasaurusDiscovery/1.0"}
      # Add authentication headers if needed
    ]
  end

  defp build_events_query do
    """
    query EventListing($area: String!, $page: Int!, $pageSize: Int!, $dateFrom: String) {
      eventListing(
        area: $area
        page: $page
        pageSize: $pageSize
        filters: {
          listingDate: {
            gte: $dateFrom
          }
        }
      ) {
        totalResults
        events {
          id
          title
          date
          startTime
          endTime
          contentUrl
          flyerFront
          isTicketed
          attending
          images {
            filename
            alt
            type
          }
          pick {
            blurb
          }
          venue {
            id
            name
            contentUrl
            live
          }
          artists {
            # TODO: Determine artist structure
          }
        }
      }
    }
    """
  end

  defp build_venue_query do
    # IF RA supports venue detail query
    """
    query VenueDetail($venueId: ID!) {
      venue(id: $venueId) {
        id
        name
        latitude
        longitude
        address
        city
        country
      }
    }
    """
  end

  defp build_variables(area_code, page, page_size, date_from) do
    variables = %{
      "area" => area_code,
      "page" => page,
      "pageSize" => page_size
    }

    if date_from do
      Map.put(variables, "dateFrom", date_from)
    else
      variables
    end
  end
end
```

3. **transformer.ex**
```elixir
defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.Transformer do
  @moduledoc """
  Transforms RA GraphQL data into unified event format.

  CRITICAL: All events must have venue with coordinates.
  Uses Google Places geocoding for missing coordinates.
  """

  require Logger
  alias EventasaurusDiscovery.Sources.ResidentAdvisor.VenueEnricher

  def transform_event(raw_event, city_context) do
    # Extract venue first (CRITICAL)
    venue_data = extract_venue(raw_event, city_context)

    # Validate venue
    case validate_venue(venue_data) do
      :ok ->
        transformed = %{
          # Required fields
          title: extract_title(raw_event),
          external_id: extract_external_id(raw_event),
          starts_at: extract_starts_at(raw_event, city_context),
          ends_at: extract_ends_at(raw_event, city_context),
          venue_data: venue_data,

          # Optional fields
          description: extract_description(raw_event),
          ticket_url: build_event_url(raw_event["contentUrl"]),
          image_url: extract_image_url(raw_event),
          is_ticketed: raw_event["isTicketed"] || false,

          # RA-specific data
          attending_count: raw_event["attending"],
          is_featured: !is_nil(raw_event["pick"]),

          # Performer data
          performer: extract_performer(raw_event),

          # Tags
          tags: extract_tags(raw_event),

          # Source reference
          source_url: build_event_url(raw_event["contentUrl"]),
          raw_data: raw_event
        }

        {:ok, transformed}

      {:error, reason} ->
        Logger.error("""
        ❌ RA event rejected: #{reason}
        Event: #{raw_event["title"]}
        URL: #{raw_event["contentUrl"]}
        Venue: #{inspect(venue_data)}
        """)
        {:error, reason}
    end
  end

  def validate_venue(venue_data) do
    cond do
      is_nil(venue_data) ->
        {:error, "Venue data required"}
      is_nil(venue_data[:name]) || venue_data[:name] == "" ->
        {:error, "Venue name required"}
      is_nil(venue_data[:latitude]) ->
        {:error, "Venue latitude required"}
      is_nil(venue_data[:longitude]) ->
        {:error, "Venue longitude required"}
      true ->
        :ok
    end
  end

  defp extract_venue(event, city_context) do
    venue = event["venue"]

    # Try to get coordinates through various strategies
    {lat, lng, needs_geocoding} = VenueEnricher.get_coordinates(
      venue["id"],
      venue["name"],
      city_context
    )

    %{
      name: venue["name"],
      latitude: lat,
      longitude: lng,
      city: city_context.name,
      country: city_context.country.name,
      needs_geocoding: needs_geocoding,
      external_venue_id: venue["id"],
      source_url: build_venue_url(venue["contentUrl"])
    }
  end

  defp extract_title(event), do: event["title"] || "Unknown Event"

  defp extract_external_id(event) do
    "resident_advisor_#{event["id"]}"
  end

  defp extract_starts_at(event, city_context) do
    # Combine date + startTime
    # Parse with city timezone, convert to UTC
    # TODO: Implement date parsing
  end

  defp extract_ends_at(event, city_context) do
    if event["endTime"] do
      # Parse end time
    else
      nil
    end
  end

  defp extract_description(event) do
    # Use pick.blurb if available
    get_in(event, ["pick", "blurb"])
  end

  defp extract_image_url(event) do
    event["flyerFront"] ||
      get_in(event, ["images", Access.at(0), "filename"])
  end

  defp extract_performer(event) do
    # TODO: Parse artists array
    nil
  end

  defp extract_tags(event) do
    tags = ["electronic-music"]

    if event["isTicketed"], do: ["ticketed" | tags], else: tags
    if event["pick"], do: ["featured" | tags], else: tags

    tags
  end

  defp build_event_url(path) do
    "https://ra.co#{path}"
  end

  defp build_venue_url(path) do
    "https://ra.co#{path}"
  end
end
```

4. **venue_enricher.ex**
```elixir
defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.VenueEnricher do
  @moduledoc """
  Handles venue coordinate enrichment for RA events.

  Strategy:
  1. Try venue detail GraphQL query (if available)
  2. Fallback to Google Places geocoding
  3. Last resort: city center coordinates
  """

  require Logger
  alias EventasaurusDiscovery.Sources.ResidentAdvisor.Client

  def get_coordinates(venue_id, venue_name, city_context) do
    cond do
      # Strategy 1: Venue detail query
      coords = try_venue_detail_query(venue_id) ->
        Logger.debug("✅ Got coordinates from venue detail query")
        {coords.lat, coords.lng, false}

      # Strategy 2: Google Places geocoding
      coords = try_google_places(venue_name, city_context) ->
        Logger.debug("✅ Got coordinates from Google Places")
        {coords.lat, coords.lng, false}

      # Strategy 3: City center fallback
      true ->
        Logger.warning("⚠️ Using city center for venue: #{venue_name}")
        lat = Decimal.to_float(city_context.latitude)
        lng = Decimal.to_float(city_context.longitude)
        {lat, lng, true}
    end
  end

  defp try_venue_detail_query(venue_id) do
    case Client.fetch_venue_details(venue_id) do
      {:ok, %{"venue" => %{"latitude" => lat, "longitude" => lng}}}
        when not is_nil(lat) and not is_nil(lng) ->
        %{lat: lat, lng: lng}

      _ ->
        nil
    end
  end

  defp try_google_places(venue_name, city_context) do
    # Use existing Google Places integration
    # Implementation TBD - reference Karnet pattern
    nil
  end
end
```

### Phase 3: Job Pipeline (Day 2-3)

**Objectives:**
- [ ] Implement SyncJob (entry point)
- [ ] Implement IndexPageJob (pagination)
- [ ] Implement EventDetailJob (enrichment)
- [ ] Test async pipeline

**Job Flow:**

```
SyncJob
  ├─ Validate city has RA area code
  ├─ Determine pagination (probe first page)
  └─ Schedule IndexPageJobs (staggered)
      │
      ├─ IndexPageJob (Page 1)
      │   ├─ Fetch events via GraphQL
      │   ├─ Parse response
      │   └─ Schedule EventDetailJobs
      │       │
      │       ├─ EventDetailJob (Event 1)
      │       │   ├─ Enrich venue coordinates
      │       │   ├─ Transform to unified format
      │       │   ├─ Validate venue
      │       │   └─ Process via Processor
      │       │
      │       ├─ EventDetailJob (Event 2)
      │       └─ ...
      │
      ├─ IndexPageJob (Page 2)
      └─ ...
```

**Jobs Implementation:**

1. **sync_job.ex** - Similar to Bandsintown SyncJob
2. **index_page_job.ex** - GraphQL pagination
3. **event_detail_job.ex** - Venue enrichment + transformation

### Phase 4: Testing & Validation (Day 3-4)

**Objectives:**
- [ ] Create Mix task for manual testing
- [ ] Write unit tests for transformer
- [ ] Write integration tests for client
- [ ] Test with real RA data (Warsaw, Kraków)
- [ ] Verify venue validation works
- [ ] Check geocoding accuracy

**Mix Task:**
```bash
# lib/mix/tasks/resident_advisor.test.ex
mix resident_advisor.test warsaw --limit 10
```

**Test Cases:**
```elixir
# test/eventasaurus_discovery/sources/resident_advisor/transformer_test.exs
defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.TransformerTest do
  use ExUnit.Case
  alias EventasaurusDiscovery.Sources.ResidentAdvisor.Transformer

  describe "transform_event/2" do
    test "transforms valid RA event" do
      raw_event = %{
        "id" => "12345",
        "title" => "Techno Night",
        "date" => "2025-10-15",
        "startTime" => "23:00",
        "venue" => %{
          "id" => "venue-123",
          "name" => "Smolna",
          "contentUrl" => "/clubs/smolna"
        }
      }

      city = %{name: "Warsaw", country: %{name: "Poland"}}

      assert {:ok, transformed} = Transformer.transform_event(raw_event, city)
      assert transformed.title == "Techno Night"
      assert transformed.external_id == "resident_advisor_12345"
      assert transformed.venue_data.name == "Smolna"
    end

    test "rejects event without venue name" do
      raw_event = %{
        "id" => "12345",
        "title" => "Event",
        "venue" => %{"id" => "123", "name" => nil}
      }

      city = %{name: "Warsaw"}

      assert {:error, _reason} = Transformer.transform_event(raw_event, city)
    end
  end

  describe "validate_venue/1" do
    test "validates venue with all required fields" do
      venue = %{
        name: "Test Venue",
        latitude: 52.0,
        longitude: 21.0
      }

      assert :ok = Transformer.validate_venue(venue)
    end

    test "rejects venue without coordinates" do
      venue = %{name: "Test Venue"}

      assert {:error, _} = Transformer.validate_venue(venue)
    end
  end
end
```

### Phase 5: Integration & Documentation (Day 4-5)

**Objectives:**
- [ ] Add to main source registry
- [ ] Configure Oban queues
- [ ] Set up monitoring
- [ ] Document usage
- [ ] Create examples
- [ ] Update SCRAPER_MANIFESTO.md

**Integration Points:**

1. **Add to source list**
```elixir
# In main source module or config
@sources [
  :ticketmaster,
  :bandsintown,
  :resident_advisor,  # NEW
  :karnet,
  :kino_krakow
]
```

2. **Update documentation**
```markdown
# README.md

## Supported Sources

- **Ticketmaster** (Priority: 90) - International events, official ticketing
- **Resident Advisor** (Priority: 75) - Electronic music events, international
- **Bandsintown** (Priority: 80) - Music events, international
- **Karnet** (Priority: 60) - Kraków cultural events
- **Kino Krakow** (Priority: 55) - Kraków cinema events
```

---

## 🔍 Research Checklist

Before starting implementation, research and document:

- [ ] **GraphQL Endpoint URL** - Actual endpoint (not confirmed yet)
- [ ] **Authentication Requirements** - API key needed? Login required?
- [ ] **Rate Limits** - Requests per second/minute
- [ ] **Venue Coordinates** - Available in detail query? Format?
- [ ] **Area Code Mapping** - List of area codes for target cities
- [ ] **Date Format** - How RA represents dates and times
- [ ] **Artist Structure** - Format of artists array
- [ ] **Pagination Limits** - Max page size, total results
- [ ] **Terms of Service** - Commercial use allowed?
- [ ] **Error Responses** - Common error codes and handling

**How to Research:**

1. **Browser DevTools**
```bash
# Open https://ra.co/events/pl/warsaw
# Open Network tab
# Filter by "graphql" or "fetch/XHR"
# Find GraphQL requests
# Copy request URL, headers, payload
# Document response structure
```

2. **Test GraphQL Queries**
```bash
# Use Postman or curl
curl -X POST https://ra.co/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ eventListing(...) { ... } }"}'
```

3. **Check robots.txt**
```
https://ra.co/robots.txt
```

4. **Check Terms of Service**
```
https://ra.co/terms
```

---

## 🚨 Known Challenges & Solutions

### Challenge 1: Venue Coordinates Not in Base Query

**Problem:** GraphQL event listing doesn't include venue lat/lng

**Solutions:**
1. ✅ Use Google Places API (proven in Karnet)
2. 🔄 Check if venue detail query provides coordinates
3. ⚠️ Scrape venue detail pages (last resort)

**Recommended:** Google Places API (reliable, proven)

### Challenge 2: Area Code Mapping

**Problem:** RA uses area codes (e.g., "pl/warsaw"), we use city IDs

**Solution:** Create mapping helper
```elixir
# config.ex
def area_for_city(%City{name: name, country: country}) do
  # Build area code: {country_code}/{city_slug}
  country_code = String.downcase(country.code)
  city_slug = Slug.slugify(name)
  "#{country_code}/#{city_slug}"
end
```

### Challenge 3: Rate Limiting

**Problem:** Unknown rate limits, risk of being blocked

**Solutions:**
1. Start conservative (2 req/s)
2. Monitor for 429 responses
3. Implement exponential backoff
4. Respect rate limit headers (if present)

### Challenge 4: Date/Time Parsing

**Problem:** RA uses separate date and time fields, timezone unclear

**Solution:**
```elixir
# Use city timezone, convert to UTC
defp parse_datetime(date_str, time_str, timezone) do
  # Combine: "2025-10-15" + "23:00"
  naive_dt = NaiveDateTime.from_iso8601!("#{date_str} #{time_str}:00")

  # Convert to city timezone, then UTC
  EventasaurusDiscovery.Scraping.Helpers.TimezoneConverter
    .convert_to_utc(naive_dt, timezone)
end
```

---

## 📊 Success Metrics

**Phase 1 Success:**
- [ ] GraphQL endpoint identified and documented
- [ ] Sample queries working
- [ ] Venue coordinate strategy decided

**Phase 2 Success:**
- [ ] All modules created with proper structure
- [ ] SourceConfig implemented
- [ ] GraphQL client working

**Phase 3 Success:**
- [ ] Async job pipeline functional
- [ ] Can fetch and process 10 events
- [ ] Venue validation working

**Phase 4 Success:**
- [ ] Mix task working
- [ ] Unit tests passing (>80% coverage)
- [ ] Integration tests passing

**Phase 5 Success:**
- [ ] Integrated into main app
- [ ] Documentation complete
- [ ] Ready for production use

**Production Success (Week 1):**
- [ ] 100+ events scraped successfully
- [ ] <5% venue geocoding failures
- [ ] No rate limit errors
- [ ] <2% event rejection rate

---

## 🔗 References

- [RA Python Scraper](https://github.com/djb-gt/resident-advisor-events-scraper) - Existing implementation
- [SCRAPER_MANIFESTO.md](./SCRAPER_MANIFESTO.md) - Our scraping standards
- [Bandsintown Implementation](../lib/eventasaurus_discovery/sources/bandsintown/) - Similar API-based scraper
- [Karnet Implementation](../lib/eventasaurus_discovery/sources/karnet/) - Geocoding reference

---

## 📝 Notes

### Why Priority 75?

- **Ticketmaster (90):** Official ticketing, highest quality
- **Bandsintown (80):** Major music platform, broad coverage
- **Resident Advisor (75):** Specialized (electronic music), high quality, international
- **Karnet (60):** Regional source, Kraków only
- **Kino Krakow (55):** Regional source, cinema only

RA gets priority 75 because:
- ✅ International coverage
- ✅ High-quality electronic music events
- ✅ Reliable data source
- ⚠️ Specialized genre (not all music)
- ⚠️ Lower than general music platforms

### Why GraphQL Instead of HTML Scraping?

1. **Reliability:** GraphQL is versioned and stable
2. **Performance:** JSON parsing faster than HTML
3. **Maintainability:** Less prone to breakage
4. **Data Quality:** Structured, validated data

### Open Questions

1. Does RA's GraphQL require authentication?
2. What are the actual rate limits?
3. Is there a venue detail query with coordinates?
4. How do we handle multiple artists per event?
5. What's the date/time timezone (local or UTC)?

**Next Steps:** Phase 1 research will answer these questions.

---

**Estimated Timeline:**
- **Day 1:** Research + module setup
- **Day 2:** Client + transformer
- **Day 3:** Job pipeline + testing
- **Day 4:** Integration tests + fixes
- **Day 5:** Documentation + production deploy

**Total:** 3-5 days (depending on venue coordinate complexity)
