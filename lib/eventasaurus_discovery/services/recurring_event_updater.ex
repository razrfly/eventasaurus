defmodule EventasaurusDiscovery.Services.RecurringEventUpdater do
  @moduledoc """
  Updates recurring events with expired dates by regenerating future occurrences from patterns.

  ## Problem
  Pattern-based recurring events (Question One, PubQuiz, Inquizition) have weekly/monthly patterns
  stored in `occurrences.pattern`. When the `starts_at` date expires, the scraper would mark the
  event as "seen recently" but fail to regenerate future dates, causing 0 future events.

  ## Solution
  When processing an event with `type: "pattern"` and expired `starts_at`:
  1. Extract the recurrence pattern (frequency, days_of_week, time, timezone)
  2. Calculate the next future occurrence from NOW
  3. Update event's `starts_at` and `ends_at` with the new date

  ## Pattern Structure
  ```json
  {
    "type": "pattern",
    "pattern": {
      "frequency": "weekly",
      "days_of_week": ["tuesday"],
      "time": "19:30",
      "timezone": "Europe/London",
      "schedule_inferred": false
    }
  }
  ```

  ## Usage
  Called automatically by EventProcessor when processing events.
  """

  require Logger

  @doc """
  Checks if event needs date regeneration and updates if necessary.

  Returns:
  - `{:ok, updated_event}` if event was updated
  - `{:ok, event}` if no update needed
  - `{:error, reason}` if update failed
  """
  def maybe_regenerate_dates(event) do
    cond do
      # No occurrences field - not a recurring event
      is_nil(event.occurrences) ->
        {:ok, event}

      # Not a pattern type - explicit dates or exhibitions don't need regeneration
      event.occurrences["type"] != "pattern" ->
        {:ok, event}

      # Pattern exists but no pattern data
      is_nil(event.occurrences["pattern"]) ->
        Logger.warning(
          "Event ##{event.id} has type='pattern' but no pattern data. Cannot regenerate dates."
        )

        {:ok, event}

      # Event's starts_at is in the future - no regeneration needed
      event.starts_at && DateTime.compare(event.starts_at, DateTime.utc_now()) == :gt ->
        {:ok, event}

      # Event needs date regeneration
      true ->
        regenerate_from_pattern(event)
    end
  end

  @doc """
  Regenerates event dates from pattern.

  Calculates the next occurrence based on the pattern and updates event dates.
  """
  def regenerate_from_pattern(event) do
    pattern = event.occurrences["pattern"]

    Logger.info("""
    🔄 Regenerating dates for expired recurring event:
    Event ID: #{event.id}
    Title: #{event.title}
    Current starts_at: #{event.starts_at}
    Pattern: #{inspect(pattern)}
    """)

    case calculate_next_occurrence(pattern) do
      {:ok, next_date} ->
        # Calculate duration if we have ends_at
        duration_seconds =
          if event.starts_at && event.ends_at do
            DateTime.diff(event.ends_at, event.starts_at)
          else
            # Default duration: 2 hours
            2 * 60 * 60
          end

        next_end_date = DateTime.add(next_date, duration_seconds, :second)

        Logger.info("""
        ✅ Calculated next occurrence:
        New starts_at: #{next_date}
        New ends_at: #{next_end_date}
        Duration: #{duration_seconds}s (#{div(duration_seconds, 60)} minutes)
        """)

        # Update the event
        changeset =
          EventasaurusDiscovery.PublicEvents.PublicEvent.changeset(event, %{
            starts_at: next_date,
            ends_at: next_end_date
          })

        case EventasaurusApp.Repo.update(changeset) do
          {:ok, updated_event} ->
            Logger.info("✅ Successfully regenerated dates for event ##{event.id}")
            {:ok, updated_event}

          {:error, changeset} ->
            Logger.error(
              "❌ Failed to update event ##{event.id}: #{inspect(changeset.errors)}"
            )

            {:error, changeset}
        end

      {:skip, reason} ->
        # Pattern type not yet supported - return event unchanged
        Logger.debug("Skipping date regeneration for event ##{event.id}: #{reason}")
        {:ok, event}

      {:error, reason} ->
        Logger.error(
          "❌ Failed to calculate next occurrence for event ##{event.id}: #{reason}"
        )

        {:error, reason}
    end
  end

  @doc """
  Calculates the next occurrence date from a pattern.

  Supports:
  - Weekly patterns (most common for trivia nights)
  - Monthly patterns (future support)

  ## Pattern Format
  ```elixir
  %{
    "frequency" => "weekly",
    "days_of_week" => ["tuesday"],
    "time" => "19:30",
    "timezone" => "Europe/London"
  }
  ```
  """
  def calculate_next_occurrence(pattern) do
    frequency = pattern["frequency"]
    timezone = pattern["timezone"] || "UTC"

    case frequency do
      "weekly" ->
        calculate_next_weekly_occurrence(pattern, timezone)

      "monthly" ->
        # Monthly patterns not yet implemented - skip regeneration gracefully
        # This allows monthly pattern events to continue processing without errors
        Logger.info("Monthly patterns not yet implemented, skipping date regeneration")
        {:skip, :monthly_not_implemented}

      _ ->
        {:error, "Unsupported frequency: #{frequency}"}
    end
  end

  defp calculate_next_weekly_occurrence(pattern, timezone) do
    days_of_week = pattern["days_of_week"]
    time_str = pattern["time"]

    if is_nil(days_of_week) || Enum.empty?(days_of_week) do
      {:error, "Pattern missing days_of_week"}
    else
      # Get current date in the event's timezone
      now = DateTime.now!(timezone)

      # Parse time (e.g., "19:30")
      {hour, minute} =
        case String.split(time_str || "19:00", ":") do
          [h, m] -> {String.to_integer(h), String.to_integer(m)}
          [h] -> {String.to_integer(h), 0}
          _ -> {19, 0}
        end

      # Find next occurrence
      next_date = find_next_weekly_date(now, days_of_week, hour, minute, timezone)

      {:ok, next_date}
    end
  end

  @doc """
  Finds the next date matching the weekly pattern.

  Searches up to 7 days ahead to find the next occurrence.
  """
  def find_next_weekly_date(now, days_of_week, hour, minute, timezone) do
    # Convert day names to day numbers (Monday = 1, Sunday = 7)
    target_day_numbers =
      Enum.map(days_of_week, fn day ->
        day_name_to_number(day)
      end)
      |> Enum.sort()

    # Build candidate dates for next 7 days
    candidates =
      Enum.map(0..7, fn days_ahead ->
        date = Date.add(DateTime.to_date(now), days_ahead)

        # Create DateTime for this candidate
        {:ok, naive} = NaiveDateTime.new(date, Time.new!(hour, minute, 0))

        # Handle DST transitions gracefully
        case DateTime.from_naive(naive, timezone) do
          {:ok, dt} ->
            dt

          {:ambiguous, earlier, _later} ->
            # During fall-back (e.g., 2:30 AM occurs twice), use earlier occurrence
            earlier

          {:gap, _just_before, just_after} ->
            # During spring-forward (e.g., 2:30 AM doesn't exist), use time just after gap
            just_after
        end
      end)

    # Filter to matching day of week and future dates
    matching_candidates =
      Enum.filter(candidates, fn candidate_dt ->
        day_number = Date.day_of_week(DateTime.to_date(candidate_dt))
        day_number in target_day_numbers && DateTime.compare(candidate_dt, now) == :gt
      end)

    # Return first match (nearest future occurrence)
    case matching_candidates do
      [] ->
        # Fallback: should never happen with 7-day lookahead, but use first candidate
        Logger.warning("No matching candidates found, using fallback")
        hd(candidates)

      [first | _] ->
        first
    end
  end

  # Convert day name to ISO day number (Monday = 1, Sunday = 7)
  defp day_name_to_number(day) when is_binary(day) do
    day
    |> String.downcase()
    |> do_day_name_to_number()
  end

  defp do_day_name_to_number("monday"), do: 1
  defp do_day_name_to_number("tuesday"), do: 2
  defp do_day_name_to_number("wednesday"), do: 3
  defp do_day_name_to_number("thursday"), do: 4
  defp do_day_name_to_number("friday"), do: 5
  defp do_day_name_to_number("saturday"), do: 6
  defp do_day_name_to_number("sunday"), do: 7
  # Fallback for invalid days
  defp do_day_name_to_number(_), do: 1
end
