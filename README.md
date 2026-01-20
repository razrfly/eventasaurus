# Eventasaurus 🦕

A modern event planning and management platform built with Phoenix LiveView, designed to help groups organize activities, coordinate schedules, and track shared experiences.

## Features

- **Event Creation & Management**: Create and manage events with rich details, themes, and customization options
- **Group Organization**: Form groups, manage memberships, and coordinate group activities
- **Polling System**: Democratic decision-making with various poll types (dates, activities, movies, restaurants)
- **Activity Tracking**: Track and log group activities with ratings and reviews
- **Real-time Updates**: LiveView-powered real-time interactions without page refreshes
- **Ticketing System**: Optional ticketing and payment processing via Stripe
- **Responsive Design**: Mobile-first design with Tailwind CSS
- **Soft Delete**: Data preservation with recovery options

## Tech Stack

- **Backend**: Elixir/Phoenix 1.7
- **Frontend**: Phoenix LiveView, Tailwind CSS, Alpine.js
- **Database**: PostgreSQL 14+ (via Fly Managed Postgres)
- **Authentication**: Clerk
- **CDN**: Cloudflare (with islands architecture for cached pages)
- **Payments**: Stripe (optional)
- **Analytics**: PostHog, Plausible (optional)
- **Testing**: ExUnit, Wallaby (E2E)

## Prerequisites

- Elixir 1.15 or later
- Phoenix 1.7 or later
- PostgreSQL 14 or later
- Node.js 18 or later
- Supabase CLI (for local development)

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/razrfly/eventasaurus.git
cd eventasaurus
```

### 2. Install dependencies

```bash
# Elixir dependencies
mix deps.get

# JavaScript dependencies
cd assets && npm install && cd ..
```

### 3. Set up environment variables

Create a `.env` file in the project root or add these to your shell profile:

```bash
# Required: Supabase (local development)
export SUPABASE_URL=http://127.0.0.1:54321
export SUPABASE_API_KEY=your_supabase_anon_key
export SUPABASE_DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres

# Optional: External services
export STRIPE_SECRET_KEY=sk_test_your_stripe_test_key
export STRIPE_CONNECT_CLIENT_ID=ca_your_connect_client_id
export POSTHOG_PUBLIC_API_KEY=your_posthog_key
export GOOGLE_MAPS_API_KEY=your_google_maps_key
export TMDB_API_KEY=your_tmdb_api_key
export RESEND_API_KEY=your_resend_api_key
export UNSPLASH_ACCESS_KEY=your_unsplash_access_key
```

### 4. Start Supabase locally

```bash
# Install Supabase CLI if you haven't already
brew install supabase/tap/supabase

# Start Supabase
supabase start
```

### 5. Set up the database

```bash
# Create and migrate the database
mix ecto.setup

# Or if the database already exists
mix ecto.migrate
```

### 6. Seed development data with authenticated users

For the seeding to create users that can actually log in, you need the Supabase service role key:

```bash
# Get the service role key from Supabase
supabase status | grep "service_role key"

# Export it for the current session
export SUPABASE_SERVICE_ROLE_KEY_LOCAL="<your-service-role-key>"

# Security note:
# - Never commit SUPABASE_SERVICE_ROLE_KEY* to the repo or share it.
# - Store it in a local .env file and ensure .env is gitignored.
# - Use different keys per environment.

# Run the main seeds (creates holden@gmail.com account)
mix run priv/repo/seeds.exs

mix seed.dev --users 5 --events 10 --groups 2
```

### 7. Start the Phoenix server

```bash
mix phx.server
```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Development Commands

### Database Management

```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Rollback migration
mix ecto.rollback

# Reset database (drop, create, migrate, seed)
mix ecto.reset

# Reset and seed with dev data
mix ecto.reset.dev

# Drop and recreate Supabase database completely
supabase db reset
```

#### Complete Database Reset with Authenticated Users

When you need to completely reset everything and create users that can log in:

```bash
# 1. Reset Supabase database (clears everything including auth users)
supabase db reset

