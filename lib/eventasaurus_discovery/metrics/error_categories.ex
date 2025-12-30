defmodule EventasaurusDiscovery.Metrics.ErrorCategories do
  @moduledoc """
  Standardized error categorization for event processing failures.

  Provides consistent error categories across all scrapers to enable
  aggregation, trending, and analysis.

  ## Error Categories (12 + 1 fallback)

  - `:validation_error` - Missing required fields, invalid data format
  - `:parsing_error` - HTML/JSON/XML parsing failures
  - `:data_quality_error` - Unexpected values, business rule violations
  - `:data_integrity_error` - DB duplicates, constraint violations
  - `:dependency_error` - Waiting for parent job to complete
  - `:network_error` - HTTP errors, timeouts, connection failures
  - `:rate_limit_error` - API throttling (429)
  - `:authentication_error` - API auth failures (401/403)
  - `:geocoding_error` - Address geocoding failures, coordinate issues
  - `:venue_error` - Venue processing or matching failures
  - `:performer_error` - Performer/artist processing failures
  - `:tmdb_error` - TMDB lookup failures (no results, low confidence)
  - `:uncategorized_error` - Errors that don't match known patterns (investigate!)

  ## Usage

      iex> ErrorCategories.categorize_error("Event title is required")
      :validation_error

      iex> ErrorCategories.categorize_error(:movie_not_ready)
      :dependency_error

      iex> ErrorCategories.categorize_error("HTTP 429 - Rate limit exceeded")
      :rate_limit_error

  See docs/error-handling-guide.md for full documentation.
  """

  @categories ~w(
    validation_error
    parsing_error
    data_quality_error
    data_integrity_error
    dependency_error
    network_error
    rate_limit_error
    authentication_error
    geocoding_error
    venue_error
    performer_error
    tmdb_error
    uncategorized_error
  )a

  @doc """
  Returns all available error categories.

  ## Examples

      iex> ErrorCategories.categories()
      [:validation_error, :parsing_error, :data_quality_error, :data_integrity_error,
       :dependency_error, :network_error, :rate_limit_error, :authentication_error,
       :geocoding_error, :venue_error, :performer_error, :tmdb_error, :uncategorized_error]
  """
  def categories, do: @categories

  @doc """
  Categorizes an error reason into a standardized category.

  Handles multiple input types:
  - Atoms (e.g., :movie_not_ready)
  - Strings (e.g., "Validation failed: missing title")
  - Exceptions (e.g., %Ecto.MultipleResultsError{})
  - Tuples (e.g., {:http_error, 429, "Too Many Requests"})

  ## Examples

      iex> categorize_error(:movie_not_ready)
      :dependency_error

      iex> categorize_error("Event title is required")
      :validation_error

      iex> categorize_error(%Ecto.MultipleResultsError{})
      :data_integrity_error

      iex> categorize_error("HTTP 429 - Rate limit exceeded")
      :rate_limit_error
  """

  # ============================================================================
  # IDENTITY MATCHING - Category atoms passed directly
  # When callers already know the category, pass it through unchanged
  # ============================================================================
  def categorize_error(:validation_error), do: :validation_error
  def categorize_error(:parsing_error), do: :parsing_error
  def categorize_error(:data_quality_error), do: :data_quality_error
  def categorize_error(:data_integrity_error), do: :data_integrity_error
  def categorize_error(:dependency_error), do: :dependency_error
  def categorize_error(:network_error), do: :network_error
  def categorize_error(:rate_limit_error), do: :rate_limit_error
  def categorize_error(:authentication_error), do: :authentication_error
  def categorize_error(:geocoding_error), do: :geocoding_error
  def categorize_error(:venue_error), do: :venue_error
  def categorize_error(:performer_error), do: :performer_error
  def categorize_error(:tmdb_error), do: :tmdb_error
  def categorize_error(:uncategorized_error), do: :uncategorized_error

  # ============================================================================
  # ATOM PATTERN MATCHING
  # These handle the common case where jobs return {:error, :some_atom}
  # ============================================================================

  # Dependency errors - waiting for parent job
  def categorize_error(:movie_not_ready), do: :dependency_error
  def categorize_error(:movie_not_found), do: :dependency_error
  def categorize_error(:venue_not_ready), do: :dependency_error
  def categorize_error(:venue_not_processed), do: :dependency_error
  def categorize_error(:parent_job_pending), do: :dependency_error
  def categorize_error(:waiting_for_dependency), do: :dependency_error
  def categorize_error(:not_ready), do: :dependency_error

  # Validation errors - missing/invalid data
  def categorize_error(:missing_external_id), do: :validation_error
  def categorize_error(:missing_title), do: :validation_error
  def categorize_error(:missing_url), do: :validation_error
  def categorize_error(:missing_source_id), do: :validation_error
  def categorize_error(:missing_required_field), do: :validation_error
  def categorize_error(:invalid_date), do: :validation_error
  def categorize_error(:invalid_showtime), do: :validation_error
  def categorize_error(:invalid_format), do: :validation_error
  def categorize_error(:invalid_data), do: :validation_error
  def categorize_error(:validation_failed), do: :validation_error

  # Parsing errors - HTML/JSON/XML parsing
  def categorize_error(:parse_failed), do: :parsing_error
  def categorize_error(:parse_error), do: :parsing_error
  def categorize_error(:json_decode_error), do: :parsing_error
  def categorize_error(:html_parse_error), do: :parsing_error
  def categorize_error(:xml_parse_error), do: :parsing_error
  def categorize_error(:malformed_response), do: :parsing_error

  # Network errors - connection failures
  def categorize_error(:timeout), do: :network_error
  def categorize_error(:connection_refused), do: :network_error
  def categorize_error(:connection_closed), do: :network_error
  def categorize_error(:econnrefused), do: :network_error
  def categorize_error(:nxdomain), do: :network_error
  def categorize_error(:closed), do: :network_error
  def categorize_error(:http_error), do: :network_error
  def categorize_error(:server_error), do: :network_error

  # Rate limit errors
  def categorize_error(:rate_limited), do: :rate_limit_error
  def categorize_error(:rate_limit_exceeded), do: :rate_limit_error
  def categorize_error(:too_many_requests), do: :rate_limit_error
  def categorize_error(:throttled), do: :rate_limit_error

  # Authentication errors
  def categorize_error(:unauthorized), do: :authentication_error
  def categorize_error(:forbidden), do: :authentication_error
  def categorize_error(:auth_failed), do: :authentication_error
  def categorize_error(:invalid_credentials), do: :authentication_error
  def categorize_error(:token_expired), do: :authentication_error

  # TMDB errors
  def categorize_error(:tmdb_not_found), do: :tmdb_error
  def categorize_error(:tmdb_no_results), do: :tmdb_error
  def categorize_error(:tmdb_low_confidence), do: :tmdb_error
  def categorize_error(:tmdb_needs_review), do: :tmdb_error
  def categorize_error(:movie_not_matched), do: :tmdb_error
  def categorize_error(:no_tmdb_match), do: :tmdb_error

  # Venue errors
  def categorize_error(:venue_not_found), do: :venue_error
  def categorize_error(:venue_creation_failed), do: :venue_error
  def categorize_error(:venue_ambiguous), do: :venue_error

  # Performer errors
  def categorize_error(:performer_not_found), do: :performer_error
  def categorize_error(:artist_not_found), do: :performer_error
  def categorize_error(:performer_matching_failed), do: :performer_error
  def categorize_error(:performer_ambiguous), do: :performer_error

  # Geocoding errors
  def categorize_error(:geocoding_failed), do: :geocoding_error
  def categorize_error(:address_not_found), do: :geocoding_error
  def categorize_error(:invalid_coordinates), do: :geocoding_error

  # Data integrity errors
  def categorize_error(:duplicate), do: :data_integrity_error
  def categorize_error(:already_exists), do: :data_integrity_error
  def categorize_error(:unique_constraint), do: :data_integrity_error
  def categorize_error(:constraint_error), do: :data_integrity_error
  def categorize_error(:rollback), do: :data_integrity_error

  # Data quality errors
  def categorize_error(:unexpected_data), do: :data_quality_error
  def categorize_error(:business_rule_violation), do: :data_quality_error
  def categorize_error(:encoding_error), do: :data_quality_error

  # ============================================================================
  # EXCEPTION PATTERN MATCHING
  # Handle common Elixir/Ecto exceptions directly
  # ============================================================================

  def categorize_error(%Ecto.MultipleResultsError{}), do: :data_integrity_error
  def categorize_error(%Ecto.NoResultsError{}), do: :data_integrity_error
  def categorize_error(%Ecto.StaleEntryError{}), do: :data_integrity_error

  def categorize_error(%Ecto.Query.CastError{}), do: :validation_error
  def categorize_error(%Ecto.CastError{}), do: :validation_error
  def categorize_error(%Ecto.InvalidChangesetError{}), do: :validation_error

  def categorize_error(%Jason.DecodeError{}), do: :parsing_error

  def categorize_error(%DBConnection.ConnectionError{}), do: :network_error

  # Oban.PerformError - unwrap and categorize the inner reason
  def categorize_error(%Oban.PerformError{reason: reason}), do: categorize_error(reason)

  # Generic exception handler - extract message and categorize
  def categorize_error(%{__exception__: true} = exception) do
    categorize_error(Exception.message(exception))
  end

  # ============================================================================
  # TUPLE PATTERN MATCHING
  # Handle common error tuple formats
  # ============================================================================

  # HTTP status code tuples
  def categorize_error({:http_error, 429, _}), do: :rate_limit_error
  def categorize_error({:http_error, 401, _}), do: :authentication_error
  def categorize_error({:http_error, 403, _}), do: :authentication_error
  def categorize_error({:http_error, status, _}) when status >= 500, do: :network_error
  def categorize_error({:http_error, status, _}) when status >= 400, do: :validation_error

  # Explicitly categorized tuples (preferred format)
  def categorize_error({:validation_error, _reason}), do: :validation_error
  def categorize_error({:parsing_error, _reason}), do: :parsing_error
  def categorize_error({:data_quality_error, _reason}), do: :data_quality_error
  def categorize_error({:data_integrity_error, _reason}), do: :data_integrity_error
  def categorize_error({:dependency_error, _reason}), do: :dependency_error
  def categorize_error({:network_error, _reason}), do: :network_error
  def categorize_error({:rate_limit_error, _reason}), do: :rate_limit_error
  def categorize_error({:authentication_error, _reason}), do: :authentication_error
  def categorize_error({:geocoding_error, _reason}), do: :geocoding_error
  def categorize_error({:venue_error, _reason}), do: :venue_error
  def categorize_error({:performer_error, _reason}), do: :performer_error
  def categorize_error({:tmdb_error, _reason}), do: :tmdb_error

  # Three-element tuples with category
  def categorize_error({:validation_error, _reason, _details}), do: :validation_error
  def categorize_error({:parsing_error, _reason, _details}), do: :parsing_error
  def categorize_error({:data_quality_error, _reason, _details}), do: :data_quality_error
  def categorize_error({:data_integrity_error, _reason, _details}), do: :data_integrity_error
  def categorize_error({:dependency_error, _reason, _details}), do: :dependency_error
  def categorize_error({:network_error, _reason, _details}), do: :network_error
  def categorize_error({:rate_limit_error, _reason, _details}), do: :rate_limit_error
  def categorize_error({:authentication_error, _reason, _details}), do: :authentication_error
  def categorize_error({:geocoding_error, _reason, _details}), do: :geocoding_error
  def categorize_error({:venue_error, _reason, _details}), do: :venue_error
  def categorize_error({:performer_error, _reason, _details}), do: :performer_error
  def categorize_error({:tmdb_error, _reason, _details}), do: :tmdb_error

  # ============================================================================
  # STRING PATTERN MATCHING
  # Handle string error messages with trigger word patterns
  # ============================================================================

  def categorize_error(error_reason) when is_binary(error_reason) do
    error_lower = String.downcase(error_reason)

    cond do
      # Rate limit errors (check before network to catch 429 specifically)
      rate_limit_error?(error_lower) ->
        :rate_limit_error

      # Authentication errors (check before network to catch 401/403 specifically)
      authentication_error?(error_lower) ->
        :authentication_error

      # Dependency errors - waiting for parent jobs
      dependency_error?(error_lower) ->
        :dependency_error

      # Data integrity errors - duplicates, constraints
      data_integrity_error?(error_lower) ->
        :data_integrity_error

      # Validation errors - missing required fields, invalid data
      validation_error?(error_lower) ->
        :validation_error

      # Parsing errors - HTML/JSON/XML parsing failures
      parsing_error?(error_lower) ->
        :parsing_error

      # Geocoding errors - address and coordinate issues
      geocoding_error?(error_lower) ->
        :geocoding_error

      # Venue errors - venue processing failures
      venue_error?(error_lower) ->
        :venue_error

      # Performer errors - artist/performer issues
      performer_error?(error_lower) ->
        :performer_error

      # TMDB errors - movie database lookup failures
      tmdb_error?(error_lower) ->
        :tmdb_error

      # Network errors - HTTP, API, connection issues
      network_error?(error_lower) ->
        :network_error

      # Data quality errors - unexpected values, business rules
      data_quality_error?(error_lower) ->
        :data_quality_error

      # Uncategorized - doesn't match any pattern (investigate!)
      true ->
        :uncategorized_error
    end
  end

  # ============================================================================
  # FALLBACK - Convert to string and try again
  # ============================================================================

  def categorize_error(other) do
    # For unknown types, inspect and try string matching
    # This catches atoms not explicitly listed above
    inspected = inspect(other)
    error_lower = String.downcase(inspected)

    cond do
      # Check for common atom patterns in the inspected string
      String.contains?(error_lower, "movie_not_ready") -> :dependency_error
      String.contains?(error_lower, "not_ready") -> :dependency_error
      String.contains?(error_lower, "missing_") -> :validation_error
      String.contains?(error_lower, "invalid_") -> :validation_error
      String.contains?(error_lower, "parse") -> :parsing_error
      String.contains?(error_lower, "timeout") -> :network_error
      String.contains?(error_lower, "connection") -> :network_error
      String.contains?(error_lower, "rate_limit") -> :rate_limit_error
      String.contains?(error_lower, "unauthorized") -> :authentication_error
      String.contains?(error_lower, "tmdb") -> :tmdb_error
      String.contains?(error_lower, "venue") -> :venue_error
      String.contains?(error_lower, "performer") -> :performer_error
      String.contains?(error_lower, "artist") -> :performer_error
      String.contains?(error_lower, "geocod") -> :geocoding_error
      String.contains?(error_lower, "duplicate") -> :data_integrity_error
      String.contains?(error_lower, "constraint") -> :data_integrity_error
      String.contains?(error_lower, "ecto.") -> :data_integrity_error
      String.contains?(error_lower, "rollback") -> :data_integrity_error
      true -> :uncategorized_error
    end
  end

  # ============================================================================
  # PATTERN MATCHING HELPER FUNCTIONS
  # ============================================================================

  defp rate_limit_error?(error_lower) do
    Enum.any?(
      [
        "rate limit",
        "rate_limit",
        "ratelimit",
        "429",
        "too many requests",
        "throttle",
        "throttled",
        "quota exceeded",
        "request limit"
      ],
      &String.contains?(error_lower, &1)
    )
  end

  defp authentication_error?(error_lower) do
    Enum.any?(
      [
        "401",
        "403",
        "unauthorized",
        "forbidden",
        "authentication failed",
        "auth failed",
        "invalid api key",
        "invalid token",
        "token expired",
        "access denied",
        "not authenticated",
        "credentials"
      ],
      &String.contains?(error_lower, &1)
    )
  end

  defp dependency_error?(error_lower) do
    Enum.any?(
      [
        "not ready",
        "not_ready",
        "dependency",
        "waiting for",
        "parent job",
        "hasn't completed",
        "not processed",
        "will retry",
        "pending"
      ],
      &String.contains?(error_lower, &1)
    )
  end

  defp data_integrity_error?(error_lower) do
    Enum.any?(
      [
        "multipleresultserror",
        "multiple results",
        "noresultserror",
        "no results error",
        "staleentryerror",
        "unique constraint",
        "uniqueness",
        "constraint violation",
        "duplicate key",
        "duplicate entry",
        "already exists",
        "integrity error",
        "foreign key",
        "referential integrity",
        # Transaction rollback
        ":rollback",
        "rollback"
      ],
      &String.contains?(error_lower, &1)
    )
  end

  defp validation_error?(error_lower) do
    Enum.any?(
      [
        "is required",
        "missing required",
        "required field",
        "cannot be blank",
        "must be present",
        "validation failed",
        "invalid format",
        "must be",
        "should be",
        "missing external_id",
        "missing title",
        "missing url",
        "invalid date",
        "invalid showtime",
        # Aggregate error patterns
        "all_events_failed",
        "missing_city",
        "missing_event_start_time"
      ],
      &String.contains?(error_lower, &1)
    )
  end

  defp parsing_error?(error_lower) do
    Enum.any?(
      [
        "parse error",
        "parse failed",
        "parsing failed",
        "json decode",
        "json parsing",
        "invalid json",
        "invalid xml",
        "html parsing",
        "malformed",
        "unexpected token",
        "syntax error",
        "decode error",
        "unable to parse",
        # Specific parsing failures from production
        "could not parse day",
        "could not parse time",
        "could not parse date"
      ],
      &String.contains?(error_lower, &1)
    )
  end

  defp geocoding_error?(error_lower) do
    Enum.any?(
      [
        "geocode",
        "geocoding",
        "address not found",
        "coordinates",
        "latitude",
        "longitude",
        "location not found",
        "invalid address",
        "could not resolve location"
      ],
      &String.contains?(error_lower, &1)
    )
  end

  defp venue_error?(error_lower) do
    Enum.any?(
      [
        "venue not found",
        "venue processing",
        "venue matching",
        "venue creation",
        "venue error",
        "ambiguous venue",
        "multiple venues"
      ],
      &String.contains?(error_lower, &1)
    )
  end

  defp performer_error?(error_lower) do
    Enum.any?(
      [
        "performer not found",
        "performer processing",
        "performer matching",
        "artist not found",
        "artist matching",
        "unknown artist",
        "spotify mismatch"
      ],
      &String.contains?(error_lower, &1)
    )
  end

  defp tmdb_error?(error_lower) do
    Enum.any?(
      [
        "tmdb",
        "movie not found",
        "movie not matched",
        "movie_not_matched",
        "no results",
        "no_results",
        "low confidence",
        "low_confidence",
        "needs review",
        "needs_review",
        "tmdb_low_confidence",
        "tmdb_no_results",
        "tmdb_needs_review",
        "no tmdb match"
      ],
      &String.contains?(error_lower, &1)
    )
  end

  defp network_error?(error_lower) do
    Enum.any?(
      [
        "http 5",
        "http 500",
        "http 502",
        "http 503",
        "http 504",
        "timeout",
        "timed out",
        "connection refused",
        "connection closed",
        "connection reset",
        "econnrefused",
        "econnreset",
        "nxdomain",
        "network error",
        "network unreachable",
        "server error",
        "service unavailable",
        "bad gateway",
        "gateway timeout",
        "dbconnection",
        "ssl",
        "handshake",
        # Redirect errors (often indicate API changes or moved endpoints)
        "http 301",
        "http 302",
        "http 303",
        "redirect"
      ],
      &String.contains?(error_lower, &1)
    )
  end

  defp data_quality_error?(error_lower) do
    Enum.any?(
      [
        "unexpected value",
        "business rule",
        "no schedule",
        "no recurring schedule",
        "special event",
        "encoding error",
        "invalid encoding",
        "utf-8",
        "data quality",
        "unexpected data",
        "inconsistent data",
        # Specific data quality issues from production
        "missing icon",
        "missing text for"
      ],
      &String.contains?(error_lower, &1)
    )
  end
end
