defmodule EventasaurusDiscovery.Admin.VenueCountryFixJob do
  @moduledoc """
  Oban worker for fixing individual venue country assignments.

  Each job fixes a single venue, allowing Oban to manage parallelism
  and retries efficiently.

  ## Usage

      # Queue fixes for all high confidence mismatches
      VenueCountryFixJob.queue_bulk_fix(confidence: :high, limit: 50)

      # Queue a single venue fix
      VenueCountryFixJob.queue_single_fix(venue_id)

  ## PubSub Events

  Progress is broadcast to the "venue_country_fix" topic:

      Phoenix.PubSub.subscribe(Eventasaurus.PubSub, "venue_country_fix")

  Events:
  - `{:venue_country_fix_progress, %{status: :queued, total: n}}`
  - `{:venue_country_fix_progress, %{status: :fixed, venue_id: id}}`
  - `{:venue_country_fix_progress, %{status: :failed, venue_id: id, reason: reason}}`
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 300, fields: [:args, :worker], states: [:available, :scheduled, :executing]]

  alias EventasaurusDiscovery.Admin.{DataQualityChecker, VenueCountryCheckJob}
  alias EventasaurusDiscovery.Metrics.MetricsTracker
  # JobRepo: Direct connection for job business logic (Issue #3353)
  # Bypasses PgBouncer to avoid 30-second timeout on long-running queries
  alias EventasaurusApp.JobRepo
  alias EventasaurusApp.Venues.Venue, as: VenueSchema
  require Logger

  @type fix_result :: %{
          queued: non_neg_integer(),
          venue_ids: [integer()]
        }

  @pubsub_topic "venue_country_fix"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"venue_id" => venue_id}} = job) do
    Logger.info("[VenueCountryFix] Processing venue #{venue_id}")
    external_id = "venue_country_fix_#{venue_id}"

    # Load the venue with its metadata
    venue =
      JobRepo.get(VenueSchema, venue_id)
      |> JobRepo.preload(city_ref: :country)

    case venue do
      nil ->
        Logger.warning("[VenueCountryFix] Venue #{venue_id} not found")
        MetricsTracker.record_failure(job, "Venue not found", external_id)
        broadcast_progress(:failed, %{venue_id: venue_id, reason: :not_found})
        # Return :ok so Oban doesn't retry - the venue doesn't exist
        :ok

      venue ->
        # Get venue info for metadata before any changes
        venue_name = venue.name
        check = venue.metadata["country_check"] || %{}
        old_country = check["current_country"]
        expected_country = check["expected_country"]

        case DataQualityChecker.fix_venue_country_from_metadata(venue) do
          {:ok, fix_result} ->
            Logger.info(
              "[VenueCountryFix] Fixed venue #{venue_id}: #{fix_result.old_country} -> #{fix_result.new_country}"
            )

            record_success_with_details(job, external_id, %{
              venue_id: venue_id,
              venue_name: venue_name,
              old_country: fix_result.old_country,
              new_country: fix_result.new_country
            })

            broadcast_progress(:fixed, %{venue_id: venue_id, result: fix_result})
            :ok

          {:error, reason} ->
            Logger.warning("[VenueCountryFix] Failed venue #{venue_id}: #{inspect(reason)}")

            # Record failure with venue context
            record_failure_with_details(job, reason, external_id, %{
              venue_id: venue_id,
              venue_name: venue_name,
              old_country: old_country,
              expected_country: expected_country
            })

            # Mark the venue as "failed" in metadata so it doesn't stay in pending list
            case DataQualityChecker.update_venue_mismatch_status(venue, "failed", reason) do
              {:ok, _} ->
                Logger.info("[VenueCountryFix] Marked venue #{venue_id} as failed in metadata")

              {:error, update_error} ->
                Logger.error(
                  "[VenueCountryFix] Could not update venue #{venue_id} status: #{inspect(update_error)}"
                )
            end

            broadcast_progress(:failed, %{venue_id: venue_id, reason: reason})
            # Return :ok so Oban doesn't retry - the venue data itself is the problem
            :ok
        end
    end
  end

  defp broadcast_progress(status, data) do
    Phoenix.PubSub.broadcast(
      Eventasaurus.PubSub,
      @pubsub_topic,
      {:venue_country_fix_progress, Map.put(data, :status, status)}
    )
  end

  # Record success with venue-specific details in job metadata
  defp record_success_with_details(job, external_id, details) do
    import Ecto.Query

    metadata = %{
      "status" => "success",
      "external_id" => to_string(external_id),
      "processed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "venue_id" => details.venue_id,
      "venue_name" => details.venue_name,
      "old_country" => details.old_country,
      "new_country" => details.new_country
    }

    updated_meta = Map.merge(job.meta || %{}, metadata)

    from(j in Oban.Job, where: j.id == ^job.id)
    |> JobRepo.update_all(set: [meta: updated_meta])
  end

  # Record failure with venue-specific details in job metadata
  defp record_failure_with_details(job, reason, external_id, details) do
    import Ecto.Query
    alias EventasaurusDiscovery.Metrics.ErrorCategories

    error_category = ErrorCategories.categorize_error(reason)
    error_message = format_error_message(reason)

    metadata = %{
      "status" => "failed",
      "external_id" => to_string(external_id),
      "processed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "error_category" => to_string(error_category),
      "error_message" => error_message,
      "venue_id" => details.venue_id,
      "venue_name" => details.venue_name,
      "old_country" => details.old_country,
      "expected_country" => details.expected_country
    }

    updated_meta = Map.merge(job.meta || %{}, metadata)

    from(j in Oban.Job, where: j.id == ^job.id)
    |> JobRepo.update_all(set: [meta: updated_meta])
  end

  defp format_error_message(reason) when is_binary(reason), do: String.slice(reason, 0, 500)

  defp format_error_message(%{__exception__: true} = ex),
    do: Exception.message(ex) |> String.slice(0, 500)

  defp format_error_message(reason), do: inspect(reason) |> String.slice(0, 500)

  @doc """
  Queue a single venue fix job.
  """
  @spec queue_single_fix(integer()) :: {:ok, Oban.Job.t()} | {:error, Ecto.Changeset.t()}
  def queue_single_fix(venue_id) when is_integer(venue_id) do
    %{"venue_id" => venue_id}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Queue bulk fix jobs - one job per venue.

  This queries for mismatches and inserts one Oban job per venue,
  allowing parallel processing with proper backpressure.

  ## Options
  - `:confidence` - :high, :medium, or :low (default: :high)
  - `:from_country` - Filter by current country name
  - `:to_country` - Filter by expected country name
  - `:limit` - Maximum venues to fix (default: 50)

  ## Returns
  - `{:ok, %{queued: count, venue_ids: [ids]}}` on success
  """
  @spec queue_bulk_fix(keyword()) :: {:ok, fix_result()}
  def queue_bulk_fix(opts \\ []) do
    confidence =
      case Keyword.get(opts, :confidence, :high) do
        :high -> "high"
        :medium -> "medium"
        :low -> "low"
        str when is_binary(str) -> str
      end

    from_country = Keyword.get(opts, :from_country)
    to_country = Keyword.get(opts, :to_country)
    limit = Keyword.get(opts, :limit, 50)

    # Get venues to fix
    venues =
      VenueCountryCheckJob.get_mismatches(
        status: "pending",
        confidence: confidence,
        limit: limit * 2
      )

    # Filter by country pair if specified
    filtered_venues =
      venues
      |> Enum.filter(fn venue ->
        check = venue.metadata["country_check"] || %{}
        current = check["current_country"]
        expected = check["expected_country"]

        (is_nil(from_country) || current == from_country) &&
          (is_nil(to_country) || expected == to_country)
      end)
      |> Enum.take(limit)

    venue_ids = Enum.map(filtered_venues, & &1.id)

    if length(venue_ids) == 0 do
      {:ok, %{queued: 0, venue_ids: []}}
    else
      # Insert all jobs using Oban.insert_all for efficiency
      # Note: Oban.insert_all/1 always returns a list of jobs, never an error tuple
      jobs =
        Enum.map(venue_ids, fn venue_id ->
          new(%{"venue_id" => venue_id})
        end)

      inserted_jobs = Oban.insert_all(jobs)
      count = length(inserted_jobs)
      Logger.info("[VenueCountryFix] Queued #{count} fix jobs")
      broadcast_progress(:queued, %{total: count, venue_ids: venue_ids})
      {:ok, %{queued: count, venue_ids: venue_ids}}
    end
  end
end