# 2. Get and export the service role key
supabase status | grep "service_role key"
export SUPABASE_SERVICE_ROLE_KEY_LOCAL="<your-service-role-key>"

# 3. Run migrations
mix ecto.migrate

# 4. Create personal login account
mix run priv/repo/seeds.exs

# 5. Create test accounts and development data
mix seed.dev --users 5 --events 10 --groups 2
```

### Development Seeding

The project includes comprehensive development seeding using Faker and ExMachina:

```bash
# Seed with default configuration (50 users, 100 events, 15 groups)
mix seed.dev

# Seed with custom quantities
mix seed.dev --users 100 --events 200 --groups 30

# Seed specific entities only
mix seed.dev --only users,events

# Add data without cleaning existing
mix seed.dev --append

# Clean all seeded data
mix seed.clean

# Clean specific entity types
mix seed.clean --only events,polls,activities

# Reset and seed in one command
mix ecto.reset.dev
```

#### Seeded Data Includes:
- **Users**: Realistic profiles with names, emails, bios, social handles
- **Groups**: Various group sizes with members and roles
- **Events**: Past, current, and future events in different states (draft, polling, confirmed, canceled)
- **Participants**: Event attendees with various RSVP statuses
- **Activities**: Historical activity records for completed events
- **Venues**: Physical and virtual venue information

#### Test Accounts:
The seeding process creates test accounts you can use for development:

**Personal Login (created via seeds.exs):**
- Email: `holden@gmail.com`
- Password: `sawyer1234`

**Test Accounts (created via dev seeds with SUPABASE_SERVICE_ROLE_KEY_LOCAL):**
- Admin: `admin@example.com` / `testpass123`
- Demo: `demo@example.com` / `testpass123`

Note: All seeded accounts have auto-confirmed emails for immediate login in the dev environment.

### Testing

```bash
# Run all tests
mix test

# Run specific test file
mix test test/eventasaurus_web/live/event_live_test.exs

# Run tests with coverage
mix test --cover

# Run tests in watch mode
mix test.watch
```

### Code Quality

```bash
# Format code
mix format

# Run linter
mix credo

# Run dialyzer for type checking
mix dialyzer

# Check for security vulnerabilities
mix sobelow
```

### Asset Management

```bash
# Build assets for development
mix assets.build

# Build assets for production
mix assets.deploy

# Watch assets for changes
mix assets.watch
```

## Event Discovery & Scrapers

Eventasaurus includes a powerful event discovery system that aggregates events from multiple sources using scrapers and APIs.

### 📚 Scraper Documentation

**IMPORTANT**: All event scrapers follow a unified specification. Please read these documents before working with scrapers:

- **[Scraper Specification](docs/scrapers/SCRAPER_SPECIFICATION.md)** - ⭐ **Required reading** - The source of truth for building and maintaining scrapers
- **[Audit Report](docs/scrapers/SCRAPER_AUDIT_REPORT.md)** - Current state analysis and grading of all scrapers
- **[Implementation Guide](docs/scrapers/SCRAPER_DOCUMENTATION_SUMMARY.md)** - 3-phase improvement plan and best practices
- **[Quick Reference](docs/scrapers/SCRAPER_QUICK_REFERENCE.md)** - Developer cheat sheet for common patterns

### Active Event Sources

| Source | Priority | Type | Status |
|--------|----------|------|--------|
| **Ticketmaster** | 90 | API | ✅ Production |
| **Resident Advisor** | 75 | GraphQL | ✅ Production |
| **Karnet Kraków** | 30 | Scraper | ⚠️ Needs Tests |
| **Bandsintown** | 80 | API | ⚠️ Needs Consolidation |
| **Cinema City** | 50 | API | ⚠️ Needs Validation |
| **Kino Krakow** | 50 | Scraper | ⚠️ Needs Validation |
| **PubQuiz PL** | 40 | Scraper | ⚠️ Needs Refactoring |

**Priority Scale**: Higher number = more trusted source (wins deduplication conflicts)

### Running Scrapers

```bash
# Run discovery sync for a specific city
mix discovery.sync --city krakow --source ticketmaster

