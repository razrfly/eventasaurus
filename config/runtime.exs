import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

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
# Must be in runtime.exs to conditionally select repo based on environment
# Production uses SessionRepo for long-running jobs (session pooler, advisory locks)
# Development/test use regular Repo (same database, simpler)
oban_repo =
  if config_env() == :prod do
    EventasaurusApp.SessionRepo
  else
    EventasaurusApp.Repo
  end

config :eventasaurus, Oban,
  repo: oban_repo,
  stage_interval: 1_000,
  queues: [
    # ====================================================================
    # QUEUE CONCURRENCY - CRITICAL: Must stay within connection pool limits!
    # ====================================================================
    # SessionRepo pool: 5 connections (for Oban - advisory locks, job fetching)
    # Repo pool: 3 connections (for web requests)
    #
    # Total concurrent workers: 15 (down from 42)
    # Rule: Total workers should be ~3x pool size to allow some queuing
    # without causing 15+ second connection timeouts
    # ====================================================================

    # Email queue with limited concurrency for Resend API rate limiting
    # Max 2 concurrent jobs to respect Resend's 2/second limit
    emails: 2,
    # Scraper queue for event data ingestion
    # Reduced from 5 to 1 - scraper jobs spawn many detail jobs
    scraper: 1,
    # Scraper detail queue for individual event processing
    # Reduced from 10 to 3 - these are the main DB-heavy jobs
    scraper_detail: 3,
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
    # Image cache queue for downloading external images to R2
    # Moderate concurrency to avoid hammering external servers
    image_cache: 3
  ],
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
       # Trivia export materialized view refresh daily at 5 AM UTC
       # Refreshes pre-computed trivia events data for QuizAdvisor API
       # See: lib/eventasaurus_app/workers/trivia_export_refresh_worker.ex
       {"0 5 * * *", EventasaurusApp.Workers.TriviaExportRefreshWorker}
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

