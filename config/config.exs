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
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
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

# Avatar configuration
config :eventasaurus, :avatars,
  provider: :dicebear,
  style: "dylan",  # Can be changed to: adventurer, avataaars, bottts, croodles, fun-emoji, etc.
  base_url: "https://api.dicebear.com/9.x",
  format: "svg",
  default_options: %{
    # Add any default DiceBear options here
    # backgroundColor: "transparent",
    # size: 200
  }

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
