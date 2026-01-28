import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# Configure Erlang's inet resolver to use Fly's internal DNS server
# This is required for Fly Managed Postgres .flympg.net domains
# Erlang's built-in inet_res resolver doesn't read /etc/resolv.conf by default
# and fails with nxdomain on Fly.io's internal DNS
if config_env() == :prod do
  # Fly's internal DNS server at fdaa::3 can resolve .flympg.net domains
  # Parse the IPv6 address into a tuple for :inet_db
  fly_dns_server = {0xFDAA, 0, 0, 0, 0, 0, 0, 3}

  # Configure Erlang's inet to use Fly's DNS server
  # This affects all DNS resolution including Postgrex hostname lookups
  :inet_db.set_lookup([:dns, :file, :native])
  :inet_db.add_ns(fly_dns_server)
end

# Load .env file in development/test environments
# This must happen BEFORE any System.get_env calls
if config_env() in [:dev, :test] do
  env_file = Path.expand("../.env", __DIR__)

  if File.exists?(env_file) do
    env_file
    |> File.read!()
    |> String.split("\n")
    |> Enum.each(fn line ->
      line = String.trim(line)

      # Skip empty lines and comments
      if line != "" and not String.starts_with?(line, "#") do
        case String.split(line, "=", parts: 2) do
          [key, value] ->
            key = String.trim(key)
            # Remove surrounding quotes if present
            value =
              value
              |> String.trim()
              |> String.trim_leading("\"")
              |> String.trim_trailing("\"")

            System.put_env(key, value)

          _ ->
            :ok
        end
      end
    end)
  end
end

# Configure the current environment for runtime access
# This replaces Mix.env() which is only available at compile time
config :eventasaurus, :environment, config_env()

# Configure Oban for background job processing
#
# ARCHITECTURE (Issue #3160):
# - Oban uses DEDICATED ObanRepo (PgBouncer) with isolated connection pool
# - Oban uses Notifiers.PG (Distributed Erlang) for pub/sub notifications
# - This eliminates the need for direct connections (LISTEN/NOTIFY doesn't work with PgBouncer)
# - SessionRepo is now only used for migrations and advisory locks
#
# Previous (Issue #3119): Oban shared Repo with web requests → connection pool exhaustion
# Now: ObanRepo has dedicated pool, preventing job stampedes from blocking web traffic
#
# IMPORTANT (Issue #3360): Oban framework MUST use ObanRepo (PgBouncer), not JobRepo (Direct).
# Oban's internal operations (polling, state updates) are fast queries that work with PgBouncer.
# Only job BUSINESS LOGIC uses JobRepo for long-running queries that need direct connections.
oban_repo = EventasaurusApp.ObanRepo

