defmodule EventasaurusWeb.Admin.DiscoveryDashboardLive do
  @moduledoc """
  Admin dashboard for managing public event discovery and synchronization.
  Allows admins to trigger imports, view statistics, and manage discovery data.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource
  alias EventasaurusDiscovery.Locations.City

  alias EventasaurusDiscovery.Admin.{
    DataManager,
    DiscoverySyncJob,
    DiscoveryConfigManager,
    DiscoveryStatsCollector
  }

  alias EventasaurusDiscovery.Categories.Category
  alias EventasaurusDiscovery.Sources.SourceRegistry

  import Ecto.Query
  require Logger

  @refresh_interval 5000
  @city_specific_sources %{
    "karnet" => "krakow",
    "kino-krakow" => "krakow",
    "cinema-city" => "krakow"
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
      |> assign(:city_specific_sources, @city_specific_sources)
      |> load_data()
      |> schedule_refresh()

    {:ok, socket}
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
      SourceRegistry.requires_city_id?(source) and not Map.has_key?(@city_specific_sources, source)

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

          case Repo.one(from(c in City, where: c.slug == ^city_slug, select: c.id)) do
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
          # Build job_args conditionally based on whether source requires city
          job_args =
            if city_required do
              %{
                "source" => source,
                "city_id" => city_id_val,
                "limit" => limit,
                "radius" => radius
              }
            else
              # Country-wide/regional sources don't need city_id
              %{
                "source" => source,
                "limit" => limit,
                "radius" => radius
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
          DataManager.clear_by_city(String.to_integer(city_id))

        "city-future:" <> city_id ->
          DataManager.clear_future_by_city(String.to_integer(city_id))

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
    city_id = String.to_integer(city_id)
    city = Enum.find(socket.assigns.discovery_cities, &(&1.id == city_id))

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

  @impl true
  def handle_event("trigger_city_discovery", %{"city_id" => city_id}, socket) do
    city_id = String.to_integer(city_id)
    city = Enum.find(socket.assigns.discovery_cities, &(&1.id == city_id))

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

  defp load_data(socket) do
    # Get overall statistics
    stats = %{
      total_events: Repo.aggregate(PublicEvent, :count, :id),
      total_venues: count_unique_venues(),
      total_performers: count_unique_performers(),
      total_categories: Repo.aggregate(Category, :count, :id),
      total_sources: count_unique_sources()
    }

    # Get per-source statistics
    source_stats = get_source_statistics()

    # Get per-city statistics
    city_stats = get_city_statistics()

    # Get available cities
    cities = Repo.all(from(c in City, order_by: c.name, preload: :country))

    # Get available sources
    sources = [
      "ticketmaster",
      "bandsintown",
      "resident-advisor",
      "karnet",
      "kino-krakow",
      "cinema-city",
      "pubquiz-pl",
      "question-one",
      "all"
    ]

    # Get queue statistics
    queue_stats = get_queue_statistics()

    # Get upcoming vs past events
    today = DateTime.utc_now()

    upcoming_count =
      Repo.aggregate(
        from(e in PublicEvent, where: e.starts_at >= ^today),
        :count,
        :id
      )

    past_count =
      Repo.aggregate(
        from(e in PublicEvent, where: e.starts_at < ^today),
        :count,
        :id
      )

    # Get automated discovery cities with Oban stats
    discovery_cities =
      DiscoveryConfigManager.list_discovery_enabled_cities()
      |> Enum.map(&load_city_stats/1)

    socket
    |> assign(:stats, stats)
    |> assign(:source_stats, source_stats)
    |> assign(:city_stats, city_stats)
    |> assign(:cities, cities)
    |> assign(:sources, sources)
    |> assign(:queue_stats, queue_stats)
    |> assign(:upcoming_count, upcoming_count)
    |> assign(:past_count, past_count)
    |> assign(:discovery_cities, discovery_cities)
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

  defp count_unique_venues do
    Repo.one(
      from(e in PublicEvent,
        where: not is_nil(e.venue_id),
        select: count(e.venue_id, :distinct)
      )
    ) || 0
  end

  defp count_unique_performers do
    # Count distinct performers from the performers association
    Repo.one(
      from(pep in EventasaurusDiscovery.PublicEvents.PublicEventPerformer,
        select: count(pep.performer_id, :distinct)
      )
    ) || 0
  end

  defp count_unique_sources do
    Repo.one(
      from(s in PublicEventSource,
        select: count(s.source_id, :distinct)
      )
    ) || 0
  end

  defp get_source_statistics do
    Repo.all(
      from(pes in PublicEventSource,
        join: e in PublicEvent,
        on: e.id == pes.event_id,
        join: s in EventasaurusDiscovery.Sources.Source,
        on: s.id == pes.source_id,
        group_by: [s.id, s.name],
        select: %{
          source: s.name,
          count: count(pes.id),
          last_sync: max(pes.inserted_at)
        },
        order_by: [desc: count(pes.id)]
      )
    )
  end

  defp get_city_statistics do
    Repo.all(
      from(e in PublicEvent,
        join: v in EventasaurusApp.Venues.Venue,
        on: v.id == e.venue_id,
        join: c in City,
        on: c.id == v.city_id,
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

  defp get_queue_statistics do
    queues = [:discovery_sync, :discovery_import]

    Enum.map(queues, fn queue ->
      available =
        Repo.aggregate(
          from(j in Oban.Job, where: j.queue == ^to_string(queue) and j.state == "available"),
          :count,
          :id
        )

      executing =
        Repo.aggregate(
          from(j in Oban.Job, where: j.queue == ^to_string(queue) and j.state == "executing"),
          :count,
          :id
        )

      completed =
        Repo.aggregate(
          from(j in Oban.Job, where: j.queue == ^to_string(queue) and j.state == "completed"),
          :count,
          :id
        )

      %{
        name: queue,
        available: available,
        executing: executing,
        completed: completed
      }
    end)
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
          _ -> "Country-wide"
        end

      {:ok, :regional} ->
        case source do
          "question-one" -> "UK & Ireland"
          "geeks-who-drink" -> "US & Canada"
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
  def format_queue_name(:discovery_sync), do: "Discovery Sync"
  def format_queue_name(:discovery_import), do: "Discovery Import"

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
end
