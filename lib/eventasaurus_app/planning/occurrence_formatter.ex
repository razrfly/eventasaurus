defmodule EventasaurusApp.Planning.OccurrenceFormatter do
  @moduledoc """
  Formats occurrence query results into poll option attributes.

  Converts raw occurrence data (movie showtimes, venue slots, etc.) into structured
  poll option maps that can be inserted as PollOption records.

  ## Format Patterns

  ### Movie Occurrences

  **Title Format**: `"{Movie Title} @ {Venue Name}"`
  **Description Format**: `"{Day of Week}, {Date} at {Time}"`

  Example:
  - Title: "Dune: Part Two @ Cinema City Arkadia"
  - Description: "Friday, Nov 25 at 7:00 PM"

  ### Venue Time Slot Occurrences

  **Title Format**: `"{Venue Name} - {Meal Period}"`
  **Description Format**: `"{Day of Week}, {Date} from {Start} to {End}"`

  Example:
  - Title: "La Forchetta - Dinner"
  - Description: "Friday, Nov 25 from 6:00 PM to 10:00 PM"

  ### External ID Formats

  - Movie: `"event:{public_event_id}"`
  - Venue: `"venue_slot:{venue_id}:{date}:{meal_period}"`

  ### Metadata Structure

  Movie showtime:
  ```elixir
  %{
    occurrence_type: "movie_showtime",
    public_event_id: 456,
    movie_id: 123,
    venue_id: 789,
    starts_at: "2024-11-25T19:00:00Z",
    ends_at: "2024-11-25T21:30:00Z"
  }
  ```

  Venue time slot:
  ```elixir
  %{
    occurrence_type: "venue_time_slot",
    venue_id: 789,
    date: "2024-11-25",
    meal_period: "dinner",
    starts_at: "2024-11-25T18:00:00Z",
    ends_at: "2024-11-25T22:00:00Z"
  }
  ```

  ## Examples

      iex> occurrences = [
      ...>   %{
      ...>     public_event_id: 456,
      ...>     movie_id: 123,
      ...>     movie_title: "Dune: Part Two",
      ...>     venue_id: 789,
      ...>     venue_name: "Cinema City Arkadia",
      ...>     starts_at: ~U[2024-11-25 19:00:00Z]
      ...>   }
      ...> ]
      iex> OccurrenceFormatter.format_movie_options(occurrences)
      [%{
        title: "Dune: Part Two @ Cinema City Arkadia",
        description: "Friday, Nov 25 at 7:00 PM",
        external_id: "event:456",
        external_data: %{...},
        metadata: %{...},
        order_index: 0
      }]
  """

  @doc """
  Formats movie occurrence query results into poll option attributes.

  Takes a list of occurrence maps from OccurrenceQuery and converts them
  into maps suitable for PollOption.creation_changeset/3.

  ## Parameters

  - `occurrences` - List of occurrence maps from OccurrenceQuery.find_movie_occurrences/2
  - `opts` - Options for formatting:
    - `:timezone` - Timezone for display (default: "UTC")
    - `:date_format` - :short or :long (default: :short)

  ## Returns

  List of maps with poll option attributes:
  - `:title` - Display title
  - `:description` - Formatted date/time description
  - `:external_id` - Event reference (e.g., "event:456")
  - `:external_data` - Full occurrence data
  - `:metadata` - Occurrence-specific metadata
  - `:order_index` - Display order (chronological)

  Note: `poll_id` and `suggested_by_id` must be added by caller before insertion.
  """
  def format_movie_options(occurrences, opts \\ []) do
    timezone = Keyword.get(opts, :timezone, "UTC")
    date_format = Keyword.get(opts, :date_format, :short)

    occurrences
    |> Enum.with_index()
    |> Enum.map(fn {occurrence, index} ->
      # Occurrence maps use :datetime field (from OccurrenceQuery)
      datetime = occurrence[:datetime] || occurrence[:starts_at]

      %{
        title: format_movie_title(occurrence),
        description: format_datetime_description(datetime, timezone, date_format),
        external_id: "event:#{occurrence.public_event_id}",
        external_data: build_external_data(occurrence, datetime),
        metadata: build_occurrence_metadata(occurrence, "movie_showtime", datetime),
        order_index: index
      }
    end)
  end

  @doc """
  Formats occurrences for discovery mode (multiple movies).

  Similar to format_movie_options/2 but includes movie title in description
  since users need to see which movie each option represents.

  ## Parameters

  - `occurrences` - List of occurrence maps
  - `opts` - Options for formatting

  ## Returns

  List of poll option attribute maps
  """
  def format_discovery_options(occurrences, opts \\ []) do
    timezone = Keyword.get(opts, :timezone, "UTC")
    date_format = Keyword.get(opts, :date_format, :short)

    occurrences
    |> Enum.with_index()
    |> Enum.map(fn {occurrence, index} ->
      # Occurrence maps use :datetime field (from OccurrenceQuery)
      datetime = occurrence[:datetime] || occurrence[:starts_at]

      %{
        title: format_discovery_title(occurrence),
        description: format_datetime_description(datetime, timezone, date_format),
        external_id: "event:#{occurrence.public_event_id}",
        external_data: build_external_data(occurrence, datetime),
        metadata: build_occurrence_metadata(occurrence, "movie_showtime", datetime),
        order_index: index
      }
    end)
  end

  @doc """
  Formats venue time slot occurrences into poll option attributes.

  Takes a list of venue time slot maps from OccurrenceQuery.find_venue_occurrences/2
  and converts them into poll option format.

  ## Parameters

  - `occurrences` - List of venue time slot maps
  - `opts` - Options for formatting:
    - `:timezone` - Timezone for display (default: "UTC")
    - `:date_format` - :short or :long (default: :short)

  ## Returns

  List of maps with poll option attributes.
  """
  def format_venue_options(occurrences, opts \\ []) do
    timezone = Keyword.get(opts, :timezone, "UTC")
    date_format = Keyword.get(opts, :date_format, :short)

    occurrences
    |> Enum.with_index()
    |> Enum.map(fn {occurrence, index} ->
      %{
        title: format_venue_title(occurrence),
        description: format_time_window_description(occurrence, timezone, date_format),
        external_id: format_venue_external_id(occurrence),
        external_data: build_venue_external_data(occurrence),
        metadata: build_venue_occurrence_metadata(occurrence),
        order_index: index
      }
    end)
  end

  @doc """
  Universal formatter that delegates based on occurrence data structure.

  Automatically detects the occurrence type:
  - Venue time slots (has `:meal_period` field)
  - Movie showtimes - single movie (all share same movie_id)
  - Movie showtimes - discovery mode (multiple movies)

  ## Parameters

  - `occurrences` - List of occurrence maps
  - `opts` - Options for formatting

  ## Returns

  List of poll option attribute maps
  """
  def format_options(occurrences, opts \\ []) do
    cond do
      venue_occurrence?(occurrences) ->
        format_venue_options(occurrences, opts)

      single_movie?(occurrences) ->
        format_movie_options(occurrences, opts)

      true ->
        format_discovery_options(occurrences, opts)
    end
  end

  @doc """
  Groups occurrences by day and formats with date headers.

  Returns a nested structure suitable for UI display with date groupings.

  ## Parameters

  - `occurrences` - List of occurrence maps
  - `opts` - Options for formatting

  ## Returns

  ```elixir
  [
    %{
      date: ~D[2024-11-25],
      date_label: "Friday, November 25",
      options: [%{title: "...", ...}, ...]
    },
    ...
  ]
  ```
  """
  def format_grouped_by_date(occurrences, opts \\ []) do
    timezone = Keyword.get(opts, :timezone, "UTC")

    occurrences
    |> Enum.group_by(fn occ ->
      datetime = occ[:datetime] || occ[:starts_at]

      datetime
      |> DateTime.shift_zone!(timezone)
      |> DateTime.to_date()
    end)
    |> Enum.map(fn {date, date_occurrences} ->
      %{
        date: date,
        date_label: format_date_label(date),
        options: format_options(date_occurrences, opts)
      }
    end)
    |> Enum.sort_by(& &1.date, Date)
  end

  # Private formatting functions

  defp format_movie_title(occurrence) do
    movie = occurrence.movie_title
    venue = occurrence.venue_name
    datetime = occurrence[:datetime] || occurrence[:starts_at]

    # Include time in title to make each showtime unique
    # Guard against nil datetime to prevent FunctionClauseError
    case datetime do
      nil -> "#{movie} @ #{venue}"
      dt -> "#{movie} @ #{venue} - #{Calendar.strftime(dt, "%I:%M %p")}"
    end
  end

  defp format_discovery_title(occurrence) do
    movie = occurrence.movie_title
    venue = occurrence.venue_name
    datetime = occurrence[:datetime] || occurrence[:starts_at]

    # Include time in title to make each showtime unique
    # Guard against nil datetime to prevent FunctionClauseError
    case datetime do
      nil -> "#{movie} @ #{venue}"
      dt -> "#{movie} @ #{venue} - #{Calendar.strftime(dt, "%I:%M %p")}"
    end
  end

  defp format_datetime_description(datetime, timezone, format) do
    case datetime do
      nil ->
        "Time to be determined"

      dt ->
        shifted = DateTime.shift_zone!(dt, timezone)

        day_name = Calendar.strftime(shifted, "%A")
        date_str = format_date(shifted, format)
        time_str = Calendar.strftime(shifted, "%I:%M %p")

        "#{day_name}, #{date_str} at #{time_str}"
    end
  end

  defp format_date(datetime, :short) do
    Calendar.strftime(datetime, "%b %d")
  end

  defp format_date(datetime, :long) do
    Calendar.strftime(datetime, "%B %d, %Y")
  end

  defp format_date_label(date) do
    # Format for grouped display
    Calendar.strftime(date, "%A, %B %d")
  end

  defp build_external_data(occurrence, datetime) do
    ends_at = occurrence[:ends_at] || occurrence[:end_datetime]

    %{
      "public_event_id" => occurrence.public_event_id,
      "movie_id" => occurrence.movie_id,
      "movie_title" => occurrence.movie_title,
      "venue_id" => occurrence.venue_id,
      "venue_name" => occurrence.venue_name,
      "starts_at" => DateTime.to_iso8601(datetime),
      "ends_at" => ends_at && DateTime.to_iso8601(ends_at)
    }
  end

  defp build_occurrence_metadata(occurrence, occurrence_type, datetime) do
    ends_at = occurrence[:ends_at] || occurrence[:end_datetime]

    %{
      occurrence_type: occurrence_type,
      public_event_id: occurrence.public_event_id,
      movie_id: occurrence.movie_id,
      venue_id: occurrence.venue_id,
      starts_at: DateTime.to_iso8601(datetime),
      ends_at: ends_at && DateTime.to_iso8601(ends_at)
    }
  end

  defp single_movie?(occurrences) do
    occurrences
    |> Enum.map(& &1.movie_id)
    |> Enum.uniq()
    |> length()
    |> Kernel.==(1)
  end

  defp venue_occurrence?(occurrences) do
    occurrences
    |> List.first()
    |> case do
      %{meal_period: _} -> true
      _ -> false
    end
  end

  # Venue-specific formatting functions

  defp format_venue_title(%{venue_name: name, meal_period: period}) do
    "#{name} - #{String.capitalize(period)}"
  end

  defp format_time_window_description(occurrence, timezone, date_format) do
    starts = DateTime.shift_zone!(occurrence.starts_at, timezone)
    ends = DateTime.shift_zone!(occurrence.ends_at, timezone)

    day_name = Calendar.strftime(starts, "%A")
    date_str = format_date(starts, date_format)
    start_time = Calendar.strftime(starts, "%I:%M %p")
    end_time = Calendar.strftime(ends, "%I:%M %p")

    "#{day_name}, #{date_str} from #{start_time} to #{end_time}"
  end

  defp format_venue_external_id(%{venue_id: venue_id, date: date, meal_period: period}) do
    "venue_slot:#{venue_id}:#{Date.to_iso8601(date)}:#{period}"
  end

  defp build_venue_external_data(occurrence) do
    %{
      "venue_id" => occurrence.venue_id,
      "venue_name" => occurrence.venue_name,
      "date" => Date.to_iso8601(occurrence.date),
      "meal_period" => occurrence.meal_period,
      "starts_at" => DateTime.to_iso8601(occurrence.starts_at),
      "ends_at" => DateTime.to_iso8601(occurrence.ends_at)
    }
  end

  defp build_venue_occurrence_metadata(occurrence) do
    %{
      occurrence_type: "venue_time_slot",
      venue_id: occurrence.venue_id,
      date: Date.to_iso8601(occurrence.date),
      meal_period: occurrence.meal_period,
      starts_at: DateTime.to_iso8601(occurrence.starts_at),
      ends_at: DateTime.to_iso8601(occurrence.ends_at)
    }
  end
end
