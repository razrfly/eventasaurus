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

  Returns {:ok, processed_events} or {:error, reason}
  """
  def process_source_data(events, source) when is_list(events) do
    results = Enum.map(events, fn event_data ->
      process_single_event(event_data, source)
    end)

    successful = Enum.filter(results, fn
      {:ok, _} -> true
      _ -> false
    end)

    failed = Enum.filter(results, fn
      {:error, _} -> true
      _ -> false
    end)

    if length(failed) > 0 do
      Logger.warning("Failed to process #{length(failed)} events out of #{length(events)}")
    end

    {:ok, Enum.map(successful, fn {:ok, event} -> event end)}
  end

  @doc """
  Process a single event with its venue and performers
  """
  def process_single_event(event_data, source) do
    # Handle different key names for venue data
    venue_data = event_data[:venue] || event_data["venue"] ||
                 event_data[:venue_data] || event_data["venue_data"]

    with {:ok, venue} <- process_venue(venue_data, source),
         {:ok, performers} <- process_performers(event_data[:performers] || event_data["performers"] || [], source),
         {:ok, event} <- process_event(event_data, source, venue, performers) do
      {:ok, event}
    else
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
    results = Enum.map(performers_data, fn performer_data ->
      PerformerStore.find_or_create_performer(performer_data)
    end)

    performers = Enum.reduce(results, {:ok, []}, fn
      {:ok, performer}, {:ok, acc} -> {:ok, [performer | acc]}
      {:error, _reason}, {:ok, acc} -> {:ok, acc}  # Skip failed performers
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