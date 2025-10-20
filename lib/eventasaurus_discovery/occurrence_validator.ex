defmodule Eventasaurus.Discovery.OccurrenceValidator do
  @moduledoc """
  Validates occurrence types and structures to ensure consistency across scrapers.

  ## Allowed Occurrence Types

  - `"explicit"` - One-time events with specific date/time (concerts, performances)
  - `"pattern"` - Recurring events with strict schedule via recurrence_rule (weekly trivia)
  - `"exhibition"` - Open-ended periods with continuous access (museums, galleries)
  - `"recurring"` - Recurring events without strict pattern ("every weekend")

  ## Usage in Transformers

      alias Eventasaurus.Discovery.OccurrenceValidator

      def transform_event(raw_event) do
        occurrence_type = determine_occurrence_type(raw_event)

        case OccurrenceValidator.validate_type(occurrence_type) do
          {:ok, validated_type} ->
            build_event(raw_event, validated_type)

          {:error, reason} ->
            Logger.error("[MySource] Error: " <> reason <> ". Defaulting to 'explicit'")
            build_event(raw_event, "explicit")
        end
      end

  ## Usage in Event Processor

      defp initialize_occurrence_with_source(data) do
        occurrence_type = get_occurrence_type(data)

        case OccurrenceValidator.validate_type(occurrence_type) do
          {:ok, valid_type} ->
            build_occurrence_structure(valid_type, data)

          {:error, reason} ->
            Logger.warning("[EventProcessor] Error: " <> reason <> ". Using 'explicit'")
            build_occurrence_structure("explicit", data)
        end
      end

  See `docs/OCCURRENCE_TYPES.md` for detailed documentation on each type.
  """

  require Logger

  @allowed_types ["explicit", "pattern", "exhibition", "recurring"]

  @type occurrence_type :: String.t()
  @type validation_result :: {:ok, occurrence_type()} | {:error, String.t()}

  @doc """
  Validates occurrence type value against allowed types.

  Returns `{:ok, type}` if valid, `{:error, reason}` otherwise.

  ## Examples

      iex> OccurrenceValidator.validate_type("explicit")
      {:ok, "explicit"}

      iex> OccurrenceValidator.validate_type("pattern")
      {:ok, "pattern"}

      iex> OccurrenceValidator.validate_type("one_time")
      {:error, "Invalid occurrence type 'one_time'. Allowed types: explicit, pattern, exhibition, recurring. See docs/OCCURRENCE_TYPES.md for documentation."}

      iex> OccurrenceValidator.validate_type("unknown")
      {:error, "Invalid occurrence type 'unknown'. Allowed types: explicit, pattern, exhibition, recurring. See docs/OCCURRENCE_TYPES.md for documentation."}

  """
  @spec validate_type(any()) :: validation_result()
  def validate_type(type) when type in @allowed_types do
    {:ok, type}
  end

  def validate_type(invalid_type) when is_binary(invalid_type) do
    {:error,
     "Invalid occurrence type '#{invalid_type}'. " <>
       "Allowed types: #{Enum.join(@allowed_types, ", ")}. " <>
       "See docs/OCCURRENCE_TYPES.md for documentation."}
  end

  def validate_type(invalid_type) do
    {:error,
     "Invalid occurrence type #{inspect(invalid_type)}. " <>
       "Must be a string. Allowed types: #{Enum.join(@allowed_types, ", ")}. " <>
       "See docs/OCCURRENCE_TYPES.md for documentation."}
  end

  @doc """
  Validates complete occurrence structure based on type.
  Ensures required fields are present for each occurrence type.

  Returns `{:ok, occurrence}` if valid, `{:error, reason}` otherwise.

  ## Examples

      iex> OccurrenceValidator.validate_structure(%{"type" => "explicit", "dates" => [%{"date" => "2024-06-15"}]})
      {:ok, %{"type" => "explicit", "dates" => [%{"date" => "2024-06-15"}]}}

      iex> OccurrenceValidator.validate_structure(%{"type" => "pattern", "pattern" => %{"frequency" => "weekly"}})
      {:ok, %{"type" => "pattern", "pattern" => %{"frequency" => "weekly"}}}

      iex> OccurrenceValidator.validate_structure(%{"type" => "explicit"})
      {:error, "Occurrence type 'explicit' is missing required field 'dates'"}

      iex> OccurrenceValidator.validate_structure(%{"foo" => "bar"})
      {:error, "Occurrence must have a 'type' field. Got: %{\\"foo\\" => \\"bar\\"}"}

  """
  @spec validate_structure(map()) :: {:ok, map()} | {:error, String.t()}
  def validate_structure(%{"type" => type} = occurrence) do
    with {:ok, _} <- validate_type(type),
         {:ok, _} <- validate_type_specific_fields(occurrence) do
      {:ok, occurrence}
    end
  end

  def validate_structure(invalid) do
    {:error, "Occurrence must have a 'type' field. Got: #{inspect(invalid)}"}
  end

  @doc """
  Returns list of all allowed occurrence types.

  Useful for generating documentation, tests, UI elements, and database constraints.

  ## Examples

      iex> OccurrenceValidator.allowed_types()
      ["explicit", "pattern", "exhibition", "recurring"]

  """
  @spec allowed_types() :: [occurrence_type()]
  def allowed_types, do: @allowed_types

  @doc """
  Validates and normalizes occurrence type from legacy values.

  Maps old occurrence type names to new standardized taxonomy:
  - "one_time" → "explicit"
  - "unknown" → "exhibition" (unparseable dates usually indicate open-ended events)
  - "movie" → "explicit" (use explicit for specific showtimes)

  Returns `{:ok, normalized_type}` with the correct type name.

  ## Examples

      iex> OccurrenceValidator.normalize_legacy_type("one_time")
      {:ok, "explicit"}

      iex> OccurrenceValidator.normalize_legacy_type("unknown")
      {:ok, "exhibition"}

      iex> OccurrenceValidator.normalize_legacy_type("movie")
      {:ok, "explicit"}

      iex> OccurrenceValidator.normalize_legacy_type("explicit")
      {:ok, "explicit"}

      iex> OccurrenceValidator.normalize_legacy_type("invalid")
      {:error, "Invalid occurrence type 'invalid'. Allowed types: explicit, pattern, exhibition, recurring. See docs/OCCURRENCE_TYPES.md for documentation."}

  """
  @spec normalize_legacy_type(any()) :: validation_result()
  def normalize_legacy_type("one_time") do
    Logger.info(
      "[OccurrenceValidator] Normalized legacy type 'one_time' to 'explicit'. Update transformer to use 'explicit' directly."
    )

    {:ok, "explicit"}
  end

  def normalize_legacy_type("unknown") do
    Logger.info(
      "[OccurrenceValidator] Normalized legacy type 'unknown' to 'exhibition'. Update transformer to use 'exhibition' directly."
    )

    {:ok, "exhibition"}
  end

  def normalize_legacy_type("movie") do
    Logger.info(
      "[OccurrenceValidator] Normalized legacy type 'movie' to 'explicit'. Use 'explicit' for movie showtimes."
    )

    {:ok, "explicit"}
  end

  def normalize_legacy_type(type) do
    validate_type(type)
  end

  # Private helper functions

  defp validate_type_specific_fields(%{"type" => "explicit", "dates" => dates})
       when is_list(dates) and length(dates) > 0 do
    {:ok, :valid}
  end

  defp validate_type_specific_fields(%{"type" => "explicit"}) do
    {:error, "Occurrence type 'explicit' is missing required field 'dates'"}
  end

  defp validate_type_specific_fields(%{"type" => "pattern", "pattern" => pattern})
       when is_map(pattern) do
    {:ok, :valid}
  end

  defp validate_type_specific_fields(%{"type" => "pattern"}) do
    {:error, "Occurrence type 'pattern' is missing required field 'pattern'"}
  end

  defp validate_type_specific_fields(%{"type" => "exhibition", "dates" => dates})
       when is_list(dates) and length(dates) > 0 do
    {:ok, :valid}
  end

  defp validate_type_specific_fields(%{"type" => "exhibition"}) do
    {:error, "Occurrence type 'exhibition' is missing required field 'dates'"}
  end

  defp validate_type_specific_fields(%{"type" => "recurring", "dates" => dates})
       when is_list(dates) and length(dates) > 0 do
    {:ok, :valid}
  end

  defp validate_type_specific_fields(%{"type" => "recurring"}) do
    {:error, "Occurrence type 'recurring' is missing required field 'dates'"}
  end

  defp validate_type_specific_fields(%{"type" => type}) do
    {:error, "Occurrence type '#{type}' is missing required fields"}
  end
end