# Base queues that run in all environments
base_queues = [
  # ====================================================================
  # QUEUE CONCURRENCY - Fly Managed Postgres capacity (Issue #3371)
  # ====================================================================
  # Fly MPG: 100 max connections, typically using ~65
  # - Repo pool: 10 connections (web requests via PgBouncer)
  # - ObanRepo pool: 5 connections (Oban framework via PgBouncer)
  # - JobRepo pool: 20 connections (job business logic, direct)
  # - SessionRepo pool: 1 connection (migrations, direct)
  #
  # Total concurrent workers: ~22
  # Headroom: ~35 unused connections available
  # ====================================================================

  # Email queue with limited concurrency for Resend API rate limiting
  # Max 2 concurrent jobs to respect Resend's 2/second limit
  emails: 2,
  # Scraper queue for event data ingestion
  # Increased from 1 to 3 for Fly MPG capacity (Issue #3371)
  # Note: scraper jobs spawn detail jobs, but we have connection headroom
  scraper: 3,
  # Scraper detail queue for individual event processing
  # REDUCED from 5 to 1 to prevent connection pool exhaustion (Issue #3383)
  # RestaurantDetailJob processes 15 dates × 9 slots = 135 DB transactions per job
  # Multiple concurrent jobs were exhausting the connection pool
  scraper_detail: 1,
  # Scraper index queue for processing index pages
  # Reduced from 2 to 1 - index pages spawn many detail jobs
  scraper_index: 1,
  # Discovery queue for unified sync jobs and admin-triggered syncs
  # Reduced from 3 to 1 - discovery jobs are orchestrators
  discovery: 1,
  # Unified venue queue for all venue-related jobs
  # Kept at 1 to respect Google rate limits
  venue: 1,
  # Default queue for other background jobs
  # Reduced from 10 to 2
  default: 2,
  # Maintenance queue for background tasks like coordinate calculation
  # Reduced from 2 to 1
  maintenance: 1,
  # Reports queue for analytics, cost reports, and stats computation
  # Reduced from 2 to 1 - stats computation is memory-intensive
  reports: 1,
  # Enrichment queue for performer data and Unsplash image refreshes
  # Reduced from 3 to 1 - rate limited by external APIs anyway
  enrichment: 1,
  # Geocoding backfill queue for venue provider ID lookups
  # Kept at 1 due to Foursquare 500 req/day limit
  geocoding: 1,
  # Analytics queue for PostHog popularity sync
  # Kept at 1 - single daily job that batches updates
  analytics: 1,
  # Timezone queue for city timezone population (Issue #3334)
  # Concurrency 1 - TzWorld ETS backend needs time to warm up
  # Jobs have 5-minute timeout to allow full initialization
  timezone: 1,
  # Cache refresh queue for city page event aggregation (Issue #3347)
  # Runs expensive list_events_with_aggregation_and_counts queries in background
  # to avoid OOM kills during user requests. Concurrency 2 to allow parallel
  # refreshes for different cities without overwhelming memory.
  cache_refresh: 2
]

# Production-only queues (image caching uploads to R2 - must not run in dev)
production_queues =
  if config_env() == :prod do
    [
      # Image cache queue for downloading external images to R2
      # PRODUCTION ONLY: Dev uses original URLs directly, no R2 uploads
      # Moderate concurrency to avoid hammering external servers
      image_cache: 3
    ]
  else
    []
  end

oban_queues = base_queues ++ production_queues

