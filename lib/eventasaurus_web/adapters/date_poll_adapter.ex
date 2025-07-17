defmodule EventasaurusWeb.Adapters.DatePollAdapter do
  @moduledoc """
  Adapter to bridge between the legacy event date polling system
  and the new generic date_selection poll system.

  This allows the existing beautiful calendar UI components (built for the legacy system)
  to seamlessly work with the new generic polling infrastructure while maintaining
  backwards compatibility and reusing proven UI patterns.
  """

  alias EventasaurusApp.Events.{Poll, PollOption, PollVote}
  alias EventasaurusApp.Events.{EventDatePoll, EventDateOption, EventDateVote}
  alias EventasaurusApp.Events
  alias EventasaurusApp.Repo
  import Ecto.Query
  import Phoenix.HTML, only: [html_escape: 1, safe_to_string: 1]

  require Logger

  @doc """
  Converts a generic date_selection poll to the legacy format expected by calendar UI.

  This allows existing calendar components to render generic polls without modification.
  """
  def convert_to_legacy_format(%Poll{poll_type: "date_selection"} = poll) do
    # Convert poll to EventDatePoll structure
    legacy_poll = %EventDatePoll{
      id: poll.id,
      voting_deadline: poll.voting_deadline,
      finalized_date: poll.finalized_date,
      event_id: poll.event_id,
      created_by_id: poll.created_by_id,
      inserted_at: poll.inserted_at,
      updated_at: poll.updated_at,
      # Virtual associations - populated separately
      date_options: [],
      event: nil,
      created_by: nil
    }

    {:ok, legacy_poll}
  end

  def convert_to_legacy_format(%Poll{poll_type: type}) do
    {:error,
     "Cannot convert poll type '#{type}' to legacy format - only date_selection polls supported"}
  end

  @doc """
  Converts generic poll options with date metadata to legacy EventDateOption format.
  """
  def convert_options_to_legacy_format(poll_options) when is_list(poll_options) do
    legacy_options =
      poll_options
      |> Enum.map(&convert_option_to_legacy_format/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.date, Date)

    {:ok, legacy_options}
  end

  defp convert_option_to_legacy_format(%PollOption{} = option) do
    case extract_date_from_option(option) do
      {:ok, date} ->
        %EventDateOption{
          id: option.id,
          date: date,
          event_date_poll_id: option.poll_id,
          inserted_at: option.inserted_at,
          updated_at: option.updated_at,
          # Virtual associations
          votes: [],
          event_date_poll: nil
        }

      {:error, _} ->
        nil
    end
  end

  @doc """
  Converts generic poll votes to legacy EventDateVote format.
  """
  def convert_votes_to_legacy_format(poll_votes) when is_list(poll_votes) do
    legacy_votes =
      poll_votes
      |> Enum.map(&convert_vote_to_legacy_format/1)
      |> Enum.reject(&is_nil/1)

    {:ok, legacy_votes}
  end

  defp convert_vote_to_legacy_format(%PollVote{} = vote) do
    case map_vote_value_to_legacy(vote.vote_value) do
      {:ok, legacy_vote_type} ->
        %EventDateVote{
          id: vote.id,
          vote_type: legacy_vote_type,
          event_date_option_id: vote.poll_option_id,
          user_id: vote.voter_id,
          inserted_at: vote.inserted_at,
          updated_at: vote.updated_at,
          # Virtual associations
          event_date_option: nil,
          user: nil
        }

      {:error, _} ->
        nil
    end
  end

  @doc """
  Converts a legacy EventDatePoll to generic Poll format.

  This enables migration of legacy polls to the new system.
  """
  def convert_to_generic_format(%EventDatePoll{} = legacy_poll) do
    generic_poll = %Poll{
      id: legacy_poll.id,
      title: "Date Selection Poll",
      description: "Select your preferred dates",
      poll_type: "date_selection",
      voting_system: "binary",
      phase: determine_phase_from_legacy(legacy_poll),
      voting_deadline: legacy_poll.voting_deadline,
      finalized_date: legacy_poll.finalized_date,
      finalized_option_ids: determine_finalized_options(legacy_poll),
      event_id: legacy_poll.event_id,
      created_by_id: legacy_poll.created_by_id,
      inserted_at: legacy_poll.inserted_at,
      updated_at: legacy_poll.updated_at,
      # Virtual associations
      poll_options: [],
      event: nil,
      created_by: nil
    }

    {:ok, generic_poll}
  end

  @doc """
  Converts legacy EventDateOption to generic PollOption with date metadata.
  """
  def convert_legacy_options_to_generic_format(date_options) when is_list(date_options) do
    generic_options =
      date_options
      |> Enum.with_index()
      |> Enum.map(fn {option, index} ->
        convert_legacy_option_to_generic_format(option, index)
      end)

    {:ok, generic_options}
  end

  defp convert_legacy_option_to_generic_format(%EventDateOption{} = option, index) do
    %PollOption{
      id: option.id,
      title: format_date_for_display(option.date),
      description: nil,
      metadata: %{
        "date" => Date.to_iso8601(option.date),
        "display_date" => format_date_for_display(option.date),
        "created_at" => DateTime.to_iso8601(option.inserted_at),
        "date_components" => %{
          "year" => option.date.year,
          "month" => option.date.month,
          "day" => option.date.day,
          "day_of_week" => Date.day_of_week(option.date),
          "day_name" => get_day_name(Date.day_of_week(option.date))
        }
      },
      status: "active",
      order_index: index,
      poll_id: option.event_date_poll_id,
      # Legacy system didn't track who suggested dates
      suggested_by_id: nil,
      inserted_at: option.inserted_at,
      updated_at: option.updated_at,
      # Virtual associations
      votes: [],
      poll: nil,
      suggested_by: nil
    }
  end

  @doc """
  Converts legacy EventDateVote to generic PollVote format.
  """
  def convert_legacy_votes_to_generic_format(date_votes) when is_list(date_votes) do
    generic_votes =
      date_votes
      |> Enum.map(&convert_legacy_vote_to_generic_format/1)
      |> Enum.reject(&is_nil/1)

    {:ok, generic_votes}
  end

  defp convert_legacy_vote_to_generic_format(%EventDateVote{} = vote) do
    case map_legacy_vote_type_to_generic(vote.vote_type) do
      {:ok, generic_vote_value} ->
        %PollVote{
          id: vote.id,
          vote_value: generic_vote_value,
          voted_at: vote.inserted_at,
          poll_option_id: vote.event_date_option_id,
          voter_id: vote.user_id,
          # Will need to be populated based on option's poll
          poll_id: nil,
          inserted_at: vote.inserted_at,
          updated_at: vote.updated_at,
          # Virtual associations
          poll_option: nil,
          voter: nil,
          poll: nil
        }

      {:error, _} ->
        nil
    end
  end

  # Private helper functions

  @doc """
  Extracts a date from a poll option's metadata.

  This function is used by components to extract date information
  from generic poll options for display and processing.
  """
  def extract_date_from_option(%PollOption{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, "date") do
      date_string when is_binary(date_string) ->
        case Date.from_iso8601(date_string) do
          {:ok, date} -> {:ok, date}
          {:error, _} -> {:error, "Invalid date format in metadata"}
        end

      _ ->
        {:error, "No date found in option metadata"}
    end
  end

  def extract_date_from_option(_), do: {:error, "Invalid option structure"}

  defp map_vote_value_to_legacy("yes"), do: {:ok, :yes}
  defp map_vote_value_to_legacy("maybe"), do: {:ok, :if_need_be}
  defp map_vote_value_to_legacy("no"), do: {:ok, :no}
  defp map_vote_value_to_legacy(value), do: {:error, "Unknown vote value: #{value}"}

  defp map_legacy_vote_type_to_generic(:yes), do: {:ok, "yes"}
  defp map_legacy_vote_type_to_generic(:if_need_be), do: {:ok, "maybe"}
  defp map_legacy_vote_type_to_generic(:no), do: {:ok, "no"}
  defp map_legacy_vote_type_to_generic(type), do: {:error, "Unknown legacy vote type: #{type}"}

  defp determine_phase_from_legacy(%EventDatePoll{finalized_date: nil}),
    do: "voting_with_suggestions"

  defp determine_phase_from_legacy(%EventDatePoll{finalized_date: _}), do: "closed"

  defp determine_finalized_options(%EventDatePoll{finalized_date: nil}), do: nil

  defp determine_finalized_options(%EventDatePoll{finalized_date: _date}) do
    # In legacy system, finalized_date represents the chosen date
    # We would need to find the option ID that matches this date
    # This is a placeholder - actual implementation would query the database
    []
  end

  defp format_date_for_display(date) do
    day_name = get_day_name(Date.day_of_week(date))
    # Use Elixir's built-in Calendar functions for date formatting
    month_name = Calendar.strftime(date, "%B")
    "#{day_name}, #{month_name} #{date.day}, #{date.year}"
  end

  defp get_day_name(1), do: "Monday"
  defp get_day_name(2), do: "Tuesday"
  defp get_day_name(3), do: "Wednesday"
  defp get_day_name(4), do: "Thursday"
  defp get_day_name(5), do: "Friday"
  defp get_day_name(6), do: "Saturday"
  defp get_day_name(7), do: "Sunday"

  @doc """
  Helper function to get all data for a date_selection poll in legacy format.

  This is the main function UI components should use to get a complete legacy-format
  data structure from a generic date_selection poll.
  """
  def get_legacy_poll_with_data(poll_id) do
    with {:ok, poll} <- get_generic_poll_with_options_and_votes(poll_id),
         {:ok, legacy_poll} <- convert_to_legacy_format(poll),
         {:ok, legacy_options} <- convert_options_to_legacy_format(poll.poll_options),
         {:ok, legacy_votes} <- convert_votes_to_legacy_format(get_all_votes_for_poll(poll)) do
      # Populate the associations
      populated_options =
        Enum.map(legacy_options, fn option ->
          option_votes = Enum.filter(legacy_votes, &(&1.event_date_option_id == option.id))
          %{option | votes: option_votes}
        end)

      populated_poll = %{legacy_poll | date_options: populated_options}

      {:ok, populated_poll}
    else
      error -> error
    end
  end

  @doc """
  Get a generic poll with all related data preloaded.
  """
  def get_generic_poll_with_options_and_votes(poll_id) do
    try do
      query =
        from(p in Poll,
          where: p.id == ^poll_id and p.poll_type == "date_selection",
          preload: [
            poll_options: [:votes, :suggested_by],
            event: [],
            created_by: []
          ]
        )

      case Repo.one(query) do
        nil -> {:error, "Poll not found or not a date_selection poll"}
        poll -> {:ok, poll}
      end
    rescue
      e ->
        Logger.error("Error fetching generic poll: #{inspect(e)}")
        {:error, "Database error while fetching poll"}
    end
  end

  @doc """
  Get a poll using the Events context functions.
  """
  def get_poll_with_events_context(poll_id) do
    try do
      poll = Events.get_poll!(poll_id)

      if poll.poll_type == "date_selection" do
        # Load options and votes using Events context
        options = Events.list_poll_options(poll)

        # Preload votes for each option
        options_with_votes =
          Enum.map(options, fn option ->
            votes =
              Events.list_votes_for_poll(poll_id)
              |> Enum.filter(&(&1.poll_option_id == option.id))

            %{option | votes: votes}
          end)

        poll_with_data = %{poll | poll_options: options_with_votes}
        {:ok, poll_with_data}
      else
        {:error, "Poll is not a date_selection type"}
      end
    rescue
      e ->
        Logger.error("Error fetching poll with Events context: #{inspect(e)}")
        {:error, "Error fetching poll data"}
    end
  end

  @doc """
  Extracts all votes from a poll's options.
  """
  def get_all_votes_for_poll(%Poll{poll_options: options}) when is_list(options) do
    options
    |> Enum.flat_map(fn option ->
      case option.votes do
        votes when is_list(votes) -> votes
        _ -> []
      end
    end)
  end

  def get_all_votes_for_poll(_), do: []

  @doc """
  Enhanced date parsing with better error handling and timezone support.
  """
  def parse_date_with_timezone(date_string, _timezone \\ "UTC") do
    with {:ok, date} <- Date.from_iso8601(date_string) do
      # For date-only polls, we use the date as-is
      # If we need timezone handling in the future, we can add it here
      {:ok, date}
    else
      {:error, reason} ->
        Logger.warning("Failed to parse date '#{date_string}': #{reason}")
        {:error, "Invalid date format"}
    end
  end

  @doc """
  Comprehensive validation function for date metadata in poll options.

  This replaces the previous basic validation with thorough checks
  using the new DateMetadata embedded schema.
  """
  def validate_date_metadata(%PollOption{} = option) do
    case option.metadata do
      nil ->
        {:error, "No metadata found in poll option"}

      metadata when is_map(metadata) ->
        # Use our comprehensive DateMetadata validation
        alias EventasaurusApp.Events.DateMetadata

        case DateMetadata.validate_metadata_structure(metadata) do
          :ok ->
            changeset = DateMetadata.changeset(%DateMetadata{}, metadata)

            if changeset.valid? do
              {:ok, option}
            else
              errors =
                Enum.map(changeset.errors, fn {field, {message, _opts}} ->
                  "#{field}: #{message}"
                end)

              {:error, "Invalid date metadata - #{Enum.join(errors, ", ")}"}
            end

          {:error, reason} ->
            {:error, "Metadata structure validation failed: #{reason}"}
        end

      _ ->
        {:error, "Metadata must be a valid map"}
    end
  end

  @doc """
  Enhanced validation function that checks both basic option validity
  and date metadata integrity for date_selection polls.
  """
  def validate_date_option(%PollOption{} = option) do
    # Use our comprehensive validation that checks both structure and content
    case validate_date_metadata(option) do
      {:ok, validated_option} ->
        # Additional legacy compatibility check
        case extract_date_from_option(validated_option) do
          {:ok, _date} ->
            {:ok, validated_option}

          {:error, reason} ->
            Logger.warning("Date extraction failed for option #{option.id}: #{reason}")
            {:error, "Invalid date metadata in option"}
        end

      {:error, reason} ->
        Logger.warning("Date metadata validation failed for option #{option.id}: #{reason}")
        {:error, reason}
    end
  end

  def validate_date_option(_), do: {:error, "Invalid option structure"}

  @doc """
  Batch convert multiple polls from generic to legacy format.
  """
  def batch_convert_to_legacy_format(polls) when is_list(polls) do
    results = Enum.map(polls, &convert_to_legacy_format/1)

    successes =
      Enum.filter(results, &match?({:ok, _}, &1)) |> Enum.map(fn {:ok, poll} -> poll end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    case errors do
      [] -> {:ok, successes}
      _ -> {:partial_success, successes, errors}
    end
  end

  @doc """
  Performance-optimized version for large datasets.
  Processes polls in batches to avoid memory issues.
  """
  def stream_convert_to_legacy_format(poll_stream, batch_size \\ 100) do
    poll_stream
    |> Stream.chunk_every(batch_size)
    |> Stream.map(&batch_convert_to_legacy_format/1)
  end

  # Phoenix.HTML Safety Functions

  @doc """
  Returns HTML-safe formatted date display string.
  """
  def safe_format_date_for_display(date) do
    date
    |> format_date_for_display()
    |> html_escape()
  end

  @doc """
  Returns HTML-safe option title for UI rendering.
  """
  def safe_option_title(%PollOption{title: title}) do
    title
    |> html_escape()
  end

  def safe_option_title(%EventDateOption{date: date}) do
    date
    |> format_date_for_display()
    |> html_escape()
  end

  @doc """
  Returns HTML-safe poll title and description for UI components.
  """
  def safe_poll_display(%Poll{title: title, description: description}) do
    %{
      title: html_escape(title),
      description: html_escape(description || "")
    }
  end

  def safe_poll_display(%EventDatePoll{}) do
    %{
      title: html_escape("Date Selection Poll"),
      description: html_escape("Select your preferred dates")
    }
  end

  @doc """
  Returns HTML-safe vote display text.
  """
  def safe_vote_display(%PollVote{vote_value: vote_value}) do
    vote_value
    |> vote_value_to_display()
    |> html_escape()
  end

  def safe_vote_display(%EventDateVote{vote_type: vote_type}) do
    vote_type
    |> legacy_vote_type_to_display()
    |> html_escape()
  end

  @doc """
  Returns HTML-safe status display for polls.
  """
  def safe_status_display(%Poll{phase: phase}) do
    phase
    |> phase_to_display()
    |> html_escape()
  end

  def safe_status_display(%EventDatePoll{finalized_date: nil}) do
    html_escape("Active")
  end

  def safe_status_display(%EventDatePoll{finalized_date: _}) do
    html_escape("Finalized")
  end

  @doc """
  Converts adapted data to safe HTML for template rendering.
  Useful for directly rendering adapter output in Phoenix templates.
  """
  def to_safe_html_attributes(legacy_poll_data) do
    %{
      poll_title: safe_poll_display(legacy_poll_data).title,
      poll_description: safe_poll_display(legacy_poll_data).description,
      status: safe_status_display(legacy_poll_data),
      options:
        Enum.map(legacy_poll_data.date_options || [], fn option ->
          %{
            id: option.id,
            title: safe_option_title(option),
            date: safe_format_date_for_display(option.date),
            votes: Enum.map(option.votes || [], &safe_vote_display/1)
          }
        end)
    }
  end

  @doc """
  Validates and sanitizes user input for date options.
  Ensures no XSS vulnerabilities when processing user-generated content.
  """
  def sanitize_date_input(date_string) when is_binary(date_string) do
    # Strip any potential HTML/script tags
    cleaned = date_string |> String.trim() |> html_escape() |> safe_to_string()

    case Date.from_iso8601(cleaned) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, "Invalid date format"}
    end
  end

  def sanitize_date_input(_), do: {:error, "Date must be a string"}

  @doc """
  Sanitizes poll metadata to prevent XSS attacks.
  """
  def sanitize_poll_metadata(%{} = metadata) do
    metadata
    |> Enum.map(fn {key, value} ->
      safe_key = key |> to_string() |> html_escape() |> safe_to_string()
      safe_value = sanitize_metadata_value(value)
      {safe_key, safe_value}
    end)
    |> Map.new()
  end

  defp sanitize_metadata_value(value) when is_binary(value) do
    value |> html_escape() |> safe_to_string()
  end

  defp sanitize_metadata_value(value) when is_map(value) do
    sanitize_poll_metadata(value)
  end

  defp sanitize_metadata_value(value) when is_list(value) do
    Enum.map(value, &sanitize_metadata_value/1)
  end

  defp sanitize_metadata_value(value), do: value

  # Helper functions for display text conversion

  defp vote_value_to_display("yes"), do: "Yes"
  defp vote_value_to_display("maybe"), do: "Maybe"
  defp vote_value_to_display("no"), do: "No"
  defp vote_value_to_display(value), do: String.capitalize(value || "Unknown")

  defp legacy_vote_type_to_display(:yes), do: "Yes"
  defp legacy_vote_type_to_display(:if_need_be), do: "If needed"
  defp legacy_vote_type_to_display(:no), do: "No"
  defp legacy_vote_type_to_display(type), do: type |> to_string() |> String.capitalize()

  defp phase_to_display("list_building"), do: "Building Options"
  defp phase_to_display("voting_with_suggestions"), do: "Voting Open"
  defp phase_to_display("voting_only"), do: "Voting Only"
  defp phase_to_display("closed"), do: "Closed"
  defp phase_to_display(phase), do: phase |> String.replace("_", " ") |> String.capitalize()

  # =================
  # Time Extraction and Formatting Functions (SIMPLIFIED - NO BACKWARDS COMPATIBILITY)
  # =================

  @doc """
  Extracts time slots from a poll option's metadata.
  Since we're in development, we expect all date options to use the new schema.

  Returns empty list for all-day events.
  """
  def extract_time_slots(%PollOption{metadata: metadata}) when is_map(metadata) do
    case metadata do
      %{"time_enabled" => true, "time_slots" => time_slots} when is_list(time_slots) ->
        time_slots

      %{"all_day" => true} ->
        []

      _ ->
        []
    end
  end

  def extract_time_slots(_), do: []

  @doc """
  Checks if a poll option has time slots enabled.
  """
  def has_time_slots?(%PollOption{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, "time_enabled", false) == true and
      not Map.get(metadata, "all_day", false)
  end

  def has_time_slots?(_), do: false

  @doc """
  Checks if a poll option is configured as all-day.
  """
  def is_all_day?(%PollOption{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, "all_day", false) == true
  end

  def is_all_day?(_), do: false

  @doc """
  Formats time slots for display in the UI.
  """
  def format_time_slots_display(time_slots) when is_list(time_slots) do
    time_slots
    |> Enum.map(&format_single_time_slot/1)
    |> Enum.join(", ")
  end

  def format_time_slots_display(_), do: ""

  @doc """
  Formats a single time slot for display.
  """
  def format_single_time_slot(%{"start_time" => start_time, "end_time" => end_time}) do
    start_formatted = format_time_for_display(start_time)
    end_formatted = format_time_for_display(end_time)
    "#{start_formatted} - #{end_formatted}"
  end

  def format_single_time_slot(%{"start_time" => start_time}) do
    format_time_for_display(start_time)
  end

  def format_single_time_slot(_), do: ""

  @doc """
  Formats a time string (HH:MM) for user-friendly display (12-hour format).
  """
  def format_time_for_display(time_string) when is_binary(time_string) do
    case String.split(time_string, ":") do
      [hour_str, minute_str] ->
        with {hour, ""} <- Integer.parse(hour_str),
             {minute, ""} <- Integer.parse(minute_str),
             true <- hour >= 0 and hour <= 23,
             true <- minute >= 0 and minute <= 59 do
          format_12_hour_time(hour, minute)
        else
          # Fallback to original string if parsing fails
          _ -> time_string
        end

      _ ->
        time_string
    end
  end

  def format_time_for_display(time) when is_integer(time) do
    hour = div(time, 60)
    minute = rem(time, 60)
    format_12_hour_time(hour, minute)
  end

  def format_time_for_display(_), do: ""

  @doc """
  Converts 24-hour time to 12-hour format with AM/PM.
  """
  def format_12_hour_time(hour, minute)
      when hour >= 0 and hour <= 23 and minute >= 0 and minute <= 59 do
    {display_hour, period} =
      case hour do
        0 -> {12, "AM"}
        h when h < 12 -> {h, "AM"}
        12 -> {12, "PM"}
        h -> {h - 12, "PM"}
      end

    minute_str = minute |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{display_hour}:#{minute_str} #{period}"
  end

  def format_12_hour_time(_, _), do: ""

  @doc """
  Gets the timezone from poll option metadata.
  """
  def get_timezone(%PollOption{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, "timezone", "UTC")
  end

  def get_timezone(_), do: "UTC"

  @doc """
  Creates a comprehensive display string for a date option including time information.
  """
  def format_date_with_time_display(%PollOption{} = option) do
    base_display = Map.get(option.metadata || %{}, "display_date", option.title)

    cond do
      is_all_day?(option) ->
        "#{base_display} (All Day)"

      has_time_slots?(option) ->
        time_slots = extract_time_slots(option)

        case time_slots do
          [] -> base_display
          slots -> "#{base_display} • #{format_time_slots_display(slots)}"
        end

      true ->
        base_display
    end
  end

  @doc """
  Validates that time slots don't overlap within a single option.
  """
  def validate_no_time_overlaps(time_slots) when is_list(time_slots) do
    time_slots
    |> Enum.map(&parse_time_slot_to_minutes/1)
    |> Enum.filter(&(&1 != nil))
    |> check_overlaps()
  end

  def validate_no_time_overlaps(_), do: true

  # Helper function to parse time slot to minutes for overlap checking
  defp parse_time_slot_to_minutes(%{"start_time" => start_time, "end_time" => end_time}) do
    with start_minutes when is_integer(start_minutes) <- time_to_minutes(start_time),
         end_minutes when is_integer(end_minutes) <- time_to_minutes(end_time) do
      {start_minutes, end_minutes}
    else
      _ -> nil
    end
  end

  defp parse_time_slot_to_minutes(_), do: nil

  # Helper function to check for overlaps
  defp check_overlaps(time_ranges) do
    time_ranges
    |> Enum.sort()
    |> Enum.reduce_while({true, nil}, fn {start, end_time}, {_acc, last_end} ->
      if last_end && start < last_end do
        {:halt, {false, nil}}
      else
        {:cont, {true, end_time}}
      end
    end)
    |> elem(0)
  end

  # Helper function to convert time string to minutes since midnight
  defp time_to_minutes(time_string) when is_binary(time_string) do
    case String.split(time_string, ":") do
      [hour_str, minute_str] ->
        with {hour, ""} <- Integer.parse(hour_str),
             {minute, ""} <- Integer.parse(minute_str),
             true <- hour >= 0 and hour <= 23,
             true <- minute >= 0 and minute <= 59 do
          hour * 60 + minute
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp time_to_minutes(_), do: nil
end
