defmodule EventasaurusApp.Planning.OccurrenceQuery do
  @moduledoc """
  Service for querying occurrences (showtimes, event instances, venue time slots) for poll-based planning.

  Supports:
  - Movie showtimes from Cinema City and Repertuary sources
  - Venue time slots (restaurants, venues) with meal period generation

  ## Filter Criteria

  Filter criteria is a map that can include:

  - `date_range`: `{start_date, end_date}` or `%{start: date, end: date}` - Date range for occurrences
  - `time_preferences`: List of time slots like `["evening", "afternoon", "late_night"]`
  - `meal_periods`: List of meal periods like `["dinner", "lunch", "brunch"]` (for venues)
  - `venue_ids`: List of specific venue IDs to filter by
  - `city_ids`: List of city IDs to filter by
  - `limit`: Maximum number of occurrences to return (default: 50)

  ## Time Preference Mapping (Movies)

  - `"morning"`: 06:00-12:00
  - `"afternoon"`: 12:00-17:00
  - `"evening"`: 17:00-22:00
  - `"late_night"`: 22:00-06:00

  ## Meal Period Mapping (Venues)

  - `"breakfast"`: 08:00-11:00
  - `"brunch"`: 10:00-14:00 (weekends only)
  - `"lunch"`: 12:00-15:00
  - `"dinner"`: 18:00-22:00
  - `"late_night"`: 22:00-01:00

  ## Examples

      # Movie showtimes
      iex> filter_criteria = %{
      ...>   date_range: %{start: ~D[2024-11-25], end: ~D[2024-11-30]},
      ...>   time_preferences: ["evening"],
      ...>   city_ids: [1]
      ...> }
      iex> OccurrenceQuery.find_movie_occurrences(123, filter_criteria)
      {:ok, [%{
        public_event_id: 456,
        movie_id: 123,
        venue_id: 789,
        starts_at: ~U[2024-11-25 19:00:00Z],
        title: "Dune: Part Two",
        venue_name: "Cinema City Arkadia"
      }]}

      # Venue time slots
      iex> filter_criteria = %{
      ...>   date_range: %{start: ~D[2024-11-25], end: ~D[2024-11-27]},
      ...>   meal_periods: ["dinner", "lunch"]
      ...> }
      iex> OccurrenceQuery.find_venue_occurrences(789, filter_criteria)
      {:ok, [%{
        venue_id: 789,
        venue_name: "La Forchetta",
        date: ~D[2024-11-25],
        meal_period: "dinner",
        starts_at: ~U[2024-11-25 18:00:00Z],
        ends_at: ~U[2024-11-25 22:00:00Z]
      }]}
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.PublicEvents.PublicEvent
  alias EventasaurusDiscovery.PublicEvents.EventMovie
  alias EventasaurusDiscovery.Movies.Movie
  alias EventasaurusApp.Venues.Venue

  @default_limit 50

  @doc """
  Finds movie occurrences (showtimes) for a specific movie.

  Returns a list of occurrence maps with public_event details, venue, and timing.

  ## Parameters

  - `movie_id` - The movie ID to find showtimes for
  - `filter_criteria` - Map of filters (date_range, time_preferences, venue_ids, city_ids, limit)

  ## Returns

  - `{:ok, occurrences}` - List of occurrence maps
  - `{:error, reason}` - If query fails
  """
  def find_movie_occurrences(movie_id, filter_criteria \\ %{}) do
    try do
      # Get venue_ids from filter_criteria
      venue_ids = get_filter_value(filter_criteria, :venue_ids, [])

      # Query events with their JSONB occurrences field
      events_query =
        from(pe in PublicEvent,
          join: em in EventMovie,
          on: em.event_id == pe.id,
          join: m in Movie,
          on: em.movie_id == m.id,
          left_join: v in Venue,
          on: pe.venue_id == v.id,
          where: em.movie_id == ^movie_id,
          select: %{
            public_event_id: pe.id,
            movie_id: m.id,
            venue_id: pe.venue_id,
            title: pe.title,
            movie_title: m.title,
            venue_name: v.name,
            venue_city_id: v.city_id,
            occurrences: pe.occurrences
          }
        )

      # Apply venue filter if specified
      events_query =
        if is_list(venue_ids) and length(venue_ids) > 0 do
          from([pe, em, m, v] in events_query, where: pe.venue_id in ^venue_ids)
        else
          events_query
        end

      # Apply city filter if specified
      city_ids = get_filter_value(filter_criteria, :city_ids, [])

      events_query =
        if is_list(city_ids) and length(city_ids) > 0 do
          from([pe, em, m, v] in events_query, where: v.city_id in ^city_ids)
        else
          events_query
        end

      events = Repo.all(events_query)

      # Extract individual showtimes from JSONB occurrences field
      date_range = get_date_range(filter_criteria)
      time_preferences = get_filter_value(filter_criteria, :time_preferences, [])
      limit = get_filter_value(filter_criteria, :limit, @default_limit)

      # Build list of individual showtimes with proper datetime field
      all_showtimes =
        events
        |> Enum.flat_map(fn event ->
          extract_showtimes_from_event(event, date_range, time_preferences)
        end)
        |> Enum.sort_by(fn showtime -> showtime.datetime end, DateTime)

      # Apply smart sampling: distribute limit evenly across dates instead of
      # just taking first N chronologically (fixes issue #3245 bug #2)
      sampled_showtimes = smart_sample_across_dates(all_showtimes, limit)

      {:ok, sampled_showtimes}
    rescue
      e ->
        {:error, "Failed to query movie occurrences: #{Exception.message(e)}"}
    end
  end

  @doc """
  Finds occurrences for a specific event (single venue).

  This is used when viewing a specific event page to constrain results
  to only that venue's showtimes, rather than all venues showing the same movie.

  ## Parameters

  - `event_id` - Integer ID of the public_event
  - `filter_criteria` - Map with optional filters (date_range, time_preferences, limit)

  ## Returns

  - `{:ok, occurrences}` - List of occurrence maps for this specific event
  - `{:error, reason}` - If query fails
  """
  def find_event_occurrences(event_id, filter_criteria \\ %{}) do
    try do
      # Query the specific event with its JSONB occurrences field
      event_query =
        from(pe in PublicEvent,
          left_join: v in Venue,
          on: pe.venue_id == v.id,
          left_join: em in EventMovie,
          on: em.event_id == pe.id,
          left_join: m in Movie,
          on: em.movie_id == m.id,
          where: pe.id == ^event_id,
          select: %{
            public_event_id: pe.id,
            movie_id: m.id,
            venue_id: pe.venue_id,
            title: pe.title,
            movie_title: m.title,
            venue_name: v.name,
            venue_city_id: v.city_id,
            occurrences: pe.occurrences
          }
        )

      case Repo.one(event_query) do
        nil ->
          {:ok, []}

        event ->
          # Extract individual showtimes from JSONB occurrences field
          date_range = get_date_range(filter_criteria)
          time_preferences = get_filter_value(filter_criteria, :time_preferences, [])
          limit = get_filter_value(filter_criteria, :limit, @default_limit)

          # Build list of individual showtimes with proper datetime field
          all_showtimes =
            extract_showtimes_from_event(event, date_range, time_preferences)
            |> Enum.sort_by(fn showtime -> showtime.datetime end, DateTime)

          # Apply smart sampling
          sampled_showtimes = smart_sample_across_dates(all_showtimes, limit)

          {:ok, sampled_showtimes}
      end
    rescue
      e ->
        {:error, "Failed to query event occurrences: #{Exception.message(e)}"}
    end
  end

  # Smart sampling: distribute the limit evenly across dates instead of
  # just taking the first N chronologically. This ensures users see options
  # across their entire selected date range, not just the first day or two.
  #
  # Algorithm:
  # 1. Group showtimes by date
  # 2. Calculate how many to take per date (round-robin distribution)
  # 3. Take proportionally from each date, preserving chronological order within each date
  # 4. Sort final result chronologically
  defp smart_sample_across_dates(showtimes, limit) when length(showtimes) <= limit do
    # No sampling needed - return all
    showtimes
  end

  defp smart_sample_across_dates(showtimes, limit) do
    # Group by date
    by_date =
      showtimes
      |> Enum.group_by(fn showtime ->
        case showtime.datetime do
          %DateTime{} = dt -> DateTime.to_date(dt)
          _ -> showtime.date
        end
      end)
      |> Enum.sort_by(fn {date, _} -> date end, Date)

    num_dates = length(by_date)

    if num_dates == 0 do
      []
    else
      # Base allocation: how many per date minimum
      base_per_date = div(limit, num_dates)
      # Remainder to distribute to earlier dates
      remainder = rem(limit, num_dates)

      # Take from each date proportionally
      {sampled, _} =
        Enum.reduce(by_date, {[], remainder}, fn {_date, date_showtimes}, {acc, extra} ->
          # Give extra 1 to first 'remainder' dates
          take_count = if extra > 0, do: base_per_date + 1, else: base_per_date

          # Take from this date's showtimes (already sorted chronologically)
          taken = Enum.take(date_showtimes, take_count)

          {acc ++ taken, max(0, extra - 1)}
        end)

      # Sort final result chronologically
      Enum.sort_by(sampled, fn showtime -> showtime.datetime end, DateTime)
    end
  end

  # Extract individual showtimes from an event's JSONB occurrences field
  defp extract_showtimes_from_event(event, date_range, time_preferences) do
    case event.occurrences do
      %{"dates" => dates} when is_list(dates) ->
        dates
        |> maybe_filter_by_date_range(date_range)
        |> maybe_filter_by_time_preferences(time_preferences)
        |> Enum.map(fn showtime ->
          datetime = parse_showtime_datetime(showtime)

          %{
            public_event_id: event.public_event_id,
            movie_id: event.movie_id,
            venue_id: event.venue_id,
            datetime: datetime,
            date: showtime["date"],
            time: showtime["time"],
            title: event.title,
            movie_title: event.movie_title,
            venue_name: event.venue_name,
            venue_city_id: event.venue_city_id
          }
        end)

      _ ->
        []
    end
  end

  # Parse date and time strings into a DateTime
  defp parse_showtime_datetime(%{"date" => date_str, "time" => time_str})
       when is_binary(date_str) and is_binary(time_str) do
    with {:ok, date} <- Date.from_iso8601(date_str),
         {:ok, time} <- parse_time_string(time_str) do
      DateTime.new!(date, time, "Etc/UTC")
    else
      _ -> nil
    end
  end

  defp parse_showtime_datetime(_), do: nil

  # Parse time string, handling both HH:MM and HH:MM:SS formats
  defp parse_time_string(time_str) do
    # If already has seconds (HH:MM:SS), use as-is; otherwise append :00
    normalized =
      case String.split(time_str, ":") do
        [_h, _m, _s] -> time_str
        [_h, _m] -> time_str <> ":00"
        _ -> time_str
      end

    Time.from_iso8601(normalized)
  end

  # Filter showtimes by date range if specified
  defp maybe_filter_by_date_range(showtimes, []), do: showtimes

  defp maybe_filter_by_date_range(showtimes, date_range) when is_list(date_range) do
    date_strings = Enum.map(date_range, &Date.to_iso8601/1)

    Enum.filter(showtimes, fn showtime ->
      showtime["date"] in date_strings
    end)
  end

  @doc """
  Finds occurrences for discovery mode (no specific series).

  Returns movie showtimes across all movies matching the filter criteria.
  Useful for "What movie should we watch?" type polls.

  ## Parameters

  - `filter_criteria` - Map of filters (date_range, time_preferences, venue_ids, city_ids, limit)

  ## Returns

  - `{:ok, occurrences}` - List of occurrence maps
  - `{:error, reason}` - If query fails
  """
  def find_discovery_occurrences(filter_criteria \\ %{}) do
    try do
      query =
        from(pe in PublicEvent,
          join: em in EventMovie,
          on: em.event_id == pe.id,
          join: m in Movie,
          on: em.movie_id == m.id,
          left_join: v in Venue,
          on: pe.venue_id == v.id,
          select: %{
            public_event_id: pe.id,
            movie_id: m.id,
            venue_id: pe.venue_id,
            starts_at: pe.starts_at,
            ends_at: pe.ends_at,
            title: pe.title,
            movie_title: m.title,
            venue_name: v.name,
            venue_city_id: v.city_id
          },
          order_by: [asc: pe.starts_at]
        )

      query
      |> apply_date_range_filter(filter_criteria)
      |> apply_time_preferences_filter(filter_criteria)
      |> apply_venue_filter(filter_criteria)
      |> apply_city_filter(filter_criteria)
      |> apply_limit(filter_criteria)
      |> Repo.all()
      |> then(&{:ok, &1})
    rescue
      e ->
        {:error, "Failed to query discovery occurrences: #{Exception.message(e)}"}
    end
  end

  @doc """
  Finds venue occurrences (time slots) for a specific venue.

  Returns a list of time slot occurrences based on meal periods.
  Generates synthetic time slots since venues have continuous availability.

  ## Parameters

  - `venue_id` - The venue ID to find time slots for
  - `filter_criteria` - Map of filters (date_range, meal_periods, limit)

  ## Returns

  - `{:ok, occurrences}` - List of occurrence maps
  - `{:error, reason}` - If query fails
  """
  def find_venue_occurrences(venue_id, filter_criteria \\ %{}) do
    try do
      venue = Repo.get!(Venue, venue_id) |> Repo.preload(:city_ref)

      # Generate time slots based on date_range and meal_periods
      time_slots = generate_venue_time_slots(venue, filter_criteria)

      {:ok, time_slots}
    rescue
      Ecto.NoResultsError ->
        {:error, "Venue not found: #{venue_id}"}

      e ->
        {:error, "Failed to query venue occurrences: #{Exception.message(e)}"}
    end
  end

  @doc """
  Universal occurrence finder that handles both specific series and discovery mode.

  Delegates to the appropriate function based on series_type and series_id.

  ## Parameters

  - `series_type` - "movie", "venue", "activity_series", etc. or nil for discovery
  - `series_id` - ID of the series entity, or nil for discovery
  - `filter_criteria` - Map of filters

  ## Returns

  - `{:ok, occurrences}` - List of occurrence maps
  - `{:error, reason}` - If query fails or unsupported series type
  """
  def find_occurrences(series_type, series_id, filter_criteria \\ %{})

  def find_occurrences("movie", movie_id, filter_criteria) when is_integer(movie_id) do
    find_movie_occurrences(movie_id, filter_criteria)
  end

  def find_occurrences("venue", venue_id, filter_criteria) when is_integer(venue_id) do
    find_venue_occurrences(venue_id, filter_criteria)
  end

  def find_occurrences("event", event_id, filter_criteria) when is_integer(event_id) do
    find_event_occurrences(event_id, filter_criteria)
  end

  def find_occurrences(nil, nil, filter_criteria) do
    find_discovery_occurrences(filter_criteria)
  end

  def find_occurrences(series_type, _series_id, _filter_criteria) do
    {:error, "Unsupported series type: #{series_type}. Supported types: 'movie', 'venue', 'event'"}
  end

  @doc """
  Gets availability counts per date for a given series.

  Returns a map of date to count: %{~D[2025-11-25] => 3, ~D[2025-11-26] => 0, ...}

  ## Parameters

  - `series_type` - "movie", "venue", or nil for discovery
  - `series_id` - ID of the series entity, or nil for discovery
  - `date_list` - List of dates to check availability for
  - `filter_criteria` - Optional filters (time_preferences, meal_periods, venue_ids, city_ids)

  ## Returns

  - `{:ok, %{Date.t() => non_neg_integer()}}` - Map of date to count
  - `{:error, reason}` - If query fails

  ## Examples

      iex> get_date_availability_counts("movie", 123, [~D[2025-11-25], ~D[2025-11-26]], %{})
      {:ok, %{~D[2025-11-25] => 3, ~D[2025-11-26] => 0}}
  """
  def get_date_availability_counts(series_type, series_id, date_list, filter_criteria \\ %{})

  def get_date_availability_counts("movie", movie_id, date_list, filter_criteria)
      when is_integer(movie_id) do
    try do
      # Get venue_ids and city_ids from filter_criteria (handle both atom and string keys)
      venue_ids = get_filter_value(filter_criteria, :venue_ids, [])
      city_ids = get_filter_value(filter_criteria, :city_ids, [])

      # Get all events linked to this movie with their occurrences JSONB
      # Optionally filtered by venue_ids and/or city_ids if provided
      events_query =
        from(pe in PublicEvent,
          join: em in EventMovie,
          on: em.event_id == pe.id,
          left_join: v in Venue,
          on: pe.venue_id == v.id,
          where: em.movie_id == ^movie_id,
          select: pe.occurrences
        )

      # Apply venue filter if specified
      events_query =
        if is_list(venue_ids) and length(venue_ids) > 0 do
          from([pe, em, v] in events_query, where: pe.venue_id in ^venue_ids)
        else
          events_query
        end

      # Apply city filter if specified (constrains to venues in specified cities)
      events_query =
        if is_list(city_ids) and length(city_ids) > 0 do
          from([pe, em, v] in events_query, where: v.city_id in ^city_ids)
        else
          events_query
        end

      all_occurrences = Repo.all(events_query)

      # Extract all showtimes from the JSONB occurrences field
      all_showtimes =
        all_occurrences
        |> Enum.flat_map(fn occurrences ->
          case occurrences do
            %{"dates" => dates} when is_list(dates) -> dates
            _ -> []
          end
        end)

      # Count showtimes for each date in the date_list
      time_preferences = get_filter_value(filter_criteria, :time_preferences, [])

      counts =
        Enum.reduce(date_list, %{}, fn date, acc ->
          date_string = Date.to_iso8601(date)

          # Filter showtimes for this date
          matching_showtimes =
            all_showtimes
            |> Enum.filter(fn showtime ->
              showtime["date"] == date_string
            end)
            |> maybe_filter_by_time_preferences(time_preferences)

          Map.put(acc, date, length(matching_showtimes))
        end)

      {:ok, counts}
    rescue
      e ->
        {:error, "Failed to get date availability counts: #{Exception.message(e)}"}
    end
  end

  def get_date_availability_counts("venue", venue_id, date_list, filter_criteria)
      when is_integer(venue_id) do
    try do
      # For venues, we generate time slots, so count based on meal_periods
      meal_periods = get_meal_periods(filter_criteria)

      counts =
        Enum.reduce(date_list, %{}, fn date, acc ->
          # Count how many meal periods apply to this date
          count =
            Enum.count(meal_periods, fn meal_period ->
              should_include_meal_period?(date, meal_period)
            end)

          Map.put(acc, date, count)
        end)

      {:ok, counts}
    rescue
      e ->
        {:error, "Failed to get date availability counts: #{Exception.message(e)}"}
    end
  end

  def get_date_availability_counts(nil, nil, date_list, filter_criteria) do
    try do
      # Discovery mode - count all movie occurrences
      counts =
        Enum.reduce(date_list, %{}, fn date, acc ->
          date_filter =
            Map.put(filter_criteria, :date_range, %{start: date, end: date})

          case find_discovery_occurrences(date_filter) do
            {:ok, occurrences} ->
              Map.put(acc, date, length(occurrences))

            {:error, _} ->
              Map.put(acc, date, 0)
          end
        end)

      {:ok, counts}
    rescue
      e ->
        {:error, "Failed to get date availability counts: #{Exception.message(e)}"}
    end
  end

  # Gets date availability counts from an event's occurrences JSONB field.
  # This handles standard events (like trivia nights) that have actual occurrence
  # data, as opposed to venue-based meal period generation.
  #
  # Supports dynamic filtering: when time_preferences are provided in filter_criteria,
  # only showtimes matching those time preferences are counted for each date.
  # This enables the "dynamic counts" UX where selecting "Afternoon" updates
  # the date counts to show only afternoon showtimes per date.
  def get_date_availability_counts("event", event_id, date_list, filter_criteria)
      when is_integer(event_id) do
    try do
      # Get the event's occurrences JSONB
      event_query =
        from(pe in PublicEvent,
          where: pe.id == ^event_id,
          select: pe.occurrences
        )

      occurrences_data = Repo.one(event_query)

      # Extract time_preferences from filter_criteria for dynamic filtering
      time_preferences = get_filter_value(filter_criteria, :time_preferences, [])

      # Count occurrences per date, optionally filtered by time preferences
      counts = count_event_occurrences_per_date_filtered(occurrences_data, date_list, time_preferences)

      {:ok, counts}
    rescue
      e ->
        {:error, "Failed to get event date availability counts: #{Exception.message(e)}"}
    end
  end

  def get_date_availability_counts(series_type, _series_id, _date_list, _filter_criteria) do
    {:error, "Unsupported series type: #{series_type}. Supported types: 'movie', 'venue', 'event'"}
  end

  # Helper functions for JSONB showtime filtering

  # Filter showtimes by time preferences if specified
  defp maybe_filter_by_time_preferences(showtimes, []), do: showtimes

  defp maybe_filter_by_time_preferences(showtimes, time_preferences) do
    Enum.filter(showtimes, fn showtime ->
      case showtime["time"] do
        nil ->
          false

        time_string ->
          hour = parse_hour_from_time_string(time_string)
          time_slot = hour_to_time_slot(hour)
          time_slot in time_preferences
      end
    end)
  end

  defp parse_hour_from_time_string(time_string) do
    case String.split(time_string, ":") do
      [hour_str | _] -> String.to_integer(hour_str)
      _ -> 0
    end
  end

  defp hour_to_time_slot(hour) when hour >= 6 and hour < 12, do: "morning"
  defp hour_to_time_slot(hour) when hour >= 12 and hour < 17, do: "afternoon"
  defp hour_to_time_slot(hour) when hour >= 17 and hour < 22, do: "evening"
  defp hour_to_time_slot(_hour), do: "late_night"

  # Private filter application functions

  # Handle map format (for persisted filter_criteria from JSONB)
  defp apply_date_range_filter(query, %{date_range: %{start: start_date, end: end_date}}) do
    start_datetime = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_datetime = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    from(q in query,
      where: q.starts_at >= ^start_datetime and q.starts_at <= ^end_datetime
    )
  end

  # Handle tuple format (for backward compatibility)
  defp apply_date_range_filter(query, %{date_range: {start_date, end_date}}) do
    start_datetime = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_datetime = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    from(q in query,
      where: q.starts_at >= ^start_datetime and q.starts_at <= ^end_datetime
    )
  end

  defp apply_date_range_filter(query, _), do: query

  defp apply_time_preferences_filter(query, %{time_preferences: preferences})
       when is_list(preferences) and length(preferences) > 0 do
    # Build time range conditions for each preference
    conditions =
      Enum.map(preferences, fn pref ->
        case time_range_for_preference(pref) do
          # Special case for late_night which wraps around midnight (22:00-02:00)
          {:wrap, start_hour, end_hour} ->
            dynamic(
              [q],
              fragment("EXTRACT(HOUR FROM ? AT TIME ZONE 'UTC')::integer", q.starts_at) >=
                ^start_hour or
                fragment("EXTRACT(HOUR FROM ? AT TIME ZONE 'UTC')::integer", q.starts_at) <
                  ^end_hour
            )

          {start_hour, end_hour} ->
            dynamic(
              [q],
              fragment("EXTRACT(HOUR FROM ? AT TIME ZONE 'UTC')::integer", q.starts_at) >=
                ^start_hour and
                fragment("EXTRACT(HOUR FROM ? AT TIME ZONE 'UTC')::integer", q.starts_at) <
                  ^end_hour
            )

          nil ->
            false
        end
      end)
      |> Enum.filter(&(&1 != false))

    # Combine with OR logic
    if length(conditions) > 0 do
      combined_condition =
        Enum.reduce(conditions, fn condition, acc ->
          dynamic([], ^acc or ^condition)
        end)

      from(q in query, where: ^combined_condition)
    else
      query
    end
  end

  defp apply_time_preferences_filter(query, _), do: query

  defp apply_venue_filter(query, %{venue_ids: venue_ids})
       when is_list(venue_ids) and length(venue_ids) > 0 do
    from(q in query, where: q.venue_id in ^venue_ids)
  end

  defp apply_venue_filter(query, _), do: query

  defp apply_city_filter(query, %{city_ids: city_ids})
       when is_list(city_ids) and length(city_ids) > 0 do
    from([_pe, _em, _m, v] in query, where: v.city_id in ^city_ids)
  end

  defp apply_city_filter(query, _), do: query

  defp apply_limit(query, %{limit: limit}) when is_integer(limit) and limit > 0 do
    from(q in query, limit: ^limit)
  end

  defp apply_limit(query, _) do
    from(q in query, limit: ^@default_limit)
  end

  # Time preference to hour range mapping
  # These must match hour_to_time_slot/1 for consistent filtering
  defp time_range_for_preference("morning"), do: {6, 12}
  defp time_range_for_preference("afternoon"), do: {12, 17}
  defp time_range_for_preference("evening"), do: {17, 22}
  # late_night wraps around midnight: 22:00-06:00 (matches hour_to_time_slot)
  defp time_range_for_preference("late_night"), do: {:wrap, 22, 6}
  defp time_range_for_preference(_), do: nil

  # Venue time slot generation

  defp generate_venue_time_slots(venue, filter_criteria) do
    date_range = get_date_range(filter_criteria)
    meal_periods = get_meal_periods(filter_criteria)
    limit = get_filter_value(filter_criteria, :limit, @default_limit)

    # Generate time slots for each date × meal period combination
    time_slots =
      for date <- date_range,
          meal_period <- meal_periods,
          should_include_meal_period?(date, meal_period) do
        create_venue_time_slot(venue, date, meal_period)
      end
      |> Enum.take(limit)

    time_slots
  end

  # Get date range, handling both atom and string keys
  defp get_date_range(filter_criteria) do
    date_range = get_filter_value(filter_criteria, :date_range, nil)

    case date_range do
      %{start: start_date, end: end_date} ->
        Date.range(start_date, end_date) |> Enum.to_list()

      {start_date, end_date} ->
        Date.range(start_date, end_date) |> Enum.to_list()

      _ ->
        []
    end
  end

  # Get meal periods, handling both atom and string keys
  defp get_meal_periods(filter_criteria) do
    periods = get_filter_value(filter_criteria, :meal_periods, [])

    if is_list(periods) and length(periods) > 0 do
      periods
    else
      # Default to all meal periods if none specified or empty list
      ["breakfast", "lunch", "dinner"]
    end
  end

  defp should_include_meal_period?(date, "brunch") do
    # Brunch only on weekends
    Date.day_of_week(date) in [6, 7]
  end

  defp should_include_meal_period?(_date, _meal_period), do: true

  defp create_venue_time_slot(venue, date, meal_period) do
    {start_hour, start_minute, end_hour, end_minute} = meal_period_to_time_range(meal_period)

    # Create starts_at datetime with explicit UTC timezone
    starts_at = DateTime.new!(date, Time.new!(start_hour, start_minute, 0), "Etc/UTC")

    # Handle cross-midnight slots (e.g., late_night 22:00-01:00)
    # If end_hour < start_hour, the slot spans midnight, so add 1 day to end date
    end_date = if end_hour < start_hour, do: Date.add(date, 1), else: date
    ends_at = DateTime.new!(end_date, Time.new!(end_hour, end_minute, 0), "Etc/UTC")

    %{
      venue_id: venue.id,
      venue_name: venue.name,
      venue_city_id: venue.city_id,
      date: date,
      meal_period: meal_period,
      starts_at: starts_at,
      ends_at: ends_at
    }
  end

  # Meal period to time range mapping (start_hour, start_min, end_hour, end_min)
  defp meal_period_to_time_range("breakfast"), do: {8, 0, 11, 0}
  defp meal_period_to_time_range("brunch"), do: {10, 0, 14, 0}
  defp meal_period_to_time_range("lunch"), do: {12, 0, 15, 0}
  defp meal_period_to_time_range("dinner"), do: {18, 0, 22, 0}
  defp meal_period_to_time_range("late_night"), do: {22, 0, 2, 0}
  # Default to lunch hours if unknown
  defp meal_period_to_time_range(_), do: {12, 0, 15, 0}

  # Helper to get filter values supporting both atom and string keys
  # This handles cases where filter_criteria comes from different sources
  # (LiveView assigns use atoms, JSON/external data may use strings)
  defp get_filter_value(filter_criteria, key, default) when is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(filter_criteria, key) -> Map.get(filter_criteria, key)
      Map.has_key?(filter_criteria, string_key) -> Map.get(filter_criteria, string_key)
      true -> default
    end
  end

  # Event occurrence counting helpers

  # Count event occurrences per date with optional time preference filtering.
  # This enables the "dynamic counts" UX where selecting a time preference
  # updates the date counts to show only showtimes in that time period.
  defp count_event_occurrences_per_date_filtered(nil, date_list, _time_preferences) do
    # No occurrences data - return zeros for all dates
    Enum.reduce(date_list, %{}, fn date, acc -> Map.put(acc, date, 0) end)
  end

  defp count_event_occurrences_per_date_filtered(%{"dates" => dates}, date_list, time_preferences)
       when is_list(dates) do
    # First filter by time preferences if specified
    filtered_dates =
      if time_preferences == [] do
        dates
      else
        Enum.filter(dates, fn showtime ->
          case showtime["time"] do
            nil -> false
            time_string ->
              hour = parse_hour_from_time_string(time_string)
              time_slot = hour_to_time_slot(hour)
              time_slot in time_preferences
          end
        end)
      end

    # Then count occurrences per date from filtered list
    Enum.reduce(date_list, %{}, fn date, acc ->
      date_string = Date.to_iso8601(date)

      count =
        Enum.count(filtered_dates, fn showtime ->
          showtime["date"] == date_string
        end)

      Map.put(acc, date, count)
    end)
  end

  defp count_event_occurrences_per_date_filtered(%{"type" => "pattern", "pattern" => pattern}, date_list, time_preferences) do
    # For pattern-based recurring events, check if the pattern's fixed time
    # matches the requested time preferences
    time_string = pattern["time"] || "19:00"
    hour = parse_hour_from_time_string(time_string)
    period = hour_to_time_slot(hour)

    # If time preferences specified and pattern doesn't match, return zeros
    if time_preferences != [] and period not in time_preferences do
      Enum.reduce(date_list, %{}, fn date, acc -> Map.put(acc, date, 0) end)
    else
      # Count matching dates based on weekday pattern
      target_weekdays = get_pattern_weekdays(pattern)

      Enum.reduce(date_list, %{}, fn date, acc ->
        day_of_week = Date.day_of_week(date)

        count =
          if day_of_week in target_weekdays do
            1
          else
            0
          end

        Map.put(acc, date, count)
      end)
    end
  end

  defp count_event_occurrences_per_date_filtered(_occurrences_data, date_list, _time_preferences) do
    # Unknown format - return zeros
    Enum.reduce(date_list, %{}, fn date, acc -> Map.put(acc, date, 0) end)
  end

  # Extract target weekdays from pattern
  # Returns list of day-of-week integers (1=Monday, 7=Sunday)
  defp get_pattern_weekdays(%{"days" => days}) when is_list(days), do: days

  defp get_pattern_weekdays(%{"day" => day}) when is_integer(day), do: [day]

  defp get_pattern_weekdays(%{"day_of_week" => dow}) when is_integer(dow), do: [dow]

  # Handle string day names in a list (e.g., ["monday", "wednesday"])
  defp get_pattern_weekdays(%{"days_of_week" => days}) when is_list(days) do
    Enum.map(days, &day_name_to_number/1) |> Enum.filter(&(&1 > 0))
  end

  # Handle single string day name
  defp get_pattern_weekdays(%{"day" => day_name}) when is_binary(day_name) do
    [day_name_to_number(day_name)]
  end

  defp get_pattern_weekdays(_), do: []

  defp day_name_to_number(name) do
    case String.downcase(name) do
      "monday" -> 1
      "tuesday" -> 2
      "wednesday" -> 3
      "thursday" -> 4
      "friday" -> 5
      "saturday" -> 6
      "sunday" -> 7
      _ -> 0
    end
  end

  # =============================================================================
  # Time Period Availability Counts
  # =============================================================================

  @doc """
  Returns counts of occurrences grouped by time period (morning, afternoon, evening, late_night).

  This enables data-driven time preference filtering in the Plan with Friends modal,
  showing only time periods that have actual occurrences.

  ## Parameters

  - `series_type` - "movie", "event", or "venue"
  - `series_id` - ID of the movie, event, or venue
  - `filter_criteria` - Optional filter criteria (date range, etc.)

  ## Returns

  `{:ok, %{"morning" => 0, "afternoon" => 3, "evening" => 15, "late_night" => 5}}`

  ## Time Period Mapping

  - `"morning"`: 06:00-12:00
  - `"afternoon"`: 12:00-17:00
  - `"evening"`: 17:00-22:00
  - `"late_night"`: 22:00-06:00
  """
  def get_time_period_availability_counts(series_type, series_id, filter_criteria \\ %{})

  def get_time_period_availability_counts("movie", movie_id, filter_criteria)
      when is_integer(movie_id) do
    try do
      # Get date range from filter_criteria or default to 7 days
      date_list = get_date_list_from_criteria(filter_criteria)

      # Get venue_ids and city_ids from filter_criteria
      venue_ids = get_filter_value(filter_criteria, :venue_ids, [])
      city_ids = get_filter_value(filter_criteria, :city_ids, [])

      # Get all events linked to this movie, optionally filtered by venue/city
      events_query =
        from(pe in PublicEvent,
          join: em in EventMovie,
          on: em.event_id == pe.id,
          left_join: v in Venue,
          on: pe.venue_id == v.id,
          where: em.movie_id == ^movie_id,
          select: pe.occurrences
        )

      # Apply venue filter if specified
      events_query =
        if is_list(venue_ids) and length(venue_ids) > 0 do
          from([pe, em, v] in events_query, where: pe.venue_id in ^venue_ids)
        else
          events_query
        end

      # Apply city filter if specified (constrains to venues in specified cities)
      events_query =
        if is_list(city_ids) and length(city_ids) > 0 do
          from([pe, em, v] in events_query, where: v.city_id in ^city_ids)
        else
          events_query
        end

      all_occurrences = Repo.all(events_query)

      # Extract all showtimes from the JSONB occurrences field
      all_showtimes =
        all_occurrences
        |> Enum.flat_map(fn occurrences ->
          case occurrences do
            %{"dates" => dates} when is_list(dates) -> dates
            _ -> []
          end
        end)
        |> Enum.filter(fn showtime ->
          # Filter by date range if specified
          case showtime["date"] do
            nil -> false
            date_str ->
              case Date.from_iso8601(date_str) do
                {:ok, date} -> date in date_list
                _ -> false
              end
          end
        end)

      # Count by time period
      counts = count_showtimes_by_time_period(all_showtimes)
      {:ok, counts}
    rescue
      e ->
        {:error, "Failed to get time period availability counts: #{Exception.message(e)}"}
    end
  end

  # Gets time period availability counts from an event's occurrences JSONB field.
  #
  # Supports dynamic filtering: when selected_dates are provided in filter_criteria,
  # only showtimes on those specific dates are counted for each time period.
  # This enables the "dynamic counts" UX where selecting "Thursday" updates
  # the time period counts to show only Thursday's distribution.
  def get_time_period_availability_counts("event", event_id, filter_criteria)
      when is_integer(event_id) do
    try do
      # Check for selected_dates first (specific dates selected by user)
      # Fall back to date_range or default 7-day range
      date_list = get_date_list_for_time_periods(filter_criteria)

      # Get the event's occurrences JSONB
      event_query =
        from(pe in PublicEvent,
          where: pe.id == ^event_id,
          select: pe.occurrences
        )

      occurrences_data = Repo.one(event_query)

      # Count occurrences by time period, filtered to selected dates
      counts = count_event_occurrences_by_time_period(occurrences_data, date_list)
      {:ok, counts}
    rescue
      e ->
        {:error, "Failed to get event time period availability counts: #{Exception.message(e)}"}
    end
  end

  def get_time_period_availability_counts(_series_type, _series_id, _filter_criteria) do
    # Default: return empty counts (no time filtering needed)
    {:ok, %{"morning" => 0, "afternoon" => 0, "evening" => 0, "late_night" => 0}}
  end

  # Helper to get date list from filter criteria or default to 7 days
  defp get_date_list_from_criteria(%{date_range: %{start: start_date, end: end_date}}) do
    Date.range(start_date, end_date) |> Enum.to_list()
  end

  defp get_date_list_from_criteria(_) do
    # Default: next 7 days
    today = Date.utc_today()
    end_date = Date.add(today, 7)
    Date.range(today, end_date) |> Enum.to_list()
  end

  # Get date list for time period calculations, prioritizing selected_dates.
  # This enables dynamic counts: when user selects specific dates, the time
  # period counts update to show only those dates' distribution.
  defp get_date_list_for_time_periods(filter_criteria) do
    # First check for selected_dates (specific dates chosen by user in UI)
    selected_dates = get_filter_value(filter_criteria, :selected_dates, [])

    if selected_dates != [] do
      # Parse date strings to Date structs
      selected_dates
      |> Enum.map(fn date_str ->
        case Date.from_iso8601(date_str) do
          {:ok, date} -> date
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
    else
      # Fall back to date_range or default
      get_date_list_from_criteria(filter_criteria)
    end
  end

  # Count showtimes by time period from JSONB showtime data
  defp count_showtimes_by_time_period(showtimes) do
    initial_counts = %{"morning" => 0, "afternoon" => 0, "evening" => 0, "late_night" => 0}

    Enum.reduce(showtimes, initial_counts, fn showtime, acc ->
      case showtime["time"] do
        nil -> acc
        time_string ->
          hour = parse_hour_from_time_string(time_string)
          period = hour_to_time_slot(hour)
          Map.update!(acc, period, &(&1 + 1))
      end
    end)
  end

  # Count event occurrences by time period
  defp count_event_occurrences_by_time_period(nil, _date_list) do
    %{"morning" => 0, "afternoon" => 0, "evening" => 0, "late_night" => 0}
  end

  defp count_event_occurrences_by_time_period(%{"dates" => dates}, date_list) when is_list(dates) do
    initial_counts = %{"morning" => 0, "afternoon" => 0, "evening" => 0, "late_night" => 0}

    dates
    |> Enum.filter(fn showtime ->
      case showtime["date"] do
        nil -> false
        date_str ->
          case Date.from_iso8601(date_str) do
            {:ok, date} -> date in date_list
            _ -> false
          end
      end
    end)
    |> Enum.reduce(initial_counts, fn showtime, acc ->
      case showtime["time"] do
        nil -> acc
        time_string ->
          hour = parse_hour_from_time_string(time_string)
          period = hour_to_time_slot(hour)
          Map.update!(acc, period, &(&1 + 1))
      end
    end)
  end

  defp count_event_occurrences_by_time_period(%{"type" => "pattern", "pattern" => pattern}, date_list) do
    # For pattern-based recurring events, count based on the fixed time
    initial_counts = %{"morning" => 0, "afternoon" => 0, "evening" => 0, "late_night" => 0}

    time_string = pattern["time"] || "19:00"
    hour = parse_hour_from_time_string(time_string)
    period = hour_to_time_slot(hour)

    # Count matching dates
    target_weekdays = get_pattern_weekdays(pattern)

    matching_count =
      Enum.count(date_list, fn date ->
        Date.day_of_week(date) in target_weekdays
      end)

    Map.put(initial_counts, period, matching_count)
  end

  defp count_event_occurrences_by_time_period(_occurrences_data, _date_list) do
    %{"morning" => 0, "afternoon" => 0, "evening" => 0, "late_night" => 0}
  end
end
