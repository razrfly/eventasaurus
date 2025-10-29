defmodule Eventasaurus.Sitemap do
  @moduledoc """
  Generates XML sitemaps for the Wombie website.
  Uses Sitemapper to generate sitemaps for activities, cities, venues, containers, and static pages.

  ## Completed Phases
  - Phase 1: Static pages (/, /activities, /about, etc.)
  - Phase 2: Activities (/activities/:slug)
  - Phase 3: Cities (/c/:city_slug and subpages)
  - Phase 4: Venues (/c/:city_slug/venues/:venue_slug)
  - Phase 5: Containers (festivals, conferences, tours, etc.)
  """

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  import Ecto.Query
  require Logger

  @doc """
  Generates and persists a sitemap for the website.
  Phase 1 includes static pages, activities, cities, and venues.

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
  Includes: Static pages, activities, cities, venues, and containers.

  ## Options
  * `:host` - Override host for URL generation
  """
  def stream_urls(opts \\ []) do
    # Combine all streams
    [
      static_urls(opts),
      activity_urls(opts),
      city_urls(opts),
      venue_urls(opts),
      container_urls(opts)
    ]
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

  # Returns a stream of all active cities and their important pages
  defp city_urls(opts) do
    base_url = get_base_url(opts)

    # Query cities where discovery_enabled = true
    from(c in EventasaurusDiscovery.Locations.City,
      select: %{slug: c.slug, name: c.name, updated_at: c.updated_at},
      where: c.discovery_enabled == true
    )
    |> Repo.stream()
    |> Stream.flat_map(fn city ->
      lastmod =
        if city.updated_at do
          NaiveDateTime.to_date(city.updated_at)
        else
          Date.utc_today()
        end

      # Main city page + important sub-pages
      [
        %Sitemapper.URL{
          loc: "#{base_url}/c/#{city.slug}",
          changefreq: :daily,
          priority: 0.9,
          lastmod: lastmod
        },
        %Sitemapper.URL{
          loc: "#{base_url}/c/#{city.slug}/venues",
          changefreq: :weekly,
          priority: 0.8,
          lastmod: lastmod
        },
        %Sitemapper.URL{
          loc: "#{base_url}/c/#{city.slug}/events",
          changefreq: :daily,
          priority: 0.85,
          lastmod: lastmod
        },
        %Sitemapper.URL{
          loc: "#{base_url}/c/#{city.slug}/search",
          changefreq: :weekly,
          priority: 0.7,
          lastmod: lastmod
        },
        %Sitemapper.URL{
          loc: "#{base_url}/c/#{city.slug}/festivals",
          changefreq: :weekly,
          priority: 0.75,
          lastmod: lastmod
        },
        %Sitemapper.URL{
          loc: "#{base_url}/c/#{city.slug}/conferences",
          changefreq: :weekly,
          priority: 0.75,
          lastmod: lastmod
        },
        %Sitemapper.URL{
          loc: "#{base_url}/c/#{city.slug}/tours",
          changefreq: :weekly,
          priority: 0.75,
          lastmod: lastmod
        },
        %Sitemapper.URL{
          loc: "#{base_url}/c/#{city.slug}/series",
          changefreq: :weekly,
          priority: 0.75,
          lastmod: lastmod
        },
        %Sitemapper.URL{
          loc: "#{base_url}/c/#{city.slug}/exhibitions",
          changefreq: :weekly,
          priority: 0.75,
          lastmod: lastmod
        },
        %Sitemapper.URL{
          loc: "#{base_url}/c/#{city.slug}/tournaments",
          changefreq: :weekly,
          priority: 0.75,
          lastmod: lastmod
        }
      ]
    end)
  end

  # Returns a stream of all venues in active cities
  defp venue_urls(opts) do
    base_url = get_base_url(opts)

    # Query venues that belong to active cities
    from(v in EventasaurusApp.Venues.Venue,
      join: c in EventasaurusDiscovery.Locations.City,
      on: v.city_id == c.id,
      select: %{slug: v.slug, updated_at: v.updated_at, city_slug: c.slug},
      where: c.discovery_enabled == true and not is_nil(v.slug)
    )
    |> Repo.stream()
    |> Stream.map(fn venue ->
      lastmod =
        if venue.updated_at do
          NaiveDateTime.to_date(venue.updated_at)
        else
          Date.utc_today()
        end

      %Sitemapper.URL{
        loc: "#{base_url}/c/#{venue.city_slug}/venues/#{venue.slug}",
        changefreq: :weekly,
        priority: 0.6,
        lastmod: lastmod
      }
    end)
  end

  # Returns a stream of all containers (festivals, conferences, etc.) in active cities
  defp container_urls(opts) do
    base_url = get_base_url(opts)

    # Query containers via their member events to determine city associations
    # A container can appear in multiple cities if it has events in different cities
    from(pec in EventasaurusDiscovery.PublicEvents.PublicEventContainer,
      join: pecm in EventasaurusDiscovery.PublicEvents.PublicEventContainerMembership,
      on: pecm.container_id == pec.id,
      join: pe in PublicEvent,
      on: pe.id == pecm.event_id,
      join: v in EventasaurusApp.Venues.Venue,
      on: v.id == pe.venue_id,
      join: c in EventasaurusDiscovery.Locations.City,
      on: c.id == v.city_id,
      select: %{
        slug: pec.slug,
        container_type: pec.container_type,
        city_slug: c.slug,
        updated_at: pec.updated_at
      },
      where:
        not is_nil(pec.slug) and
          c.discovery_enabled == true,
      distinct: [pec.id, c.id]
    )
    |> Repo.stream()
    |> Stream.map(fn container ->
      lastmod =
        if container.updated_at do
          NaiveDateTime.to_date(container.updated_at)
        else
          Date.utc_today()
        end

      # Convert container_type atom to string for URL (e.g., :festival -> "festivals")
      type_plural = pluralize_container_type(container.container_type)

      %Sitemapper.URL{
        loc: "#{base_url}/c/#{container.city_slug}/#{type_plural}/#{container.slug}",
        changefreq: :weekly,
        priority: 0.8,
        lastmod: lastmod
      }
    end)
  end

  # Convert container type to plural form for URL generation
  defp pluralize_container_type(:festival), do: "festivals"
  defp pluralize_container_type(:conference), do: "conferences"
  defp pluralize_container_type(:tour), do: "tours"
  defp pluralize_container_type(:series), do: "series"
  defp pluralize_container_type(:exhibition), do: "exhibitions"
  defp pluralize_container_type(:tournament), do: "tournaments"
  defp pluralize_container_type(_), do: "unknown"

  # Calculate changefreq based on event date
  defp calculate_changefreq(starts_at) when is_nil(starts_at), do: :weekly

  defp calculate_changefreq(starts_at) do
    # Convert NaiveDateTime to Date for comparison
    event_date = to_date(starts_at)
    today = Date.utc_today()

    case Date.compare(event_date, today) do
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
    # Convert NaiveDateTime to Date for comparison
    event_date = to_date(starts_at)
    today = Date.utc_today()
    diff_days = Date.diff(event_date, today)

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

  # Convert NaiveDateTime or DateTime to Date
  defp to_date(%NaiveDateTime{} = naive_dt), do: NaiveDateTime.to_date(naive_dt)
  defp to_date(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp to_date(%Date{} = date), do: date

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
