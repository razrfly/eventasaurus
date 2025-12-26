# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Include Clerk configuration
import_config "clerk.exs"

# Configure Eventasaurus main app
# Only Repo needs migrations - SessionRepo and ReplicaRepo share the same database schema
config :eventasaurus,
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

# Oban configuration moved to config/runtime.exs
# (Cannot use functions in compile-time config for releases)

# Venue matching configuration
config :eventasaurus, :venue_matching,
  # Proximity threshold in meters for venue deduplication
  # Venues within this distance are considered the same location
  # Increased from 50m to 200m to better handle geocoding variations
  # between different data sources (e.g., Cinema City vs Kino Krakow)
  proximity_threshold_meters: 200

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
  # Disabled in dev - set to true to test orchestrator mode
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

# Unsplash image refresh configuration
# Controls how often to refresh Unsplash images for cities and countries
# Images are only refreshed if older than this threshold
config :eventasaurus, :unsplash,
  # Refresh interval in days for city images
  city_refresh_days: 7,
  # Refresh interval in days for country images
  country_refresh_days: 7

# Configure geocoder for forward geocoding (address → city/coordinates)
config :geocoder, :worker, provider: Geocoder.Providers.OpenStreetMaps

# Configure venue image enrichment job
config :eventasaurus, EventasaurusDiscovery.VenueImages.EnrichmentJob,
  batch_size: 100,
  max_retries: 3

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
