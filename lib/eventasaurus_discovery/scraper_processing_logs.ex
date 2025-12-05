defmodule EventasaurusDiscovery.ScraperProcessingLogs do
  @moduledoc """
  Context module for tracking and analyzing scraper processing outcomes.

  Provides functions for logging successes and failures across all scrapers,
  with flexible metadata storage and error categorization.

  ## Key Features

  - **No ENUMs**: Add new error types without migrations
  - **JSONB metadata**: Store any context without schema changes
  - **Unknown error handling**: Surface uncategorized errors for investigation
  - **Oban job linking**: Easy debugging via Oban dashboard
  - **Analytics queries**: Success rates, error breakdowns, trends
  """

  import Ecto.Query, warn: false
  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.ScraperProcessingLogs.ScraperProcessingLog

  # Use read replica for read operations
  defp read_repo, do: Repo.replica()

  @doc """
  Logs a successful processing attempt.

  ## Parameters
    - `source` - Source struct with `id` and `name` fields
    - `job_id` - Optional Oban job ID for debugging (default: nil)
    - `metadata` - Optional map with additional context (default: %{})

  ## Metadata Examples

      %{
        entity_type: "venue",
        entity_name: "Sky7 Cracow",
        external_id: "ra_275320"
      }

      %{
        entity_type: "event",
        entity_name: "Jazz Concert",
        external_id: "bandsintown_12345",
        venue_city: "Kraków"
      }

  ## Examples

      iex> log_success(source, job.id, %{entity_type: "event"})
      {:ok, %ScraperProcessingLog{}}
  """
  def log_success(source, job_id \\ nil, metadata \\ %{}) do
    %ScraperProcessingLog{}
    |> ScraperProcessingLog.changeset(%{
      source_id: source.id,
      source_name: source.name,
      job_id: job_id,
      status: "success",
      metadata: metadata,
      processed_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  @doc """
  Logs a failed processing attempt with automatic error categorization.

  ## Parameters
    - `source` - Source struct with `id` and `name` fields
    - `job_id` - Optional Oban job ID for debugging (default: nil)
    - `error_reason` - The error (string, exception, atom, tuple, or changeset)
    - `metadata` - Optional map with additional context (default: %{})

  ## Examples

      iex> log_failure(source, job.id, "GPS coordinates required", %{entity_type: "venue"})
      {:ok, %ScraperProcessingLog{error_type: "missing_coordinates"}}

      iex> log_failure(source, nil, %Ecto.Changeset{}, %{entity_type: "event"})
      {:ok, %ScraperProcessingLog{error_type: "validation_error"}}
  """
  def log_failure(source, job_id \\ nil, error_reason, metadata \\ %{}) do
    error_type = categorize_error(error_reason)
    error_message = format_error_message(error_reason)

    %ScraperProcessingLog{}
    |> ScraperProcessingLog.changeset(%{
      source_id: source.id,
      source_name: source.name,
      job_id: job_id,
      status: "failure",
      error_type: error_type,
      error_message: error_message,
      metadata: metadata,
      processed_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  @doc """
  Gets success rate statistics for a scraper.

  ## Parameters
    - `source_name` - Name of the source (e.g., "bandsintown", "karnet")
    - `days` - Number of days to look back (default: 7)

  ## Returns

      %{
        success_count: 3256,
        failure_count: 165,
        total_count: 3421,
        success_rate: 95.18
      }

  ## Examples

      iex> get_success_rate("bandsintown")
      %{success_count: 3256, failure_count: 165, total_count: 3421, success_rate: 95.18}

      iex> get_success_rate("karnet", 30)
      %{success_count: 5123, failure_count: 2012, total_count: 7135, success_rate: 71.81}
  """
  def get_success_rate(source_name, days \\ 7) do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-(days * 86_400))

    stats =
      from(l in ScraperProcessingLog,
        where: l.source_name == ^source_name,
        where: l.processed_at > ^cutoff_date,
        group_by: l.status,
        select: {l.status, count(l.id)}
      )
      |> read_repo().all()
      |> Map.new()

    success = stats["success"] || 0
    failure = stats["failure"] || 0
    total = success + failure
    success_rate = if total > 0, do: success / total * 100, else: 0.0

    %{
      success_count: success,
      failure_count: failure,
      total_count: total,
      success_rate: Float.round(success_rate, 2)
    }
  end

  @doc """
  Gets error breakdown by type for a scraper.

  ## Parameters
    - `source_name` - Name of the source (e.g., "sortiraparis")
    - `days` - Number of days to look back (default: 7)

  ## Returns

  List of tuples with error type and count, ordered by frequency:

      [
        {"geocoding_failed", 234},
        {"missing_coordinates", 156},
        {"unknown_error", 89},
        {"venue_creation_failed", 45}
      ]

  ## Examples

      iex> get_error_breakdown("sortiraparis")
      [{"geocoding_failed", 234}, {"missing_coordinates", 156}]
  """
  def get_error_breakdown(source_name, days \\ 7) do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-(days * 86_400))

    from(l in ScraperProcessingLog,
      where: l.source_name == ^source_name,
      where: l.status == "failure",
      where: l.processed_at > ^cutoff_date,
      group_by: l.error_type,
      select: {l.error_type, count(l.id)},
      order_by: [desc: count(l.id)]
    )
    |> read_repo().all()
  end

  @doc """
  Lists all unique error types across all scrapers.

  Useful for discovering new error patterns that need categorization.

  ## Returns

  List of error type strings:

      ["geocoding_failed", "missing_coordinates", "unknown_error", ...]

  ## Examples

      iex> list_error_types()
      ["geocoding_failed", "missing_coordinates", "unknown_error"]
  """
  def list_error_types do
    from(l in ScraperProcessingLog,
      where: l.status == "failure",
      distinct: true,
      select: l.error_type,
      order_by: l.error_type
    )
    |> read_repo().all()
  end

  @doc """
  Gets recent unknown errors for investigation.

  Use this to discover new error patterns that aren't being categorized.

  ## Parameters
    - `limit` - Maximum number of errors to return (default: 50)

  ## Returns

  List of maps with error details:

      [
        %{
          id: 123,
          source_name: "karnet",
          error_message: "Connection timeout after 30s",
          metadata: %{entity_type: "venue", venue_city: "Warsaw"},
          processed_at: ~U[2025-11-06 16:30:00Z],
          job_id: 4567
        }
      ]

  ## Examples

      iex> get_unknown_errors(10)
      [%{source_name: "karnet", error_message: "timeout", ...}]
  """
  def get_unknown_errors(limit \\ 50) do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-(7 * 86_400))

    from(l in ScraperProcessingLog,
      where: l.error_type == "unknown_error",
      where: l.processed_at > ^cutoff_date,
      order_by: [desc: l.processed_at],
      limit: ^limit,
      select: %{
        id: l.id,
        source_name: l.source_name,
        error_message: l.error_message,
        metadata: l.metadata,
        processed_at: l.processed_at,
        job_id: l.job_id
      }
    )
    |> read_repo().all()
  end

  # Private helper functions

  @doc false
  def categorize_error(reason) when is_binary(reason) do
    cond do
      # Job-level scraping errors (HTTP, parsing, data extraction)
      # These occur before event processing begins

      # HTML Parsing & Data Extraction Errors
      String.contains?(reason, "Missing icon text for") or
          String.contains?(reason, "icon text") ->
        "missing_address_data"

      String.contains?(reason, "Failed to parse HTML") ->
        "html_parsing_failed"

      String.contains?(reason, "Failed to extract") ->
        "data_extraction_failed"

      # HTTP Errors
      String.contains?(reason, ["timeout", "timed out"]) ->
        "http_timeout"

      String.contains?(reason, ["403", "Forbidden"]) ->
        "http_forbidden"

      String.contains?(reason, ["404", "Not Found"]) ->
        "http_not_found"

      String.contains?(reason, ["500", "Internal Server Error"]) ->
        "http_server_error"

      String.contains?(reason, ["502", "Bad Gateway"]) ->
        "http_bad_gateway"

      String.contains?(reason, ["503", "Service Unavailable"]) ->
        "http_service_unavailable"

      String.contains?(reason, ["rate limit", "429", "Too Many Requests"]) ->
        "rate_limit_exceeded"

      String.contains?(reason, "SSL") ->
        "ssl_error"

      String.contains?(reason, ["connection", "refused", "ECONNREFUSED"]) ->
        "connection_refused"

      # Venue errors
      String.contains?(reason, "Unknown country") or
          String.contains?(reason, "without a valid country") ->
        "unknown_country"

      String.contains?(reason, "geocoding failed") ->
        "geocoding_failed"

      String.contains?(reason, "Failed to create venue") ->
        "venue_creation_failed"

      String.contains?(reason, "Failed to update venue") ->
        "venue_update_failed"

      String.contains?(reason, "City is required") ->
        "missing_city"

      String.contains?(reason, ["Venue name is required", "name is required"]) ->
        "missing_venue_name"

      String.contains?(reason, ["GPS coordinates", "coordinates required"]) ->
        "missing_coordinates"

      # Event validation errors
      String.contains?(reason, "Event start time is required") or
          String.contains?(reason, "start time is required") ->
        "missing_event_start_time"

      String.contains?(reason, "Event end time is required") or
          String.contains?(reason, "end time is required") ->
        "missing_event_end_time"

      String.contains?(reason, "Event title is required") or
          String.contains?(reason, "title is required") ->
        "missing_event_title"

      String.contains?(reason, "Event description is required") or
          String.contains?(reason, "description is required") ->
        "missing_event_description"

      # Default: Unknown (investigate these!)
      true ->
        "unknown_error"
    end
  end

  def categorize_error(%Ecto.Changeset{} = changeset) do
    # Check changeset errors for specific fields
    error_fields = Enum.map(changeset.errors, fn {field, _} -> field end)

    cond do
      :slug in error_fields -> "duplicate_slug"
      :latitude in error_fields or :longitude in error_fields -> "invalid_coordinates"
      true -> "validation_error"
    end
  end

  # Handle Oban.PerformError and other exception structs
  def categorize_error(%{__exception__: true} = exception) do
    # Extract the error message and recursively categorize it
    message = Exception.message(exception)
    categorize_error(message)
  end

  def categorize_error(reason) when is_atom(reason), do: Atom.to_string(reason)

  def categorize_error({error_type, _detail}) when is_atom(error_type),
    do: Atom.to_string(error_type)

  def categorize_error(_), do: "unknown_error"

  defp format_error_message(reason) when is_binary(reason) do
    String.slice(reason, 0, 500)
  end

  defp format_error_message(%{__exception__: true} = exception) do
    exception
    |> Exception.message()
    |> String.slice(0, 500)
  end

  defp format_error_message(reason) do
    reason
    |> inspect()
    |> String.slice(0, 500)
  end
end
