defmodule EventasaurusDiscovery.Services.CollisionDetector do
  @moduledoc """
  Shared service for detecting event collisions across all sources.

  Identifies when events from different sources are actually the same event
  based on venue and time proximity.
  """

  import Ecto.Query
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  require Logger

  # 4 hours
  @collision_window_seconds 14400

  @doc """
  Find an existing event that matches the given criteria.

  Uses venue + time window matching for collision detection.
  Events at the same venue within a 4-hour window are considered potential duplicates.

  ## Parameters
  - venue: The venue struct (can be nil)
  - starts_at: DateTime when the event starts
  - title: Event title (optional, for logging only)

  ## Returns
  - nil if no similar event found
  - %PublicEvent{} if a similar event exists
  """
  def find_similar_event(venue, starts_at, title \\ nil) do
    # Normalize to NaiveDateTime for consistency with database
    starts_at = to_naive(starts_at)

    # Guard against nil starts_at
    unless starts_at do
      Logger.warning("find_similar_event: invalid starts_at; skipping collision check")
      nil
    else
      # Calculate time window for collision detection
      start_window = NaiveDateTime.add(starts_at, -@collision_window_seconds, :second)
      end_window = NaiveDateTime.add(starts_at, @collision_window_seconds, :second)

      Logger.info("""
      🕐 Checking for similar events:
      Title: #{title || "N/A"}
      Time window: #{start_window} to #{end_window}
      Venue: #{if venue, do: "#{venue.name} (ID: #{venue.id})", else: "None"}
      """)

      # Venue + time is our strongest signal for collision detection
      if venue do
        # First check time window
        time_match_query =
          from(pe in PublicEvent,
            where:
              pe.venue_id == ^venue.id and
                pe.starts_at >= ^start_window and
                pe.starts_at <= ^end_window,
            limit: 1
          )

        time_match = Repo.one(time_match_query)

        # Also check fuzzy title matching at the same venue
        fuzzy_match =
          if is_nil(time_match) && title do
            from(pe in PublicEvent,
              where: pe.venue_id == ^venue.id,
              where: fragment("similarity(?, ?) > ?", pe.title, ^title, 0.85),
              order_by: [desc: fragment("similarity(?, ?)", pe.title, ^title)],
              limit: 1
            )
            |> Repo.one()
          else
            nil
          end

        # Return whichever match we found
        case {time_match, fuzzy_match} do
          {nil, nil} ->
            Logger.info("❌ No similar events found in time window or by title")
            nil

          {found_event, _} when not is_nil(found_event) ->
            # Log when we find a potential match
            Logger.info("""
            🔍 Found potential collision by time:
            Existing event ##{found_event.id}: #{found_event.title}
            Starts at: #{found_event.starts_at}
            Venue ID: #{venue.id}
            Time difference: #{calculate_time_difference(starts_at, found_event.starts_at)} hours
            """)

            found_event

          {_, found_event} when not is_nil(found_event) ->
            # Log fuzzy match
            Logger.info("""
            🔍 Found potential collision by title similarity:
            Existing event ##{found_event.id}: #{found_event.title}
            Starts at: #{found_event.starts_at}
            Venue ID: #{venue.id}
            Title similarity: High (>85%)
            """)

            found_event
        end
      else
        Logger.info("⚠️ No venue provided, cannot reliably check for collisions")
        # Without venue, we can't reliably match
        # TODO: Future enhancement - check performers + date as fallback
        nil
      end
    end

    # End of unless starts_at
  end

  @doc """
  Find similar event using basic event data map.
  Convenience function for sources that pass data as maps.
  """
  def find_similar_event_from_data(event_data) when is_map(event_data) do
    venue = event_data[:venue] || event_data["venue"]

    starts_at =
      event_data[:starts_at] || event_data["starts_at"] ||
        event_data[:start_at] || event_data["start_at"]

    title = event_data[:title] || event_data["title"]

    if venue && starts_at do
      find_similar_event(venue, starts_at, title)
    else
      Logger.warning("Missing venue or starts_at in event data, cannot check for collisions")
      nil
    end
  end

  @doc """
  Check if two events are likely the same based on collision criteria.
  """
  def events_match?(event1, event2) do
    same_venue = event1.venue_id == event2.venue_id

    # Normalize to NaiveDateTime for comparison
    dt1 = to_naive(event1.starts_at)
    dt2 = to_naive(event2.starts_at)

    # Guard against nil dates
    time_diff =
      if is_nil(dt1) or is_nil(dt2) do
        # If either date is nil, consider them not matching
        @collision_window_seconds + 1
      else
        NaiveDateTime.diff(dt1, dt2, :second) |> abs()
      end

    within_window = time_diff <= @collision_window_seconds

    same_venue && within_window
  end

  # Private helpers

  defp calculate_time_difference(datetime1, datetime2) do
    dt1 = to_naive(datetime1)
    dt2 = to_naive(datetime2)
    diff_seconds = NaiveDateTime.diff(dt1, dt2, :second) |> abs()
    # Convert to hours with 1 decimal
    Float.round(diff_seconds / 3600, 1)
  end

  defp to_naive(nil), do: nil
  defp to_naive(%NaiveDateTime{} = dt), do: dt
  defp to_naive(%DateTime{} = dt), do: DateTime.to_naive(dt)

  defp to_naive(dt) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, _} ->
        DateTime.to_naive(datetime)

      _ ->
        case NaiveDateTime.from_iso8601(dt) do
          {:ok, naive} -> naive
          _ -> nil
        end
    end
  end
end
