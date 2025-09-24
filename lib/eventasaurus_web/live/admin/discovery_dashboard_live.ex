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
  alias EventasaurusDiscovery.Admin.{DataManager, DiscoverySyncJob}
  alias EventasaurusDiscovery.Categories.Category

  import Ecto.Query
  require Logger

  @refresh_interval 5000

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
          assign(socket, :import_progress, "Starting import...")

        :completed ->
          socket
          |> put_flash(:info, "Import completed: #{progress.message}")
          |> assign(:import_running, false)
          |> assign(:import_progress, nil)
          |> load_data()

        :progress ->
          assign(socket, :import_progress, format_progress(progress))

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
    limit = String.to_integer(params["limit"] || "100")
    radius = String.to_integer(params["radius"] || "50")

    # Queue the discovery sync job
    job_args = %{
      "source" => source,
      "city_id" => city_id,
      "limit" => limit,
      "radius" => radius
    }

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

        "source:" <> source ->
          DataManager.clear_by_source(source)

        "city:" <> city_id ->
          DataManager.clear_by_city(String.to_integer(city_id))

        _ ->
          {:error, "Unknown clear target"}
      end

    socket =
      case result do
        {:ok, count} ->
          message = if clear_oban_jobs do
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
    socket = assign(socket, :import_limit, String.to_integer(limit))
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_radius", %{"radius" => radius}, socket) do
    socket = assign(socket, :import_radius, String.to_integer(radius))
    {:noreply, socket}
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
    cities = Repo.all(from c in City, order_by: c.name, preload: :country)

    # Get available sources
    sources = ["ticketmaster", "bandsintown", "karnet", "all"]

    # Get queue statistics
    queue_stats = get_queue_statistics()

    # Get upcoming vs past events
    today = DateTime.utc_now()
    upcoming_count = Repo.aggregate(
      from(e in PublicEvent, where: e.starts_at >= ^today),
      :count
    )
    past_count = Repo.aggregate(
      from(e in PublicEvent, where: e.starts_at < ^today),
      :count
    )

    socket
    |> assign(:stats, stats)
    |> assign(:source_stats, source_stats)
    |> assign(:city_stats, city_stats)
    |> assign(:cities, cities)
    |> assign(:sources, sources)
    |> assign(:queue_stats, queue_stats)
    |> assign(:upcoming_count, upcoming_count)
    |> assign(:past_count, past_count)
  end

  defp count_unique_venues do
    Repo.one(
      from e in PublicEvent,
        where: not is_nil(e.venue_id),
        select: count(e.venue_id, :distinct)
    ) || 0
  end

  defp count_unique_performers do
    # Count distinct performers from the performers association
    Repo.one(
      from pep in EventasaurusDiscovery.PublicEvents.PublicEventPerformer,
        select: count(pep.performer_id, :distinct)
    ) || 0
  end

  defp count_unique_sources do
    Repo.one(
      from s in PublicEventSource,
        select: count(s.source_id, :distinct)
    ) || 0
  end

  defp get_source_statistics do
    Repo.all(
      from pes in PublicEventSource,
        join: e in PublicEvent, on: e.id == pes.event_id,
        join: s in EventasaurusDiscovery.Sources.Source, on: s.id == pes.source_id,
        group_by: [s.id, s.name],
        select: %{
          source: s.name,
          count: count(pes.id),
          last_sync: max(pes.inserted_at)
        },
        order_by: [desc: count(pes.id)]
    )
  end

  defp get_city_statistics do
    Repo.all(
      from e in PublicEvent,
        join: v in EventasaurusApp.Venues.Venue, on: v.id == e.venue_id,
        join: c in City, on: c.id == v.city_id,
        group_by: [c.id, c.name],
        having: count(e.id) >= 10,
        select: %{
          city_id: c.id,
          city_name: c.name,
          count: count(e.id)
        },
        order_by: [desc: count(e.id)]
    )
  end

  defp get_queue_statistics do
    queues = [:discovery_sync, :discovery_import]

    Enum.map(queues, fn queue ->
      available =
        Repo.aggregate(
          from(j in Oban.Job, where: j.queue == ^to_string(queue) and j.state == "available"),
          :count
        )

      executing =
        Repo.aggregate(
          from(j in Oban.Job, where: j.queue == ^to_string(queue) and j.state == "executing"),
          :count
        )

      completed =
        Repo.aggregate(
          from(j in Oban.Job, where: j.queue == ^to_string(queue) and j.state == "completed"),
          :count
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
      %{current: current, total: total} ->
        "Processing: #{current}/#{total} (#{round(current / total * 100)}%)"

      %{message: message} ->
        message

      _ ->
        "Processing..."
    end
  end

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
  def format_clear_target("source:" <> source), do: "all #{source} data"
  def format_clear_target("city:" <> _city_id), do: "all events for this city"
  def format_clear_target(_), do: "selected data"
end