defmodule EventasaurusWeb.Admin.VenueImageEnrichmentHistoryLive do
  @moduledoc """
  Unified venue image enrichment history dashboard.

  Provides comprehensive view of all venue image operations including:
  - Tabbed interface (All, City Backfills, Individual Venues, Partial Failures, Failed Only)
  - Both BackfillOrchestratorJob (city-wide) and EnrichmentJob (individual venue) operations
  - Partial failure detection for venues with mixed success/failure
  - Advanced filtering (provider, status, date range, city)
  - Granular retry controls (venue-level and per-image)
  - Real-time updates via Phoenix PubSub
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusApp.Venues.Venue
  alias EventasaurusDiscovery.VenueImages.{CleanupScheduler, FailedUploadRetryWorker}
  import Ecto.Query
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to PubSub for real-time updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Eventasaurus.PubSub, "venue_image_operations")
    end

    socket =
      socket
      |> assign(:page_title, "Venue Image Enrichment History")
      |> assign(:active_tab, :all)
      |> assign(:provider_filter, :all)
      |> assign(:status_filter, :all)
      |> assign(:city_filter, :all)
      |> assign(:date_filter, :all_time)
      |> assign(:expanded_job_ids, MapSet.new())
      |> assign(:show_clear_cache_modal, false)
      |> assign(:loading, true)
      |> load_cities()
      |> load_operations()
      |> assign(:loading, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    tab_atom =
      case tab do
        "all" -> :all
        "city_backfills" -> :city_backfills
        "individual_venues" -> :individual_venues
        "partial_failures" -> :partial_failures
        "failed_only" -> :failed_only
        _ -> :all
      end

    {:noreply, socket |> assign(:active_tab, tab_atom) |> load_operations()}
  end

  @impl true
  def handle_event("filter_change", params, socket) do
    # Parse provider filter
    provider_filter =
      case Map.get(params, "provider", "all") do
        "all" -> :all
        other -> other
      end

    # Parse status filter
    status_filter =
      case Map.get(params, "status", "all") do
        "all" -> :all
        other -> other
      end

    # Parse city filter
    city_filter =
      case Map.get(params, "city", "all") do
        "all" ->
          :all

        other ->
          case Integer.parse(other) do
            {id, ""} -> id
            _ -> :all
          end
      end

    # Parse date filter
    date_filter =
      case Map.get(params, "date", "all_time") do
        "all_time" -> :all_time
        "today" -> :today
        "week" -> :week
        "month" -> :month
        _ -> :all_time
      end

    # Apply all filters and reload operations
    socket
    |> assign(:provider_filter, provider_filter)
    |> assign(:status_filter, status_filter)
    |> assign(:city_filter, city_filter)
    |> assign(:date_filter, date_filter)
    |> load_operations()
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_event("toggle_job_details", %{"job_id" => job_id_str}, socket) do
    expanded_job_ids = socket.assigns.expanded_job_ids

    updated_expanded_job_ids =
      if MapSet.member?(expanded_job_ids, job_id_str) do
        MapSet.delete(expanded_job_ids, job_id_str)
      else
        MapSet.put(expanded_job_ids, job_id_str)
      end

    {:noreply, assign(socket, :expanded_job_ids, updated_expanded_job_ids)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_operations(socket)}
  end

  @impl true
  def handle_event("retry_all_failed", _params, socket) do
    case CleanupScheduler.enqueue() do
      {:ok, _job} ->
        socket =
          socket
          |> put_flash(
            :info,
            "✅ Batch retry queued - will scan all venues and retry transient failures"
          )
          |> load_operations()

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> put_flash(:error, "❌ Failed to enqueue batch retry: #{inspect(reason)}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("retry_venue", %{"venue_id" => venue_id_str}, socket) do
    case Integer.parse(venue_id_str) do
      {venue_id, ""} ->
        case FailedUploadRetryWorker.enqueue_venue(venue_id) do
          {:ok, _job} ->
            socket =
              socket
              |> put_flash(:info, "✅ Retry queued for venue ##{venue_id}")
              |> load_operations()

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "❌ Failed to enqueue retry: #{inspect(reason)}")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "❌ Invalid venue ID")}
    end
  end

  @impl true
  def handle_event("retry_venue_images", %{"venue_id" => venue_id_str, "image_indexes" => indexes_json}, socket) do
    case Integer.parse(venue_id_str) do
      {venue_id, ""} ->
        case Jason.decode(indexes_json) do
          {:ok, indexes} when is_list(indexes) ->
            # Validate and sanitize image indexes
            parsed =
              indexes
              |> Enum.map(fn
                i when is_integer(i) and i >= 0 -> {:ok, i}
                s when is_binary(s) ->
                  case Integer.parse(String.trim(s)) do
                    {i, ""} when i >= 0 -> {:ok, i}
                    _ -> :error
                  end
                _ -> :error
              end)

            if Enum.any?(parsed, &(&1 == :error)) do
              {:noreply, put_flash(socket, :error, "❌ Image indexes must be non-negative integers")}
            else
              validated_indexes =
                parsed
                |> Enum.map(fn {:ok, i} -> i end)
                |> Enum.uniq()
                |> Enum.take(200) # Safety bound to prevent abuse

              case FailedUploadRetryWorker.enqueue_venue_images(venue_id, validated_indexes) do
                {:ok, _job} ->
                  socket =
                    socket
                    |> put_flash(:info, "✅ Retry queued for #{length(validated_indexes)} images from venue ##{venue_id}")
                    |> load_operations()

                  {:noreply, socket}

                {:error, reason} ->
                  {:noreply, put_flash(socket, :error, "❌ Failed to enqueue retry: #{inspect(reason)}")}
              end
            end

          _ ->
            {:noreply, put_flash(socket, :error, "❌ Invalid image indexes JSON")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "❌ Invalid venue ID")}
    end
  end

  @impl true
  def handle_event("show_clear_cache_modal", _params, socket) do
    {:noreply, assign(socket, :show_clear_cache_modal, true)}
  end

  @impl true
  def handle_event("hide_clear_cache_modal", _params, socket) do
    {:noreply, assign(socket, :show_clear_cache_modal, false)}
  end

  @impl true
  def handle_event("clear_image_cache", %{"city_id" => city_id_str}, socket) do
    # Build query based on city filter
    query = from(v in Venue)

    {query, scope_description} =
      case city_id_str do
        "all" ->
          {query, "ALL cities"}

        city_id_str when is_binary(city_id_str) ->
          case Integer.parse(city_id_str) do
            {city_id, ""} ->
              city = Enum.find(socket.assigns.cities, fn c -> c.id == city_id end)
              city_name = if city, do: city.name, else: "Unknown"

              query = from(v in query, where: v.city_id == ^city_id)
              {query, city_name}

            _ ->
              {query, "ALL cities"}
          end
      end

    # Clear venue_images and image_enrichment_metadata
    {count, _} =
      Repo.update_all(query,
        set: [
          venue_images: nil,
          image_enrichment_metadata: nil
        ]
      )

    Logger.info("🗑️ Cleared image cache for #{count} venues in #{scope_description}")

    socket =
      socket
      |> put_flash(:info, "🗑️ Cleared image cache for #{count} venues in #{scope_description}")
      |> assign(:show_clear_cache_modal, false)
      |> load_operations()

    {:noreply, socket}
  end

  # PubSub handler for real-time updates
  @impl true
  def handle_info({:venue_image_operation_update, _operation}, socket) do
    {:noreply, load_operations(socket)}
  end

  defp load_cities(socket) do
    cities =
      Repo.all(
        from c in City,
          where: c.discovery_enabled == true,
          order_by: c.name,
          select: %{id: c.id, name: c.name}
      )

    assign(socket, :cities, cities)
  end

  defp load_operations(socket) do
    tab = socket.assigns.active_tab
    provider_filter = socket.assigns.provider_filter
    status_filter = socket.assigns.status_filter
    city_filter = socket.assigns.city_filter
    date_filter = socket.assigns.date_filter

    operations = get_operations(tab, provider_filter, status_filter, city_filter, date_filter)

    # Extract unique providers for filter dropdown
    providers =
      operations
      |> Enum.flat_map(fn op -> op.providers end)
      |> Enum.uniq()
      |> Enum.sort()

    socket
    |> assign(:operations, operations)
    |> assign(:providers, providers)
  end

  defp get_operations(tab, provider_filter, status_filter, city_filter, date_filter) do
    base_query =
      from(j in "oban_jobs",
        where:
          j.worker in [
            "EventasaurusDiscovery.VenueImages.BackfillOrchestratorJob",
            "EventasaurusDiscovery.VenueImages.EnrichmentJob"
          ],
        where: j.state in ["completed", "discarded"],
        where: not is_nil(j.completed_at),
        order_by: [desc: j.completed_at],
        limit: 100,
        select: %{
          id: j.id,
          completed_at: j.completed_at,
          attempted_at: j.attempted_at,
          state: j.state,
          args: j.args,
          meta: j.meta,
          worker: j.worker
        }
      )

    # Apply tab filter
    query =
      case tab do
        :all ->
          base_query

        :city_backfills ->
          from(j in base_query,
            where: j.worker == "EventasaurusDiscovery.VenueImages.BackfillOrchestratorJob"
          )

        :individual_venues ->
          from(j in base_query,
            where: j.worker == "EventasaurusDiscovery.VenueImages.EnrichmentJob"
          )

        :partial_failures ->
          # Will filter in Elixir after enrichment
          base_query

        :failed_only ->
          from(j in base_query, where: j.state == "discarded")
      end

    # Apply city filter
    query =
      if city_filter != :all do
        from(j in query,
          where:
            fragment("args->>'city_id' = ?", ^to_string(city_filter)) or
              fragment(
                """
                EXISTS (
                  SELECT 1 FROM venues v
                  WHERE v.id = CAST(args->>'venue_id' AS INTEGER)
                  AND v.city_id = ?
                )
                """,
                ^city_filter
              )
        )
      else
        query
      end

    # Apply date filter
    query =
      case date_filter do
        :all_time ->
          query

        :today ->
          today = DateTime.utc_now() |> DateTime.to_date()
          from(j in query, where: fragment("DATE(?)", j.completed_at) == ^today)

        :week ->
          week_ago = DateTime.utc_now() |> DateTime.add(-7, :day)
          from(j in query, where: j.completed_at >= ^week_ago)

        :month ->
          month_ago = DateTime.utc_now() |> DateTime.add(-30, :day)
          from(j in query, where: j.completed_at >= ^month_ago)
      end

    jobs = Repo.all(query)

    # Batch load all venues for EnrichmentJob operations to avoid N+1 queries
    venue_ids =
      jobs
      |> Enum.filter(fn j -> String.ends_with?(j.worker, "EnrichmentJob") end)
      |> Enum.map(& &1.args["venue_id"])
      |> Enum.map(fn
        id when is_integer(id) -> id
        id when is_binary(id) ->
          case Integer.parse(String.trim(id)) do
            {i, ""} -> i
            _ -> nil
          end
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    venues_map =
      if Enum.empty?(venue_ids) do
        %{}
      else
        from(v in Venue, where: v.id in ^venue_ids, select: {v.id, v})
        |> Repo.all()
        |> Map.new()
      end

    # Apply Elixir-level filters
    jobs
    |> Enum.map(&enrich_operation(&1, venues_map))
    |> apply_provider_filter(provider_filter)
    |> apply_status_filter(status_filter)
    |> apply_tab_filter(tab)
  end

  defp apply_provider_filter(operations, :all), do: operations

  defp apply_provider_filter(operations, provider) do
    Enum.filter(operations, fn op ->
      provider in op.providers
    end)
  end

  defp apply_status_filter(operations, :all), do: operations

  defp apply_status_filter(operations, status) do
    Enum.filter(operations, fn op ->
      op.state == status
    end)
  end

  defp apply_tab_filter(operations, :partial_failures) do
    Enum.filter(operations, fn op ->
      op.failure_type == :partial_failure
    end)
  end

  defp apply_tab_filter(operations, _tab), do: operations

  defp enrich_operation(job, venues_map) do
    # Calculate duration
    duration_seconds =
      if job.completed_at && job.attempted_at do
        completed = to_datetime(job.completed_at)
        attempted = to_datetime(job.attempted_at)
        DateTime.diff(completed, attempted)
      else
        nil
      end

    # Extract data from meta
    meta = job.meta || %{}
    args = job.args || %{}
    providers = args["providers"] || []
    worker = job.worker || "EventasaurusDiscovery.VenueImages.BackfillOrchestratorJob"

    # Handle both job types
    {total_venues, enriched, geocoded, skipped, failed, by_provider, venue_id} =
      if String.ends_with?(worker, "EnrichmentJob") do
        # EnrichmentJob: single venue operation
        venue_id = args["venue_id"]
        status = meta["status"] || "unknown"
        images_uploaded = meta["images_uploaded"] || 0

        enriched_count = if images_uploaded > 0, do: 1, else: 0
        failed_count = if status in ["failed", "no_images"] or images_uploaded == 0, do: 1, else: 0

        # Convert provider metadata
        provider_results =
          case meta["providers"] do
            providers_map when is_map(providers_map) ->
              Map.new(providers_map, fn {provider, info} ->
                status = if is_map(info), do: info["status"], else: "unknown"
                {provider, if(status == "success", do: 1, else: 0)}
              end)

            _ ->
              %{}
          end

        {1, enriched_count, 0, 0, failed_count, provider_results, venue_id}
      else
        # BackfillOrchestratorJob: city-wide operation
        {
          meta["total_venues"] || 0,
          meta["enriched"] || 0,
          meta["geocoded"] || 0,
          meta["skipped"] || 0,
          meta["failed"] || 0,
          meta["by_provider"] || %{},
          nil
        }
      end

    base_op = %{
      id: job.id,
      completed_at: job.completed_at,
      duration_seconds: duration_seconds,
      state: meta["status"] || if(job.state == "completed", do: "success", else: "failed"),
      providers: providers,
      worker: worker,
      total_venues: total_venues,
      enriched: enriched,
      geocoded: geocoded,
      skipped: skipped,
      failed: failed,
      by_provider: by_provider,
      total_cost_usd: meta["total_cost_usd"] || 0,
      venue_results: meta["venue_results"] || [],
      processed_at: meta["processed_at"] || meta["completed_at"],
      args: args,
      venue_id: venue_id,
      images_discovered: meta["images_discovered"] || 0,
      images_uploaded: meta["images_uploaded"] || 0,
      images_failed: meta["images_failed"] || 0,
      failed_images: meta["failed_images"] || [],
      imagekit_urls: meta["imagekit_urls"] || []
    }

    # Add partial failure detection and venue images using preloaded venues
    {failure_type, venue_images} = detect_partial_failure(base_op, venues_map)

    # Get preloaded venue to avoid N+1 queries in template
    venue = Map.get(venues_map, base_op.venue_id)

    base_op
    |> Map.put(:failure_type, failure_type)
    |> Map.put(:venue_images, venue_images)
    |> Map.put(:venue, venue)
  end

  defp detect_partial_failure(op, venues_map) do
    cond do
      # Check if this is an EnrichmentJob with venue_id
      op.venue_id != nil ->
        # Use preloaded venue from venues_map to avoid N+1 queries
        case Map.get(venues_map, op.venue_id) do
          nil ->
            {:unknown, []}

          venue ->
            venue_images = venue.venue_images || []

            failed_count =
              Enum.count(venue_images, fn img ->
                img["upload_status"] in ["failed", "permanently_failed"]
              end)

            # Count both uploaded (production) and skipped_dev (development) as successful
            uploaded_count =
              Enum.count(venue_images, fn img ->
                img["upload_status"] in ["uploaded", "skipped_dev"]
              end)

            failure_type = cond do
              failed_count > 0 and uploaded_count > 0 -> :partial_failure
              failed_count > 0 -> :complete_failure
              uploaded_count > 0 -> :success
              true -> :no_images
            end

            {failure_type, venue_images}
        end

      # BackfillOrchestratorJob - check aggregated stats
      op.enriched > 0 and op.failed > 0 ->
        {:partial_failure, []}

      op.failed > 0 ->
        {:complete_failure, []}

      op.enriched > 0 ->
        {:success, []}

      true ->
        {:no_images, []}
    end
  end

  defp to_datetime(%NaiveDateTime{} = ndt) do
    DateTime.from_naive!(ndt, "Etc/UTC")
  end

  defp to_datetime(%DateTime{} = dt), do: dt

  # Helper functions for template

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %I:%M %p")
  end

  defp format_duration(nil), do: "N/A"
  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)
    "#{minutes}m #{remaining_seconds}s"
  end

  defp format_provider_name("google_places"), do: "Google Places"
  defp format_provider_name("foursquare"), do: "Foursquare"
  defp format_provider_name("here"), do: "HERE"
  defp format_provider_name("mapbox"), do: "Mapbox"
  defp format_provider_name(nil), do: "Unknown"

  defp format_provider_name(name),
    do: name |> String.replace("_", " ") |> String.capitalize()

  defp provider_badge_class("google_places"), do: "bg-orange-100 text-orange-800"
  defp provider_badge_class("foursquare"), do: "bg-pink-100 text-pink-800"
  defp provider_badge_class("here"), do: "bg-purple-100 text-purple-800"
  defp provider_badge_class("mapbox"), do: "bg-blue-100 text-blue-800"
  defp provider_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp failure_type_badge(:partial_failure), do: "bg-yellow-100 text-yellow-800"
  defp failure_type_badge(:complete_failure), do: "bg-red-100 text-red-800"
  defp failure_type_badge(:success), do: "bg-green-100 text-green-800"
  defp failure_type_badge(:no_images), do: "bg-gray-100 text-gray-800"
  defp failure_type_badge(_), do: "bg-gray-100 text-gray-800"

  defp failure_type_label(:partial_failure), do: "Partial Failure"
  defp failure_type_label(:complete_failure), do: "Complete Failure"
  defp failure_type_label(:success), do: "Success"
  defp failure_type_label(:no_images), do: "No Images"
  defp failure_type_label(_), do: "Unknown"

  defp format_cost(cost) when is_float(cost) do
    :erlang.float_to_binary(cost, decimals: 4)
  end

  defp format_cost(cost) when is_integer(cost) do
    :erlang.float_to_binary(cost * 1.0, decimals: 4)
  end

  defp format_cost(_), do: "0.0000"

  defp tab_active_class(tab, active_tab) do
    if tab == active_tab do
      "border-blue-500 text-blue-600"
    else
      "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
    end
  end

  # Safely render HTML attribution from providers (XSS protection)
  defp safe_attribution(nil), do: ""
  defp safe_attribution(html) when is_binary(html) do
    html
    |> HtmlSanitizeEx.html5()
    |> Phoenix.HTML.raw()
  end
  defp safe_attribution(_), do: ""

  # Safely format timestamps with error handling
  defp format_timestamp(nil), do: "unknown"
  defp format_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%b %d, %Y %I:%M:%S %p")
      _ -> timestamp
    end
  end
  defp format_timestamp(_), do: "unknown"
end
