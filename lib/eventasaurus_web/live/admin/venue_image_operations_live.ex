defmodule EventasaurusWeb.Admin.VenueImageOperationsLive do
  @moduledoc """
  Venue image enrichment operations view.

  Shows all venue image enrichment operations, including:
  - Recent enrichment job history
  - Job-level summaries (total images, uploaded, failed)
  - Per-venue details with retry capability
  - Failed image details with error classification
  - Individual and batch retry buttons
  """
  use EventasaurusWeb, :live_view

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.VenueImages.{CleanupScheduler, FailedUploadRetryWorker}
  import Ecto.Query
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Venue Image Enrichment Operations")
      |> assign(:provider_filter, :all)
      |> assign(:error_type_filter, :all)
      |> assign(:expanded_job_ids, MapSet.new())
      |> assign(:loading, true)
      |> load_operations()
      |> assign(:loading, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_provider", %{"provider" => provider}, socket) do
    provider_filter =
      case provider do
        "all" -> :all
        other -> other
      end

    {:noreply, assign(socket, :provider_filter, provider_filter)}
  end

  @impl true
  def handle_event("filter_error_type", %{"error_type" => error_type}, socket) do
    error_type_filter =
      case error_type do
        "all" -> :all
        other -> other
      end

    {:noreply, assign(socket, :error_type_filter, error_type_filter)}
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

  defp load_operations(socket) do
    operations = get_recent_operations(50)

    # Extract unique providers and error types
    providers =
      operations
      |> Enum.flat_map(fn op -> Map.keys(op.providers) end)
      |> Enum.uniq()
      |> Enum.sort()

    error_types =
      operations
      |> Enum.flat_map(fn op -> Map.keys(op.failure_breakdown) end)
      |> Enum.uniq()
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()

    socket
    |> assign(:operations, operations)
    |> assign(:providers, providers)
    |> assign(:error_types, error_types)
  end

  defp get_recent_operations(limit) do
    query =
      from(j in "oban_jobs",
        where: j.worker == "EventasaurusDiscovery.VenueImages.EnrichmentJob",
        where: j.state in ["completed", "discarded"],
        where: not is_nil(j.completed_at),
        order_by: [desc: j.completed_at],
        limit: ^limit,
        select: %{
          id: j.id,
          completed_at: j.completed_at,
          attempted_at: j.attempted_at,
          state: j.state,
          args: j.args,
          meta: j.meta
        }
      )

    query
    |> Repo.all()
    |> Enum.map(&enrich_operation/1)
  end

  defp enrich_operation(job) do
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

    # Extract venue information from args
    venue_id = args["venue_id"]
    venue_ids = args["venue_ids"]

    %{
      id: job.id,
      completed_at: job.completed_at,
      duration_seconds: duration_seconds,
      state: meta["status"] || if(job.state == "completed", do: "success", else: "failed"),
      venue_id: venue_id,
      venue_ids: venue_ids,
      # Image statistics
      images_discovered: meta["images_discovered"] || 0,
      images_uploaded: meta["images_uploaded"] || 0,
      images_failed: meta["images_failed"] || 0,
      # Failure details
      failure_breakdown: meta["failure_breakdown"] || %{},
      failed_images: meta["failed_images"] || [],
      # Provider details
      providers: meta["providers"] || %{},
      total_cost_usd: meta["total_cost_usd"] || 0,
      summary: meta["summary"] || "",
      imagekit_urls: meta["imagekit_urls"] || [],
      processed_at: meta["completed_at"],
      args: args
    }
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

  defp format_provider_name(name) when is_binary(name),
    do: name |> String.replace("_", " ") |> String.capitalize()

  defp format_provider_name(name) when is_atom(name),
    do: name |> Atom.to_string() |> format_provider_name()

  defp format_error_type(nil), do: "unknown"
  defp format_error_type(type) when is_binary(type), do: type
  defp format_error_type(type) when is_atom(type), do: Atom.to_string(type)

  defp provider_badge_class("google_places"), do: "bg-orange-100 text-orange-800"
  defp provider_badge_class("foursquare"), do: "bg-pink-100 text-pink-800"
  defp provider_badge_class("here"), do: "bg-purple-100 text-purple-800"
  defp provider_badge_class("mapbox"), do: "bg-blue-100 text-blue-800"
  defp provider_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp status_badge_class("success"), do: "bg-green-100 text-green-800"
  defp status_badge_class("partial"), do: "bg-yellow-100 text-yellow-800"
  defp status_badge_class("no_images"), do: "bg-gray-100 text-gray-800"
  defp status_badge_class("failed"), do: "bg-red-100 text-red-800"
  defp status_badge_class("error"), do: "bg-red-100 text-red-800"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp error_type_badge_class("rate_limited"), do: "bg-yellow-100 text-yellow-800"
  defp error_type_badge_class("network_timeout"), do: "bg-orange-100 text-orange-800"
  defp error_type_badge_class("network_error"), do: "bg-orange-100 text-orange-800"
  defp error_type_badge_class("not_found"), do: "bg-red-100 text-red-800"
  defp error_type_badge_class("forbidden"), do: "bg-red-100 text-red-800"
  defp error_type_badge_class("auth_error"), do: "bg-red-100 text-red-800"
  defp error_type_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp error_type_icon("rate_limited"), do: "⏱️"
  defp error_type_icon("network_timeout"), do: "🌐"
  defp error_type_icon("network_error"), do: "🌐"
  defp error_type_icon("not_found"), do: "❓"
  defp error_type_icon("forbidden"), do: "🚫"
  defp error_type_icon("auth_error"), do: "🔐"
  defp error_type_icon(_), do: "❌"

  defp is_transient_error?(error_type) when is_binary(error_type) do
    error_type in [
      "rate_limited",
      "network_timeout",
      "network_error",
      "gateway_timeout",
      "bad_gateway",
      "service_unavailable"
    ]
  end

  defp is_transient_error?(_), do: false

  defp format_cost(cost) when is_float(cost) do
    :erlang.float_to_binary(cost, decimals: 4)
  end

  defp format_cost(cost) when is_integer(cost) do
    :erlang.float_to_binary(cost * 1.0, decimals: 4)
  end

  defp format_cost(_), do: "0.0000"

  defp has_retryable_failures?(op) do
    op.images_failed > 0 and
      Enum.any?(op.failure_breakdown, fn {error_type, _count} ->
        is_transient_error?(error_type)
      end)
  end

  defp format_json(nil), do: "{}"

  defp format_json(data) when is_map(data) do
    Jason.encode!(data, pretty: true)
  rescue
    _ -> inspect(data)
  end
end