# Sync all sources for a city
mix discovery.sync --city krakow --source all

# Sync specific source with custom limit
mix discovery.sync --city krakow --source resident-advisor --limit 50
```

### Testing Recurring Event Regeneration

For pattern-based scrapers (Question One, Inquizition, etc.), test the automatic date regeneration feature for recurring events:

```bash
# Test Question One scraper with default settings (5 events)
mix discovery.test_recurring question-one

# Test with auto-scrape (automatically triggers scraper and verifies)
mix discovery.test_recurring question-one --auto-scrape

# Test specific number of events
mix discovery.test_recurring question-one --limit 10

# Test specific events by ID
mix discovery.test_recurring inquizition --ids 54,192,193

# Verify results after manual scraper run
mix discovery.test_recurring question-one --verify-only
```

**Supported scrapers**: `question-one`, `inquizition`, `speed-quizzing`, `pubquiz`, `quizmeisters`, `geeks-who-drink`

**What it does**:
1. Ages selected events to expired state (dates in past, last_seen_at > 7 days ago)
2. Optionally triggers scraper automatically or provides instructions
3. Verifies that RecurringEventUpdater regenerated future dates from patterns
4. Reports success/failure with detailed event-by-event analysis

**Use cases**:
- Testing RecurringEventUpdater integration after code changes
- Verifying scraper correctly handles expired pattern-based events
- Debugging date regeneration issues for specific events

### Quality Assessment & Analysis

Eventasaurus provides command-line tools for assessing data quality and analyzing category patterns across event sources. These tools are designed for programmatic access (ideal for Claude Code and other AI agents) with both human-readable and JSON output formats.

#### Quality Check (`mix quality.check`)

Evaluate data quality across 9 dimensions for event sources:

**Quality Dimensions**:
1. **Venue Completeness** (16%) - Events with valid venue information
2. **Image Completeness** (15%) - Events with images
3. **Category Completeness** (15%) - Events with at least one category
4. **Category Specificity** (15%) - Category diversity and appropriateness
5. **Occurrence Richness** (13%) - Events with detailed occurrence/scheduling data
6. **Price Completeness** (10%) - Events with pricing information
7. **Description Quality** (8%) - Events with descriptions
8. **Performer Completeness** (6%) - Events with performer/artist information
9. **Translation Completeness** (2%) - Multi-language support (if applicable)

**Usage**:

```bash
# Check quality for a specific source (formatted output)
mix quality.check sortiraparis

# List all sources with quality scores
mix quality.check --all

# Get machine-readable JSON output
mix quality.check sortiraparis --json
mix quality.check --all --json
```

**Example Output**:
```text
Quality Report: sortiraparis
============================================================
Overall Score: 84% 😊 Good

Dimensions:
  Venue:          100% ✅
  Image:          100% ✅
  Category:       100% ✅
  Specificity:     91% ✅
  Price:          100% ✅
  Description:     92% ✅
  Performer:        0% 🔴
  Occurrence:      52% 🔴
  Translation:     25% 🔴

Issues Found:
  • Low performer completeness (0%) - Consider adding performer extraction
  • Moderate occurrence richness (52%) - Many events lack detailed scheduling
  • Low translation completeness (25%) - Multi-language support incomplete

Total Events: 343
```

**Quality Score Interpretation**:
- **90-100%**: Excellent ✅ - Production-ready data quality
- **75-89%**: Good 😊 - Minor improvements needed
- **60-74%**: Fair ⚠️ - Significant gaps to address
- **Below 60%**: Poor 🔴 - Major quality issues

#### Category Analysis (`mix category.analyze`)

Analyze events categorized as "Other" to identify patterns and suggest category mapping improvements:

**Analysis Includes**:
- **URL Patterns**: Common path segments in event source URLs
- **Title Keywords**: Frequently appearing words in event titles
- **Venue Types**: Distribution of venue types for uncategorized events
- **AI Suggestions**: Category mapping recommendations with confidence levels
- **YAML Snippets**: Ready-to-use configuration for category mappings

**Usage**:

```bash
# Analyze a specific source (formatted output)
mix category.analyze sortiraparis

