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
  alias EventasaurusApp.Repo
  alias EventasaurusApp.Venues.Venue, as: VenueSchema
  require Logger

  @pubsub_topic "venue_country_fix"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"venue_id" => venue_id}}) do
    Logger.info("[VenueCountryFix] Processing venue #{venue_id}")

    # Load the venue with its metadata
    venue =
      Repo.get(VenueSchema, venue_id)
      |> Repo.preload(city_ref: :country)

    case venue do
      nil ->
        Logger.warning("[VenueCountryFix] Venue #{venue_id} not found")
        broadcast_progress(:failed, %{venue_id: venue_id, reason: :not_found})
        {:error, :venue_not_found}

      venue ->
        case DataQualityChecker.fix_venue_country_from_metadata(venue) do
          {:ok, fix_result} ->
            Logger.info("[VenueCountryFix] Fixed venue #{venue_id}: #{fix_result.old_country} -> #{fix_result.new_country}")
            broadcast_progress(:fixed, %{venue_id: venue_id, result: fix_result})
            :ok

          {:error, reason} ->
            Logger.warning("[VenueCountryFix] Failed venue #{venue_id}: #{inspect(reason)}")
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

  @doc """
  Queue a single venue fix job.
  """
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
    venues = VenueCountryCheckJob.get_mismatches(
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
      jobs =
        Enum.map(venue_ids, fn venue_id ->
          new(%{"venue_id" => venue_id})
        end)

      case Oban.insert_all(jobs) do
        inserted_jobs when is_list(inserted_jobs) ->
          count = length(inserted_jobs)
          Logger.info("[VenueCountryFix] Queued #{count} fix jobs")
          broadcast_progress(:queued, %{total: count, venue_ids: venue_ids})
          {:ok, %{queued: count, venue_ids: venue_ids}}

        {:error, reason} ->
          Logger.error("[VenueCountryFix] Failed to queue jobs: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end
end