config :eventasaurus, Oban,
  repo: oban_repo,
  # Use Distributed Erlang for notifications instead of PostgreSQL LISTEN/NOTIFY
  # This allows Oban to work with PgBouncer (transaction pooling) which doesn't support LISTEN/NOTIFY
  # Requires Distributed Erlang clustering (Fly.io provides this via dns_cluster)
  # See: https://hexdocs.pm/oban/Oban.Notifiers.PG.html
  notifier: Oban.Notifiers.PG,
  # Enable leader election so only one machine runs plugins (Cron, Reindexer, etc.)
  # Without this, all machines compete for advisory locks and run duplicate work.
  # See: https://hexdocs.pm/oban/Oban.Peers.Postgres.html
  #
  # Issue #3140: Switched from Peers.Postgres to Peers.Global
  # Peers.Postgres uses pg_advisory_lock which DOES NOT WORK with PgBouncer transaction pooling.
  # Advisory locks are session-scoped but PgBouncer releases connections after each transaction,
  # causing all nodes to think they're leader and retry constantly → connection exhaustion.
  # Peers.Global uses Distributed Erlang (same as Notifiers.PG) which works with PgBouncer.
  peer: Oban.Peers.Global,
  # Increased from 1_000 to 5_000 to reduce polling pressure (Issue #3140)
  # Each queue polls every stage_interval, so 13 queues × 2 machines = 26 polls/second at 1s
  # At 5s this drops to ~5 polls/second, significantly reducing connection contention
  # Tradeoff: Job pickup latency increases from max 1s to max 5s (acceptable for scrapers)
  stage_interval: 5_000,
  # Issue #3172: Give jobs 60s to complete gracefully during shutdown
  # Default was 15s, but Lifeline rescue_after is 300s - the mismatch caused state corruption
  # during deploys (jobs orphaned in weird states). 60s aligns with Fly.io kill timeout.
  shutdown_grace_period: :timer.seconds(60),
  queues: oban_queues,
  plugins: [
    # Keep completed jobs for 12 hours for debugging
    # Reduced from 2 days to lower oban_jobs table row count
    # Faster monitoring queries = less connection contention
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 12},
    # Reindex daily for performance
    {Oban.Plugins.Reindexer, schedule: "@daily"},
    # Recover orphaned jobs after 5 minutes
    # Extended from 60s to 300s to give stats computation more time before rescue
    {Oban.Plugins.Lifeline, rescue_after: 300},
    # Scheduled cron jobs
    {Oban.Plugins.Cron,
     crontab: [
       # Daily sitemap generation at 2 AM UTC
       {"0 2 * * *", Eventasaurus.Workers.SitemapWorker},
       # City discovery orchestration runs daily at midnight UTC
       {"0 0 * * *", EventasaurusDiscovery.Workers.CityDiscoveryOrchestrator},
       # City coordinate recalculation runs daily at 1 AM UTC
       {"0 1 * * *", EventasaurusDiscovery.Workers.CityCoordinateRecalculationWorker},
       # Unsplash city images refresh daily at 3 AM UTC
       {"0 3 * * *", EventasaurusApp.Workers.UnsplashRefreshWorker},
       # PostHog popularity sync daily at 4 AM UTC
       # Syncs pageview data from PostHog to public_events.view_count for popularity sorting
       {"0 4 * * *", EventasaurusDiscovery.Workers.PostHogPopularitySyncWorker},
       # Admin stats computation hourly (at minute 0)
       # This populates the discovery_stats_snapshots table for the admin dashboard
       # Reduced from every 15 min to hourly due to memory constraints on 1GB VM
       {"0 * * * *", EventasaurusDiscovery.Admin.ComputeStatsJob},
       # City events materialized view refresh hourly (at minute 15)
       # Refreshes city_events_mv used by CityEventsFallback for guaranteed cache fallback
       # See: https://github.com/anthropics/eventasaurus/issues/3373
       {"15 * * * *", EventasaurusWeb.Workers.RefreshCityEventsViewJob},
       # Trivia export materialized view refresh daily at 5 AM UTC
       # Refreshes pre-computed trivia events data for QuizAdvisor API
       # See: lib/eventasaurus_app/workers/trivia_export_refresh_worker.ex
       {"0 5 * * *", EventasaurusApp.Workers.TriviaExportRefreshWorker},
       # Job execution stats materialized view refresh hourly at minute 30
       # Pre-aggregates collision dashboard statistics for fast queries
       # Hourly is sufficient since dashboard caches results and data isn't time-sensitive
       # See: lib/eventasaurus_app/workers/job_execution_stats_refresh_worker.ex
       {"30 * * * *", EventasaurusApp.Workers.JobExecutionStatsRefreshWorker},
       # Image cache stats refresh daily at 6 AM UTC
       # Populates image_cache_stats_snapshots table for the admin image cache dashboard
       # Daily is sufficient since cached image counts don't change frequently
       {"0 6 * * *", EventasaurusApp.Images.ComputeImageCacheStatsJob},
       # TMDB Now Playing movies sync daily at 7 AM UTC
       # Pre-populates movie database with currently playing movies in Poland
       {"0 7 * * *", EventasaurusDiscovery.Jobs.SyncNowPlayingMoviesJob,
        args: %{region: "PL", pages: 10}},
       # Daily external service cost summary at 8 AM UTC
       # Generates cost reports, checks budget thresholds, triggers alerts
       # See: lib/eventasaurus_discovery/costs/workers/daily_cost_summary_worker.ex
       {"0 8 * * *", EventasaurusDiscovery.Costs.Workers.DailyCostSummaryWorker},
       # Oban job sanitizer runs every 30 minutes (Issue #3172)
       # Detects and fixes corrupted jobs: zombies, priority blockers, stuck executing
       # See: lib/eventasaurus_app/workers/oban_job_sanitizer_worker.ex
       {"*/30 * * * *", EventasaurusApp.Workers.ObanJobSanitizerWorker}
       # Note: Venue image cleanup can be triggered manually via CleanupScheduler.enqueue()
     ]}
  ]

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/eventasaurus start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :eventasaurus, EventasaurusWeb.Endpoint, server: true
end

