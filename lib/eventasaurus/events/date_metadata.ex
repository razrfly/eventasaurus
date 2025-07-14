defmodule EventasaurusApp.Events.DateMetadata do
  @moduledoc """
  Embedded schema for validating date metadata in poll options.

  This schema ensures data integrity and type safety for date_selection polls
  by validating the structure and content of date metadata stored in the
  metadata field of poll options.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :date, :string
    field :display_date, :string
    field :date_type, :string, default: "single_date"
    field :created_at, :string
    field :updated_at, :string

    embeds_one :date_components, DateComponents, primary_key: false do
      field :year, :integer
      field :month, :integer
      field :day, :integer
      field :day_of_week, :integer
      field :day_name, :string
    end
  end

  @doc """
  Validates date metadata for poll options.

  Ensures all required fields are present and properly formatted,
  with special validation for date formats and component consistency.
  """
  def changeset(date_metadata, attrs) do
    date_metadata
    |> cast(attrs, [:date, :display_date, :date_type, :created_at, :updated_at])
    |> cast_embed(:date_components, with: &date_components_changeset/2)
    |> validate_required([:date, :display_date, :date_type])
    |> validate_inclusion(:date_type, ~w(single_date date_range recurring_date))
    |> validate_date_format()
    |> validate_timestamp_format(:created_at)
    |> validate_timestamp_format(:updated_at)
    |> validate_date_components_consistency()
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

  # Private validation functions

  defp validate_date_format(changeset) do
    case get_field(changeset, :date) do
      nil -> changeset
      date_string ->
        case Date.from_iso8601(date_string) do
          {:ok, _date} -> changeset
          {:error, _} -> add_error(changeset, :date, "must be a valid ISO8601 date (YYYY-MM-DD)")
        end
    end
  end

  defp validate_timestamp_format(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
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
      {nil, _} -> changeset
      {_, nil} -> changeset
      {date_str, components} ->
        case Date.from_iso8601(date_str) do
          {:ok, date} ->
            if components_match_date?(date, components) do
              changeset
            else
              add_error(changeset, :date_components, "do not match the date value")
            end
          {:error, _} -> changeset  # Already handled by validate_date_format
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
              add_error(changeset, :day_of_week, "does not match the calculated day of week for #{y}-#{m}-#{d}")
            end
          {:error, _} ->
            add_error(changeset, :day, "invalid date combination: #{y}-#{m}-#{d}")
        end
      _ -> changeset
    end
  end

  defp components_match_date?(date, components) do
    date.year == components.year &&
    date.month == components.month &&
    date.day == components.day &&
    Date.day_of_week(date) == components.day_of_week
  end

  @doc """
  Validates raw metadata map before casting to embedded schema.

  This function provides early validation of metadata structure
  before attempting to cast it to the embedded schema.
  """
  def validate_metadata_structure(metadata) when is_map(metadata) do
    required_keys = ["date", "display_date", "date_type"]

    missing_keys = Enum.filter(required_keys, fn key -> not Map.has_key?(metadata, key) end)

    case missing_keys do
      [] -> :ok
      keys -> {:error, "missing required keys: #{Enum.join(keys, ", ")}"}
    end
  end

  def validate_metadata_structure(_), do: {:error, "metadata must be a map"}

  @doc """
  Creates a properly structured date metadata map.

  This helper function ensures consistent metadata structure
  when creating new date options.
  """
  def build_date_metadata(date, opts \\ []) do
    parsed_date = case date do
      %Date{} = d -> d
      date_string when is_binary(date_string) ->
        case Date.from_iso8601(date_string) do
          {:ok, d} -> d
          {:error, _} -> raise ArgumentError, "Invalid date: #{date_string}"
        end
    end

    now = DateTime.utc_now() |> DateTime.to_iso8601()

    %{
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
      }
    }
  end

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
