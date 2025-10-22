defmodule EventasaurusDiscovery.Sources.Inquizition.Jobs.VenueDetailJob do
  @moduledoc """
  Processes individual Inquizition venues with metadata tracking.

  ## Workflow
  1. Receive venue data from IndexJob
  2. Transform venue/event data using Transformer
  3. Process through unified Processor.process_source_data/3
  4. Track success/failure in job metadata via MetricsTracker

  ## Two-Stage Architecture Benefits
  - Individual venue error tracking and retry capability
  - MetricsTracker provides per-venue success/failure metadata
  - Proper observability in admin dashboard stats
  - Consistent with other pattern scrapers (Speed Quizzing, etc.)

  ## Integration Points
  - Called by: IndexJob (after EventFreshnessChecker filtering)
  - Uses: Transformer for data transformation
  - Uses: Processor.process_source_data/3 for venue/event creation
  - Uses: MetricsTracker for job metadata status tracking
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3,
    priority: 2

  require Logger

  alias EventasaurusDiscovery.Sources.Inquizition.Transformer
  alias EventasaurusDiscovery.Sources.Processor
  alias EventasaurusDiscovery.Metrics.MetricsTracker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, id: _job_id} = job) do
    source_id = args["source_id"]
    venue_id = args["venue_id"]
    venue_data_raw = args["venue_data"]

    # Use venue_id as external_id for tracking (matches IndexJob pattern)
    external_id = "inquizition-#{venue_id}"

    Logger.info("🔄 Processing Inquizition venue: #{venue_id}")

    # Convert string keys to atom keys (Oban serializes args as JSON)
    venue_data = atomize_venue_data(venue_data_raw)

    result =
      with {:ok, transformed} <- transform_venue(venue_data),
           {:ok, events} <- process_venue(transformed, source_id) do
        Logger.info("✅ Successfully processed venue: #{venue_id} (#{length(events)} events)")
        {:ok, %{events: length(events)}}
      else
        {:error, reason} = error ->
          Logger.error("❌ Failed to process venue #{venue_id}: #{inspect(reason)}")
          error
      end

    # Track metrics in job metadata (enables admin dashboard stats)
    case result do
      {:ok, _} ->
        MetricsTracker.record_success(job, external_id)
        result

      {:error, reason} ->
        MetricsTracker.record_failure(job, reason, external_id)
        result

      _other ->
        result
    end
  end

  # Transform venue data using existing Transformer (returns map directly)
  defp transform_venue(venue_data) do
    case Transformer.transform_event(venue_data) do
      transformed when is_map(transformed) ->
        {:ok, transformed}

      _ ->
        {:error, "Transformation failed"}
    end
  end

  # Process venue through unified processor (handles venue geocoding + event creation)
  defp process_venue(transformed, source_id) do
    case Processor.process_source_data([transformed], source_id, "inquizition") do
      {:ok, events} -> {:ok, events}
      error -> error
    end
  end

  # Convert string keys to atom keys (Oban serializes args as JSON)
  defp atomize_venue_data(venue_data) when is_map(venue_data) do
    %{
      venue_id: venue_data["venue_id"],
      name: venue_data["name"],
      address: venue_data["address"],
      latitude: venue_data["latitude"],
      longitude: venue_data["longitude"],
      phone: venue_data["phone"],
      website: venue_data["website"],
      email: venue_data["email"],
      schedule_text: venue_data["schedule_text"],
      day_filters: venue_data["day_filters"] || [],
      timezone: venue_data["timezone"],
      country: venue_data["country"]
    }
  end
end
