# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Include Supabase configuration
import_config "supabase.exs"

# Configure Eventasaurus main app to use Supabase (not Ecto)
config :eventasaurus,
  use_supabase: true,
  ecto_repos: [EventasaurusApp.Repo]

# Configure EventasaurusApp Repo with PostGIS types
config :eventasaurus, EventasaurusApp.Repo, types: EventasaurusApp.PostgresTypes

# Configures the endpoint
config :eventasaurus, EventasaurusWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [html: EventasaurusWeb.ErrorHTML, json: EventasaurusWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Eventasaurus.PubSub,
  live_view: [signing_salt: "I+vQtlzp"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :eventasaurus, Eventasaurus.Mailer, adapter: Swoosh.Adapters.Local

# Swoosh API client is needed for adapters other than SMTP.
config :swoosh, :api_client, false

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.19.11",
  eventasaurus: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --loader:.png=dataurl --loader:.css=css),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  eventasaurus: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# To debug HeEx templates
config :phoenix_live_view, :debug_heex_annotations, true

# Configure time zone database
config :elixir, :time_zone_database, TimeZoneInfo.TimeZoneDatabase

# Configure Hammer for rate limiting
config :hammer,
  backend: {
    Hammer.Backend.ETS,
    [
      # 4 hours
      expiry_ms: 60_000 * 60 * 4,
      # 10 minutes
      cleanup_interval_ms: 60_000 * 10
    ]
  }

# Configure Oban for background job processing
config :eventasaurus, Oban,
  repo: EventasaurusApp.Repo,
  queues: [
    # Email queue with limited concurrency for Resend API rate limiting
    # Max 2 concurrent jobs to respect Resend's 2/second limit
    emails: 2,
    # Scraper queue for event data ingestion
    # Limited concurrency for rate-limited external APIs
    scraper: 5,
    # Scraper detail queue for individual event processing
    # Limited concurrency for event detail scraping
    scraper_detail: 3,
    # Scraper index queue for processing index pages
    # Low concurrency to prevent timeouts and respect rate limits
    scraper_index: 2,
    # Discovery queue for unified sync jobs
    # Limited concurrency for discovery source sync
    discovery: 3,
    # Discovery sync queue for admin dashboard operations
    # Limited concurrency for admin-triggered syncs
    discovery_sync: 2,
    # Google API queue for places lookups
    # Single concurrency to respect Google's rate limits
    google_lookup: 1,
    # Venue enrichment queue for image fetching
    # Low concurrency to respect provider rate limits
    venue_enrichment: 2,
    # Venue image backfill queue for admin-triggered backfills
    # Low concurrency to respect API rate limits and costs
    venue_backfill: 2,
    # Default queue for other background jobs
    default: 10,
    # Maintenance queue for background tasks like coordinate calculation
    maintenance: 2,
    # Reports queue for generating analytics and cost reports
    reports: 1
  ],
  plugins: [
    # Keep completed jobs for 7 days for debugging
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    # Reindex daily for performance
    {Oban.Plugins.Reindexer, schedule: "@daily"},
    # Recover orphaned jobs after 60 seconds
    {Oban.Plugins.Lifeline, rescue_after: 60},
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
       {"0 3 * * *", EventasaurusApp.Workers.UnsplashRefreshWorker}
     ]}
  ]

# Avatar configuration
config :eventasaurus, :avatars,
  provider: :dicebear,
  # Can be changed to: adventurer, avataaars, bottts, croodles, fun-emoji, etc.
  style: "dylan",
  base_url: "https://api.dicebear.com/9.x",
  format: "svg",
  default_options: %{
    # Add any default DiceBear options here
    # backgroundColor: "transparent",
    # size: 200
    backgroundBorderRadius: 50
  }

# CDN configuration for Cloudflare Image Resizing
config :eventasaurus, :cdn,
  enabled: false,
  domain: "cdn.wombie.com"

# ImageKit CDN configuration (for venue images)
# Disabled by default in development, enabled in production
# Test locally with: IMAGEKIT_CDN_ENABLED=true mix phx.server
config :eventasaurus, :imagekit,
  enabled: false,
  id: "wombie",
  endpoint: "https://ik.imagekit.io/wombie"

# Discovery source configuration
config :eventasaurus,
  pubquiz_enabled: true,
  question_one_enabled: true,
  # Discovery quality thresholds
  quality_thresholds: [
    venue_completeness: 90,
    image_completeness: 80,
    category_completeness: 85,
    excellent_score: 90,
    good_score: 75,
    fair_score: 60
  ],
  # Discovery change tracking
  change_tracking: [
    new_events_window_hours: 24,
    dropped_events_window_hours: 48
  ],
  # Generic categories that indicate poor categorization specificity
  generic_categories: [
    "other",
    "miscellaneous",
    "general",
    "events",
    "various"
  ]

# Configure geocoder for forward geocoding (address → city/coordinates)
config :geocoder, :worker, provider: Geocoder.Providers.OpenStreetMaps

# Configure venue image enrichment job
config :eventasaurus, EventasaurusDiscovery.VenueImages.EnrichmentJob,
  batch_size: 100,
  max_retries: 3

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