# Configure per-source HTTP strategies for the Http.Client fallback chain
# Each source can specify an ordered list of adapters to try:
#   - :direct - Plain HTTPoison (fast, no cost, may be blocked)
#   - :zyte - Zyte browser rendering proxy (bypasses blocking, has cost)
#
# Strategies:
#   - Single adapter: [:direct] or [:zyte] - Use only that adapter
#   - Fallback chain: [:direct, :zyte] - Try direct first, fallback to Zyte if blocked
#
# Http.Client will detect blocking (Cloudflare, CAPTCHA, rate limits) and
# automatically try the next adapter in the chain.
config :eventasaurus, :http_strategies, %{
  # Default strategy: try direct first, fallback to Zyte if blocked
  default: [:direct, :zyte],
  # Bandsintown: always use Zyte (known Cloudflare blocking)
  bandsintown: [:zyte],
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
  kupbilecik: [:zyte]
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
    "https://eventasaur.us"
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

# ImageKit CDN configuration (for venue images)
# Enabled by default in production, disabled by default in dev/test
# Can be overridden with IMAGEKIT_CDN_ENABLED environment variable
default_imagekit_enabled = if config_env() == :prod, do: "true", else: "false"

# Upload enabled separately from CDN display (saves API credits in dev)
# Set ENABLE_IMAGEKIT_UPLOAD=true in development to test uploads
default_upload_enabled = if config_env() == :prod, do: "true", else: "false"

# Use separate folders for dev vs production (never pollute production folder from dev)
default_imagekit_folder = if config_env() == :prod, do: "/venues", else: "/venues_test"
raw_imagekit_folder = System.get_env("IMAGEKIT_FOLDER", default_imagekit_folder) |> String.trim()

sanitized_imagekit_folder =
  raw_imagekit_folder
  |> (fn f -> if String.starts_with?(f, "/"), do: f, else: "/" <> f end).()
  |> String.trim_trailing("/")

config :eventasaurus, :imagekit,
  enabled: System.get_env("IMAGEKIT_CDN_ENABLED", default_imagekit_enabled) == "true",
  upload_enabled: System.get_env("ENABLE_IMAGEKIT_UPLOAD", default_upload_enabled) == "true",
  id: System.get_env("IMAGEKIT_ID", "wombie"),
  endpoint: System.get_env("IMAGEKIT_END_POINT", "https://ik.imagekit.io/wombie"),
  folder: sanitized_imagekit_folder

# Sanity CMS configuration for changelog
# Used by Eventasaurus.Sanity.Client to fetch changelog entries
config :eventasaurus, :sanity,
  project_id: System.get_env("SANITY_PROJECT_ID"),
  api_token: System.get_env("SANITY_API_TOKEN"),
  dataset: System.get_env("SANITY_DATASET", "production")

# Venue image enrichment configuration
# Limit images processed in development to save API credits (Google Places + ImageKit)
default_max_images = if config_env() == :prod, do: 10, else: 2

max_images_env = System.get_env("MAX_IMAGES_PER_PROVIDER")

safe_max_images =
  case max_images_env do
    nil ->
      default_max_images

    "" ->
      default_max_images

    v ->
      case Integer.parse(v) do
        {int, _} when int >= 0 ->
          int

        _ ->
          require Logger

          Logger.error(
            "Invalid MAX_IMAGES_PER_PROVIDER value: #{inspect(v)}, using default: #{default_max_images}"
          )

          default_max_images
      end
  end

cooldown_env = System.get_env("NO_IMAGES_COOLDOWN_DAYS")

safe_cooldown_days =
  case cooldown_env do
    nil ->
      7

    "" ->
      7

    v ->
      case Integer.parse(v) do
        {int, _} when int >= 0 ->
          int

        _ ->
          require Logger
          Logger.error("Invalid NO_IMAGES_COOLDOWN_DAYS value: #{inspect(v)}, using default: 7")
          7
      end
  end

# Max images per venue (controls ImageKit storage costs)
# Default: 25 images per venue (after per-provider limits applied)
default_max_per_venue = if config_env() == :prod, do: 25, else: 10

max_per_venue_env = System.get_env("MAX_IMAGES_PER_VENUE")

safe_max_per_venue =
  case max_per_venue_env do
    nil ->
      default_max_per_venue

    "" ->
      default_max_per_venue

    v ->
      case Integer.parse(v) do
        {int, _} when int >= 0 ->
          int

        _ ->
          require Logger

          Logger.error(
            "Invalid MAX_IMAGES_PER_VENUE value: #{inspect(v)}, using default: #{default_max_per_venue}"
          )

          default_max_per_venue
      end
  end

config :eventasaurus, :venue_images,
  max_images_per_provider: safe_max_images,
  max_images_per_venue: safe_max_per_venue,
  no_images_cooldown_days: safe_cooldown_days

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
  # Validate required PlanetScale environment variables
  for var <-
        ~w(PLANETSCALE_DATABASE_HOST PLANETSCALE_DATABASE PLANETSCALE_DATABASE_USERNAME PLANETSCALE_DATABASE_PASSWORD) do
    System.fetch_env!(var)
  end

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
      "https://eventasaur.us",
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

  # Configure the database for production (PlanetScale)
  # Using hostname-based config (not URL-based) to ensure socket_options and ssl_opts
  # are properly applied. URL-based config may not merge these options correctly.
  # This matches the proven working configuration from cinegraph project.
  ps_host = System.get_env("PLANETSCALE_DATABASE_HOST")
  ps_db = System.get_env("PLANETSCALE_DATABASE")
  ps_user = System.get_env("PLANETSCALE_DATABASE_USERNAME")
  ps_pass = System.get_env("PLANETSCALE_DATABASE_PASSWORD")

  ps_direct_port =
    case Integer.parse(System.get_env("PLANETSCALE_DATABASE_PORT", "5432")) do
      {port, _} when port > 0 and port <= 65535 ->
        port

      _ ->
        require Logger
        Logger.error("Invalid PLANETSCALE_DATABASE_PORT, using default: 5432")
        5432
    end

  ps_pooler_port =
    case Integer.parse(System.get_env("PLANETSCALE_PG_BOUNCER_PORT", "6432")) do
      {port, _} when port > 0 and port <= 65535 ->
        port

      _ ->
        require Logger
        Logger.error("Invalid PLANETSCALE_PG_BOUNCER_PORT, using default: 6432")
        6432
    end

  # Force IPv4 unless IPv6 is explicitly enabled
  # PlanetScale requires IPv4 for reliable connectivity from Fly.io
  # This MUST be applied via hostname-based config, not URL-based
  socket_opts = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: [:inet]

  # PlanetScale SSL: Standard SSL verification using CAStore
  # (proven working configuration from cinegraph project)
  planetscale_ssl_opts = [
    verify: :verify_peer,
    cacertfile: CAStore.file_path(),
    server_name_indication: String.to_charlist(ps_host),
    customize_hostname_check: [
      match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
    ]
  ]

  # Repo: Pooled connection via PgBouncer (port 6432) for web requests
  # Using hostname-based config to guarantee socket_options: [:inet] is applied
  #
  # Pool size: 3 connections for web request handling
  # PgBouncer provides additional pooling on the database side.
  #
  # Total connections per machine: Repo(3) + SessionRepo(5) + ReplicaRepo(5) = 13
  # PlanetScale connection limits should accommodate this comfortably.
  config :eventasaurus, EventasaurusApp.Repo,
    username: ps_user,
    password: ps_pass,
    hostname: ps_host,
    port: ps_pooler_port,
    database: ps_db,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "3"),
    socket_options: socket_opts,
    queue_target: 5000,
    queue_interval: 30000,
    connect_timeout: 30_000,
    handshake_timeout: 30_000,
    ssl: true,
    ssl_opts: planetscale_ssl_opts,
    # Disable prepared statements for PgBouncer compatibility
    prepare: :unnamed

  # SessionRepo: Direct connection (port 5432) for Oban, migrations, advisory locks
  # Using hostname-based config to guarantee socket_options: [:inet] is applied
  #
  # Pool size increased from 2 to 5 to support Oban job processing.
  # With 15 total Oban workers (reduced from 42), 5 connections provides
  # reasonable throughput without overwhelming PlanetScale connection limits.
  #
  # Connection math:
  # - Oban needs 1-2 connections for producer/notifier (advisory locks)
  # - Remaining 3-4 connections for actual job processing
  # - Total workers (15) / pool (5) = 3x ratio allows some queuing
  config :eventasaurus, EventasaurusApp.SessionRepo,
    username: ps_user,
    password: ps_pass,
    hostname: ps_host,
    port: ps_direct_port,
    database: ps_db,
    pool_size: String.to_integer(System.get_env("SESSION_POOL_SIZE") || "5"),
    socket_options: socket_opts,
    queue_target: 5000,
    queue_interval: 30000,
    connect_timeout: 30_000,
    handshake_timeout: 30_000,
    ssl: true,
    ssl_opts: planetscale_ssl_opts

  # ReplicaRepo: Direct connection to read replicas (port 5432)
  # PlanetScale routes to replicas when username has |replica suffix
  # PgBouncer does NOT support replica routing, so direct connection is required
  #
  # Use for:
  # - Admin dashboards and analytics
  # - DiscoveryStatsCache background refresh
  # - Heavy read queries where eventual consistency is acceptable
  #
  # DO NOT use for:
  # - Reads immediately after writes (replication lag)
  # - Authentication or session queries
  # - Any write operations (will be rejected by Ecto read_only: true)
  #
  # Kill switch: Set USE_REPLICA=false to route all reads to primary
  # See: https://planetscale.com/docs/postgres/scaling/replicas
  ps_replica_user = "#{ps_user}|replica"

  config :eventasaurus, EventasaurusApp.ReplicaRepo,
    username: ps_replica_user,
    password: ps_pass,
    hostname: ps_host,
    port: ps_direct_port,
    database: ps_db,
    pool_size: String.to_integer(System.get_env("REPLICA_POOL_SIZE") || "5"),
    socket_options: socket_opts,
    queue_target: 5000,
    queue_interval: 30000,
    connect_timeout: 30_000,
    handshake_timeout: 30_000,
    ssl: true,
    ssl_opts: planetscale_ssl_opts

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