# Get machine-readable JSON output with full pattern data
mix category.analyze sortiraparis --json
```

**Example Output**:
```text
Category Analysis: sortiraparis
============================================================

Summary Statistics:
  Total Events:    343
  'Other' Events:  32
  Percentage:      9.3% ✓ Good (Target: <10%)

💡 Suggested Category Mappings:

  Festivals
    Confidence: Low
    Would categorize: 2 events
    Keywords: festival

  Film
    Confidence: Low
    Would categorize: 2 events
    Keywords: film

🔗 Top URL Patterns:
  /what-to-visit-in-paris/ - 30 events (93.8%)
  /hotels-unusual-accommodation/ - 12 events (37.5%)

🏷️  Top Title Keywords:
  paris - 28 events (87.5%)
  hotel - 12 events (37.5%)
  unusual - 11 events (34.4%)

Next Steps:
  1. Review patterns and suggestions above
  2. Update priv/category_mappings/sortiraparis.yml
  3. Run: mix eventasaurus.recategorize_events --source sortiraparis
  4. Re-run this analysis to verify improvements
```

**Categorization Quality Standards**:
- **<10%**: Excellent - Most events are properly categorized
- **10-20%**: Good - Minor categorization gaps
- **20-30%**: Needs improvement - Significant uncategorized events
- **>30%**: Poor - Major categorization issues

**JSON Output**: The `--json` flag provides complete structured data including:
- Full pattern analysis with sample events
- AI-generated suggestions with confidence scores
- Ready-to-use YAML snippets for category mappings
- Categorization status and recommendations

**Integration with Category Mappings**:
The analysis output directly informs updates to category mapping files in `priv/category_mappings/{source}.yml`. Review the suggested patterns and keywords, then update the mapping configuration accordingly.

#### Scraper Audit Tools

Eventasaurus includes CLI tools for auditing scraper health and detecting data issues:

- **`mix audit.scheduler_health`** — Verify scrapers are running on schedule
- **`mix audit.date_coverage`** — Check date coverage for upcoming showtimes
- **`mix monitor.collisions`** — Detect TMDB matching collisions
- **`mix fix_cinema_city_duplicates`** — Repair duplicate film ID data

See **[Scraper Monitoring Guide](docs/scraper-monitoring-guide.md#cli-audit--maintenance-tools)** for complete usage examples, production deployment instructions, and all available options.

### Adding a New Scraper

1. **Read the specification**: Start with `docs/scrapers/SCRAPER_SPECIFICATION.md`
2. **Copy reference implementation**: Use `sources/resident_advisor/` as template
3. **Follow the structure**: All scrapers live in `lib/eventasaurus_discovery/sources/{name}/`
4. **Test thoroughly**: Must handle daily runs without creating duplicates
5. **Document**: Create README with setup and configuration

**Required Files**:
- `source.ex` - Configuration and metadata
- `config.ex` - Runtime settings
- `transformer.ex` - Data transformation to unified format
- `jobs/sync_job.ex` - Main synchronization job
- `README.md` - Setup and usage documentation

See [Quick Reference](docs/scrapers/SCRAPER_QUICK_REFERENCE.md) for code examples and patterns.

### Key Features

- **Automatic Deduplication**: Venues matched by GPS coordinates (50m/200m radius), events by external_id
- **Multi-Provider Geocoding**: Automatic address geocoding with 6 free providers and intelligent fallback (see [Geocoding System](docs/geocoding/GEOCODING_SYSTEM.md))
- **Priority System**: Higher-priority sources win deduplication conflicts
- **Daily Operation**: All scrapers designed to run daily without duplicates
- **Unified Format**: All sources transform data into standard format for processing

### Geocoding System

Eventasaurus includes a sophisticated multi-provider geocoding system that automatically converts venue addresses to GPS coordinates:

- **6 Free Providers**: Mapbox, HERE, Geoapify, LocationIQ, OpenStreetMap, Photon
- **Automatic Fallback**: Tries providers in priority order until one succeeds
- **Built-in Rate Limiting**: Respects provider quotas to stay within free tiers
- **Admin Dashboard**: Configure provider priority and monitor performance at `/admin/geocoding`
- **Cost-Effective**: Google Maps/Places APIs are disabled by default (only free providers used)

**Documentation**: See [docs/geocoding/GEOCODING_SYSTEM.md](docs/geocoding/GEOCODING_SYSTEM.md) for complete documentation, including:
- How to use geocoding in scrapers
- Provider details and rate limits
- Error handling strategies
- Cost management and monitoring
- Adding new providers

### Unsplash City Images

Eventasaurus integrates with Unsplash to automatically fetch and cache high-quality city images for visual enhancement:

- **Automatic Caching**: Fetches 10 landscape-oriented images per active city (discovery_enabled = true)
- **Daily Rotation**: Images rotate daily based on day of year for variety
- **Popularity-Based**: Images sorted by popularity (likes) from Unsplash
- **Batch Queries**: Optimized batch fetching to prevent N+1 query issues
- **Automatic Refresh**: Daily refresh worker runs at 3 AM UTC via Oban
- **Proper Attribution**: All images include photographer credits and UTM parameters

#### Setup

1. **Get an Unsplash API Access Key**:
   - Visit [Unsplash Developers](https://unsplash.com/oauth/applications)
   - Create a new application
   - Copy your Access Key

2. **Add to environment variables**:
   ```bash
   export UNSPLASH_ACCESS_KEY=your_access_key_here
   ```

3. **Test the integration**:
   ```bash
   # Test fetching for a specific city
   mix unsplash.test London

   # Test fetching for all active cities
   mix unsplash.test
   ```

#### Usage in Code

```elixir
# Get today's image for a city
{:ok, image} = UnsplashService.get_city_image("London")
# Returns: %{url: "...", thumb_url: "...", color: "#...", attribution: %{...}}

