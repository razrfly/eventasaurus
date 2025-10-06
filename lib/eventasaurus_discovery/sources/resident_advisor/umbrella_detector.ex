defmodule EventasaurusDiscovery.Sources.ResidentAdvisor.UmbrellaDetector do
  @moduledoc """
  Detects umbrella/festival container events in Resident Advisor data.

  Umbrella events are multi-day, multi-venue festivals that should be treated
  as containers rather than individual events.

  ## Detection Signals

  1. **Venue ID Match** (strongest signal) - RA uses specific venue IDs for "Various venues"
  2. **Multi-day Pattern** - Event spans multiple days (end_date != start_date)
  3. **Generic Time** - Starts at noon (12:00) or ends at 23:59
  4. **High Artist Count** - Many artists indicate festival lineup

  ## Known "Various Venues" Venue IDs

  - `267425` - Various venues - Kraków
  - Add more as discovered through API research
  """

  require Logger

  @doc """
  Check if an event is an umbrella/festival container event.

  Returns:
  - `{:umbrella, %{reason: atom, confidence: float}}` if umbrella detected
  - `:not_umbrella` if regular event

  ## Examples

      iex> event = %{"venue" => %{"id" => "267425"}}
      iex> is_umbrella_event?(event, %{name: "Kraków"})
      {:umbrella, %{reason: :venue_id_match, confidence: 1.0}}

      iex> event = %{"venue" => %{"id" => "12345"}}
      iex> is_umbrella_event?(event, %{name: "Kraków"})
      :not_umbrella
  """
  def is_umbrella_event?(event, city_context) do
    signals = [
      check_venue_id(event, city_context),
      check_multi_day_pattern(event),
      check_generic_times(event),
      check_artist_count(event)
    ]

    # Count positive signals
    positive_signals = Enum.count(signals, fn {result, _} -> result == :umbrella end)

    cond do
      # Venue ID match is definitive
      match?({:umbrella, %{reason: :venue_id_match}}, List.first(signals)) ->
        {:umbrella, %{reason: :venue_id_match, confidence: 1.0, signals: positive_signals}}

      # Multiple heuristic signals (2+) indicate umbrella
      positive_signals >= 2 ->
        primary_reason = signals |> Enum.find(fn {r, _} -> r == :umbrella end) |> elem(1) |> Map.get(:reason)
        {:umbrella, %{reason: primary_reason, confidence: 0.85, signals: positive_signals}}

      true ->
        :not_umbrella
    end
  end

  # Check if venue ID matches known "Various venues" IDs
  defp check_venue_id(event, city_context) do
    venue = event["venue"]
    venue_id = venue && venue["id"]

    if venue_id in umbrella_venue_ids(city_context.name) do
      {:umbrella, %{reason: :venue_id_match, venue_id: venue_id}}
    else
      {:not_umbrella, nil}
    end
  end

  # Check for multi-day pattern
  defp check_multi_day_pattern(event) do
    date = event["date"]
    end_time = event["endTime"]

    with true <- is_binary(date) and is_binary(end_time),
         {:ok, event_date, _} <- DateTime.from_iso8601(date),
         {:ok, event_end, _} <- DateTime.from_iso8601(end_time),
         true <- DateTime.diff(event_end, event_date, :day) >= 3 do
      {:umbrella, %{reason: :multi_day_pattern, days: DateTime.diff(event_end, event_date, :day)}}
    else
      _ -> {:not_umbrella, nil}
    end
  end

  # Check for generic start/end times (12:00 start or 23:59 end)
  defp check_generic_times(event) do
    start_time = event["startTime"]
    end_time = event["endTime"]

    has_generic_start = is_binary(start_time) && String.contains?(start_time, "T12:00:00")
    has_late_end = is_binary(end_time) && String.contains?(end_time, "T23:59:00")

    if has_generic_start or has_late_end do
      {:umbrella, %{reason: :generic_times, generic_start: has_generic_start, late_end: has_late_end}}
    else
      {:not_umbrella, nil}
    end
  end

  # Check for high artist count (festivals have many artists)
  defp check_artist_count(event) do
    artists = event["artists"] || []
    artist_count = length(artists)

    if artist_count >= 10 do
      {:umbrella, %{reason: :high_artist_count, count: artist_count}}
    else
      {:not_umbrella, nil}
    end
  end

  @doc """
  Get list of "Various venues" venue IDs for a city.

  ## Known Venue IDs

  - Kraków: `267425` (confirmed from Unsound Kraków 2025 data)
  - Warsaw: TBD (needs research)
  - Berlin: TBD (needs research)
  - London: TBD (needs research)
  - New York: TBD (needs research)
  - Los Angeles: TBD (needs research)
  """
  def umbrella_venue_ids(city_name) do
    case String.downcase(city_name) do
      "kraków" -> ["267425"]
      "krakow" -> ["267425"]
      # Add more as discovered
      _ -> []
    end
  end

  @doc """
  Log umbrella event detection for debugging.
  """
  def log_detection(event, detection_result) do
    case detection_result do
      {:umbrella, metadata} ->
        Logger.info("""
        🎪 Umbrella event detected:
        Event: #{event["title"]}
        ID: #{event["id"]}
        Reason: #{metadata.reason}
        Confidence: #{metadata.confidence}
        Signals: #{metadata.signals}
        """)

      :not_umbrella ->
        :ok
    end
  end
end
