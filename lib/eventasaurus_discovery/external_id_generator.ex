defmodule EventasaurusDiscovery.ExternalIdGenerator do
  @moduledoc """
  Generates and validates external_id values following documented conventions.

  This module enforces the external_id patterns defined in docs/EXTERNAL_ID_CONVENTIONS.md
  to prevent convention violations that cause data integrity issues.

  ## Event Types and Patterns

  | Type         | Pattern                                          | Date? | Example                                    |
  |--------------|--------------------------------------------------|-------|--------------------------------------------|
  | single       | `{source}_{type}_{source_id}`                    | No    | `bandsintown_event_12345`                  |
  | multi_date   | `{source}_{type}_{source_id}_{YYYY-MM-DD}`       | Yes   | `karnet_event_abc123_2025-01-15`           |
  | showtime     | `{source}_{showtime_id}` or complex form         | Yes   | `cinema_city_showtime_789`                 |
  | recurring    | `{source}_{venue_id}`                            | No    | `inquizition_97520779`                     |

  ## Critical Rule

  **Recurring events MUST NOT include dates in their external_id.**

  The recurrence_rule field handles scheduling; the external_id identifies the venue pattern.
  Adding dates to recurring event external_ids causes:
  - Database bloat (52+ records per venue instead of 1)
  - EventFreshnessChecker bypasses
  - Duplicate event creation

  ## Usage

      # Generate external_id
      {:ok, external_id} = ExternalIdGenerator.generate(:recurring, "inquizition", %{venue_id: "97520779"})
      # => {:ok, "inquizition_97520779"}

      # Validate external_id
      ExternalIdGenerator.valid?(:recurring, "inquizition_97520779")
      # => true

      ExternalIdGenerator.valid?(:recurring, "inquizition_97520779_2025-01-15")
      # => false (dates not allowed in recurring)

  ## See Also

  - docs/EXTERNAL_ID_CONVENTIONS.md for complete specification
  - GitHub issue #2929 for enforcement rationale
  """

  @type event_type :: :single | :multi_date | :showtime | :recurring
  @type generation_params :: %{
          optional(:venue_id) => String.t(),
          optional(:source_id) => String.t(),
          optional(:type) => String.t(),
          optional(:showtime_id) => String.t(),
          optional(:movie_id) => String.t(),
          optional(:date) => Date.t() | String.t(),
          optional(:datetime) => DateTime.t() | String.t()
        }

  # Regex patterns for validation
  # Single: source_type_id (no date)
  @single_pattern ~r/^[a-z][a-z0-9_]*_[a-z]+_[a-zA-Z0-9_-]+$/

  # Multi-date: source_type_id_YYYY-MM-DD
  @multi_date_pattern ~r/^[a-z][a-z0-9_]*_[a-z]+_[a-zA-Z0-9_-]+_\d{4}-\d{2}-\d{2}$/

  # Showtime simple: source_showtime_id
  @showtime_simple_pattern ~r/^[a-z][a-z0-9_]*_showtime_[a-zA-Z0-9_-]+$/

  # Showtime complex: source_venue_movie_datetime
  @showtime_complex_pattern ~r/^[a-z][a-z0-9_]*_[a-zA-Z0-9_-]+_[a-zA-Z0-9_-]+_\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/

  # Recurring: source_venue_id (NO date allowed)
  @recurring_pattern ~r/^[a-z][a-z0-9_]*_[a-zA-Z0-9_-]+$/

  # Pattern to detect date suffixes (used to reject them in recurring)
  @date_suffix_pattern ~r/_\d{4}-\d{2}-\d{2}$/

  @doc """
  Generates an external_id for the given event type.

  ## Parameters

  - `event_type` - One of `:single`, `:multi_date`, `:showtime`, or `:recurring`
  - `source` - Source name/slug (e.g., "inquizition", "cinema_city")
  - `params` - Map with required fields based on event type

  ## Required Params by Type

  - `:single` - `%{type: "event", source_id: "123"}`
  - `:multi_date` - `%{type: "event", source_id: "123", date: ~D[2025-01-15]}`
  - `:showtime` - `%{showtime_id: "789"}` or `%{venue_id: "v1", movie_id: "m1", datetime: ~U[...]}`
  - `:recurring` - `%{venue_id: "97520779"}`

  ## Returns

  - `{:ok, external_id}` on success
  - `{:error, reason}` on validation failure

  ## Examples

      iex> ExternalIdGenerator.generate(:recurring, "inquizition", %{venue_id: "97520779"})
      {:ok, "inquizition_97520779"}

      iex> ExternalIdGenerator.generate(:single, "bandsintown", %{type: "event", source_id: "12345"})
      {:ok, "bandsintown_event_12345"}

      iex> ExternalIdGenerator.generate(:multi_date, "karnet", %{type: "event", source_id: "abc", date: ~D[2025-01-15]})
      {:ok, "karnet_event_abc_2025-01-15"}
  """
  @spec generate(event_type(), String.t(), generation_params()) ::
          {:ok, String.t()} | {:error, String.t()}
  def generate(event_type, source, params)

  def generate(:single, source, %{type: type, source_id: source_id})
      when is_binary(source) and is_binary(type) and is_binary(source_id) do
    external_id = "#{normalize_source(source)}_#{type}_#{source_id}"
    {:ok, external_id}
  end

  def generate(:single, _source, params) do
    {:error, "Single event requires :type and :source_id params, got: #{inspect(Map.keys(params))}"}
  end

  def generate(:multi_date, source, %{type: type, source_id: source_id, date: date})
      when is_binary(source) and is_binary(type) and is_binary(source_id) do
    date_str = format_date(date)

    case date_str do
      {:ok, formatted} ->
        external_id = "#{normalize_source(source)}_#{type}_#{source_id}_#{formatted}"
        {:ok, external_id}

      {:error, _} = error ->
        error
    end
  end

  def generate(:multi_date, _source, params) do
    {:error,
     "Multi-date event requires :type, :source_id, and :date params, got: #{inspect(Map.keys(params))}"}
  end

  def generate(:showtime, source, %{showtime_id: showtime_id})
      when is_binary(source) and is_binary(showtime_id) do
    external_id = "#{normalize_source(source)}_showtime_#{showtime_id}"
    {:ok, external_id}
  end

  def generate(:showtime, source, %{venue_id: venue_id, movie_id: movie_id, datetime: datetime})
      when is_binary(source) and is_binary(venue_id) and is_binary(movie_id) do
    datetime_str = format_datetime(datetime)

    case datetime_str do
      {:ok, formatted} ->
        external_id = "#{normalize_source(source)}_#{venue_id}_#{movie_id}_#{formatted}"
        {:ok, external_id}

      {:error, _} = error ->
        error
    end
  end

  def generate(:showtime, _source, params) do
    {:error,
     "Showtime requires either :showtime_id or :venue_id/:movie_id/:datetime, got: #{inspect(Map.keys(params))}"}
  end

  def generate(:recurring, source, %{venue_id: venue_id})
      when is_binary(source) and is_binary(venue_id) do
    # CRITICAL: Recurring events must NOT include dates
    external_id = "#{normalize_source(source)}_#{venue_id}"
    {:ok, external_id}
  end

  def generate(:recurring, _source, params) do
    {:error, "Recurring event requires :venue_id param, got: #{inspect(Map.keys(params))}"}
  end

  def generate(event_type, _source, _params) do
    {:error, "Unknown event type: #{inspect(event_type)}. Valid types: :single, :multi_date, :showtime, :recurring"}
  end

  @doc """
  Validates an external_id against the expected pattern for an event type.

  ## Parameters

  - `event_type` - One of `:single`, `:multi_date`, `:showtime`, or `:recurring`
  - `external_id` - The external_id string to validate

  ## Returns

  - `true` if the external_id matches the pattern for the given type
  - `false` otherwise

  ## Examples

      iex> ExternalIdGenerator.valid?(:recurring, "inquizition_97520779")
      true

      iex> ExternalIdGenerator.valid?(:recurring, "inquizition_97520779_2025-01-15")
      false  # Dates not allowed in recurring!

      iex> ExternalIdGenerator.valid?(:multi_date, "karnet_event_123_2025-01-15")
      true
  """
  @spec valid?(event_type(), String.t()) :: boolean()
  def valid?(event_type, external_id) when is_binary(external_id) do
    case validate(event_type, external_id) do
      :ok -> true
      {:error, _} -> false
    end
  end

  def valid?(_, _), do: false

  @doc """
  Validates an external_id and returns detailed error information.

  ## Returns

  - `:ok` if valid
  - `{:error, reason}` with explanation if invalid

  ## Examples

      iex> ExternalIdGenerator.validate(:recurring, "inquizition_97520779_2025-01-15")
      {:error, "Recurring event external_id must NOT contain date suffix. Found: _2025-01-15"}
  """
  @spec validate(event_type(), String.t()) :: :ok | {:error, String.t()}
  def validate(:single, external_id) do
    if Regex.match?(@single_pattern, external_id) do
      # Also ensure it doesn't have a date (would make it multi_date)
      if Regex.match?(@date_suffix_pattern, external_id) do
        {:error, "Single event external_id must NOT contain date suffix. Use :multi_date type for dated events."}
      else
        :ok
      end
    else
      {:error, "Single event external_id must match pattern: {source}_{type}_{source_id}"}
    end
  end

  def validate(:multi_date, external_id) do
    if Regex.match?(@multi_date_pattern, external_id) do
      :ok
    else
      {:error, "Multi-date event external_id must match pattern: {source}_{type}_{source_id}_{YYYY-MM-DD}"}
    end
  end

  def validate(:showtime, external_id) do
    if Regex.match?(@showtime_simple_pattern, external_id) or
         Regex.match?(@showtime_complex_pattern, external_id) do
      :ok
    else
      {:error,
       "Showtime external_id must match pattern: {source}_showtime_{id} or {source}_{venue}_{movie}_{datetime}"}
    end
  end

  def validate(:recurring, external_id) do
    # First check: Must NOT have a date suffix
    if Regex.match?(@date_suffix_pattern, external_id) do
      # Extract the date for a helpful error message
      [date_part] = Regex.run(@date_suffix_pattern, external_id)

      {:error,
       "Recurring event external_id must NOT contain date suffix. Found: #{date_part}. " <>
         "Dates are handled by recurrence_rule, not external_id. See docs/EXTERNAL_ID_CONVENTIONS.md"}
    else
      # Check basic format
      if Regex.match?(@recurring_pattern, external_id) do
        :ok
      else
        {:error, "Recurring event external_id must match pattern: {source}_{venue_id}"}
      end
    end
  end

  def validate(event_type, _external_id) do
    {:error, "Unknown event type: #{inspect(event_type)}"}
  end

  @doc """
  Detects the likely event type from an external_id pattern.

  Useful for auditing and migration purposes.

  ## Returns

  - `{:ok, event_type}` if pattern is recognized
  - `{:error, :ambiguous}` if multiple types could match
  - `{:error, :unknown}` if no pattern matches

  ## Examples

      iex> ExternalIdGenerator.detect_type("karnet_event_123_2025-01-15")
      {:ok, :multi_date}

      iex> ExternalIdGenerator.detect_type("inquizition_97520779")
      {:ok, :recurring}  # or :single - ambiguous without context
  """
  @spec detect_type(String.t()) :: {:ok, event_type()} | {:error, :ambiguous | :unknown}
  def detect_type(external_id) when is_binary(external_id) do
    cond do
      # Multi-date is most specific (has date suffix)
      Regex.match?(@multi_date_pattern, external_id) ->
        {:ok, :multi_date}

      # Showtime patterns
      Regex.match?(@showtime_simple_pattern, external_id) ->
        {:ok, :showtime}

      Regex.match?(@showtime_complex_pattern, external_id) ->
        {:ok, :showtime}

      # Single event (has type in middle)
      Regex.match?(@single_pattern, external_id) ->
        # Could be single or recurring depending on context
        # If it has a known type word (event, activity, etc.), it's single
        if Regex.match?(~r/_(?:event|activity|show|concert|movie)_/, external_id) do
          {:ok, :single}
        else
          # Ambiguous - could be recurring venue ID
          {:error, :ambiguous}
        end

      # Recurring (simplest pattern - source_venue_id)
      Regex.match?(@recurring_pattern, external_id) ->
        {:ok, :recurring}

      true ->
        {:error, :unknown}
    end
  end

  def detect_type(_), do: {:error, :unknown}

  @doc """
  Checks if an external_id has a date suffix (for detecting violations).

  This is useful for auditing recurring events that incorrectly have dates.

  ## Examples

      iex> ExternalIdGenerator.has_date_suffix?("inquizition_97520779_2025-01-15")
      true

      iex> ExternalIdGenerator.has_date_suffix?("inquizition_97520779")
      false
  """
  @spec has_date_suffix?(String.t()) :: boolean()
  def has_date_suffix?(external_id) when is_binary(external_id) do
    Regex.match?(@date_suffix_pattern, external_id)
  end

  def has_date_suffix?(_), do: false

  @doc """
  Strips date suffix from an external_id (for fixing violations).

  ## Examples

      iex> ExternalIdGenerator.strip_date_suffix("inquizition_97520779_2025-01-15")
      "inquizition_97520779"

      iex> ExternalIdGenerator.strip_date_suffix("inquizition_97520779")
      "inquizition_97520779"
  """
  @spec strip_date_suffix(String.t()) :: String.t()
  def strip_date_suffix(external_id) when is_binary(external_id) do
    String.replace(external_id, @date_suffix_pattern, "")
  end

  def strip_date_suffix(external_id), do: external_id

  # Private helpers

  defp normalize_source(source) do
    source
    |> String.downcase()
    |> String.replace("-", "_")
  end

  defp format_date(%Date{} = date), do: {:ok, Date.to_iso8601(date)}

  defp format_date(date_str) when is_binary(date_str) do
    if Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, date_str) do
      {:ok, date_str}
    else
      {:error, "Invalid date format. Expected YYYY-MM-DD, got: #{date_str}"}
    end
  end

  defp format_date(other) do
    {:error, "Invalid date type. Expected Date or string, got: #{inspect(other)}"}
  end

  defp format_datetime(%DateTime{} = dt) do
    # Format as ISO8601 without timezone suffix for compactness
    {:ok, Calendar.strftime(dt, "%Y-%m-%dT%H:%M:%S")}
  end

  defp format_datetime(dt_str) when is_binary(dt_str) do
    if Regex.match?(~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/, dt_str) do
      {:ok, dt_str}
    else
      {:error, "Invalid datetime format. Expected ISO8601, got: #{dt_str}"}
    end
  end

  defp format_datetime(other) do
    {:error, "Invalid datetime type. Expected DateTime or string, got: #{inspect(other)}"}
  end
end