# Configure Stripe for all environments
# This ensures the configuration is loaded after .env files are processed
config :stripity_stripe,
  api_key: System.get_env("STRIPE_SECRET_KEY"),
  connect_client_id: System.get_env("STRIPE_CONNECT_CLIENT_ID")

# Configure Zyte API for browser-rendered HTTP requests
# Used by Http.Adapters.Zyte to bypass Cloudflare and other anti-bot protections
# Optional: adapter returns {:error, :not_configured} when key is not set
config :eventasaurus, :zyte_api_key, System.get_env("ZYTE_API_KEY") || ""

# Configure Crawlbase API for browser-rendered HTTP requests
# Used by Http.Adapters.Crawlbase to bypass Cloudflare and other anti-bot protections
# Two token types available:
#   - CRAWLBASE_API_KEY: For static HTML requests (1 credit per request)
#   - CRAWLBASE_JS_API_KEY: For JavaScript-rendered requests (2 credits per request)
# Optional: adapter returns {:error, :not_configured} when required key is not set
config :eventasaurus, :crawlbase_api_key, System.get_env("CRAWLBASE_API_KEY")
config :eventasaurus, :crawlbase_js_api_key, System.get_env("CRAWLBASE_JS_API_KEY")

# Configure per-source HTTP strategies for the Http.Client fallback chain
# Each source can specify an ordered list of adapters to try:
#   - :direct - Plain HTTPoison (fast, no cost, may be blocked)
#   - :zyte - Zyte browser rendering proxy (bypasses blocking, has cost)
#   - :crawlbase - Crawlbase API proxy (alternative to Zyte, has cost)
#
# Strategies:
#   - Single adapter: [:direct] or [:zyte] or [:crawlbase] - Use only that adapter
#   - Fallback chain: [:direct, :zyte] - Try direct first, fallback to proxy if blocked
#
# Http.Client will detect blocking (Cloudflare, CAPTCHA, rate limits) and
# automatically try the next adapter in the chain.
config :eventasaurus, :http_strategies, %{
  # Default strategy: try direct first, fallback to Zyte if blocked
  default: [:direct, :zyte],
  # Bandsintown: always use Crawlbase (known Cloudflare blocking)
  bandsintown: [:crawlbase],
  # Resident Advisor: try direct first, fallback to Zyte
  resident_advisor: [:direct, :zyte],
  # Cinema City: direct only (API works fine)
  cinema_city: [:direct],
  # Repertuary: direct only
  repertuary: [:direct],
  # Karnet: try direct first, fallback to Zyte
  karnet: [:direct, :zyte],
  # Week.pl: direct only
  week_pl: [:direct],
  # Kupbilecik: always use Zyte (React SPA requiring JS rendering)
  kupbilecik: [:zyte],
  # IMDB: always use Crawlbase (JS rendering for search results)
  imdb: [:crawlbase]
}

# Configure Clerk authentication
# Clerk credentials are set in environment variables:
#   CLERK_PUBLISHABLE_KEY - Frontend key (pk_test_... or pk_live_...)
#   CLERK_SECRET_KEY - Backend key (sk_test_... or sk_live_...)
clerk_publishable_key = System.get_env("CLERK_PUBLISHABLE_KEY")
clerk_secret_key = System.get_env("CLERK_SECRET_KEY")

