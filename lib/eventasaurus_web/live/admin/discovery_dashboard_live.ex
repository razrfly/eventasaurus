defmodule EventasaurusWeb.Admin.DiscoveryDashboardLive do
  @moduledoc """
  Admin dashboard for managing public event discovery and synchronization.
  Allows admins to trigger imports, view statistics, and manage discovery data.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.{Repo, Venues}
  alias EventasaurusApp.Cache.DashboardStats
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.Locations.City

  alias EventasaurusDiscovery.Admin.{
    DataManager,
    DiscoverySyncJob,
    DiscoveryConfigManager,
    DiscoveryStatsCollector
  }

  alias EventasaurusDiscovery.Sources.SourceRegistry
  alias EventasaurusDiscovery.VenueImages.BackfillOrchestratorJob
  alias EventasaurusDiscovery.Geocoding.Schema.GeocodingProvider
  # Collisions module now used via DashboardStats cache

  import Ecto.Query
  require Logger

  # Refresh interval increased from 30s to 5 minutes to reduce query load
  # Dashboard stats are already cached (1-10 min TTL), frequent UI refresh is unnecessary
  @refresh_interval 300_000
  # City-specific sources: These sources ONLY work for a single hardcoded city
  # (they don't have multi-city support in their scraper implementation)
  #
  # NOTE: Cinema City and Repertuary are NOT city-specific - they support 29+ Polish
  # cities via the "city" option in job args. They show a city dropdown in the UI.
  @city_specific_sources %{
    "karnet" => "krakow",
    "sortiraparis" => "paris",
    "waw4free" => "warsaw"
  }

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to discovery progress updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Eventasaurus.PubSub, "discovery_progress")
    end

    socket =
      socket
      |> assign(:page_title, "Discovery Dashboard")
      |> assign(:refresh_timer, nil)
      |> assign(:import_running, false)
      |> assign(:import_progress, nil)
      |> assign(:show_clear_modal, false)
      |> assign(:clear_target, nil)
      |> assign(:clear_oban_jobs, false)
      |> assign(:selected_source, nil)
      |> assign(:selected_city, nil)
      |> assign(:import_limit, 100)
      |> assign(:import_radius, 50)
      |> assign(:force_import, false)
      |> assign(:city_specific_sources, @city_specific_sources)
      |> assign(:expanded_source_jobs, MapSet.new())
      |> assign(:expanded_metro_areas, MapSet.new())
      # Venue backfill assigns
      |> assign(:backfill_city_id, nil)
      |> assign(:backfill_providers, [])
      |> assign(:backfill_limit, 10)
      |> assign(:backfill_geocode, true)
      |> assign(:backfill_running, false)
      |> assign(:image_providers, [])
      # Initialize all data as nil/loading state - will be loaded async
      |> assign(:venue_duplicates, nil)
      |> assign(:collision_summary, nil)
      |> assign(:loading, true)
      # Per-section loading states for staged loading
      |> assign(:city_stats_loading, true)
      |> assign(:collision_loading, true)
      |> assign(:venue_duplicates_loading, true)
      # Initialize with empty/default values for required assigns
      |> assign(:stats, %{
        total_events: 0,
        total_venues: 0,
        total_performers: 0,
        total_categories: 0,
        total_sources: 0
      })
      |> assign(:source_stats, [])
      |> assign(:detailed_source_stats, [])
      |> assign(:city_stats, [])
      |> assign(:cities, [])
      |> assign(:sources, [])
      |> assign(:queue_stats, [])
      |> assign(:upcoming_count, 0)
      |> assign(:past_count, 0)
      |> assign(:discovery_cities, [])

    # Defer ALL expensive data loading to after mount completes
    # This prevents mount timeout (Bad Gateway) on cold cache
    if connected?(socket) do
      send(self(), :load_initial_data)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_initial_data, socket) do
    # STAGED LOADING: Only load basic stats first to prevent OOM
    # Expensive operations (city_stats, collision_summary, venue_duplicates)
    # are loaded in separate handle_info calls to isolate memory usage
    socket =
      socket
      |> load_basic_data()
      |> assign(:loading, false)
      |> schedule_refresh()

    # Trigger staged loading of expensive operations
    # Each runs in its own handle_info to isolate memory pressure
    send(self(), :load_city_stats)

    {:noreply, socket}
  end

  @impl true
  def handle_info(:load_city_stats, socket) do
    # Load city statistics with geographic clustering
    # This is expensive on cold cache - isolate to prevent OOM cascading
    city_stats =
      try do
        get_cached(:city_stats, fn ->
          DashboardStats.get_city_statistics_with_clustering(
            &get_active_city_statistics/0,
            &get_inactive_city_statistics/0,
            20.0
          )
        end)
      rescue
        e ->
          require Logger
          Logger.error("Failed to load city stats: #{inspect(e)}")
          []
      end

    # Trigger next expensive operation
    send(self(), :load_collision_stats)

    {:noreply,
     socket
     |> assign(:city_stats, city_stats)
     |> assign(:city_stats_loading, false)}
  end

  @impl true
  def handle_info(:load_collision_stats, socket) do
    # Load collision/deduplication summary
    # This queries job_execution_summaries which can be heavy
    collision_summary =
      try do
        get_cached(:collision_summary, fn ->
          DashboardStats.get_collision_summary(24)
        end)
      rescue
        e ->
          require Logger
          Logger.error("Failed to load collision summary: #{inspect(e)}")
          nil
      end

    # Trigger next expensive operation
    send(self(), :load_venue_duplicates)

    {:noreply,
     socket
     |> assign(:collision_summary, collision_summary)
     |> assign(:collision_loading, false)}
  end

  @impl true
  def handle_info(:load_venue_duplicates, socket) do
    # Load venue duplicate statistics - using cached version
    # Wrap in try/rescue to prevent OOM from crashing the entire LiveView
    venue_duplicates =
      try do
        groups =
          case DashboardStats.get_venue_duplicates(200, 0.6) do
            {:ok, result} -> result
            {:commit, result} -> result
            _ -> []
          end

        total_venues = Repo.replica().aggregate(Venues.Venue, :count, :id)

        duplicate_count = length(groups)

        affected_venues =
          Enum.reduce(groups, 0, fn group, acc ->
            acc + length(group.venues)
          end)

        percentage =
          if total_venues > 0 do
            Float.round(affected_venues / total_venues * 100, 1)
          else
            0.0
          end

        %{
          duplicate_groups: duplicate_count,
          affected_venues: affected_venues,
          total_venues: total_venues,
          percentage: percentage
        }
      rescue
        e ->
          require Logger
          Logger.error("Failed to load venue duplicates: #{inspect(e)}")
          nil
      end

    {:noreply,
     socket
     |> assign(:venue_duplicates, venue_duplicates)
     |> assign(:venue_duplicates_loading, false)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    socket =
      socket
      |> load_data()
      |> schedule_refresh()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:discovery_progress, progress}, socket) do
    socket =
      case progress.status do
        :started ->
          socket
          |> assign(:import_running, true)
          |> assign(:import_progress, "Starting import...")

        :completed ->
          socket
          |> put_flash(:info, "Import completed: #{progress.message}")
          |> assign(:import_running, false)
          |> assign(:import_progress, nil)
          |> load_data()

        :progress ->
          socket
          |> assign(:import_running, true)
          |> assign(:import_progress, format_progress(progress))

        :error ->
          socket
          |> put_flash(:error, "Import failed: #{progress.message}")
          |> assign(:import_running, false)
          |> assign(:import_progress, nil)

        _ ->
          assign(socket, :import_progress, inspect(progress))
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("start_import", %{"source" => source} = params, socket) do
    city_id = params["city_id"]
    limit = parse_int(params["limit"], 100)
    radius = parse_int(params["radius"], 50)

    # For city-specific sources (like Karnet → Kraków), auto-set the city
    city_id_or_slug =
      if Map.has_key?(@city_specific_sources, source) do
        @city_specific_sources[source]
      else
        city_id
      end

    # Validate: source is required, city is required only for city-scoped sources (not regional/country)
    city_required =
      SourceRegistry.requires_city_id?(source) and
        not Map.has_key?(@city_specific_sources, source)

    missing_city = city_required and (is_nil(city_id_or_slug) or city_id_or_slug == "")

    if is_nil(source) or source == "" or missing_city do
      error_msg =
        if missing_city do
          "Please select a city before starting an import"
        else
          "Please select a source before starting an import"
        end

      socket = put_flash(socket, :error, error_msg)
      {:noreply, socket}
    else
      # Queue the discovery sync job
      # For city-specific sources, look up the city by slug
      city_id_result =
        if Map.has_key?(@city_specific_sources, source) do
          city_slug = @city_specific_sources[source]

          case Repo.replica().one(from(c in City, where: c.slug == ^city_slug, select: c.id)) do
            nil ->
              Logger.error("City not found for slug: #{city_slug}, source: #{source}")
              {:error, "City '#{city_slug}' not found in database. Please add it first."}

            id ->
              {:ok, id}
          end
        else
          # Parse city_id to integer if it's a numeric string
          case Integer.parse(to_string(city_id_or_slug)) do
            {i, _} -> {:ok, i}
            :error -> {:ok, city_id_or_slug}
          end
        end

      case city_id_result do
        {:error, error_message} ->
          socket = put_flash(socket, :error, error_message)
          {:noreply, socket}

        {:ok, city_id_val} ->
          force = Map.get(params, "force", false)

          # Build job_args conditionally based on whether source requires city
          job_args =
            if city_required do
              %{
                "source" => source,
                "city_id" => city_id_val,
                "limit" => limit,
                "radius" => radius,
                "force" => force
              }
            else
              # Country-wide/regional sources don't need city_id
              %{
                "source" => source,
                "limit" => limit,
                "radius" => radius,
                "force" => force
              }
            end

          case DiscoverySyncJob.new(job_args) |> Oban.insert() do
            {:ok, job} ->
              socket =
                socket
                |> put_flash(:info, "Queued import job ##{job.id} for #{source}")
                |> assign(:import_running, true)
                |> assign(:import_progress, "Queued...")

              {:noreply, socket}

            {:error, reason} ->
              socket = put_flash(socket, :error, "Failed to queue import: #{inspect(reason)}")
              {:noreply, socket}
          end
      end
    end
  end

  @impl true
  def handle_event("show_clear_modal", %{"target" => target}, socket) do
    socket =
      socket
      |> assign(:show_clear_modal, true)
      |> assign(:clear_target, target)

    {:noreply, socket}
  end

  @impl true
  def handle_event("hide_clear_modal", _params, socket) do
    socket =
      socket
      |> assign(:show_clear_modal, false)
      |> assign(:clear_target, nil)
      |> assign(:clear_oban_jobs, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_clear_oban_jobs", _params, socket) do
    socket = assign(socket, :clear_oban_jobs, !socket.assigns.clear_oban_jobs)
    {:noreply, socket}
  end

  @impl true
  def handle_event("confirm_clear", _params, socket) do
    target = socket.assigns.clear_target
    clear_oban_jobs = socket.assigns.clear_oban_jobs

    result =
      case target do
        "all" ->
          DataManager.clear_all_public_events(clear_oban_jobs: clear_oban_jobs)

        "all-future" ->
          DataManager.clear_future_public_events(clear_oban_jobs: clear_oban_jobs)

        "source:" <> source ->
          DataManager.clear_by_source(source)

        "source-future:" <> source ->
          DataManager.clear_future_by_source(source)

        "city:" <> city_id ->
          case Integer.parse(city_id) do
            {city_id_int, _} -> DataManager.clear_by_city(city_id_int)
            :error -> {:error, "Invalid city ID"}
          end

        "city-future:" <> city_id ->
          case Integer.parse(city_id) do
            {city_id_int, _} -> DataManager.clear_future_by_city(city_id_int)
            :error -> {:error, "Invalid city ID"}
          end

        _ ->
          {:error, "Unknown clear target"}
      end

    socket =
      case result do
        {:ok, count} ->
          message =
            if clear_oban_jobs do
              "Successfully cleared #{count} events and related Oban jobs"
            else
              "Successfully cleared #{count} events"
            end

          socket
          |> put_flash(:info, message)
          |> assign(:show_clear_modal, false)
          |> assign(:clear_target, nil)
          |> assign(:clear_oban_jobs, false)
          |> load_data()

        {:error, reason} ->
          socket
          |> put_flash(:error, "Failed to clear data: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("source_selected", %{"source" => source}, socket) do
    socket = assign(socket, :selected_source, source)
    {:noreply, socket}
  end

  @impl true
  def handle_event("city_selected", %{"city_id" => city_id}, socket) do
    socket = assign(socket, :selected_city, city_id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_limit", %{"limit" => limit}, socket) do
    socket = assign(socket, :import_limit, parse_int(limit, socket.assigns.import_limit))
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_radius", %{"radius" => radius}, socket) do
    socket = assign(socket, :import_radius, parse_int(radius, socket.assigns.import_radius))
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_force_import", _params, socket) do
    socket = assign(socket, :force_import, !socket.assigns.force_import)
    {:noreply, socket}
  end

  @impl true
  def handle_event("sync_now_playing", params, socket) do
    region = params["region"] || "PL"
    pages = parse_int(params["pages"] || "3", 3)

    job_args = %{
      "region" => region,
      "pages" => pages
    }

    case EventasaurusDiscovery.Jobs.SyncNowPlayingMoviesJob.new(job_args) |> Oban.insert() do
      {:ok, job} ->
        socket =
          socket
          |> put_flash(
            :info,
            "Queued TMDB Now Playing sync job ##{job.id} for region #{region} (#{pages} pages)"
          )
          |> assign(:import_running, true)
          |> assign(:import_progress, "Syncing TMDB movies...")

        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to queue TMDB sync: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_city_discovery", %{"city_id" => city_id}, socket) do
    case Integer.parse(city_id) do
      {city_id_int, _} ->
        city = Enum.find(socket.assigns.discovery_cities, &(&1.id == city_id_int))
        toggle_city_discovery_internal(city, city_id_int, socket)

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid city ID")}
    end
  end

  @impl true
  def handle_event("recalculate_coordinates", _params, socket) do
    # Queue the coordinate recalculation worker
    case EventasaurusDiscovery.Workers.CityCoordinateRecalculationWorker.new(%{})
         |> Oban.insert() do
      {:ok, job} ->
        socket =
          socket
          |> put_flash(:info, "Queued city coordinate recalculation job ##{job.id}")
          |> assign(:import_running, true)
          |> assign(:import_progress, "Recalculating city coordinates...")

        {:noreply, socket}

      {:error, reason} ->
        socket =
          put_flash(
            socket,
            :error,
            "Failed to queue coordinate recalculation: #{inspect(reason)}"
          )

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("trigger_city_discovery", %{"city_id" => city_id}, socket) do
    case Integer.parse(city_id) do
      {city_id_int, _} ->
        city = Enum.find(socket.assigns.discovery_cities, &(&1.id == city_id_int))
        trigger_city_discovery_internal(city, city_id_int, socket)

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid city ID")}
    end
  end

  @impl true
  def handle_event("toggle_source_jobs", %{"source" => source}, socket) do
    expanded = socket.assigns.expanded_source_jobs

    new_expanded =
      if MapSet.member?(expanded, source) do
        MapSet.delete(expanded, source)
      else
        MapSet.put(expanded, source)
      end

    {:noreply, assign(socket, :expanded_source_jobs, new_expanded)}
  end

  @impl true
  def handle_event("toggle_metro_area", %{"city-id" => city_id}, socket) do
    case Integer.parse(city_id) do
      {city_id_int, _} ->
        expanded = socket.assigns.expanded_metro_areas

        new_expanded =
          if MapSet.member?(expanded, city_id_int) do
            MapSet.delete(expanded, city_id_int)
          else
            MapSet.put(expanded, city_id_int)
          end

        {:noreply, assign(socket, :expanded_metro_areas, new_expanded)}

      :error ->
        # Invalid city-id, no-op gracefully
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("start_backfill", params, socket) do
    city_id = parse_int(params["city_id"], nil)
    providers = Map.get(params, "providers", [])
    limit = parse_int(params["limit"], 10)
    geocode = socket.assigns.backfill_geocode

    cond do
      is_nil(city_id) ->
        {:noreply, put_flash(socket, :error, "Please select a city")}

      Enum.empty?(providers) ->
        {:noreply, put_flash(socket, :error, "Please select at least one provider")}

      true ->
        # Enqueue backfill orchestrator job
        case BackfillOrchestratorJob.enqueue(
               city_id: city_id,
               providers: providers,
               limit: limit,
               geocode: geocode
             ) do
          {:ok, job} ->
            city = Enum.find(socket.assigns.cities, &(&1.id == city_id))
            city_name = if city, do: city.name, else: "City ##{city_id}"

            socket =
              socket
              |> put_flash(
                :info,
                "Queued venue backfill orchestrator job ##{job.id} for #{city_name} (will spawn #{limit} individual enrichment jobs, #{length(providers)} providers)"
              )
              |> assign(:backfill_running, true)

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to queue backfill: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("toggle_provider", %{"provider" => provider}, socket) do
    current_providers = socket.assigns.backfill_providers

    new_providers =
      if provider in current_providers do
        List.delete(current_providers, provider)
      else
        [provider | current_providers]
      end

    {:noreply, assign(socket, :backfill_providers, new_providers)}
  end

  @impl true
  def handle_event("update_backfill_limit", %{"limit" => limit_str}, socket) do
    limit = parse_int(limit_str, 10)
    {:noreply, assign(socket, :backfill_limit, limit)}
  end

  @impl true
  def handle_event("select_backfill_city", %{"city_id" => city_id_str}, socket) do
    city_id = parse_int(city_id_str, nil)
    {:noreply, assign(socket, :backfill_city_id, city_id)}
  end

  @impl true
  def handle_event("toggle_geocode", _params, socket) do
    {:noreply, assign(socket, backfill_geocode: !socket.assigns.backfill_geocode)}
  end

  # Private helper functions

  defp toggle_city_discovery_internal(city, city_id, socket) do
    result =
      if city && city.discovery_enabled do
        DiscoveryConfigManager.disable_city(city_id)
      else
        DiscoveryConfigManager.enable_city(city_id)
      end

    socket =
      case result do
        {:ok, _city} ->
          action = if city && city.discovery_enabled, do: "disabled", else: "enabled"

          socket
          |> put_flash(:info, "Automated discovery #{action} successfully")
          |> load_data()

        {:error, reason} ->
          put_flash(socket, :error, "Failed to update discovery: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  defp trigger_city_discovery_internal(city, city_id, socket) do
    if city do
      # Get all enabled sources for this city
      config_sources = Map.get(city.discovery_config || %{}, "sources", [])

      sources =
        (DiscoveryConfigManager.get_due_sources(city) ++ config_sources)
        |> Enum.filter(& &1["enabled"])
        |> Enum.uniq_by(& &1["name"])

      # Queue jobs for each source
      results =
        Enum.map(sources, fn source ->
          source_name = source["name"]
          source_settings = source["settings"] || %{}
          limit = source_settings["limit"] || 100

          job_args =
            EventasaurusDiscovery.Admin.SourceOptionsBuilder.build_job_args(
              source_name,
              city_id,
              limit,
              source_settings
            )

          DiscoverySyncJob.new(job_args) |> Oban.insert()
        end)

      success_count = Enum.count(results, &match?({:ok, _}, &1))

      socket =
        if success_count > 0 do
          put_flash(socket, :info, "Queued #{success_count} discovery jobs for #{city.name}")
        else
          put_flash(socket, :error, "Failed to queue discovery jobs")
        end

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "City not found")}
    end
  end

  # Load only basic/fast stats - used for initial page load
  # Expensive operations (city_stats, collision_summary, venue_duplicates)
  # are loaded separately via staged handle_info calls
  defp load_basic_data(socket) do
    # Get overall statistics from cache (shared with AdminDashboardLive)
    stats = %{
      total_events: get_cached(:total_events, &DashboardStats.get_total_events/0),
      total_venues: get_cached(:total_venues, &DashboardStats.get_unique_venues/0),
      total_performers: get_cached(:total_performers, &DashboardStats.get_unique_performers/0),
      total_categories: get_cached(:total_categories, &DashboardStats.get_total_categories/0),
      total_sources: get_cached(:total_sources, &DashboardStats.get_unique_sources/0)
    }

    # Get per-source statistics (cached)
    source_stats = get_cached(:source_stats, &DashboardStats.get_source_statistics/0)

    # Get detailed source statistics with success rates (cached)
    detailed_source_stats =
      get_cached(:detailed_source_stats, fn ->
        DashboardStats.get_detailed_source_statistics(min_events: 1)
      end)

    # Get active cities only (those with discovery enabled)
    cities =
      Repo.replica().all(
        from(c in City,
          where: c.discovery_enabled == true,
          order_by: c.name,
          preload: :country
        )
      )

    # Get available sources dynamically from SourceRegistry
    # "all" is a special option for syncing from all sources
    sources = SourceRegistry.all_sources() ++ ["all"]

    # Get queue statistics (cached)
    queue_stats = get_cached(:queue_stats, &DashboardStats.get_queue_statistics/0)

    # Get upcoming vs past events (cached)
    upcoming_count = get_cached(:upcoming_events, &DashboardStats.get_upcoming_events/0)
    past_count = get_cached(:past_events, &DashboardStats.get_past_events/0)

    # Get automated discovery cities with Oban stats
    discovery_cities =
      DiscoveryConfigManager.list_discovery_enabled_cities()
      |> Enum.map(&load_city_stats/1)

    # Get ALL image providers for backfill form (including disabled ones)
    image_providers =
      from(p in GeocodingProvider,
        where: fragment("? @> ?", p.capabilities, ^%{"images" => true}),
        order_by: [
          asc:
            fragment(
              "COALESCE(CAST(? ->> 'images' AS INTEGER), 999)",
              p.priorities
            )
        ]
      )
      |> Repo.replica().all()
      |> Enum.map(fn p ->
        %{
          name: p.name,
          display_name: format_provider_name(p.name),
          is_active: p.is_active,
          priority: get_in(p.priorities, ["images"]) || 999
        }
      end)

    socket
    |> assign(:stats, stats)
    |> assign(:source_stats, source_stats)
    |> assign(:detailed_source_stats, detailed_source_stats)
    |> assign(:cities, cities)
    |> assign(:sources, sources)
    |> assign(:queue_stats, queue_stats)
    |> assign(:upcoming_count, upcoming_count)
    |> assign(:past_count, past_count)
    |> assign(:discovery_cities, discovery_cities)
    |> assign(:image_providers, image_providers)
  end

  # Full data load - used for refresh (when cache is likely warm)
  defp load_data(socket) do
    # Get overall statistics from cache (shared with AdminDashboardLive)
    stats = %{
      total_events: get_cached(:total_events, &DashboardStats.get_total_events/0),
      total_venues: get_cached(:total_venues, &DashboardStats.get_unique_venues/0),
      total_performers: get_cached(:total_performers, &DashboardStats.get_unique_performers/0),
      total_categories: get_cached(:total_categories, &DashboardStats.get_total_categories/0),
      total_sources: get_cached(:total_sources, &DashboardStats.get_unique_sources/0)
    }

    # Get per-source statistics (cached)
    source_stats = get_cached(:source_stats, &DashboardStats.get_source_statistics/0)

    # Get detailed source statistics with success rates (cached)
    detailed_source_stats =
      get_cached(:detailed_source_stats, fn ->
        DashboardStats.get_detailed_source_statistics(min_events: 1)
      end)

    # Get per-city statistics (cached with geographic clustering)
    # On refresh, cache should be warm so this is fast
    city_stats =
      get_cached(:city_stats, fn ->
        DashboardStats.get_city_statistics_with_clustering(
          &get_active_city_statistics/0,
          &get_inactive_city_statistics/0,
          20.0
        )
      end)

    # Get active cities only (those with discovery enabled)
    cities =
      Repo.replica().all(
        from(c in City,
          where: c.discovery_enabled == true,
          order_by: c.name,
          preload: :country
        )
      )

    # Get available sources dynamically from SourceRegistry
    # "all" is a special option for syncing from all sources
    sources = SourceRegistry.all_sources() ++ ["all"]

    # Get queue statistics (cached)
    queue_stats = get_cached(:queue_stats, &DashboardStats.get_queue_statistics/0)

    # Get upcoming vs past events (cached)
    upcoming_count = get_cached(:upcoming_events, &DashboardStats.get_upcoming_events/0)
    past_count = get_cached(:past_events, &DashboardStats.get_past_events/0)

    # Get automated discovery cities with Oban stats
    discovery_cities =
      DiscoveryConfigManager.list_discovery_enabled_cities()
      |> Enum.map(&load_city_stats/1)

    # Get ALL image providers for backfill form (including disabled ones)
    image_providers =
      from(p in GeocodingProvider,
        where: fragment("? @> ?", p.capabilities, ^%{"images" => true}),
        order_by: [
          asc:
            fragment(
              "COALESCE(CAST(? ->> 'images' AS INTEGER), 999)",
              p.priorities
            )
        ]
      )
      |> Repo.replica().all()
      |> Enum.map(fn p ->
        %{
          name: p.name,
          display_name: format_provider_name(p.name),
          is_active: p.is_active,
          priority: get_in(p.priorities, ["images"]) || 999
        }
      end)

    # Get collision/deduplication metrics (last 24 hours) - cached
    # On refresh, cache should be warm so this is fast
    collision_summary =
      get_cached(:collision_summary, fn ->
        DashboardStats.get_collision_summary(24)
      end)

    socket
    |> assign(:stats, stats)
    |> assign(:source_stats, source_stats)
    |> assign(:detailed_source_stats, detailed_source_stats)
    |> assign(:city_stats, city_stats)
    |> assign(:cities, cities)
    |> assign(:sources, sources)
    |> assign(:queue_stats, queue_stats)
    |> assign(:upcoming_count, upcoming_count)
    |> assign(:past_count, past_count)
    |> assign(:discovery_cities, discovery_cities)
    |> assign(:image_providers, image_providers)
    |> assign(:collision_summary, collision_summary)
  end

  defp load_city_stats(city) do
    config = city.discovery_config || %{}
    sources = config["sources"] || []
    source_names = Enum.map(sources, & &1["name"])

    # Get real-time stats from Oban for this city
    oban_stats = DiscoveryStatsCollector.get_all_source_stats(city.id, source_names)

    # Calculate next run times based on last run + frequency
    sources_with_next_run =
      Enum.map(sources, fn source ->
        source_name = source["name"]
        frequency_hours = source["frequency_hours"] || 24
        last_run = get_in(oban_stats, [source_name, :last_run_at])

        next_run_at =
          if last_run && source["enabled"] do
            # Add frequency hours to last run time
            last_run
            |> DateTime.from_naive!("Etc/UTC")
            |> DateTime.add(frequency_hours * 3600, :second)
          else
            nil
          end

        Map.put(source, "next_run_at", next_run_at)
      end)

    # Update city with enhanced sources
    config = Map.put(config, "sources", sources_with_next_run)
    city = Map.put(city, :discovery_config, config)

    # Attach stats to city for easy template access
    Map.put(city, :oban_stats, oban_stats)
  end

  # Helper to get cached value and handle errors gracefully
  # Cachex.fetch returns:
  # - {:ok, value} when cache hit
  # - {:commit, value} when cache miss and fallback executed
  # - {:error, reason} on error
  defp get_cached(name, cache_fn) do
    case cache_fn.() do
      {:ok, value} ->
        value

      {:commit, value} ->
        value

      {:error, reason} ->
        Logger.warning("Failed to get cached stat #{name}: #{inspect(reason)}")
        # Return appropriate default based on type
        case name do
          name when name in [:source_stats, :queue_stats, :detailed_source_stats] -> []
          _ -> 0
        end
    end
  end

  # NOTE: get_city_statistics is now handled via DashboardStats.get_city_statistics_with_clustering/3
  # The helper functions below are still used by the cached version

  defp get_active_city_statistics do
    # Get all active cities with coordinates
    active_cities =
      Repo.replica().all(
        from(c in City,
          where: c.discovery_enabled == true,
          where: not is_nil(c.latitude) and not is_nil(c.longitude),
          select: %{
            id: c.id,
            name: c.name,
            latitude: c.latitude,
            longitude: c.longitude
          }
        )
      )

    # For each active city, count events within geographic radius
    Enum.flat_map(active_cities, fn city ->
      # Default radius: 20km (TODO: make configurable per city)
      radius = 20.0

      # Calculate bounding box (convert to float for Ecto query compatibility)
      city_lat = Decimal.to_float(city.latitude)
      city_lng = Decimal.to_float(city.longitude)

      lat_delta = radius / 111.0
      lng_delta = radius / (111.0 * :math.cos(city_lat * :math.pi() / 180.0))

      min_lat = city_lat - lat_delta
      max_lat = city_lat + lat_delta
      min_lng = city_lng - lng_delta
      max_lng = city_lng + lng_delta

      # Count events with venues in this radius
      count =
        Repo.replica().one(
          from(e in PublicEvent,
            join: v in EventasaurusApp.Venues.Venue,
            on: v.id == e.venue_id,
            where: not is_nil(v.latitude) and not is_nil(v.longitude),
            where: v.latitude >= ^min_lat and v.latitude <= ^max_lat,
            where: v.longitude >= ^min_lng and v.longitude <= ^max_lng,
            select: count(e.id)
          )
        ) || 0

      # Only include cities with >= 10 events
      if count >= 10 do
        [%{city_id: city.id, city_name: city.name, count: count}]
      else
        []
      end
    end)
  end

  defp get_inactive_city_statistics do
    # Get statistics for inactive cities using traditional city_id matching
    Repo.replica().all(
      from(e in PublicEvent,
        join: v in EventasaurusApp.Venues.Venue,
        on: v.id == e.venue_id,
        join: c in City,
        on: c.id == v.city_id,
        where: c.discovery_enabled == false or is_nil(c.discovery_enabled),
        group_by: [c.id, c.name],
        having: count(e.id) >= 10,
        select: %{
          city_id: c.id,
          city_name: c.name,
          count: count(e.id)
        },
        order_by: [desc: count(e.id)]
      )
    )
  end

  defp schedule_refresh(socket) do
    if connected?(socket) do
      timer = Process.send_after(self(), :refresh, @refresh_interval)
      assign(socket, :refresh_timer, timer)
    else
      socket
    end
  end

  defp format_progress(progress) do
    case progress do
      %{current: current, total: total} when is_integer(total) and total > 0 ->
        "Processing: #{current}/#{total} (#{round(current / total * 100)}%)"

      %{current: current, total: total} ->
        "Processing: #{current}/#{total}"

      %{message: message} ->
        message

      _ ->
        "Processing..."
    end
  end

  # Safe integer parsing with default
  defp parse_int(nil, default), do: default
  defp parse_int("", default), do: default
  defp parse_int(v, _default) when is_integer(v), do: v

  defp parse_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      :error -> default
    end
  end

  @doc """
  Checks if a source is country-wide or regional (doesn't require city selection).
  Uses SourceRegistry to dynamically determine scope.
  """
  def country_wide_source?(source) when is_binary(source) do
    !SourceRegistry.requires_city_id?(source)
  end

  def country_wide_source?(_), do: false

  @doc """
  Returns the coverage description for a country-wide or regional source.
  """
  def source_coverage(source) when is_binary(source) do
    case SourceRegistry.get_scope(source) do
      {:ok, :country} ->
        case source do
          "pubquiz-pl" -> "Poland"
          "inquizition" -> "United Kingdom"
          _ -> "Country-wide"
        end

      {:ok, :regional} ->
        case source do
          "question-one" -> "UK & Ireland"
          "geeks-who-drink" -> "US & Canada"
          "quizmeisters" -> "Australia"
          "speed-quizzing" -> "International (UK, US, UAE)"
          _ -> "Regional"
        end

      _ ->
        "Unknown"
    end
  end

  def source_coverage(_), do: "Unknown"

  @doc """
  Formats a number with thousand separators.
  """
  def format_number(nil), do: "0"

  def format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  def format_number(num) when is_float(num) do
    format_number(round(num))
  end

  @doc """
  Formats a datetime for display.
  """
  def format_datetime(nil), do: "Never"

  def format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %Y %I:%M %p")
  end

  def format_datetime(%NaiveDateTime{} = dt) do
    dt
    |> DateTime.from_naive!("Etc/UTC")
    |> format_datetime()
  end

  @doc """
  Formats queue names for display.
  """
  def format_queue_name(:discovery), do: "Discovery"

  def format_queue_name(queue) when is_atom(queue),
    do: queue |> to_string() |> String.capitalize()

  def format_queue_name(queue), do: String.capitalize(queue)

  @doc """
  Formats clear target for display.
  """
  def format_clear_target("all"), do: "all public event data"

  def format_clear_target("all-future"),
    do: "all future public events (preserving historical data)"

  def format_clear_target("source:" <> source), do: "all #{source} data"

  def format_clear_target("source-future:" <> source),
    do: "all future #{source} events (preserving historical data)"

  def format_clear_target("city:" <> _city_id), do: "all events for this city"

  def format_clear_target("city-future:" <> _city_id),
    do: "all future events for this city (preserving historical data)"

  def format_clear_target(_), do: "selected data"

  @doc """
  Returns CSS classes for success rate color coding.
  """
  def success_rate_color(rate) when rate >= 95, do: "bg-green-100 text-green-800"
  def success_rate_color(rate) when rate >= 80, do: "bg-yellow-100 text-yellow-800"
  def success_rate_color(_), do: "bg-red-100 text-red-800"

  @doc """
  Formats error category for display.
  """
  def format_error_category(category) do
    category
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  # Formats provider name for display
  defp format_provider_name(provider_name) do
    case provider_name do
      "google_places" -> "Google Places"
      "foursquare" -> "Foursquare"
      "here" -> "Here"
      "geoapify" -> "Geoapify"
      "unsplash" -> "Unsplash"
      name -> String.capitalize(name)
    end
  end

  # Collision/deduplication helpers
  # NOTE: get_collision_summary is now handled via DashboardStats.get_collision_summary/1

  # Severity class helpers for duplicate warnings
  defp duplicate_severity_class(percentage) when percentage >= 5.0,
    do: "border-red-500 bg-red-50"

  defp duplicate_severity_class(percentage) when percentage >= 1.0,
    do: "border-yellow-500 bg-yellow-50"

  defp duplicate_severity_class(_), do: "border-blue-500 bg-blue-50"

  defp duplicate_severity_icon_class(percentage) when percentage >= 5.0, do: "text-red-600"
  defp duplicate_severity_icon_class(percentage) when percentage >= 1.0, do: "text-yellow-600"
  defp duplicate_severity_icon_class(_), do: "text-blue-600"

  defp duplicate_severity_text_class(percentage) when percentage >= 5.0, do: "text-red-900"
  defp duplicate_severity_text_class(percentage) when percentage >= 1.0, do: "text-yellow-900"
  defp duplicate_severity_text_class(_), do: "text-blue-900"

  defp duplicate_severity_button_class(percentage) when percentage >= 5.0,
    do: "border-red-700 text-red-900 bg-red-100 hover:bg-red-200"

  defp duplicate_severity_button_class(percentage) when percentage >= 1.0,
    do: "border-yellow-700 text-yellow-900 bg-yellow-100 hover:bg-yellow-200"

  defp duplicate_severity_button_class(_),
    do: "border-blue-700 text-blue-900 bg-blue-100 hover:bg-blue-200"
end
