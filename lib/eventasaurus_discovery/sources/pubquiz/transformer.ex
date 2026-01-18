defmodule EventasaurusDiscovery.Sources.Pubquiz.Transformer do
  @moduledoc """
  Transforms PubQuiz venue data into PublicEvent schema with recurrence rules.

  This is the first real-world implementation of recurring events using the
  recurrence_rule field from #1399.
  """

  require Logger

  alias EventasaurusDiscovery.Sources.Shared.JsonSanitizer

  @doc """
  Transforms venue data into a PublicEvent map with recurrence_rule.

  ## Parameters
  - venue_data: Map with name, url, description, address, phone, host, schedule
  - venue_record: The Venue database record (with id, lat/lng)
  - city: The City database record

  ## Returns
  {:ok, event_map} | {:error, reason}
  """
  def transform_venue_to_event(venue_data, venue_record, _city) do
    with {:ok, recurrence_rule} <- parse_schedule_to_recurrence(venue_data[:schedule]),
         {:ok, next_occurrence} <- calculate_next_occurrence(recurrence_rule) do
      event_map = %{
        title: build_title(venue_data[:name]),
        starts_at: next_occurrence,
        ends_at: DateTime.add(next_occurrence, 2 * 3600, :second),
        # 2 hours duration
        venue_id: venue_record.id,
        recurrence_rule: recurrence_rule,
        # Store additional venue info in source_data for reference
        source_metadata: %{
          "venue_name" => venue_data[:name],
          "host" => venue_data[:host],
          "phone" => venue_data[:phone],
          "description" => venue_data[:description],
          "schedule_text" => venue_data[:schedule],
          # Raw upstream data for debugging (sanitized for JSON)
          "_raw_upstream" => JsonSanitizer.sanitize(venue_data)
        }
      }

      {:ok, event_map}
    end
  end

  @doc """
  Builds a standardized event title from venue name.

  Removes PubQuiz.pl branding and creates consistent title format.
  """
  def build_title(venue_name) do
    # Clean up venue name and create event title
    cleaned_name =
      venue_name
      |> String.replace(~r/PubQuiz\.pl\s+-\s+/i, "")
      |> String.replace(~r/Pub\s+Quiz\s+-\s+/i, "")
      |> String.trim()

    "Weekly Trivia Night - #{cleaned_name}"
  end

  @doc """
  Parses Polish schedule text into recurrence_rule JSON.

  ## Examples

      iex> parse_schedule_to_recurrence("Każdy poniedziałek 19:00")
      {:ok, %{frequency: "weekly", days_of_week: ["monday"], time: "19:00", timezone: "Europe/Warsaw"}}

      iex> parse_schedule_to_recurrence("Wtorki o 20:00")
      {:ok, %{frequency: "weekly", days_of_week: ["tuesday"], time: "20:00", timezone: "Europe/Warsaw"}}
  """
  def parse_schedule_to_recurrence(nil), do: {:error, :no_schedule}
  def parse_schedule_to_recurrence(""), do: {:error, :no_schedule}

  def parse_schedule_to_recurrence(schedule_text) when is_binary(schedule_text) do
    schedule_lower = String.downcase(schedule_text)

    with {:ok, day_of_week} <- extract_day_of_week(schedule_lower),
         {:ok, time} <- extract_time(schedule_text) do
      recurrence_rule = %{
        "frequency" => "weekly",
        "days_of_week" => [day_of_week],
        "time" => time,
        "timezone" => "Europe/Warsaw"
      }

      {:ok, recurrence_rule}
    end
  end

  # Polish day names to English mapping
  @polish_days %{
    "poniedziałek" => "monday",
    "poniedzialek" => "monday",
    "wtorek" => "tuesday",
    "środa" => "wednesday",
    "sroda" => "wednesday",
    "czwartek" => "thursday",
    "piątek" => "friday",
    "piatek" => "friday",
    "sobota" => "saturday",
    "niedziela" => "sunday"
  }

  # Plural forms
  @polish_day_plurals %{
    "poniedziałki" => "monday",
    "wtorki" => "tuesday",
    "środy" => "wednesday",
    "czwartki" => "thursday",
    "piątki" => "friday",
    "soboty" => "saturday",
    "niedziele" => "sunday"
  }

  defp extract_day_of_week(schedule_lower) do
    # Try singular forms first
    day =
      Enum.find_value(@polish_days, fn {polish, english} ->
        if String.contains?(schedule_lower, polish), do: english
      end)

    # Try plural forms if singular not found
    day =
      day ||
        Enum.find_value(@polish_day_plurals, fn {polish, english} ->
          if String.contains?(schedule_lower, polish), do: english
        end)

    if day do
      {:ok, day}
    else
      Logger.warning("Could not extract day of week from schedule: #{schedule_lower}")
      {:error, :no_day_found}
    end
  end

  defp extract_time(schedule_text) do
    # Extract time in HH:MM format
    case Regex.run(~r/(\d{1,2}):(\d{2})/, schedule_text) do
      [_, hour, minute] ->
        # Pad hour to 2 digits
        hour_padded = String.pad_leading(hour, 2, "0")
        {:ok, "#{hour_padded}:#{minute}"}

      nil ->
        Logger.warning("Could not extract time from schedule: #{schedule_text}")
        {:error, :no_time_found}
    end
  end

  @doc """
  Calculates the next occurrence datetime based on recurrence_rule.

  Returns the next upcoming date/time when this event will occur.
  """
  def calculate_next_occurrence(recurrence_rule) do
    timezone = recurrence_rule["timezone"] || "Europe/Warsaw"
    [day_of_week] = recurrence_rule["days_of_week"]
    time_str = recurrence_rule["time"]

    # Parse time
    [hour, minute] = String.split(time_str, ":") |> Enum.map(&String.to_integer/1)

    # Get current time in event timezone
    now = DateTime.now!(timezone)
    today = DateTime.to_date(now)

    # Map day names to numbers (1 = Monday, 7 = Sunday)
    day_numbers = %{
      "monday" => 1,
      "tuesday" => 2,
      "wednesday" => 3,
      "thursday" => 4,
      "friday" => 5,
      "saturday" => 6,
      "sunday" => 7
    }

    target_day_num = day_numbers[day_of_week]
    current_day_num = Date.day_of_week(today)

    # Calculate days until next occurrence
    days_until =
      if target_day_num >= current_day_num do
        target_day_num - current_day_num
      else
        7 - current_day_num + target_day_num
      end

    # Calculate the target date
    target_date = Date.add(today, days_until)

    # If it's today but the time has passed, move to next week
    target_date =
      if days_until == 0 do
        event_time = Time.new!(hour, minute, 0)
        current_time = DateTime.to_time(now)

        if Time.compare(current_time, event_time) == :gt do
          Date.add(target_date, 7)
        else
          target_date
        end
      else
        target_date
      end

    # Create DateTime for the next occurrence
    {:ok, naive_dt} = NaiveDateTime.new(target_date, Time.new!(hour, minute, 0))
    {:ok, dt} = DateTime.from_naive(naive_dt, timezone)

    {:ok, dt}
  rescue
    error ->
      Logger.error("Error calculating next occurrence: #{inspect(error)}")
      {:error, :calculation_failed}
  end
end
