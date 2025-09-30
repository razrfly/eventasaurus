defmodule EventasaurusDiscovery.Services.EventFreshnessChecker do
  @moduledoc """
  Checks if events need processing based on last_seen_at timestamps.
  Uses batch queries for performance.
  Universal across all scrapers.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEventSource

  @doc """
  Filters events to only those needing processing.
  Returns events NOT recently seen.

  ## Parameters
  - events: List of event maps with external_id
  - source_id: The source identifier
  - threshold_hours: Optional override, defaults to application config (168 hours / 7 days)

  ## Examples

      iex> events = [%{"external_id" => "bit_123"}, %{"external_id" => "bit_456"}]
      iex> filter_events_needing_processing(events, 1)
      [%{"external_id" => "bit_456"}]  # bit_123 was seen recently

  """
  @spec filter_events_needing_processing([map()], integer(), integer() | nil) :: [map()]
  def filter_events_needing_processing(events, source_id, threshold_hours \\ nil) do
    threshold = threshold_hours || get_threshold()

    # Extract external_ids from events (works with any scraper format)
    external_ids =
      events
      |> Enum.map(&extract_external_id/1)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(external_ids) do
      # If no valid external_ids, process all events (safe default)
      events
    else
      # Query for recently seen external_ids
      threshold_datetime = DateTime.add(DateTime.utc_now(), -threshold, :hour)

      fresh_external_ids =
        from(pes in PublicEventSource,
          where: pes.source_id == ^source_id,
          where: pes.external_id in ^external_ids,
          where: pes.last_seen_at > ^threshold_datetime,
          select: pes.external_id
        )
        |> Repo.all()
        |> MapSet.new()

      # Return events NOT in fresh set
      Enum.filter(events, fn event ->
        external_id = extract_external_id(event)
        is_nil(external_id) or not MapSet.member?(fresh_external_ids, external_id)
      end)
    end
  end

  @doc """
  Get the configured freshness threshold in hours.
  Universal across all scrapers - no per-scraper configuration needed.

  ## Examples

      iex> get_threshold()
      168  # 7 days default

  """
  @spec get_threshold() :: integer()
  def get_threshold do
    Application.get_env(:eventasaurus, :event_discovery, [])
    |> Keyword.get(:freshness_threshold_hours, 168)
  end

  # Extract external_id from event map (works with different scraper formats)
  defp extract_external_id(%{"external_id" => id}) when not is_nil(id), do: id
  defp extract_external_id(%{external_id: id}) when not is_nil(id), do: id
  defp extract_external_id(_), do: nil
end