# Get images for multiple cities (batch, no N+1)
images = UnsplashService.get_city_images_batch(["London", "Paris", "Kraków"])
# Returns: %{"London" => %{url: "...", ...}, "Paris" => %{...}, ...}

# Manually refresh a city's images
{:ok, gallery} = UnsplashService.refresh_city_images("London")

# Get all cities with cached galleries
cities = UnsplashService.cities_with_galleries()
```

#### Rate Limits

- **Demo**: 50 requests/hour
- **Production**: 5,000 requests/hour
- The automatic refresh worker handles rate limiting gracefully with retry logic

#### Attribution Requirements

All Unsplash images must display:
- Photographer name and link
- Link to the Unsplash photo page
- UTM parameters: `utm_source=eventasaurus&utm_medium=referral`

The service automatically includes proper attribution data in all returned images.

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

---

## Project Structure

```
eventasaurus/
├── assets/              # JavaScript, CSS, and static assets
├── config/              # Configuration files
├── docs/
│   └── scrapers/        # ⭐ Scraper documentation (READ FIRST!)
├── lib/
│   ├── eventasaurus/    # Business logic
│   │   ├── accounts/    # User management
│   │   ├── events/      # Event, polls, activities
│   │   ├── groups/      # Group management
│   │   └── venues/      # Venue management
│   ├── eventasaurus_discovery/  # Event discovery system
│   │   ├── sources/     # Event scrapers and APIs
│   │   ├── scraping/    # Shared scraping infrastructure
│   │   ├── locations/   # Cities, countries, geocoding
│   │   └── performers/  # Artist/performer management
│   ├── eventasaurus_web/ # Web layer
│   │   ├── components/  # Reusable LiveView components
│   │   ├── live/        # LiveView modules
│   │   └── controllers/ # Traditional controllers
│   └── mix/
│       └── tasks/       # Custom mix tasks (seed.dev, discovery.sync, etc.)
├── priv/
│   ├── repo/
│   │   ├── migrations/  # Database migrations
│   │   ├── seeds.exs    # Production seeds
│   │   └── dev_seeds/   # Development seed modules
│   └── static/          # Static files
├── test/                # Test files
│   └── support/
│       └── factory.ex   # Test factories (ExMachina)
└── .formatter.exs       # Code formatter config
```

## Key Concepts

### Event Lifecycle
Events progress through various states:
1. **Draft**: Initial creation, editing details
2. **Polling**: Collecting availability and preferences
3. **Threshold**: Waiting for minimum participants
4. **Confirmed**: Event is happening
5. **Canceled**: Event was canceled

### Polling System
- **Date Polls**: Find the best date for an event
- **Activity Polls**: Vote on movies, restaurants, activities
- **Generic Polls**: Custom decision-making
- Supports multiple voting systems (single choice, multiple choice, ranked)

### Soft Delete
Most entities support soft delete, allowing data recovery:
- Events, polls, users, and groups can be soft-deleted
- Deleted items are excluded from queries by default
- Can be restored through the admin interface

### CDN Caching & Authentication (Islands Architecture)

This application uses Cloudflare CDN caching with an "islands architecture" pattern. Public pages are cached and served from the CDN for performance, while authenticated features hydrate client-side via LiveView.

#### The Challenge

When Cloudflare caches a page, it strips `Set-Cookie` headers from responses. This means the Phoenix session cookie may not be set for users who first visit a cached page. However, Clerk's `__session` cookie (set client-side by Clerk's JavaScript) survives CDN caching.

#### The Solution: LiveSocket connect_params

We pass client-side data to LiveView via `connect_params` during WebSocket connection:

**Client-side** (`assets/js/app.js`):
```javascript
function getCookie(name) {
  const value = `; ${document.cookie}`;
  const parts = value.split(`; ${name}=`);
  if (parts.length === 2) return parts.pop().split(';').shift();
  return null;
}

