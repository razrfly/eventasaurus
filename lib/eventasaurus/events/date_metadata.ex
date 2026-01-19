defmodule EventasaurusApp.Events.DateMetadata do
  @moduledoc """
  Embedded schema for validating date metadata in poll options.

  This schema ensures data integrity and type safety for date_selection polls
  by validating the structure and content of date metadata stored in the
  metadata field of poll options.

  Enhanced to support time slot validation for Date+Time polling functionality.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:date, :string)
    field(:display_date, :string)
    field(:date_type, :string, default: "single_date")
    field(:created_at, :string)
    field(:updated_at, :string)

    # NEW: Time support fields
    field(:time_enabled, :boolean, default: false)
    field(:all_day, :boolean, default: true)
    field(:duration_minutes, :integer)
    field(:flexible_duration, :boolean, default: false)

    embeds_one :date_components, DateComponents, primary_key: false do
      field(:year, :integer)
      field(:month, :integer)
      field(:day, :integer)
      field(:day_of_week, :integer)
      field(:day_name, :string)
    end

    # NEW: Time slots embedded schema
    embeds_many :time_slots, TimeSlot, primary_key: false do
      field(:start_time, :string)
      field(:end_time, :string)
      # Default to Europe/Warsaw - the primary market for this application
      field(:timezone, :string, default: "Europe/Warsaw")
      field(:display, :string)
    end
  end

  @doc """
  Validates date metadata for poll options.

  Ensures all required fields are present and properly formatted,
  with special validation for date formats and component consistency.
  Enhanced to support time slot validation.
  """
  def changeset(date_metadata, attrs) do
    date_metadata
    |> cast(attrs, [
      :date,
      :display_date,
      :date_type,
      :created_at,
      :updated_at,
      :time_enabled,
      :all_day,
      :duration_minutes,
      :flexible_duration
    ])
    |> cast_embed(:date_components, with: &date_components_changeset/2)
    |> cast_embed(:time_slots, with: &time_slot_changeset/2)
    |> validate_required([:date, :display_date, :date_type])
    |> validate_inclusion(:date_type, ~w(single_date date_range recurring_date))
    |> validate_date_format()
    |> validate_timestamp_format(:created_at)
    |> validate_timestamp_format(:updated_at)
    |> validate_date_components_consistency()
    |> validate_time_configuration()
    |> validate_time_slots_when_enabled()
    |> validate_duration_constraints()
  end

  @doc """
  Validates date components embedded schema.
  """
  def date_components_changeset(date_components, attrs) do
    date_components
    |> cast(attrs, [:year, :month, :day, :day_of_week, :day_name])
    |> validate_required([:year, :month, :day])
    |> validate_number(:year, greater_than: 1900, less_than: 3000)
    |> validate_number(:month, greater_than: 0, less_than: 13)
    |> validate_number(:day, greater_than: 0, less_than: 32)
    |> validate_number(:day_of_week, greater_than: 0, less_than: 8)
    |> validate_inclusion(:day_name, ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday))
    |> validate_date_components_match()
  end

  @doc """
  Validates time slot embedded schema.
  """
  def time_slot_changeset(time_slot, attrs) do
    # Handle case where Ecto passes an empty map for new embedded structs
    time_slot_struct =
      case time_slot do
        # Already a proper struct
        %__MODULE__.TimeSlot{} -> time_slot
        # Empty map, create proper struct
        %{} -> %__MODULE__.TimeSlot{}
        # Other cases (shouldn't happen but be defensive)
        _ -> time_slot
      end

    time_slot_struct
    |> cast(attrs, [:start_time, :end_time, :timezone, :display])
    |> validate_required([:start_time, :end_time])
    |> validate_time_format(:start_time)
    |> validate_time_format(:end_time)
    |> validate_timezone()
    |> validate_time_slot_order()
    |> validate_display_format()
  end

  # Private validation functions

  defp validate_date_format(changeset) do
    case get_field(changeset, :date) do
      nil ->
        changeset

      date_string ->
        case Date.from_iso8601(date_string) do
          {:ok, _date} -> changeset
          {:error, _} -> add_error(changeset, :date, "must be a valid ISO8601 date (YYYY-MM-DD)")
        end
    end
  end

  defp validate_timestamp_format(changeset, field) do
    case get_field(changeset, field) do
      nil ->
        changeset

      timestamp_string ->
        case DateTime.from_iso8601(timestamp_string) do
          {:ok, _datetime, _} -> changeset
          {:error, _} -> add_error(changeset, field, "must be a valid ISO8601 timestamp")
        end
    end
  end

  defp validate_date_components_consistency(changeset) do
    date_string = get_field(changeset, :date)
    date_components = get_field(changeset, :date_components)

    case {date_string, date_components} do
      {nil, _} ->
        changeset

      {_, nil} ->
        changeset

      {date_str, components} ->
        case Date.from_iso8601(date_str) do
          {:ok, date} ->
            if components_match_date?(date, components) do
              changeset
            else
              add_error(changeset, :date_components, "do not match the date value")
            end

          # Already handled by validate_date_format
          {:error, _} ->
            changeset
        end
    end
  end

  defp validate_date_components_match(changeset) do
    year = get_field(changeset, :year)
    month = get_field(changeset, :month)
    day = get_field(changeset, :day)
    day_of_week = get_field(changeset, :day_of_week)

    case {year, month, day, day_of_week} do
      {y, m, d, dow} when is_integer(y) and is_integer(m) and is_integer(d) and is_integer(dow) ->
        case Date.new(y, m, d) do
          {:ok, date} ->
            actual_dow = Date.day_of_week(date)

            if actual_dow == dow do
              changeset
            else
              add_error(
                changeset,
                :day_of_week,
                "does not match the calculated day of week for #{y}-#{m}-#{d}"
              )
            end

          {:error, _} ->
            add_error(changeset, :day, "invalid date combination: #{y}-#{m}-#{d}")
        end

      _ ->
        changeset
    end
  end

  # NEW: Time-related validation functions

  defp validate_time_configuration(changeset) do
    time_enabled = get_field(changeset, :time_enabled)
    all_day = get_field(changeset, :all_day)

    case {time_enabled, all_day} do
      {true, true} ->
        add_error(changeset, :all_day, "cannot be true when time_enabled is true")

      {false, false} ->
        add_error(changeset, :all_day, "must be true when time_enabled is false")

      _ ->
        changeset
    end
  end

  defp validate_time_slots_when_enabled(changeset) do
    time_enabled = get_field(changeset, :time_enabled)
    time_slots = get_field(changeset, :time_slots)

    case {time_enabled, time_slots} do
      {true, []} ->
        add_error(
          changeset,
          :time_slots,
          "must have at least one time slot when time_enabled is true"
        )

      {true, nil} ->
        add_error(
          changeset,
          :time_slots,
          "must have at least one time slot when time_enabled is true"
        )

      {false, slots} when is_list(slots) and length(slots) > 0 ->
        add_error(changeset, :time_slots, "should be empty when time_enabled is false")

      _ ->
        changeset
    end
  end

  defp validate_duration_constraints(changeset) do
    changeset
    # Max 24 hours
    |> validate_number(:duration_minutes, greater_than: 0, less_than: 1440)
  end

  defp validate_time_format(changeset, field) do
    case get_field(changeset, field) do
      nil ->
        changeset

      time_string when is_binary(time_string) ->
        if Regex.match?(~r/^([01]?[0-9]|2[0-3]):[0-5][0-9]$/, time_string) do
          changeset
        else
          add_error(changeset, field, "must be in HH:MM format (24-hour)")
        end

      _ ->
        add_error(changeset, field, "must be a string in HH:MM format")
    end
  end

  defp validate_timezone(changeset) do
    case get_field(changeset, :timezone) do
      nil ->
        changeset

      timezone when is_binary(timezone) ->
        # Timezone validation - accept UTC, common timezones, IANA format, or offset
        # IANA format supports multi-segment names like America/Argentina/Buenos_Aires
        # and hyphenated names like America/Port-au-Prince
        if timezone in ["UTC", "Europe/Warsaw"] or
             Regex.match?(~r/^[A-Za-z][A-Za-z0-9_+-]*(\/[A-Za-z0-9_+-]+)+$/, timezone) or
             Regex.match?(~r/^[+-]\d{2}:\d{2}$/, timezone) do
          changeset
        else
          add_error(
            changeset,
            :timezone,
            "must be a valid timezone (UTC, IANA format, or offset like +05:30)"
          )
        end

      _ ->
        add_error(changeset, :timezone, "must be a string")
    end
  end

  defp validate_time_slot_order(changeset) do
    start_time = get_field(changeset, :start_time)
    end_time = get_field(changeset, :end_time)

    case {start_time, end_time} do
      {start, finish} when is_binary(start) and is_binary(finish) ->
        case {parse_time_to_minutes(start), parse_time_to_minutes(finish)} do
          {{:ok, start_minutes}, {:ok, end_minutes}} ->
            if start_minutes < end_minutes do
              changeset
            else
              add_error(changeset, :end_time, "must be after start_time")
            end

          _ ->
            # Time format errors will be caught by validate_time_format
            changeset
        end

      _ ->
        changeset
    end
  end

  defp validate_display_format(changeset) do
    start_time = get_field(changeset, :start_time)
    end_time = get_field(changeset, :end_time)
    display = get_field(changeset, :display)

    # Auto-generate display if not provided
    if (is_nil(display) and start_time) && end_time do
      generated_display = generate_time_display(start_time, end_time)
      put_change(changeset, :display, generated_display)
    else
      changeset
    end
  end

  # Helper functions

  defp components_match_date?(date, components) do
    date.year == components.year &&
      date.month == components.month &&
      date.day == components.day &&
      Date.day_of_week(date) == components.day_of_week
  end

  defp parse_time_to_minutes(time_string) do
    case Regex.run(~r/^(\d{1,2}):(\d{2})$/, time_string) do
      [_, hour_str, minute_str] ->
        hour = String.to_integer(hour_str)
        minute = String.to_integer(minute_str)

        if hour >= 0 and hour <= 23 and minute >= 0 and minute <= 59 do
          {:ok, hour * 60 + minute}
        else
          {:error, "invalid time range"}
        end

      _ ->
        {:error, "invalid time format"}
    end
  end

  defp generate_time_display(start_time, end_time) do
    "#{format_time_24h(start_time)} - #{format_time_24h(end_time)}"
  end

  defp format_time_24h(time_string) do
    case parse_time_to_minutes(time_string) do
      {:ok, minutes} ->
        hour = div(minutes, 60)
        minute = rem(minutes, 60)

        hour_str = String.pad_leading("#{hour}", 2, "0")
        minute_str = String.pad_leading("#{minute}", 2, "0")
        "#{hour_str}:#{minute_str}"

      _ ->
        time_string
    end
  end

  @doc """
  Validates raw metadata map before casting to embedded schema.

  This function provides early validation of metadata structure
  before attempting to cast it to the embedded schema.
  Enhanced to support time slot validation.
  """
  def validate_metadata_structure(metadata) when is_map(metadata) do
    required_keys = ["date", "display_date", "date_type"]

    missing_keys = Enum.filter(required_keys, fn key -> not Map.has_key?(metadata, key) end)

    case missing_keys do
      [] ->
        # Additional validation for time-enabled polls
        validate_time_structure(metadata)

      keys ->
        {:error, "missing required keys: #{Enum.join(keys, ", ")}"}
    end
  end

  def validate_metadata_structure(_), do: {:error, "metadata must be a map"}

  defp validate_time_structure(metadata) do
    time_enabled = Map.get(metadata, "time_enabled", false)

    if time_enabled do
      time_slots = Map.get(metadata, "time_slots", [])

      cond do
        not is_list(time_slots) ->
          {:error, "time_slots must be a list when time_enabled is true"}

        length(time_slots) == 0 ->
          {:error, "time_slots must have at least one slot when time_enabled is true"}

        not valid_time_slots_structure?(time_slots) ->
          {:error, "time_slots have invalid structure"}

        true ->
          :ok
      end
    else
      :ok
    end
  end

  defp valid_time_slots_structure?(time_slots) do
    Enum.all?(time_slots, fn slot ->
      is_map(slot) and
        Map.has_key?(slot, "start_time") and
        Map.has_key?(slot, "end_time") and
        is_binary(slot["start_time"]) and
        is_binary(slot["end_time"])
    end)
  end

  @doc """
  Creates a properly structured date metadata map.

  This helper function ensures consistent metadata structure
  when creating new date options.
  Enhanced to support time slot metadata.
  """
  def build_date_metadata(date, opts \\ []) do
    parsed_date =
      case date do
        %Date{} = d ->
          d

        date_string when is_binary(date_string) ->
          case Date.from_iso8601(date_string) do
            {:ok, d} -> d
            {:error, _} -> raise ArgumentError, "Invalid date: #{date_string}"
          end
      end

    now = DateTime.utc_now() |> DateTime.to_iso8601()
    time_enabled = Keyword.get(opts, :time_enabled, false)

    base_metadata = %{
      "date" => Date.to_iso8601(parsed_date),
      "display_date" => Keyword.get(opts, :display_date, format_date_for_display(parsed_date)),
      "date_type" => Keyword.get(opts, :date_type, "single_date"),
      "created_at" => Keyword.get(opts, :created_at, now),
      "updated_at" => Keyword.get(opts, :updated_at, now),
      "date_components" => %{
        "year" => parsed_date.year,
        "month" => parsed_date.month,
        "day" => parsed_date.day,
        "day_of_week" => Date.day_of_week(parsed_date),
        "day_name" => get_day_name(Date.day_of_week(parsed_date))
      },
      # NEW: Time support fields
      "time_enabled" => time_enabled,
      "all_day" => not time_enabled
    }

    # Add time slots if time is enabled
    metadata_with_time =
      if time_enabled do
        time_slots = Keyword.get(opts, :time_slots, [])
        duration_minutes = Keyword.get(opts, :duration_minutes)
        flexible_duration = Keyword.get(opts, :flexible_duration, false)

        enhanced_metadata =
          Map.merge(base_metadata, %{
            "time_slots" => time_slots,
            "flexible_duration" => flexible_duration
          })

        if duration_minutes do
          Map.put(enhanced_metadata, "duration_minutes", duration_minutes)
        else
          enhanced_metadata
        end
      else
        base_metadata
      end

    metadata_with_time
  end

  @doc """
  Builds time slot metadata structure.

  Defaults to Europe/Warsaw timezone (the primary market) if not specified.
  """
  def build_time_slot(start_time, end_time, opts \\ []) do
    # Default to Europe/Warsaw - the primary market for this application
    timezone = Keyword.get(opts, :timezone, "Europe/Warsaw")
    display = Keyword.get(opts, :display, generate_time_display(start_time, end_time))

    %{
      "start_time" => start_time,
      "end_time" => end_time,
      "timezone" => timezone,
      "display" => display
    }
  end

  @doc """
  Validates a list of time slots for internal consistency.
  """
  def validate_time_slots(time_slots) when is_list(time_slots) do
    changeset = %Ecto.Changeset{data: %{time_slots: time_slots}, valid?: true, errors: []}

    time_slots
    |> Enum.with_index()
    |> Enum.reduce(changeset, fn {slot, index}, acc ->
      # Use proper embedded schema validation
      slot_changeset = time_slot_changeset(%__MODULE__.TimeSlot{}, slot)

      if slot_changeset.valid? do
        acc
      else
        Enum.reduce(slot_changeset.errors, acc, fn {field, {message, opts}}, changeset_acc ->
          Ecto.Changeset.add_error(
            changeset_acc,
            :time_slots,
            "slot #{index + 1} #{field} #{message}",
            opts
          )
        end)
      end
    end)
  end

  def validate_time_slots(_), do: {:error, "time_slots must be a list"}

  defp format_date_for_display(date) do
    Calendar.strftime(date, "%A, %B %d, %Y")
  end

  defp get_day_name(1), do: "Monday"
  defp get_day_name(2), do: "Tuesday"
  defp get_day_name(3), do: "Wednesday"
  defp get_day_name(4), do: "Thursday"
  defp get_day_name(5), do: "Friday"
  defp get_day_name(6), do: "Saturday"
  defp get_day_name(7), do: "Sunday"
end
