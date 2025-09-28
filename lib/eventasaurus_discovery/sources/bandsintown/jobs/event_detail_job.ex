defmodule EventasaurusDiscovery.Sources.Bandsintown.Jobs.EventDetailJob do
  @moduledoc """
  Oban job for processing individual Bandsintown event details.

  This job processes a single event through the unified Processor,
  maintaining venue validation requirements while providing:
  - Retry capability per event
  - Parallel processing
  - Failure isolation

  Each EventDetailJob:
  1. Receives event data from IndexPageJob
  2. Transforms the event using Bandsintown.Transformer
  3. Processes through the unified Processor for venue validation
  4. Creates or updates the event in the database

  This restores the async functionality that was removed in commit d42309da
  while maintaining the venue validation requirements that were added.
  """

  use Oban.Worker,
    queue: :scraper_detail,
    max_attempts: 3

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Locations.City
  alias EventasaurusDiscovery.Sources.Source
  alias EventasaurusDiscovery.Sources.Bandsintown.Transformer
  alias EventasaurusDiscovery.Sources.Processor

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    event_data = args["event_data"]
    source_id = args["source_id"]
    city_id = args["city_id"]
    external_id = args["external_id"]
    from_page = args["from_page"]

    Logger.debug("""
    🎵 Processing Bandsintown event
    External ID: #{external_id}
    From page: #{from_page}
    Artist: #{event_data["artist_name"]}
    Venue: #{event_data["venue_name"]}
    """)

    # Get source and city
    with {:ok, source} <- get_source(source_id),
         {:ok, city} <- get_city(city_id),
         # Transform the event data with city context for proper venue association
         {:ok, transformed_event} <- transform_event(event_data, city),
         # Process through unified Processor for venue validation
         {:ok, result} <- process_event(transformed_event, source, city) do

      case result do
        event when is_struct(event) ->
          # Successfully processed and created/updated event
          {:ok, event}

        :filtered ->
          # Event was filtered out during processing
          {:ok, :filtered}

        :discarded ->
          # Event was discarded (e.g., missing GPS coordinates)
          {:ok, :discarded}

        other ->
          Logger.warning("⚠️ Unexpected processing result: #{inspect(other)}")
          {:ok, other}
      end
    else
      {:error, :source_not_found} ->
        Logger.error("❌ Source not found: #{source_id}")
        {:error, :source_not_found}

      {:error, :city_not_found} ->
        Logger.error("❌ City not found: #{city_id}")
        {:error, :city_not_found}

      {:error, reason} ->
        Logger.error("❌ Failed to process event: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_source(source_id) do
    case Repo.get(Source, source_id) do
      nil -> {:error, :source_not_found}
      source -> {:ok, source}
    end
  end

  defp get_city(city_id) do
    case Repo.get(City, city_id) |> Repo.preload(:country) do
      nil -> {:error, :city_not_found}
      city -> {:ok, city}
    end
  end

  defp transform_event(event_data, city) do
    # Use the Transformer to convert the event data
    # The event_data already has string keys from IndexPageJob
    # Pass the city context for proper venue association
    case Transformer.transform_event(event_data, city) do
      {:ok, event} ->
        Logger.debug("✅ Event transformed successfully")
        {:ok, event}

      {:error, reason} ->
        Logger.warning("⚠️ Failed to transform event: #{inspect(reason)}")
        {:error, {:transform_failed, reason}}
    end
  end

  defp process_event(event, source, _city) do
    # Process through the unified Processor
    # This maintains the venue validation requirements from commit d42309da
    # The Processor expects a list of events
    events_to_process = [event]

    Logger.debug("🔄 Processing event through unified Processor")

    # Call the Processor with the required arguments
    # The Processor will handle venue validation and event creation/updating
    # Note: City is not needed by the Processor, it uses venue data from the event
    case Processor.process_source_data(events_to_process, source) do
      {:ok, results} when is_list(results) ->
        # process_source_data returns a list of processed events
        Logger.debug("✅ Event processed through Processor")

        case results do
          [processed_event | _] ->
            Logger.info("""
            ✅ Event processed successfully
            Title: #{processed_event.title}
            Venue: #{processed_event.venue.name}
            """)
            {:ok, processed_event}

          [] ->
            Logger.warning("⚠️ Event was filtered out during processing")
            {:ok, :filtered}
        end

      {:error, reason} ->
        Logger.error("❌ Processor failed: #{inspect(reason)}")
        {:error, {:processor_failed, reason}}

      {:discard, reason} ->
        Logger.warning("⚠️ Event discarded: #{inspect(reason)}")
        {:ok, :discarded}
    end
  rescue
    error ->
      Logger.error("""
      ❌ Exception during event processing:
      #{inspect(error)}
      #{inspect(__STACKTRACE__)}
      """)
      {:error, {:exception, error}}
  end
end