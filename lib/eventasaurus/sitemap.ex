defmodule Eventasaurus.Sitemap do
  @moduledoc """
  Generates XML sitemaps for the Wombie website.
  Uses Sitemapper to generate sitemaps for activities, cities, venues, and static pages.

  ## Phase 1: Activities (Primary Focus)
  Activities (/activities/:slug) are the most important content for SEO.
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  import Ecto.Query
  require Logger

  @doc """
  Generates and persists a sitemap for the website.
  Phase 1 includes activities and static pages.

  ## Options
  * `:environment` - Override environment detection (e.g., :prod, :dev)
  * `:host` - Override host for URL generation (e.g., "wombie.com")

  Returns :ok on success or {:error, reason} on failure.
  """
  def generate_and_persist(opts \\ []) do
    try do
      # Ensure environment variables are loaded
      load_env_vars()

      # Get the sitemap configuration with optional overrides
      config = get_sitemap_config(opts)

      # Log start of generation
      Logger.info("Starting sitemap generation")

      # Use a database transaction to ensure proper streaming
      # Set timeout to :infinity to allow long-running sitemap generation + S3 upload
      Repo.transaction(
        fn ->
          # Stream URLs directly to Sitemapper without consuming the stream
          stream_urls(opts)
          |> tap(fn _ -> Logger.info("Starting sitemap generation with all available URLs") end)
          |> Sitemapper.generate(config)
          |> tap(fn _ -> Logger.info("Sitemap generated, starting persistence") end)
          |> Sitemapper.persist(config)
          |> tap(fn _ -> Logger.info("Completed sitemap persistence") end)
          |> Stream.run()
        end,
        timeout: :infinity
      )

      Logger.info("Sitemap generation completed")
      :ok
    rescue
      error ->
        Logger.error("Sitemap generation failed: #{inspect(error, pretty: true)}")
        Logger.error("Stacktrace: #{Exception.format_stacktrace()}")
        {:error, error}
    catch
      kind, reason ->
        Logger.error("Caught #{kind} in sitemap generation: #{inspect(reason, pretty: true)}")
        Logger.error("Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
        {:error, reason}
    end
  end

  @doc """
  Creates a stream of URLs for the sitemap.
  Phase 1: Static pages and activities.

  ## Options
  * `:host` - Override host for URL generation
  """
  def stream_urls(opts \\ []) do
    # Combine all streams
    [static_urls(opts), activity_urls(opts)]
    |> Enum.reduce(Stream.concat([]), fn stream, acc ->
      Stream.concat(acc, stream)
    end)
  end

  # Returns a stream of static pages
  defp static_urls(opts) do
    base_url = get_base_url(opts)

    [
      %Sitemapper.URL{
        loc: base_url,
        changefreq: :weekly,
        priority: 1.0,
        lastmod: Date.utc_today()
      },
      %Sitemapper.URL{
        loc: "#{base_url}/activities",
        changefreq: :daily,
        priority: 0.95,
        lastmod: Date.utc_today()
      },
      %Sitemapper.URL{
        loc: "#{base_url}/about",
        changefreq: :monthly,
        priority: 0.5,
        lastmod: Date.utc_today()
      },
      %Sitemapper.URL{
        loc: "#{base_url}/our-story",
        changefreq: :monthly,
        priority: 0.5,
        lastmod: Date.utc_today()
      },
      %Sitemapper.URL{
        loc: "#{base_url}/privacy",
        changefreq: :monthly,
        priority: 0.3,
        lastmod: Date.utc_today()
      },
      %Sitemapper.URL{
        loc: "#{base_url}/terms",
        changefreq: :monthly,
        priority: 0.3,
        lastmod: Date.utc_today()
      },
      %Sitemapper.URL{
        loc: "#{base_url}/your-data",
        changefreq: :monthly,
        priority: 0.3,
        lastmod: Date.utc_today()
      }
    ]
    |> Stream.map(& &1)
  end

  # Returns a stream of all activities (Phase 1 primary focus)
  defp activity_urls(opts) do
    base_url = get_base_url(opts)

    # Query public_events for activities
    # Only include events that have valid slugs and timestamps
    # Filter out broken slugs (empty strings or starting with "-")
    # Include starts_at for date-based priority and changefreq calculation
    from(pe in PublicEvent,
      select: %{slug: pe.slug, updated_at: pe.updated_at, starts_at: pe.starts_at},
      where:
        not is_nil(pe.slug) and
          not is_nil(pe.updated_at) and
          pe.slug != "" and
          fragment("? !~ ?", pe.slug, "^-")
    )
    |> Repo.stream()
    |> Stream.map(fn activity ->
      # Use updated_at for lastmod (last significant modification)
      # This is already properly tracked by EventProcessor - only updates on content changes
      lastmod =
        if activity.updated_at do
          NaiveDateTime.to_date(activity.updated_at)
        else
          Date.utc_today()
        end

      # Calculate changefreq based on event date
      # Future events: weekly (matches our scraper frequency)
      # Past events: never (they won't change anymore)
      changefreq = calculate_changefreq(activity.starts_at)

      # Calculate priority based on event date relative to today
      # Upcoming events get higher priority, past events get lower priority
      priority = calculate_priority(activity.starts_at)

      %Sitemapper.URL{
        loc: "#{base_url}/activities/#{activity.slug}",
        changefreq: changefreq,
        priority: priority,
        lastmod: lastmod
      }
    end)
  end

  # Calculate changefreq based on event date
  defp calculate_changefreq(starts_at) when is_nil(starts_at), do: :weekly

  defp calculate_changefreq(starts_at) do
    now = DateTime.utc_now()

    case DateTime.compare(starts_at, now) do
      # Future event - might change as scrapers run weekly
      comp when comp in [:gt, :eq] -> :weekly
      # Past event - won't change anymore
      :lt -> :never
    end
  end

  # Calculate priority based on event date relative to today
  # Uses Google's recommended 0.0-1.0 scale (relative importance within YOUR site)
  defp calculate_priority(starts_at) when is_nil(starts_at), do: 0.5

  defp calculate_priority(starts_at) do
    now = DateTime.utc_now()
    diff_days = DateTime.diff(starts_at, now, :day)

    cond do
      # Happening today or tomorrow - highest priority
      diff_days >= 0 and diff_days <= 1 -> 1.0
      # Next 7 days - very high priority
      diff_days > 1 and diff_days <= 7 -> 0.9
      # Next 8-30 days - high priority
      diff_days > 7 and diff_days <= 30 -> 0.7
      # Next 31-90 days - medium-high priority
      diff_days > 30 and diff_days <= 90 -> 0.6
      # Future (>90 days) - medium priority
      diff_days > 90 -> 0.5
      # Past (0-7 days ago) - low-medium priority
      diff_days < 0 and diff_days >= -7 -> 0.4
      # Past (8-30 days ago) - low priority
      diff_days < -7 and diff_days >= -30 -> 0.3
      # Past (>30 days ago) - very low priority
      diff_days < -30 -> 0.1
    end
  end

  # Get the base URL for the sitemap
  defp get_base_url(opts) do
    # Allow host override via opts
    override_host = Keyword.get(opts, :host)
    Logger.info("Sitemap URL generation - override_host from opts: #{inspect(override_host)}")

    # Use EventasaurusWeb.Endpoint configuration
    endpoint_config = Application.get_env(:eventasaurus, EventasaurusWeb.Endpoint)
    url_config = endpoint_config[:url]
    config_host = url_config[:host]
    port = url_config[:port]
    scheme = url_config[:scheme] || "https"

    Logger.info(
      "Sitemap URL generation - config_host from endpoint: #{inspect(config_host)}, port: #{inspect(port)}, scheme: #{inspect(scheme)}"
    )

    # Determine environment from opts or application config
    env_from_opts = Keyword.get(opts, :environment)
    app_env = Application.get_env(:eventasaurus, :environment)

    is_prod =
      case env_from_opts do
        nil -> app_env == :prod
        env -> env == :prod
      end

    Logger.info(
      "Sitemap URL generation - environment from opts: #{inspect(env_from_opts)}, app environment: #{inspect(app_env)}, is_prod: #{is_prod}"
    )

    # Use override_host if provided, otherwise fall back to config or PHX_HOST
    host =
      if is_prod do
        override_host || config_host || System.get_env("PHX_HOST") || "wombie.com"
      else
        override_host || config_host
      end

    Logger.info("Sitemap URL generation - selected host: #{inspect(host)}")

    base_url =
      cond do
        # In production, use the configured host directly
        is_prod ->
          "#{scheme}://#{host}"

        # In development with non-standard port
        port && port != 80 && port != 443 ->
          "#{scheme}://#{host}:#{port}"

        # In development with standard port
        true ->
          "#{scheme}://#{host}"
      end

    Logger.info("Sitemap URL generation - final base_url: #{base_url}")
    base_url
  end

  # Get the sitemap configuration
  defp get_sitemap_config(opts) do
    # Get base URL
    base_url = get_base_url(opts)

    # Determine if we're in production environment
    is_prod =
      case Keyword.get(opts, :environment) do
        nil -> Application.get_env(:eventasaurus, :environment) == :prod
        env -> env == :prod
      end

    Logger.debug("Environment: #{if is_prod, do: "production", else: "development"}")

    # For local development, use FileStore
    # For production, use SupabaseStore
    if is_prod do
      # Define path for sitemaps (store in sitemaps/ directory)
      sitemap_path = "sitemaps"

      # Get Supabase configuration
      supabase_config = Application.get_env(:eventasaurus, :supabase)
      supabase_url = supabase_config[:url]
      bucket = System.get_env("SUPABASE_BUCKET") || supabase_config[:bucket] || "eventasaur.us"

      # Build Supabase Storage public URL for sitemap files
      # This is where the actual sitemap chunk files will be accessible
      supabase_sitemap_url = "#{supabase_url}/storage/v1/object/public/#{bucket}/#{sitemap_path}"

      # Log the final configuration details
      Logger.info("Sitemap config - SupabaseStore, path: #{sitemap_path}")
      Logger.info("Sitemap public URL: #{supabase_sitemap_url}")

      # Configure sitemap to store on Supabase Storage using S3-compatible API
      # This works with NEW Supabase secret keys (sb_secret_...)
      [
        store: Eventasaurus.Sitemap.SupabaseS3Store,
        store_config: [
          path: sitemap_path
        ],
        # Point to Supabase Storage public URL so sitemap index contains correct URLs
        sitemap_url: supabase_sitemap_url
      ]
    else
      # For local development, use file storage
      priv_dir = :code.priv_dir(:eventasaurus)
      sitemap_path = Path.join([priv_dir, "static", "sitemaps"])

      # Ensure directory exists
      File.mkdir_p!(sitemap_path)

      Logger.debug("Sitemap config - FileStore, path: #{sitemap_path}")

      # Return file store config
      [
        store: Sitemapper.FileStore,
        store_config: [path: sitemap_path],
        sitemap_url: "#{base_url}/sitemaps"
      ]
    end
  end

  # Load environment variables from .env file
  defp load_env_vars do
    case Code.ensure_loaded(DotenvParser) do
      {:module, mod} ->
        Logger.debug("Checking for .env file")

        if File.exists?(".env") do
          Logger.debug("Loading environment variables from .env file")
          apply(mod, :load_file, [".env"])
        else
          Logger.debug("No .env file found, using system environment variables")
          :ok
        end

      _ ->
        Logger.debug("DotenvParser module not found. Using system environment variables.")
        :ok
    end
  end
end