function getClerkToken() {
  if (window.currentUser) return null; // Server already knows us
  return getCookie('__session') || null;
}

let liveSocket = new LiveSocket("/live", Socket, {
  params: () => ({
    _csrf_token: csrfToken,
    clerk_token: getClerkToken(),
    // Add more client data here as needed
  }),
  // ...
});
```

**Server-side** (`lib/eventasaurus_web/live/auth_hooks.ex`):
```elixir
# connect_params only available when socket is connected
defp get_user_from_connect_params(socket) do
  if connected?(socket) do
    case get_connect_params(socket) do
      %{"clerk_token" => token} when is_binary(token) and token != "" ->
        verify_and_get_user(token)
      _ -> nil
    end
  else
    nil
  end
end
```

#### When to Use This Pattern

Use `connect_params` for any data where:
1. **Client has it** - Available in cookies, localStorage, or browser APIs
2. **Server needs it** - Required for rendering or business logic
3. **CDN caching blocks normal flow** - Session cookies stripped by CDN

#### Key Files

- `assets/js/app.js` - Client-side params function
- `lib/eventasaurus_web/live/auth_hooks.ex` - Server-side JWT verification
- `lib/eventasaurus_app/auth/clerk/jwt.ex` - Clerk JWT verification
- `lib/eventasaurus_app/auth/clerk/sync.ex` - User sync from Clerk claims

## SEO & Social Cards

Eventasaurus includes a comprehensive SEO and social media optimization system designed to maximize visibility and shareability.

### Features

- **JSON-LD Structured Data**: Schema.org-compliant structured data for rich search results
  - Event schemas for Google event listings
  - City schemas for location-based discovery
  - LocalBusiness schemas for venue pages
  - Breadcrumb schemas for site structure

- **Dynamic Social Cards**: Auto-generated Open Graph images for social media
  - Custom cards for events, polls, and cities
  - Hash-based cache busting (updates automatically when content changes)
  - 1200x630px optimized for Facebook, Twitter, LinkedIn
  - SVG-to-PNG conversion for dynamic content

- **Meta Tag Standardization**: Consistent SEO metadata across all pages
  - Open Graph tags for social sharing
  - Twitter Card tags for Twitter previews
  - Canonical URLs for SEO
  - Optimized page titles and descriptions

### Quick Start

Adding SEO to a new page:

```elixir
defmodule EventasaurusWeb.MyPageLive do
  use EventasaurusWeb, :live_view

  alias EventasaurusWeb.Helpers.SEOHelpers

  def mount(_params, _session, socket) do
    entity = load_my_entity()

    # Capture request URI for correct URL generation (ngrok support)
    raw_uri = get_connect_info(socket, :uri)
    request_uri =
      cond do
        match?(%URI{}, raw_uri) -> raw_uri
        is_binary(raw_uri) -> URI.parse(raw_uri)
        true -> nil
      end

    socket =
      socket
      |> assign(:entity, entity)
      |> SEOHelpers.assign_meta_tags(
        title: "My Page Title",
        description: "My page description for SEO",
        image: social_card_url,
        type: "website",
        canonical_path: "/my-page",
        request_uri: request_uri
      )

    {:ok, socket}
  end
