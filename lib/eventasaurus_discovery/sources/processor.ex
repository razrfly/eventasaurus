defmodule EventasaurusDiscovery.Sources.Processor do
  @moduledoc """
  Unified processor for all event sources.

  Handles the standard workflow of processing venues, performers, and events
  from any source using the shared processors.
  """

  require Logger

  alias EventasaurusDiscovery.Scraping.Processors.{EventProcessor, VenueProcessor}
  alias EventasaurusDiscovery.Performers.PerformerStore

  @doc """
  Process a list of events from any source.

  Returns:
    - {:ok, processed_events} - Successfully processed events
    - {:error, reason} - Processing failed with retryable error
    - {:discard, reason} - Critical failure, job should be discarded (e.g., missing GPS coordinates)
  """
  def process_source_data(events, source) when is_list(events) do
    results =
      Enum.map(events, fn event_data ->
        process_single_event(event_data, source)
      end)

    # Check if any events failed with critical GPS coordinate errors
    critical_failures =
      Enum.filter(results, fn
        {:error, {:discard, _}} -> true
        _ -> false
      end)

    # If we have critical failures (missing GPS coordinates), fail the entire job
    if length(critical_failures) > 0 do
      failure_messages = Enum.map(critical_failures, fn {:error, {:discard, msg}} -> msg end)
      combined_message = Enum.join(failure_messages, "; ")

      # Log summary without exposing full address details
      Logger.error(
        "🚫 CRITICAL: Discarding job due to missing GPS coordinates. failures=#{length(critical_failures)}/#{length(events)}"
      )

      # Return error that will cause Oban to discard the job
      {:discard, "GPS coordinate validation failed: #{combined_message}"}
    else
      successful =
        Enum.filter(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      failed =
        Enum.filter(results, fn
          {:error, _} -> true
          _ -> false
        end)

      # Return proper error tuples based on results
      case {successful, failed} do
        {[], [_ | _] = failed} ->
          # All events failed - return error
          Logger.error("All #{length(failed)} events failed processing")
          {:error, :all_events_failed}

        {successful, []} ->
          # All events succeeded
          Logger.info("Successfully processed all #{length(successful)} events")
          {:ok, Enum.map(successful, fn {:ok, event} -> event end)}

        {_successful, failed} ->
          # Partial success - return error so Oban can retry
          Logger.warning("Partial failure: #{length(failed)} failed out of #{length(events)} total events")
          {:error, {:partial_failure, length(failed), length(events)}}
      end
    end
  end

  @doc """
  Process a single event with its venue and performers
  """
  def process_single_event(event_data, source) do
    # Handle different key names for venue data
    venue_data =
      event_data[:venue] || event_data["venue"] ||
        event_data[:venue_data] || event_data["venue_data"]

    with {:ok, venue} <- process_venue(venue_data, source),
         {:ok, performers} <-
           process_performers(event_data[:performers] || event_data["performers"] || [], source),
         {:ok, event} <- process_event(event_data, source, venue, performers) do
      {:ok, event}
    else
      {:error, reason} = error when is_binary(reason) ->
        # Check if this is a GPS coordinate error that should fail the job
        # More robust matching for GPS-related errors
        if String.contains?(String.downcase(reason), "gps coordinates") or
             String.contains?(String.downcase(reason), "latitude") or
             String.contains?(String.downcase(reason), "longitude") do
          Logger.error("🚫 Critical venue error - Missing GPS coordinates")
          # Log limited event data to avoid PII exposure
          event_summary = Map.take(event_data, [:external_id, :title])
          Logger.debug("Event summary: #{inspect(event_summary)}")
          # Return a special error tuple that indicates job should be discarded
          {:error, {:discard, reason}}
        else
          Logger.error("Failed to process event: #{String.slice(reason, 0, 200)}")
          error
        end

      {:error, reason} = error ->
        Logger.error("Failed to process event: #{inspect(reason)}")
        Logger.debug("Event data: #{inspect(event_data)}")
        error
    end
  end

  defp process_venue(nil, _source) do
    {:error, :venue_required}
  end

  defp process_venue(venue_data, source) when is_map(venue_data) do
    VenueProcessor.process_venue(venue_data, source)
  end

  defp process_performers(nil, _source), do: {:ok, []}
  defp process_performers([], _source), do: {:ok, []}

  defp process_performers(performers_data, _source) when is_list(performers_data) do
    results =
      Enum.map(performers_data, fn performer_data ->
        PerformerStore.find_or_create_performer(performer_data)
      end)

    performers =
      Enum.reduce(results, {:ok, []}, fn
        {:ok, performer}, {:ok, acc} -> {:ok, [performer | acc]}
        # Skip failed performers
        {:error, _reason}, {:ok, acc} -> {:ok, acc}
        _, error -> error
      end)

    case performers do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp process_event(event_data, source, venue, performers) do
    event_with_venue = Map.put(event_data, :venue_id, venue.id)

    # EventProcessor expects performer_names as a list of strings
    performer_names = Enum.map(performers, fn p -> p.name end)
    event_with_performers = Map.put(event_with_venue, :performer_names, performer_names)

    # EventProcessor expects source_id, not the source struct
    source_id = if is_struct(source), do: source.id, else: source
    EventProcessor.process_event(event_with_performers, source_id)
  end
end
