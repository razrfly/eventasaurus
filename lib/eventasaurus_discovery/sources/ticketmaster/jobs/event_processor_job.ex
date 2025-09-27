defmodule EventasaurusDiscovery.Sources.Ticketmaster.Jobs.EventProcessorJob do
  @moduledoc """
  Oban job for processing individual Ticketmaster event details.

  Processes a single transformed event through the unified discovery pipeline.
  This follows the same pattern as Karnet's EventDetailJob but for Ticketmaster events
  that have already been transformed.
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Sources.{Source, Processor}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    event_data = args["event_data"]
    source_id = args["source_id"]
    external_id = event_data["external_id"] || event_data[:external_id]

    Logger.info("🎫 Processing Ticketmaster event: #{external_id}")

    # Get the source
    with {:ok, source} <- get_source(source_id),
         # Process the single event
         {:ok, _processed_event} <- process_single_event(event_data, source) do
      Logger.info("✅ Successfully processed Ticketmaster event: #{external_id}")
      {:ok, %{event_id: external_id, status: "processed"}}
    else
      {:error, {:discard, reason}} ->
        # Critical failure (e.g., missing GPS coordinates) - discard the job
        Logger.error("🚫 Discarding event #{external_id}: #{reason}")
        {:discard, reason}

      {:error, reason} ->
        # Regular error - allow retry
        Logger.error("❌ Failed to process event #{external_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_source(source_id) do
    case Repo.get(Source, source_id) do
      nil -> {:error, :source_not_found}
      source -> {:ok, source}
    end
  end

  defp process_single_event(event_data, source) do
    # Process the single event through the Processor
    # Note: We wrap it in a list because Processor.process_source_data expects a list
    case Processor.process_source_data([event_data], source) do
      {:ok, [processed_event]} ->
        {:ok, processed_event}

      {:ok, []} ->
        # Event was filtered out or skipped
        {:ok, nil}

      {:discard, reason} ->
        # Critical failure that should discard the job
        {:error, {:discard, reason}}

      other ->
        # Catch any other unexpected return value
        Logger.warning("Unexpected return from Processor: #{inspect(other)}")
        {:error, :unexpected_processor_response}
    end
  end
end