defmodule Eventasaurus.Sitemap do
  @moduledoc """
  Generates XML sitemaps for the Wombie website.
  Uses Sitemapper to generate sitemaps for activities, cities, venues, containers, movies, and aggregations.

  ## Completed Phases
  - Phase 1: Static pages (/, /activities, /about, etc.)
  - Phase 2: Activities (/activities/:slug)
  - Phase 3: Cities (/c/:city_slug and subpages)
  - Phase 4: Venues (/c/:city_slug/venues/:venue_slug)
  - Phase 5: Containers (festivals, conferences, tours, etc.)
  - Phase 6: Movie aggregation pages (/c/:city_slug/movies/:movie_slug)
  - Phase 7: Content aggregation pages (/:content_type/:identifier)
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
  Returns URL statistics for each sitemap category.
  This is the SINGLE SOURCE OF TRUTH for sitemap composition.

  Used by SitemapStats and admin dashboard to show what WOULD be in the sitemap.

  ## Options
  * `:host` - Override host for URL generation (default: wombie.com in prod)
  """
  @spec url_stats(keyword()) :: [map()]
  def url_stats(opts \\ []) do
    base_url = get_base_url(opts)

    [
      %{
        key: :static,
        name: "Static Pages",
        description: "Home, about, privacy, movies index, etc.",
        count: count_static_urls(),
        sample: base_url
      },
      %{
        key: :activities,
        name: "Activities",
        description: "Individual event/activity pages",
        count: count_activities(),
        sample: sample_activity_url(base_url)
      },
      %{
        key: :cities,
        name: "City Pages",
        description: "City landing pages with 10 subpages each",
        count: count_city_urls(),
        sample: "#{base_url}/c/krakow"
      },
      %{
        key: :venues,
        name: "Venues",
        description: "Venue pages within cities (only venues with public events)",
        count: count_venues(),
        sample: sample_venue_url(base_url)
      },
      %{
        key: :containers,
        name: "Containers",
        description: "Festivals, conferences, tours, series, etc.",
        count: count_containers(),
        sample: sample_container_url(base_url)
      },
      %{
        key: :city_movies,
        name: "City Movie Pages",
        description: "Movie pages within specific cities (/c/:city/movies/:movie)",
        count: count_city_movies(),
        sample: sample_city_movie_url(base_url)
      },
      %{
        key: :generic_movies,
        name: "Generic Movie Pages",
        description: "Cross-city movie aggregation pages (/movies/:slug)",
        count: count_generic_movies(),
        sample: sample_generic_movie_url(base_url)
      }
    ]
  end

  @doc """
  Creates a stream of URLs for the sitemap.
  Includes: Static pages, activities, cities, venues, containers, movies, and aggregations.

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
      container_urls(opts),
      movie_urls(opts),
      generic_movie_urls(opts)
      # aggregation_urls(opts) - Disabled: AggregatedEventGroup is virtual struct, not queryable
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
      },
      %Sitemapper.URL{
        loc: "#{base_url}/movies",
        changefreq: :daily,
        priority: 0.9,
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

  # Returns a stream of all venues in active cities that have public events
  # Excludes private venues (user home addresses, etc.) from the sitemap
  defp venue_urls(opts) do
    base_url = get_base_url(opts)

    # Query public venues in active cities
    # is_public=true indicates scraper-created venues (theaters, bars, concert halls)
    # is_public=false indicates user-created private venues (excluded from sitemap)
    from(v in EventasaurusApp.Venues.Venue,
      join: c in EventasaurusDiscovery.Locations.City,
      on: v.city_id == c.id,
      select: %{slug: v.slug, updated_at: v.updated_at, city_slug: c.slug},
      where: v.is_public == true and c.discovery_enabled == true and not is_nil(v.slug)
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

  # Returns a stream of all movie aggregation pages in active cities
  defp movie_urls(opts) do
    base_url = get_base_url(opts)

    # Query movies that have screenings in active cities
    # Get distinct movie + city combinations
    from(m in EventasaurusDiscovery.Movies.Movie,
      join: em in "event_movies",
      on: em.movie_id == m.id,
      join: pe in PublicEvent,
      on: pe.id == em.event_id,
      join: v in EventasaurusApp.Venues.Venue,
      on: v.id == pe.venue_id,
      join: c in EventasaurusDiscovery.Locations.City,
      on: c.id == v.city_id,
      select: %{
        movie_slug: m.slug,
        city_slug: c.slug,
        updated_at: m.updated_at
      },
      where: c.discovery_enabled == true and not is_nil(m.slug) and m.slug != "",
      distinct: [m.id, c.id]
    )
    |> Repo.stream()
    |> Stream.map(fn movie ->
      lastmod =
        if movie.updated_at do
          NaiveDateTime.to_date(movie.updated_at)
        else
          Date.utc_today()
        end

      %Sitemapper.URL{
        loc: "#{base_url}/c/#{movie.city_slug}/movies/#{movie.movie_slug}",
        changefreq: :weekly,
        priority: 0.8,
        lastmod: lastmod
      }
    end)
  end

  # Returns a stream of generic movie pages (not city-specific)
  defp generic_movie_urls(opts) do
    base_url = get_base_url(opts)

    # Query all movies with valid slugs
    from(m in EventasaurusDiscovery.Movies.Movie,
      select: %{slug: m.slug, updated_at: m.updated_at},
      where: not is_nil(m.slug) and m.slug != ""
    )
    |> Repo.stream()
    |> Stream.map(fn movie ->
      lastmod =
        if movie.updated_at do
          NaiveDateTime.to_date(movie.updated_at)
        else
          Date.utc_today()
        end

      %Sitemapper.URL{
        loc: "#{base_url}/movies/#{movie.slug}",
        changefreq: :weekly,
        priority: 0.7,
        lastmod: lastmod
      }
    end)
  end

  # NOTE: aggregation_urls/1 removed because AggregatedEventGroup is a virtual struct
  # (not a database table), so it cannot be queried with Ecto. Aggregation URLs are
  # generated dynamically and don't need to be in the sitemap.

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
    # For production, use R2Store (Cloudflare R2)
    if is_prod do
      # Define path for sitemaps (store in sitemaps/ directory)
      sitemap_path = "sitemaps"

      # Get R2 configuration
      r2_config = Application.get_env(:eventasaurus, :r2) || %{}
      cdn_url = r2_config[:cdn_url] || System.get_env("R2_CDN_URL") || "https://cdn2.wombie.com"

      # Build R2 CDN URL for sitemap files
      # This is where the actual sitemap chunk files will be accessible
      r2_sitemap_url = "#{cdn_url}/#{sitemap_path}"

      # Log the final configuration details
      Logger.info("Sitemap config - R2Store, path: #{sitemap_path}")
      Logger.info("Sitemap public URL: #{r2_sitemap_url}")

      # Configure sitemap to store on Cloudflare R2 via S3-compatible API
      [
        store: Eventasaurus.Sitemap.R2Store,
        store_config: [
          path: sitemap_path
        ],
        # Point to R2 CDN URL so sitemap index contains correct URLs
        sitemap_url: r2_sitemap_url
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

  # =============================================================================
  # Count functions for url_stats/0 - Single source of truth for sitemap counts
  # =============================================================================

  # Count static pages (dynamically from static_urls list)
  defp count_static_urls do
    # Count the actual static URLs list to stay in sync
    static_urls([]) |> Enum.count()
  end

  # Count activities (public events with valid slugs)
  defp count_activities do
    from(pe in PublicEvent,
      select: count(pe.id),
      where:
        not is_nil(pe.slug) and
          not is_nil(pe.updated_at) and
          pe.slug != "" and
          fragment("? !~ ?", pe.slug, "^-")
    )
    |> Repo.one() || 0
  end

  # Count city URLs (active cities × 10 subpages per city)
  defp count_city_urls do
    active_cities =
      from(c in EventasaurusDiscovery.Locations.City,
        select: count(c.id),
        where: c.discovery_enabled == true
      )
      |> Repo.one() || 0

    # Each city has 10 pages: main + events + venues + search + 6 container types
    active_cities * 10
  end

  # Count venues in active cities that have public events
  # Must match the filtering logic in venue_urls/1
  defp count_venues do
    from(v in EventasaurusApp.Venues.Venue,
      join: c in EventasaurusDiscovery.Locations.City,
      on: v.city_id == c.id,
      inner_join: pe in PublicEvent,
      on: pe.venue_id == v.id,
      select: count(v.id, :distinct),
      where: c.discovery_enabled == true and not is_nil(v.slug)
    )
    |> Repo.one() || 0
  end

  # Count containers in active cities
  defp count_containers do
    from(pec in EventasaurusDiscovery.PublicEvents.PublicEventContainer,
      join: pecm in EventasaurusDiscovery.PublicEvents.PublicEventContainerMembership,
      on: pecm.container_id == pec.id,
      join: pe in PublicEvent,
      on: pe.id == pecm.event_id,
      join: v in EventasaurusApp.Venues.Venue,
      on: v.id == pe.venue_id,
      join: c in EventasaurusDiscovery.Locations.City,
      on: c.id == v.city_id,
      select: count(pec.id, :distinct),
      where:
        not is_nil(pec.slug) and
          c.discovery_enabled == true
    )
    |> Repo.one() || 0
  end

  # Count city-specific movie pages (movie + city combinations)
  defp count_city_movies do
    # Use subquery with DISTINCT to get unique movie-city pairs, then count
    subquery =
      from(m in EventasaurusDiscovery.Movies.Movie,
        join: em in "event_movies",
        on: em.movie_id == m.id,
        join: pe in PublicEvent,
        on: pe.id == em.event_id,
        join: v in EventasaurusApp.Venues.Venue,
        on: v.id == pe.venue_id,
        join: c in EventasaurusDiscovery.Locations.City,
        on: c.id == v.city_id,
        select: %{movie_id: m.id, city_id: c.id},
        where: c.discovery_enabled == true and not is_nil(m.slug) and m.slug != "",
        distinct: true
      )

    from(s in subquery(subquery), select: count(s.movie_id))
    |> Repo.one() || 0
  end

  # Count generic movie pages (all movies with valid slugs)
  defp count_generic_movies do
    from(m in EventasaurusDiscovery.Movies.Movie,
      select: count(m.id),
      where: not is_nil(m.slug) and m.slug != ""
    )
    |> Repo.one() || 0
  end

  # =============================================================================
  # Sample URL functions for url_stats/0
  # =============================================================================

  # Get a sample activity URL
  defp sample_activity_url(base_url) do
    activity =
      from(pe in PublicEvent,
        select: pe.slug,
        where:
          not is_nil(pe.slug) and
            pe.slug != "" and
            fragment("? !~ ?", pe.slug, "^-"),
        limit: 1
      )
      |> Repo.one()

    if activity do
      "#{base_url}/activities/#{activity}"
    else
      nil
    end
  end

  # Get a sample venue URL (only venues with public events)
  # Must match the filtering logic in venue_urls/1
  defp sample_venue_url(base_url) do
    venue =
      from(v in EventasaurusApp.Venues.Venue,
        join: c in EventasaurusDiscovery.Locations.City,
        on: v.city_id == c.id,
        inner_join: pe in PublicEvent,
        on: pe.venue_id == v.id,
        select: %{venue_slug: v.slug, city_slug: c.slug},
        where: c.discovery_enabled == true and not is_nil(v.slug),
        limit: 1
      )
      |> Repo.one()

    if venue do
      "#{base_url}/c/#{venue.city_slug}/venues/#{venue.venue_slug}"
    else
      nil
    end
  end

  # Get a sample container URL
  defp sample_container_url(base_url) do
    container =
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
          city_slug: c.slug
        },
        where:
          not is_nil(pec.slug) and
            c.discovery_enabled == true,
        limit: 1
      )
      |> Repo.one()

    if container do
      type_plural = pluralize_container_type(container.container_type)
      "#{base_url}/c/#{container.city_slug}/#{type_plural}/#{container.slug}"
    else
      nil
    end
  end

  # Get a sample city movie URL
  defp sample_city_movie_url(base_url) do
    movie =
      from(m in EventasaurusDiscovery.Movies.Movie,
        join: em in "event_movies",
        on: em.movie_id == m.id,
        join: pe in PublicEvent,
        on: pe.id == em.event_id,
        join: v in EventasaurusApp.Venues.Venue,
        on: v.id == pe.venue_id,
        join: c in EventasaurusDiscovery.Locations.City,
        on: c.id == v.city_id,
        select: %{movie_slug: m.slug, city_slug: c.slug},
        where: c.discovery_enabled == true and not is_nil(m.slug) and m.slug != "",
        limit: 1
      )
      |> Repo.one()

    if movie do
      "#{base_url}/c/#{movie.city_slug}/movies/#{movie.movie_slug}"
    else
      nil
    end
  end

  # Get a sample generic movie URL
  defp sample_generic_movie_url(base_url) do
    movie =
      from(m in EventasaurusDiscovery.Movies.Movie,
        select: m.slug,
        where: not is_nil(m.slug) and m.slug != "",
        limit: 1
      )
      |> Repo.one()

    if movie do
      "#{base_url}/movies/#{movie}"
    else
      nil
    end
  end
end