end
```

### Social Card Types

**Event Cards** - Show event title, date, venue, and theme:
```elixir
# URL: /:slug/social-card-:hash.png
social_card_url = SEOHelpers.build_social_card_url(event, :event)
```

**Poll Cards** - Display poll questions and options:
```elixir
# URL: /:slug/polls/:number/social-card-:hash.png
social_card_url = SEOHelpers.build_social_card_url(poll, :poll, event: event)
```

**City Cards** - Feature city stats and event count:
```elixir
# URL: /social-cards/city/:slug/:hash.png
social_card_url = SEOHelpers.build_social_card_url(city, :city, stats: stats)
```

### Documentation

For comprehensive SEO implementation guides, see:

📖 **[SEO Best Practices Guide](docs/seo_best_practices.md)** - Complete guide covering:
- JSON-LD structured data implementation
- Social media card generation
- Meta tag best practices
- Testing and validation procedures
- Troubleshooting common issues

📋 **[ADR 001: Meta Tag Pattern](docs/adr/001-meta-tag-pattern-standardization.md)** - Architectural decision for meta tag standardization

### Helper Modules

- **`SEOHelpers`** - Standardized SEO metadata assignment for LiveViews
- **`SocialCardHelpers`** - Shared logic for social card controllers
- **`HashGenerator`** - Content-based hashing for cache busting
- **`UrlHelper`** - Centralized URL generation

### Testing SEO Implementation

Validate your pages with these tools:
- **Google Rich Results Test**: https://search.google.com/test/rich-results
- **Facebook Sharing Debugger**: https://developers.facebook.com/tools/debug/
- **Twitter Card Validator**: https://cards-dev.twitter.com/validator
- **LinkedIn Post Inspector**: https://www.linkedin.com/post-inspector/

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`mix test`)
5. Format your code (`mix format`)
6. Commit your changes (`git commit -m 'Add some amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

## Troubleshooting

### Common Issues

**Database connection errors:**
- Ensure PostgreSQL/Supabase is running
- Check DATABASE_URL in your environment

**Asset compilation errors:**
- Run `cd assets && npm install`
- Clear build cache: `rm -rf _build deps`

**Seeding errors:**
- Ensure database is migrated: `mix ecto.migrate`
- Check for unique constraint violations
- Try cleaning first: `mix seed.clean`

## License

This project is proprietary software. All rights reserved.

## Support

For issues and questions, please open an issue on GitHub or contact the maintainers.

---

Built with ❤️ using Elixir and Phoenix LiveView