# Extract Clerk domain from publishable key
# Format: pk_test_<base64url-encoded-domain>$ or pk_live_<base64url-encoded-domain>$
# The trailing $ is part of the base64 encoding, decoded result ends with $
clerk_domain =
  case clerk_publishable_key do
    nil ->
      nil

    key ->
      # Extract the base64 part after pk_test_/pk_live_
      key
      |> String.replace(~r/^pk_(test|live)_/, "")
      |> Base.url_decode64(padding: false)
      |> case do
        {:ok, domain} -> String.trim_trailing(domain, "$")
        :error -> nil
      end
  end

# Clerk is the sole authentication provider (no CLERK_ENABLED toggle needed)
# Just check that keys are configured
clerk_configured =
  clerk_publishable_key != nil and
    clerk_secret_key != nil and
    clerk_domain != nil

if not clerk_configured do
  if config_env() == :prod do
    raise """
    Clerk is not configured but is required in production.
    Set CLERK_PUBLISHABLE_KEY and CLERK_SECRET_KEY environment variables.
    """
  else
    IO.warn(
      "Clerk is not configured. Set CLERK_PUBLISHABLE_KEY and CLERK_SECRET_KEY environment variables."
    )
  end
end

config :eventasaurus, :clerk,
  publishable_key: clerk_publishable_key,
  secret_key: clerk_secret_key,
  domain: clerk_domain,
  jwks_url: if(clerk_domain, do: "https://#{clerk_domain}/.well-known/jwks.json"),
  authorized_parties: [
    "http://localhost:4000",
    "https://wombie.com",
    "https://www.wombie.com",
    "https://eventasaur.us",
    "https://www.eventasaur.us"
  ],
  jwks_cache_ttl: 3_600_000

# Configure Cloudflare Turnstile for bot protection
config :eventasaurus, :turnstile,
  site_key: System.get_env("TURNSTILE_SITE_KEY"),
  secret_key: System.get_env("TURNSTILE_SECRET_KEY")

# Configure CDN with environment variable override
# Enabled by default in production, disabled by default in dev/test
# Can be overridden with CDN_ENABLED environment variable
default_cdn_enabled = if config_env() == :prod, do: "true", else: "false"

config :eventasaurus, :cdn,
  enabled: System.get_env("CDN_ENABLED", default_cdn_enabled) == "true",
  domain: System.get_env("CDN_DOMAIN", "cdn.wombie.com")

# Sanity CMS configuration for changelog
# Used by Eventasaurus.Sanity.Client to fetch changelog entries
config :eventasaurus, :sanity,
  project_id: System.get_env("SANITY_PROJECT_ID"),
  api_token: System.get_env("SANITY_API_TOKEN"),
  dataset: System.get_env("SANITY_DATASET", "production")

# NOTE: Legacy venue_images config removed in Issue #2977
# Venue images now use cached_images table with R2/Cloudflare CDN storage

# Configure Unsplash image refresh intervals
# How often to refresh city and country images (in days)
# Default: 7 days (weekly refresh keeps images fresh without wasting API quota)
# Unsplash rate limit: 5000 requests/hour
unsplash_city_refresh_days =
  case System.get_env("UNSPLASH_CITY_REFRESH_DAYS") do
    nil ->
      7

    days_str ->
      case Integer.parse(days_str) do
        {days, _} when days > 0 ->
          days

        _ ->
          require Logger
          Logger.warning("Invalid UNSPLASH_CITY_REFRESH_DAYS: #{days_str}, using default: 7")
          7
      end
  end

unsplash_country_refresh_days =
  case System.get_env("UNSPLASH_COUNTRY_REFRESH_DAYS") do
    nil ->
      7

    days_str ->
      case Integer.parse(days_str) do
        {days, _} when days > 0 ->
          days

        _ ->
          require Logger
          Logger.warning("Invalid UNSPLASH_COUNTRY_REFRESH_DAYS: #{days_str}, using default: 7")
          7
      end
  end

