defmodule EventasaurusWeb.Adapters.DatePollAdapter do
  @moduledoc """
  Simplified adapter for date selection polling.

  Provides essential date extraction and formatting functions for generic polling system.
  """

  alias EventasaurusApp.Events.{Poll, PollOption, PollVote}
  alias EventasaurusApp.Repo
  alias EventasaurusWeb.Utils.TimezoneUtils
  import Ecto.Query
  import Phoenix.HTML, only: [html_escape: 1, safe_to_string: 1]

  require Logger

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
  Simplified poll data loader that returns poll data directly (no legacy conversion).
  """
  def get_poll_with_data(poll_id) do
    get_generic_poll_with_options_and_votes(poll_id)
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
  def parse_date_with_timezone(date_string, _timezone \\ nil) do
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

  @doc """
  Returns HTML-safe poll title and description for UI components.
  """
  def safe_poll_display(%Poll{title: title, description: description}) do
    %{
      title: html_escape(title),
      description: html_escape(description || "")
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

  @doc """
  Returns HTML-safe status display for polls.
  """
  def safe_status_display(%Poll{phase: phase}) do
    phase
    |> phase_to_display()
    |> html_escape()
  end

  @doc """
  Converts adapted data to safe HTML for template rendering.
  Useful for directly rendering adapter output in Phoenix templates.
  """
  def to_safe_html_attributes(poll_data) do
    %{
      poll_title: safe_poll_display(poll_data).title,
      poll_description: safe_poll_display(poll_data).description,
      status: safe_status_display(poll_data),
      options:
        Enum.map(poll_data.poll_options || [], fn option ->
          %{
            id: option.id,
            title: safe_option_title(option),
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
  Formats time in 24-hour format.

  Legacy function name retained for compatibility.
  """
  def format_12_hour_time(hour, minute)
      when hour >= 0 and hour <= 23 and minute >= 0 and minute <= 59 do
    hour_str = hour |> Integer.to_string() |> String.pad_leading(2, "0")
    minute_str = minute |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{hour_str}:#{minute_str}"
  end

  def format_12_hour_time(_, _), do: ""

  @doc """
  Gets the timezone from poll option metadata.

  Falls back to Europe/Warsaw (the primary market) if not specified.
  """
  def get_timezone(%PollOption{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, "timezone") || TimezoneUtils.default_timezone()
  end

  def get_timezone(_), do: TimezoneUtils.default_timezone()

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
