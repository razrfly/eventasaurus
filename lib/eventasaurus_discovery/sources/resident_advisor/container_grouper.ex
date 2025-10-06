defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.ContainerGrouper do
  @moduledoc """
  Multi-signal container detection for RA festival events.

  Uses promoter ID as primary grouping signal with additional validation
  from title patterns and date ranges. Handles both scenarios:

  1. Umbrella event arrives first → Store prospective associations
  2. Individual events arrive first → Retrospective association during container creation
  """

  require Logger

  @doc """
  Group events into festival containers using multi-signal detection.

  ## Signals
  1. Umbrella Event Detection (venue ID "267425") - Indicates festival exists
  2. Promoter Matching (PRIMARY) - Group by promoters[0].id (confidence: 1.0)
  3. Title Prefix (VALIDATION) - Confirm with pattern matching (confidence: +0.05)
  4. Date Range (BOUNDARY) - Events within ±7 days of umbrella event

  ## Returns
  List of container data maps with:
  - title: Festival name (from umbrella event title prefix)
  - promoter_id: Promoter ID for grouping
  - promoter_name: Promoter name for display
  - container_type: :festival
  - start_date/end_date: Calculated from sub-events
  - source_event_id: Reference to umbrella event
  - sub_events: List of related events (can be empty if events not yet imported)
  - confidence_scores: Per-event confidence scores
  - metadata: Detection signals and counts
  """
  def group_events_into_containers(events) when is_list(events) do
    {umbrella_events, regular_events} = detect_umbrella_events(events)

    umbrella_events
    |> Enum.map(fn festival ->
      sub_events = find_related_events(festival, regular_events)

      %{
        title: festival.title_prefix,
        promoter_id: festival.promoter_id,
        promoter_name: festival.promoter_name,
        container_type: :festival,
        start_date: calculate_start_date(sub_events, festival),
        end_date: calculate_end_date(sub_events, festival),
        source_event_id: festival.umbrella_event_id,
        sub_events: sub_events,
        confidence_scores: calculate_confidence_scores(festival, sub_events),
        metadata: %{
          detection_signals: ["promoter_match", "title_pattern", "date_range"],
          umbrella_event_id: festival.umbrella_event_id,
          total_sub_events: length(sub_events),
          umbrella_date: festival.start_date
        }
      }
    end)
  end

  # Detect umbrella events (venue ID 267425) and extract festival metadata
  defp detect_umbrella_events(events) do
    umbrella_events =
      events
      |> Enum.filter(&is_umbrella_event?/1)
      |> Enum.map(&extract_festival_metadata/1)

    regular_events = Enum.reject(events, &is_umbrella_event?/1)

    {umbrella_events, regular_events}
  end

  defp is_umbrella_event?(event) do
    get_in(event, ["event", "venue", "id"]) == "267425"
  end

  defp extract_festival_metadata(umbrella_event) do
    event = umbrella_event["event"]

    %{
      promoter_id: get_in(event, ["promoters", Access.at(0), "id"]),
      promoter_name: get_in(event, ["promoters", Access.at(0), "name"]),
      title_prefix: extract_title_prefix(event["title"]),
      start_date: parse_date(event["date"]),
      umbrella_event_id: event["id"]
    }
  end

  # Find events related to a festival using multi-signal matching
  defp find_related_events(festival, regular_events) do
    regular_events
    |> Enum.filter(&matches_festival?(&1, festival))
  end

  defp matches_festival?(raw_event, festival) do
    event = raw_event["event"]

    # Signal 1: Promoter match (strongest signal)
    promoter_match? =
      get_in(event, ["promoters", Access.at(0), "id"]) == festival.promoter_id

    # Signal 2: Date range boundary (±7 days from umbrella event)
    event_date = parse_date(event["date"])

    date_within_range? =
      if event_date && festival.start_date do
        case Date.diff(event_date, festival.start_date) do
          diff when abs(diff) <= 7 -> true
          _ -> false
        end
      else
        # If either date is nil, skip date check and rely on promoter match
        true
      end

    # Primary: Promoter match + Date range
    promoter_match? && date_within_range?
  end

  defp calculate_confidence_scores(festival, sub_events) do
    Enum.map(sub_events, fn raw_event ->
      event = raw_event["event"]
      base_confidence = 1.0  # Promoter match

      # Boost if title also matches (validates grouping decision)
      title_boost = if title_matches?(event, festival), do: 0.05, else: 0.0

      %{
        event_id: event["id"],
        confidence: base_confidence + title_boost,
        signals: %{
          promoter_match: true,
          title_match: title_matches?(event, festival),
          date_match: true
        }
      }
    end)
  end

  # Extract title prefix before first colon (e.g., "Unsound Kraków 2025: EVENT" → "Unsound Kraków 2025")
  defp extract_title_prefix(title) when is_binary(title) do
    case Regex.run(~r/^(.+?):\s+/, title) do
      [_full, prefix] -> prefix
      nil -> title  # No colon, use full title
    end
  end

  defp extract_title_prefix(_), do: ""

  defp title_matches?(event, festival) do
    extract_title_prefix(event["title"]) == festival.title_prefix
  end

  # Calculate start date from sub-events, or use umbrella date if no sub-events yet
  defp calculate_start_date([], festival), do: festival.start_date

  defp calculate_start_date(sub_events, festival) do
    sub_events
    |> Enum.map(fn raw_event -> parse_date(raw_event["event"]["date"]) end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> festival.start_date
      dates -> Enum.min(dates, Date)
    end
  end

  # Calculate end date from sub-events, or use umbrella date if no sub-events yet
  defp calculate_end_date([], festival), do: festival.start_date

  defp calculate_end_date(sub_events, festival) do
    sub_events
    |> Enum.map(fn raw_event -> parse_date(raw_event["event"]["date"]) end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> festival.start_date
      dates -> Enum.max(dates, Date)
    end
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ ->
        with {:ok, dt, _offset} <- DateTime.from_iso8601(date_string) do
          DateTime.to_date(dt)
        else
          _ -> nil
        end
    end
  end

  defp parse_date(_), do: nil
end
