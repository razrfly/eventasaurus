defmodule EventasaurusDiscovery.Sources.Inquizition.Helpers.ScheduleHelper do
  @moduledoc """
  Helper functions for parsing Inquizition schedule information.

  Uses shared RecurringEventParser for common parsing logic.
  Provides Inquizition-specific logic for:
  - Parsing day filters (["Tuesday"] → :tuesday) - Inquizition-specific format
  - Delegates time parsing, next occurrence, and recurrence rule building to shared module

  ## Examples

      iex> parse_day_from_filter("Tuesday")
      {:ok, :tuesday}

      iex> parse_time_from_text("6.30pm")
      {:ok, ~T[18:30:00]}

      iex> parse_time_from_text("7pm")
      {:ok, ~T[19:00:00]}
  """

  alias EventasaurusDiscovery.Sources.Shared.RecurringEventParser
  require Logger

  @doc """
  Parse day of week from filter string.

  Inquizition provides filters like "Tuesday", "Wednesday", etc.
  Delegates to shared RecurringEventParser.

  ## Examples

      iex> parse_day_from_filter("Tuesday")
      {:ok, :tuesday}

      iex> parse_day_from_filter("Wednesday")
      {:ok, :wednesday}

      iex> parse_day_from_filter("invalid")
      {:error, "Could not parse day from filter: invalid"}
  """
  def parse_day_from_filter(filter) when is_binary(filter) do
    RecurringEventParser.parse_day_of_week(filter)
  end

  def parse_day_from_filter(nil), do: {:error, "Filter is nil"}

  @doc """
  Parse day of week from filters array.

  Returns the first valid day found in the filters.

  ## Examples

      iex> parse_day_from_filters(["Tuesday"])
      {:ok, :tuesday}

      iex> parse_day_from_filters(["Wednesday", "Friday"])
      {:ok, :wednesday}

      iex> parse_day_from_filters([])
      {:error, "No valid day in filters"}
  """
  def parse_day_from_filters(filters) when is_list(filters) do
    case Enum.find_value(filters, fn filter ->
           case parse_day_from_filter(filter) do
             {:ok, day} -> day
             _ -> nil
           end
         end) do
      nil -> {:error, "No valid day in filters"}
      day -> {:ok, day}
    end
  end

  def parse_day_from_filters(_), do: {:error, "Filters must be a list"}

  @doc """
  Parse time from schedule text.

  Supports UK formats with dots (6.30pm) or colons (6:30pm).
  Delegates to shared RecurringEventParser.

  ## Examples

      iex> parse_time_from_text("6.30pm")
      {:ok, ~T[18:30:00]}

      iex> parse_time_from_text("7pm")
      {:ok, ~T[19:00:00]}

      iex> parse_time_from_text("8:00 PM")
      {:ok, ~T[20:00:00]}
  """
  def parse_time_from_text(text) when is_binary(text) do
    RecurringEventParser.parse_time(text)
  end

  def parse_time_from_text(nil), do: {:error, "Text is nil"}

  @doc """
  Build a recurrence rule for weekly events.

  Delegates to shared RecurringEventParser.

  ## Examples

      iex> build_recurrence_rule(:tuesday, ~T[18:30:00], "Europe/London")
      %{
        frequency: "weekly",
        day_of_week: "tuesday",
        time: ~T[18:30:00],
        timezone: "Europe/London"
      }
  """
  def build_recurrence_rule(day_atom, time, timezone) do
    RecurringEventParser.build_recurrence_rule(day_atom, time, timezone)
  end

  @doc """
  Calculate next occurrence of a weekly event.

  Delegates to shared RecurringEventParser.

  ## Examples

      iex> next_occurrence(:tuesday, ~T[18:30:00], "Europe/London")
      #DateTime<...>  # Next Tuesday at 6:30pm London time in UTC
  """
  def next_occurrence(day_of_week, time, timezone \\ "Europe/London") do
    RecurringEventParser.next_occurrence(day_of_week, time, timezone)
  end
end
