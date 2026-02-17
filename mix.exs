defmodule Eventasaurus.MixProject do
  use Mix.Project

  def project do
    [
      app: :eventasaurus,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :dev,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Eventasaurus.Application, []},
      # :castore ensures the CA certificate bundle is available in releases for SSL verification
      extra_applications: [:logger, :runtime_tools, :crypto, :castore]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:ecto_erd, "~> 0.5", only: [:dev], runtime: false},
      {:tidewave, "~> 0.1", only: [:dev]},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:phoenix, "~> 1.7.10"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 3.3"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0.0"},
      {:floki, ">= 0.30.0"},
      {:phoenix_live_dashboard, "~> 0.8.2"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2.0", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.3"},
      {:finch, "~> 0.13"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:plug_cowboy, "~> 2.5"},
      {:heroicons, "~> 0.5.6"},
      {:nanoid, "~> 2.1.0"},
      {:time_zone_info, "~> 0.7.8"},
      {:earmark, "~> 1.5.0-pre"},

      # HTTP client for API calls (used for Supabase integration)
      {:httpoison, "~> 2.0"},

      # Modern HTTP client for ImageKit uploads (better multipart form support)
      {:req, "~> 0.5.10"},

      # Load environment variables from .env file
      {:dotenv, "~> 3.1", only: [:dev, :test]},

      # Test data factories
      {:ex_machina, "~> 2.7.0", only: [:dev, :test]},

      # Fake data generation for development seeds
      {:faker, "~> 0.18", only: [:dev, :test]},

      # Mocking library for external services in tests
      {:mox, "~> 1.0", only: :test},
      {:mock, "~> 0.3.0", only: :test},

      # Browser automation for end-to-end testing
      {:wallaby, "~> 0.30.0", only: :test, runtime: false},

      # HTML sanitization for social cards
      {:html_sanitize_ex, "~> 1.4"},

      # HTML entity decoding for Question One venue extraction
      {:html_entities, "~> 0.5"},

      # State machine library for event lifecycle management
      {:machinery, "~> 1.0"},

      # Stripe payment processing
      {:stripity_stripe, "~> 3.2"},

      # Email service for guest invitations
      {:resend, "~> 0.4"},

      # Background job processing
      # Upgraded from 2.17 to 2.20.2 for v12/v13 migrations (Issue #3172)
      {:oban, "~> 2.20.2"},
      {:oban_web, "~> 2.11.6"},

      # Enhanced polling system dependencies
      # Caching for API responses and poll results
      {:cachex, "~> 4.1"},

      # Data encryption for sensitive information
      {:cloak, "~> 1.1"},

      # Rate limiting for API endpoints
      {:hammer, "~> 7.0"},

      # Error tracking and performance monitoring
      {:sentry, git: "https://github.com/getsentry/sentry-elixir.git", branch: "master"},
      {:hackney, "~> 1.8"},

      # Override nimble_ownership version for Sentry compatibility
      {:nimble_ownership, "~> 1.0", override: true},

      # Soft delete functionality for preserving data
      {:ecto_soft_delete, "~> 2.1"},

      # HTML helpers for text truncation and more
      {:phoenix_html_simplified_helpers, "~> 2.1.0"},

      # Geo-spatial support for venue deduplication
      {:geo, "~> 3.6"},
      {:geo_postgis, "~> 3.6"},

      # Fuzzy string matching for deduplication
      {:akin, "~> 0.2.0"},

      # Auto-generate slugs for models
      {:ecto_autoslug_field, "~> 3.1"},

      # Country codes and names
      {:countries, "~> 1.6"},

      # Comprehensive date/time parsing and manipulation
      {:timex, "~> 3.7"},

      # Timezone lookup by geographic coordinates
      {:tz_world, "~> 1.3"},

      # Offline reverse geocoding (lat/lng → city name)
      {:geocoding, "~> 0.3.0"},

      # Forward geocoding (address → city/coordinates)
      {:geocoder, "~> 1.1"},

      # YAML parsing for category mappings
      {:yaml_elixir, "~> 2.11"},

      # XML Sitemap generation for SEO
      {:sitemapper, "~> 0.10"},

      # AWS S3 client for Supabase Storage compatibility
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:sweet_xml, "~> 0.7"},

      # Clerk authentication (replacing Supabase Auth)
      # Using JOSE for JWT verification - clerk hex package has dependency conflicts
      {:jose, "~> 1.11"},

      # SSL certificate store for PlanetScale and other TLS connections
      # Must be explicit (not transitive) to ensure availability in releases
      {:castore, "~> 1.0"},

      # Server-side SVG chart generation (sparklines for monitoring dashboard)
      {:contex, "~> 0.5"},

      # ML Framework - Phase 0 (Issue #3213)
      # Zero-shot classification for event categorization
      # Model: MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7
      # DEV ONLY: Production uses HuggingFace Inference API (Phase 3+)
      {:bumblebee, "~> 0.6", only: :dev},
      {:nx, "~> 0.9", only: :dev},
      {:exla, "~> 0.9", only: :dev}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      test: ["test"],
      "assets.setup": ["cmd --cd assets npm install", "tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind eventasaurus", "esbuild eventasaurus"],
      "assets.deploy": [
        "tailwind eventasaurus --minify",
        "esbuild eventasaurus --minify",
        "phx.digest",
        "sentry.package_source_code"
      ],
      "erd.gen.png": [
        "ecto.gen.erd",
        "cmd dot -Tpng eventasaurus.dot -o ecto_erd.png",
        "cmd rm eventasaurus.dot"
      ],
      "currencies.refresh": ["currencies refresh"]
    ]
  end
end
