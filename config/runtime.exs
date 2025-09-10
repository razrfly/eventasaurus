import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

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

# Configure Cloudflare Turnstile for bot protection
config :eventasaurus, :turnstile,
  site_key: System.get_env("TURNSTILE_SITE_KEY"),
  secret_key: System.get_env("TURNSTILE_SECRET_KEY")

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
  # Validate required Supabase environment variables are set
  for var <- ~w(SUPABASE_URL SUPABASE_PUBLISHABLE_KEY SUPABASE_DATABASE_URL) do
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

  host = System.get_env("PHX_HOST") || "eventasaur.us"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :eventasaurus, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :eventasaurus, EventasaurusWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    check_origin: ["https://eventasaur.us", "https://eventasaurus.fly.dev"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
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

  # Configure the database for production
  # Note: Supabase typically requires verify_none in containerized environments
  # Set SSL_VERIFY_PEER=true to enable certificate verification (may cause connection issues with Supabase)
  ssl_verify =
    if System.get_env("SSL_VERIFY_PEER") == "true", do: :verify_peer, else: :verify_none

  if ssl_verify == :verify_none do
    require Logger

    Logger.warning(
      "Database SSL verification disabled for Supabase compatibility. Set SSL_VERIFY_PEER=true to enable certificate verification."
    )
  end

  config :eventasaurus, EventasaurusApp.Repo,
    url: System.get_env("SUPABASE_DATABASE_URL"),
    database: "postgres",
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5"),
    queue_target: 5000,
    queue_interval: 30000,
    ssl: true,
    ssl_opts: [verify: ssl_verify]

  # Configure Supabase settings for production
  config :eventasaurus, :supabase,
    url: System.get_env("SUPABASE_URL"),
    api_key: System.get_env("SUPABASE_PUBLISHABLE_KEY"),
    service_role_key: System.get_env("SUPABASE_SECRET_KEY"),
    database_url: System.get_env("SUPABASE_DATABASE_URL"),
    bucket: System.get_env("SUPABASE_BUCKET") || "event-images",
    auth: %{
      site_url: "https://eventasaur.us",
      additional_redirect_urls: ["https://eventasaur.us/auth/callback"],
      auto_confirm_email: false
    }

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
  config :eventasaurus, :base_url, "https://eventasaur.us"

  # Stripe configuration is now handled globally above (lines 25-27)
  # Sentry configuration is now handled globally above (lines 29-47)
end
