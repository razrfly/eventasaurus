defmodule EventasaurusWeb.Admin.VenueCountryMismatchesLive do
  @moduledoc """
  Admin page for reviewing and fixing venue country mismatches.

  Features:
  - Dashboard with summary stats and country pair breakdown
  - Paginated list of mismatches with filtering
  - Fix individual mismatches (reassign to correct country)
  - Ignore false positives
  - Bulk fix HIGH confidence mismatches
  - Background job processing with cached results in venue metadata

  Phase 2 architecture: Uses Oban background job (VenueCountryCheckJob) to process
  venues and store results in venue.metadata["country_check"]. The page reads
  cached results for fast loading.
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusDiscovery.Admin.DataQualityChecker
  alias EventasaurusDiscovery.Admin.VenueCountryCheckJob
  alias EventasaurusDiscovery.Admin.VenueCountryFixJob

  @default_limit 50
  @pubsub_topic "venue_country_check"
  @fix_pubsub_topic "venue_country_fix"

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to job progress updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Eventasaurus.PubSub, @pubsub_topic)
      Phoenix.PubSub.subscribe(Eventasaurus.PubSub, @fix_pubsub_topic)
    end

    socket =
      socket
      |> assign(:page_title, "Venue Country Mismatches")
      |> assign(:filters, %{
        source: nil,
        from_country: nil,
        to_country: nil,
        confidence: nil
      })
      |> assign(:limit, @default_limit)
      |> assign(:active_tab, "dashboard")
      |> assign(:bulk_fixing, false)
      |> assign(:check_running, false)
      |> assign(:data_loaded, false)
      |> assign(:sources, [])
      |> assign(:country_pairs, [])
      |> assign(:last_check_stats, nil)

    # Auto-load if we have existing data and connected
    # This provides a better UX: page shows data immediately if available
    socket =
      if connected?(socket) and has_country_check_data?() do
        socket
        |> assign(:data_loaded, true)
        |> start_async_load()
      else
        socket
      end

    {:ok, socket}
  end

  # Check if there's any country_check data in venues
  defp has_country_check_data? do
    import Ecto.Query
    alias EventasaurusApp.Repo
    alias EventasaurusApp.Venues.Venue

    query =
      from(v in Venue,
        where: not is_nil(fragment("?->'country_check'", v.metadata)),
        limit: 1,
        select: 1
      )

    Repo.replica().exists?(query)
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Just update filters, NO database queries
    filters = %{
      source: params["source"],
      from_country: params["from"],
      to_country: params["to"],
      confidence: parse_confidence(params["confidence"])
    }

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:limit, parse_limit(params["limit"]))

    {:noreply, socket}
  end

  # Start async loading of mismatch data
  defp start_async_load(socket) do
    filters = socket.assigns.filters
    limit = socket.assigns.limit

    assign_async(socket, :mismatch_data, fn ->
      load_mismatch_data(filters, limit)
    end)
  end

  # Async data loading function - reads from cached venue metadata
  defp load_mismatch_data(filters, limit) do
    # Build options for fetching mismatches from venue metadata
    options =
      [limit: limit, status: "pending"]
      |> maybe_add_filter(:confidence, filters.confidence && Atom.to_string(filters.confidence))

    # Fetch mismatches from venue metadata (fast - just reads cached data)
    mismatches = VenueCountryCheckJob.get_mismatches(options)

    # Get last check stats for the header
    stats = VenueCountryCheckJob.get_last_check_stats()

    # Transform venue records to mismatch maps for template compatibility
    transformed_mismatches =
      mismatches
      |> Enum.map(&transform_venue_to_mismatch/1)
      |> filter_by_source(filters.source)
      |> filter_by_from_country(filters.from_country)
      |> filter_by_to_country(filters.to_country)

    # Build confidence breakdown
    by_confidence =
      transformed_mismatches
      |> Enum.group_by(& &1.confidence)
      |> Enum.map(fn {k, v} -> {k, length(v)} end)
      |> Enum.into(%{})

    # Build country pair breakdown
    by_country_pair =
      transformed_mismatches
      |> Enum.group_by(fn m -> {m.current_country, m.expected_country} end)
      |> Enum.map(fn {k, v} -> {k, length(v)} end)
      |> Enum.into(%{})

    result = %{
      total_checked: stats[:total_checked] || 0,
      mismatch_count: length(transformed_mismatches),
      mismatches: transformed_mismatches,
      by_confidence: by_confidence,
      by_country_pair: by_country_pair,
      last_checked: stats[:last_checked]
    }

    # Get unique sources and country pairs for filter dropdowns
    sources = get_unique_sources(transformed_mismatches)
    country_pairs = get_country_pairs(by_country_pair)

    # assign_async expects the key to match what was registered (:mismatch_data)
    {:ok,
     %{
       mismatch_data: %{
         result: result,
         sources: sources,
         country_pairs: country_pairs,
         stats: stats
       }
     }}
  end

  # Transform a venue with metadata to the mismatch map format expected by template
  defp transform_venue_to_mismatch(venue) do
    check = venue.metadata["country_check"] || %{}

    %{
      venue_id: venue.id,
      venue_name: venue.name,
      venue_slug: venue.slug,
      latitude: venue.latitude,
      longitude: venue.longitude,
      # Two separate source fields:
      # 1. geocoding_source - where the GPS coordinates came from (mapbox, here, geoapify, etc.)
      geocoding_source: venue.source,
      # 2. scraper_source - which scraper created events for this venue (speed-quizzing, etc.)
      scraper_source: check["scraper_source"],
      current_country: check["current_country"],
      current_city: check["current_city"],
      expected_country: check["expected_country"],
      expected_city: check["expected_city"],
      confidence: parse_confidence_atom(check["confidence"]),
      checked_at: check["checked_at"]
    }
  end

  defp parse_confidence_atom("high"), do: :high
  defp parse_confidence_atom("medium"), do: :medium
  defp parse_confidence_atom("low"), do: :low
  defp parse_confidence_atom(_), do: nil

  defp filter_by_source(mismatches, nil), do: mismatches

  # Filter by scraper_source (which scraper created the events)
  defp filter_by_source(mismatches, source) do
    Enum.filter(mismatches, &(&1.scraper_source == source))
  end

  defp filter_by_from_country(mismatches, nil), do: mismatches

  defp filter_by_from_country(mismatches, from_country) do
    Enum.filter(mismatches, &(&1.current_country == from_country))
  end

  @impl true
  def handle_event("load_data", _params, socket) do
    # User explicitly requested to load data - now we can query
    socket =
      socket
      |> assign(:data_loaded, true)
      |> start_async_load()
      |> put_flash(:info, "Loading mismatch data...")

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    # Only refresh if data was already loaded
    if socket.assigns.data_loaded do
      socket =
        socket
        |> start_async_load()
        |> put_flash(:info, "Refreshing mismatch data...")

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :info, "Click 'Load Data' first to view mismatches")}
    end
  end

  @impl true
  def handle_event("run_check", _params, socket) do
    case VenueCountryCheckJob.queue_check() do
      {:ok, _job} ->
        socket =
          socket
          |> assign(:check_running, true)
          |> put_flash(:info, "Country check job queued. Processing venues in background...")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to queue check: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters = %{
      source: blank_to_nil(params["source"]),
      from_country: blank_to_nil(params["from_country"]),
      to_country: blank_to_nil(params["to_country"]),
      confidence: parse_confidence(params["confidence"])
    }

    socket = assign(socket, :filters, filters)

    # Only reload if data was already loaded
    socket =
      if socket.assigns.data_loaded do
        start_async_load(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    socket =
      assign(socket, :filters, %{source: nil, from_country: nil, to_country: nil, confidence: nil})

    # Only reload if data was already loaded
    socket =
      if socket.assigns.data_loaded do
        start_async_load(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("fix_venue", %{"venue_id" => venue_id_str}, socket) do
    venue_id = String.to_integer(venue_id_str)

    case DataQualityChecker.fix_venue_country(venue_id) do
      {:ok, fix_result} ->
        socket =
          socket
          |> put_flash(
            :info,
            "Fixed venue: #{fix_result.venue.name} moved from #{fix_result.old_country} to #{fix_result.new_country}"
          )
          |> start_async_load()

        {:noreply, socket}

      {:error, reason} ->
        error_msg = format_error(reason)
        {:noreply, put_flash(socket, :error, "Failed to fix venue: #{error_msg}")}
    end
  end

  @impl true
  def handle_event("ignore_venue", %{"venue_id" => venue_id_str}, socket) do
    venue_id = String.to_integer(venue_id_str)

    case DataQualityChecker.ignore_venue_country_mismatch(venue_id) do
      {:ok, _venue} ->
        socket =
          socket
          |> put_flash(:info, "Venue marked as ignored (false positive)")
          |> start_async_load()

        {:noreply, socket}

      {:error, reason} ->
        error_msg = format_error(reason)
        {:noreply, put_flash(socket, :error, "Failed to ignore venue: #{error_msg}")}
    end
  end

  @impl true
  def handle_event("bulk_fix", _params, socket) do
    filters = socket.assigns.filters

    options = [
      confidence: :high,
      from_country: filters.from_country,
      to_country: filters.to_country,
      limit: @default_limit
    ]

    # Note: queue_bulk_fix always returns {:ok, %{queued: count, venue_ids: [...]}}
    case VenueCountryFixJob.queue_bulk_fix(options) do
      {:ok, %{queued: 0}} ->
        {:noreply, put_flash(socket, :info, "No venues to fix")}

      {:ok, %{queued: count}} ->
        socket =
          socket
          |> assign(:bulk_fixing, true)
          |> put_flash(:info, "Queued #{count} venue fix jobs. Processing in background...")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("export_json", _params, socket) do
    # Generate export data - only if we have loaded data
    case socket.assigns.mismatch_data do
      %{ok?: true} ->
        export_data = DataQualityChecker.export_venue_country_report(limit: 1000)
        json = Jason.encode!(export_data, pretty: true)

        {:noreply,
         push_event(socket, "download", %{
           filename: "venue_country_mismatches_#{Date.utc_today()}.json",
           content: json,
           content_type: "application/json"
         })}

      _ ->
        {:noreply, put_flash(socket, :error, "No data to export - please wait for data to load")}
    end
  end

  # Handle PubSub messages from the background job
  @impl true
  def handle_info({:venue_country_check_progress, %{status: :completed} = stats}, socket) do
    socket =
      socket
      |> assign(:check_running, false)
      |> assign(:last_check_stats, stats)
      |> start_async_load()
      |> put_flash(:info, "Country check completed! Processed #{stats[:processed] || 0} venues.")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:venue_country_check_progress, %{status: :started}}, socket) do
    {:noreply, assign(socket, :check_running, true)}
  end

  @impl true
  def handle_info({:venue_country_check_progress, _progress}, socket) do
    # Intermediate progress updates - could add progress bar later
    {:noreply, socket}
  end

  # Handle PubSub messages from the venue fix job
  @impl true
  def handle_info({:venue_country_fix_progress, %{status: :queued, total: total}}, socket) do
    socket =
      socket
      |> assign(:bulk_fixing, true)
      |> assign(:fix_progress, %{total: total, fixed: 0, failed: 0})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:venue_country_fix_progress, %{status: :fixed}}, socket) do
    progress = socket.assigns[:fix_progress] || %{total: 0, fixed: 0, failed: 0}
    new_progress = Map.update!(progress, :fixed, &(&1 + 1))

    socket = assign(socket, :fix_progress, new_progress)

    # Check if all jobs completed
    if new_progress.fixed + new_progress.failed >= new_progress.total do
      socket =
        socket
        |> assign(:bulk_fixing, false)
        |> put_flash(
          :info,
          "Bulk fix complete: #{new_progress.fixed} fixed, #{new_progress.failed} failed"
        )
        |> start_async_load()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:venue_country_fix_progress, %{status: :failed}}, socket) do
    progress = socket.assigns[:fix_progress] || %{total: 0, fixed: 0, failed: 0}
    new_progress = Map.update!(progress, :failed, &(&1 + 1))

    socket = assign(socket, :fix_progress, new_progress)

    # Check if all jobs completed
    if new_progress.fixed + new_progress.failed >= new_progress.total do
      socket =
        socket
        |> assign(:bulk_fixing, false)
        |> put_flash(
          :info,
          "Bulk fix complete: #{new_progress.fixed} fixed, #{new_progress.failed} failed"
        )
        |> start_async_load()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(_msg, socket) do
    # Catch-all for any other messages
    {:noreply, socket}
  end

  # Private functions

  defp maybe_add_filter(options, _key, nil), do: options
  defp maybe_add_filter(options, key, value), do: [{key, value} | options]

  defp filter_by_to_country(mismatches, nil), do: mismatches

  defp filter_by_to_country(mismatches, to_country) do
    Enum.filter(mismatches, &(&1.expected_country == to_country))
  end

  # Get unique scraper sources for the filter dropdown
  defp get_unique_sources(mismatches) do
    mismatches
    |> Enum.map(& &1.scraper_source)
    |> Enum.uniq()
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
  end

  defp get_country_pairs(by_country_pair) do
    by_country_pair
    |> Enum.map(fn {{from, to}, count} -> %{from: from, to: to, count: count} end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  defp parse_confidence(nil), do: nil
  defp parse_confidence(""), do: nil
  defp parse_confidence("high"), do: :high
  defp parse_confidence("medium"), do: :medium
  defp parse_confidence("low"), do: :low
  defp parse_confidence(_), do: nil

  defp parse_limit(nil), do: @default_limit

  defp parse_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {n, _} when n > 0 -> n
      _ -> @default_limit
    end
  end

  defp parse_limit(limit) when is_integer(limit) and limit > 0, do: limit
  defp parse_limit(_), do: @default_limit

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp format_error(:venue_not_found), do: "Venue not found"
  defp format_error(:no_coordinates), do: "Venue has no GPS coordinates"
  defp format_error(:not_a_mismatch), do: "Venue is not a mismatch"
  defp format_error({:geocoding_failed, reason}), do: "Geocoding failed: #{inspect(reason)}"

  defp format_error({:city_creation_failed, reason}),
    do: "City creation failed: #{inspect(reason)}"

  defp format_error({:update_failed, _}), do: "Database update failed"
  defp format_error(reason), do: inspect(reason)

  # Helper functions for template
  def confidence_color(:high), do: "bg-green-100 text-green-800"
  def confidence_color(:medium), do: "bg-yellow-100 text-yellow-800"
  def confidence_color(:low), do: "bg-red-100 text-red-800"
  def confidence_color(_), do: "bg-gray-100 text-gray-800"

  def confidence_label(:high), do: "HIGH"
  def confidence_label(:medium), do: "MEDIUM"
  def confidence_label(:low), do: "LOW"
  def confidence_label(_), do: "UNKNOWN"

  def format_coords(lat, lng) when is_float(lat) and is_float(lng) do
    "#{Float.round(lat, 4)}, #{Float.round(lng, 4)}"
  end

  def format_coords(_, _), do: "N/A"

  def truncate(str, max_len) when is_binary(str) and max_len >= 4 do
    if String.length(str) > max_len do
      String.slice(str, 0, max_len - 3) <> "..."
    else
      str
    end
  end

  def truncate(str, max_len) when is_binary(str) and max_len < 4 do
    String.slice(str, 0, max_len)
  end

  def truncate(str, _max_len), do: str

  def format_time_ago(nil), do: "Never"

  def format_time_ago(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, dt, _offset} -> format_time_ago(dt)
      _ -> "Unknown"
    end
  end

  def format_time_ago(%DateTime{} = datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 -> "Just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)} min ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)} hours ago"
      diff_seconds < 604_800 -> "#{div(diff_seconds, 86400)} days ago"
      true -> Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
    end
  end

  def format_time_ago(_), do: "Unknown"
end