config :eventasaurus, :unsplash,
  city_refresh_days: unsplash_city_refresh_days,
  country_refresh_days: unsplash_country_refresh_days

# Configure Mapbox for static maps
config :eventasaurus, :mapbox, access_token: System.get_env("MAPBOX_ACCESS_TOKEN")

# Configure geocoder's Google Maps provider to use our existing API key
# We've been using Google Maps API for 6+ months - this wires up the new geocoder library
config :geocoder, Geocoder.Providers.GoogleMaps, api_key: System.get_env("GOOGLE_MAPS_API_KEY")

# Configure OpenStreetMap Nominatim provider with proper User-Agent
# OSM Usage Policy requires identifying the application making requests
# See: https://operations.osmfoundation.org/policies/nominatim/
config :geocoder, Geocoder.Providers.OpenStreetMaps,
  headers: [
    {"User-Agent",
     "Wombie/1.0 (#{System.get_env("APP_URL") || "https://wombie.com"}; #{System.get_env("CONTACT_EMAIL") || "support@wombie.com"})"}
  ]

# Configure multi-provider geocoding system
# Providers are tried in priority order until one succeeds
# Free providers first (Mapbox, HERE, OSM alternatives), paid providers last (Google)
config :eventasaurus, :geocoding,
  providers: [
    # Priority 1: Mapbox (100K/month free, high quality, global coverage)
    {EventasaurusDiscovery.Geocoding.Providers.Mapbox,
     enabled: System.get_env("MAPBOX_ENABLED", "true") == "true", priority: 1},

    # Priority 2: HERE (250K/month free, high quality, generous rate limits)
    {EventasaurusDiscovery.Geocoding.Providers.Here,
     enabled: System.get_env("HERE_ENABLED", "true") == "true", priority: 2},

    # Priority 3: Geoapify (90K/month free, good quality)
    {EventasaurusDiscovery.Geocoding.Providers.Geoapify,
     enabled: System.get_env("GEOAPIFY_ENABLED", "true") == "true", priority: 3},

    # Priority 4: LocationIQ (150K/month free, OSM-based)
    {EventasaurusDiscovery.Geocoding.Providers.LocationIQ,
     enabled: System.get_env("LOCATIONIQ_ENABLED", "true") == "true", priority: 4},

    # Priority 5: OpenStreetMap (free, 1 req/sec limit)
    {EventasaurusDiscovery.Geocoding.Providers.OpenStreetMap,
     enabled: System.get_env("OSM_ENABLED", "true") == "true", priority: 5},

    # Priority 6: Photon (unlimited free, OSM-based, community service)
    {EventasaurusDiscovery.Geocoding.Providers.Photon,
     enabled: System.get_env("PHOTON_ENABLED", "true") == "true", priority: 6},

    # Priority 97: Google Maps ($0.005/call, DISABLED by default)
    {EventasaurusDiscovery.Geocoding.Providers.GoogleMaps,
     enabled: System.get_env("GOOGLE_MAPS_ENABLED", "false") == "true", priority: 97},

    # Priority 99: Google Places ($0.034/call, DISABLED by default)
    {EventasaurusDiscovery.Geocoding.Providers.GooglePlaces,
     enabled: System.get_env("GOOGLE_PLACES_ENABLED", "false") == "true", priority: 99}
  ]

# Configure Sentry for all environments (dev/test/prod)
# Using runtime.exs ensures File.cwd() runs at startup, not compile time
case System.get_env("SENTRY_DSN") do
  nil ->
    # Explicitly disable Sentry when SENTRY_DSN is not set
    config :sentry, dsn: nil

  dsn ->
    # Configure Sentry with robust file path handling
    root_path =
      case File.cwd() do
        {:ok, cwd} -> cwd
        _ -> "."
      end

    config :sentry,
      dsn: dsn,
      environment_name: config_env(),
      enable_source_code_context: true,
      root_source_code_paths: [root_path]
end

if config_env() == :prod do
  # Validate required Fly Managed Postgres environment variables
  # DATABASE_URL: PgBouncer pooled connection for web/Oban traffic
  # DATABASE_DIRECT_URL: Direct connection for migrations (advisory locks)
  database_url = System.fetch_env!("DATABASE_URL")
  database_direct_url = System.fetch_env!("DATABASE_DIRECT_URL")

  # Validate required Cloudflare R2 credentials for file storage (uploads + sitemap)
  for var <- ~w(CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_ACCESS_KEY_ID CLOUDFLARE_SECRET_ACCESS_KEY) do
    System.fetch_env!(var)
  end

  # Validate required email service environment variables
  System.fetch_env!("RESEND_API_KEY")
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "wombie.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :eventasaurus, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :eventasaurus, EventasaurusWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    check_origin: [
      "https://wombie.com",
      "https://www.wombie.com",
      "https://eventasaur.us",
      "https://www.eventasaur.us",
      "https://eventasaurus.fly.dev"
    ],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port,
      # Increase max header length for Clerk JWT tokens in cookies
      # Default is 8KB, Clerk tokens can exceed this when combined with Phoenix session
      # 16KB is sufficient for Clerk JWTs (typically 2-4KB) with session overhead
      # Cowboy protocol_options for HTTP/1.1
      protocol_options: [
        max_header_value_length: 16_384,
        max_headers: 100
      ]
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :eventasaurus, EventasaurusWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :eventasaurus, EventasaurusWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # Configure Resend for production email sending using Resend's Swoosh adapter
  config :eventasaurus, Eventasaurus.Mailer,
    adapter: Resend.Swoosh.Adapter,
    api_key: System.get_env("RESEND_API_KEY")

  # Configure Swoosh API client
  config :swoosh, :api_client, Swoosh.ApiClient.Finch

  # Configure the database for production (Fly Managed Postgres)
  #
  # Connection Architecture:
  # - DATABASE_URL: PgBouncer pooled connection (pgbouncer.xxx.flympg.net)
  # - DATABASE_DIRECT_URL: Direct connection (direct.xxx.flympg.net)
  #
  # IMPORTANT: PgBouncer MUST be set to "Transaction" mode in Fly dashboard
  # (Ecto requires Transaction mode, not the default Session mode)
  #
  # Pool sizing for Fly MPG:
  # - Repo: 10 connections (web requests via PgBouncer)
  # - ObanRepo: 5 connections (Oban jobs via PgBouncer)
  # - SessionRepo: 1 connection (migrations only via direct)

  # Repo: Pooled connection via PgBouncer for web requests
  # PgBouncer handles connection pooling, these are client connections TO PgBouncer
  config :eventasaurus, EventasaurusApp.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    queue_target: 5000,
    queue_interval: 30000,
    # Disable prepared statements for PgBouncer Transaction mode
    prepare: :unnamed,
    # Force IPv6 for Fly.io internal network (.flympg.net resolves to IPv6)
    socket_options: [:inet6]

  # SessionRepo: Direct connection for migrations and advisory locks
  # Advisory locks (used by Ecto migrations) don't work through PgBouncer
  # in Transaction mode - they require session-scoped connections
  config :eventasaurus, EventasaurusApp.SessionRepo,
    url: database_direct_url,
    pool_size: String.to_integer(System.get_env("SESSION_POOL_SIZE") || "1"),
    queue_target: 5000,
    queue_interval: 30000,
    # Force IPv6 for Fly.io internal network
    socket_options: [:inet6]

  # JobRepo: Direct connection for ALL Oban job business logic (Issue #3353)
  # PgBouncer in transaction mode kills queries >30 seconds. Job queries can run
  # 30-90+ seconds (city aggregation, materialized views, heavy syncs).
  # This repo bypasses PgBouncer for unlimited query duration.
  #
  # Architecture:
  # - Web Requests → Repo (pool: 10) → PgBouncer → PostgreSQL
  # - Oban Jobs → JobRepo (pool: 20) → Direct → PostgreSQL
  # - Migrations → SessionRepo (pool: 1) → Direct → PostgreSQL
  config :eventasaurus, EventasaurusApp.JobRepo,
    url: database_direct_url,
    pool_size: String.to_integer(System.get_env("JOB_POOL_SIZE") || "20"),
    queue_target: 5000,
    queue_interval: 30000,
    # Force IPv6 for Fly.io internal network
    socket_options: [:inet6]

  # ObanRepo: DEPRECATED - kept for backwards compatibility during migration
  # Will be removed once all jobs use JobRepo (Issue #3353)
  # New code should use JobRepo instead
  config :eventasaurus, EventasaurusApp.ObanRepo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("OBAN_POOL_SIZE") || "5"),
    queue_target: 5000,
    queue_interval: 30000,
    # Disable prepared statements for PgBouncer Transaction mode
    prepare: :unnamed,
    # Force IPv6 for Fly.io internal network
    socket_options: [:inet6]

  # NOTE: ReplicaRepo removed (Issue #3360)
  # Fly MPG basic plan has no read replicas (HA replica is failover only).
  # Repo.replica() returns Repo anyway, so ReplicaRepo was unused.
  # If you upgrade to a plan with read replicas, add ReplicaRepo config here.

  # Configure Cloudflare R2 storage settings
  config :eventasaurus, :r2,
    account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID"),
    access_key_id: System.get_env("CLOUDFLARE_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("CLOUDFLARE_SECRET_ACCESS_KEY"),
    bucket: System.get_env("R2_BUCKET") || "wombie",
    cdn_url: System.get_env("R2_CDN_URL") || "https://cdn2.wombie.com"

  # Configure PostHog settings for production
  # PostHog provides analytics and event tracking for your application
  # To enable PostHog, set the following environment variables:
  # - POSTHOG_PUBLIC_API_KEY: Your PostHog project API key (for event tracking)
  # - POSTHOG_PRIVATE_API_KEY: Your PostHog personal API key (for analytics queries)
  # - POSTHOG_PROJECT_ID: Your PostHog project ID (for analytics queries)
  #
  # Get these from your PostHog dashboard:
  # 1. Project API Key: Project Settings > API Keys
  # 2. Personal API Key: Personal Settings > Personal API Keys
  # 3. Project ID: Project Settings > Project Variables
  config :eventasaurus, :posthog,
    api_key: System.get_env("POSTHOG_PUBLIC_API_KEY"),
    api_host: "https://eu.i.posthog.com"

  # Configure base URL for email links
  config :eventasaurus, :base_url, "https://wombie.com"

  # Event discovery scraper configuration
  # Note: Not a separate OTP app, just using config namespace for organization
  config :eventasaurus, :event_discovery,
    # Universal event freshness threshold for all scrapers (in hours)
    # Events seen within this window will NOT be re-scraped
    # Can be overridden via EVENT_FRESHNESS_THRESHOLD_HOURS env var
    freshness_threshold_hours:
      System.get_env("EVENT_FRESHNESS_THRESHOLD_HOURS", "168") |> String.to_integer(),
    # Source-specific freshness threshold overrides
    # Sources not listed here will use the default freshness_threshold_hours
    source_freshness_overrides: %{
      # Repertuary - Daily scraping due to data quality issues
      "repertuary" => 24,
      # Cinema City - Every 2 days (movie showtimes change frequently)
      "cinema-city" => 48
    }

  # Stripe configuration is now handled globally above (lines 25-27)
  # Sentry configuration is now handled globally above (lines 29-47)
end
