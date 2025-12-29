defmodule EventasaurusApp.Monitoring.ObanTelemetry do
  @moduledoc """
  Telemetry event handlers for Oban job monitoring and error tracking.

  Captures job lifecycle events (start, stop, exception) to provide visibility
  into background job execution and failures. Integrates with Sentry for
  alerting on critical failures like rate limiting.

  ## Events Monitored

  - `[:oban, :job, :start]` - Job begins execution
  - `[:oban, :job, :stop]` - Job completes (success or failure)
  - `[:oban, :job, :exception]` - Job raises an exception

  ## Usage

  This module is automatically attached during application startup via
  `EventasaurusApp.Application.start/2`.

  ## Metrics Tracked

  - Job duration and queue time
  - Success/failure rates by worker
  - Rate limit errors (critical alerts)
  - Retry attempts and backoff delays
  - **Job execution summaries** - Historical tracking beyond Oban retention period

  ## Job Execution Summaries

  All job completions (success/failure) are recorded in the `job_execution_summaries`
  table for long-term analysis and monitoring. This provides:

  - Historical tracking beyond Oban's 7-day default retention
  - Custom metrics per scraper (via job.meta field)
  - Dashboard analytics and trend analysis
  - Silent failure detection (jobs succeeding but no entities created)
  """

  require Logger

  alias EventasaurusDiscovery.Metrics.ErrorCategories

  @doc """
  Attaches telemetry handlers for Oban events.

  This should be called once during application startup.
  """
  def attach do
    events = [
      [:oban, :job, :start],
      [:oban, :job, :stop],
      [:oban, :job, :exception]
    ]

    :telemetry.attach_many(
      "oban-error-tracking",
      events,
      &__MODULE__.handle_event/4,
      nil
    )

    Logger.info("📊 Oban telemetry handlers attached")
  end

  @doc """
  Handles telemetry events from Oban.
  """
  def handle_event([:oban, :job, :start], _measurements, %{job: job} = _metadata, _config) do
    Logger.debug("🔄 Job started: #{job.worker} [#{job.id}] (attempt #{job.attempt})")
  end

  def handle_event([:oban, :job, :stop], measurements, %{job: job} = metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    queue_time_ms = System.convert_time_unit(measurements.queue_time, :native, :millisecond)

    # Record job execution summary for historical tracking
    # Pass full metadata to capture return value if available
    record_job_summary(job, metadata.state, duration_ms, nil, metadata)

    case metadata.state do
      :success ->
        Logger.info("""
        ✅ Job completed: #{job.worker} [#{job.id}]
        Duration: #{duration_ms}ms
        Queue time: #{queue_time_ms}ms
        Attempt: #{job.attempt}/#{job.max_attempts}
        """)

      :failure ->
        Logger.warning("""
        ⚠️  Job failed (will retry): #{job.worker} [#{job.id}]
        Duration: #{duration_ms}ms
        Attempt: #{job.attempt}/#{job.max_attempts}
        State: #{metadata.state}
        """)

      :discard ->
        Logger.error("""
        ❌ Job discarded (max attempts reached): #{job.worker} [#{job.id}]
        Duration: #{duration_ms}ms
        Attempts: #{job.attempt}/#{job.max_attempts}
        """)

        # Report discarded jobs to Sentry
        report_to_sentry(:job_discarded, job, %{
          duration_ms: duration_ms,
          queue_time_ms: queue_time_ms
        })

      other ->
        Logger.warning("""
        Job stopped with state: #{other}
        Worker: #{job.worker} [#{job.id}]
        Duration: #{duration_ms}ms
        """)
    end
  end

  def handle_event([:oban, :job, :exception], measurements, metadata, _config) do
    %{job: job, kind: kind, reason: reason, stacktrace: stacktrace} = metadata
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    # Check if this is a cancellation (intentional skip) or a real exception
    cancelled? = cancellation_reason?(reason)

    # Determine job state based on exception type
    state =
      cond do
        cancelled? -> :cancelled
        job.attempt >= job.max_attempts -> :discard
        true -> :failure
      end

    # Record job exception in summary
    error_message = Exception.format(kind, reason, stacktrace)
    record_job_summary(job, state, duration_ms, error_message, metadata)

    # Handle cancellations differently from errors
    if cancelled? do
      # Cancellations are expected behavior (e.g., movie not matched in TMDB)
      # Log as info, not error, and don't report to Sentry
      cancel_reason = extract_cancel_reason(reason)

      Logger.info("""
      ⏭️  Job cancelled (expected): #{job.worker} [#{job.id}]
      Reason: #{cancel_reason}
      Duration: #{duration_ms}ms
      """)
    else
      # This is a real error - handle normally

      # Check if this is a rate limit error
      rate_limited? = rate_limit_error?(reason)

      error_type = if rate_limited?, do: "RATE LIMIT", else: "ERROR"
      emoji = if rate_limited?, do: "⚠️", else: "❌"

      Logger.error("""
      #{emoji} Job #{error_type}: #{job.worker} [#{job.id}]
      Attempt: #{job.attempt}/#{job.max_attempts}
      Duration: #{duration_ms}ms
      Error: #{Exception.format(kind, reason, stacktrace)}
      """)

      # Always report rate limit errors to monitoring
      if rate_limited? do
        Logger.warning("🚨 RATE LIMIT detected in #{job.worker} - alerting monitoring system")

        report_to_sentry(:rate_limit_error, job, %{
          duration_ms: duration_ms,
          attempt: job.attempt,
          max_attempts: job.max_attempts,
          error: inspect(reason)
        })
      end

      # Report other critical errors based on attempt count
      # Only alert after multiple failures to avoid noise
      if job.attempt >= 3 and not rate_limited? do
        report_to_sentry(:job_exception, job, %{
          kind: kind,
          reason: reason,
          stacktrace: stacktrace,
          duration_ms: duration_ms,
          attempt: job.attempt
        })
      end
    end
  end

  # Convert map keys to strings for consistent JSONB storage
  # Handles plain maps, but safely handles structs (like Ecto schemas)
  defp stringify_keys(%{__struct__: struct_name} = struct) do
    # For structs, just store the type and ID if available
    # Don't try to enumerate the entire struct
    base = %{"_struct" => inspect(struct_name)}

    if Map.has_key?(struct, :id) do
      Map.put(base, "id", struct.id)
    else
      base
    end
  end

  defp stringify_keys(map) when is_map(map) do
    map
    |> Enum.into(%{}, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      {key, v}
    end)
  end

  # Record job execution summary for historical tracking
  defp record_job_summary(job, state, duration_ms, error_message, metadata) do
    # Convert Oban state atoms to string states for database
    db_state =
      case state do
        :success -> "completed"
        :failure -> "retryable"
        :discard -> "discarded"
        :cancelled -> "cancelled"
        other -> to_string(other)
      end

    # Extract cancellation reason if state is cancelled
    # For :stop events, reason is in metadata.result
    # For :exception events, reason is in metadata.reason
    cancel_reason =
      if state == :cancelled do
        cond do
          Map.has_key?(metadata, :result) -> extract_cancel_reason(metadata.result)
          Map.has_key?(metadata, :reason) -> extract_cancel_reason(metadata.reason)
          true -> nil
        end
      else
        nil
      end

    # Merge results from multiple sources:
    # 1. job.meta - metadata set when job was created (e.g., parent_job_id)
    # 2. metadata.result - return value from perform/1 (e.g., movies_scheduled, showtimes_count)
    # 3. cancel_reason - extracted from exception reason if job was cancelled
    # Normalize all keys to strings for consistent JSONB storage
    job_meta = job |> Map.get(:meta, %{}) |> stringify_keys()
    return_value = Map.get(metadata, :result, %{})

    # Merge both sources, with return_value taking precedence for overlapping keys
    # This gives us parent_job_id from meta + execution results from return value
    results =
      case return_value do
        # If return value is a struct (e.g., {:ok, %PublicEvent{}}), just store reference
        {:ok, %{__struct__: struct_name, id: id}} ->
          Map.merge(job_meta, %{"result_type" => inspect(struct_name), "result_id" => id})

        {:ok, %{__struct__: struct_name}} ->
          Map.merge(job_meta, %{"result_type" => inspect(struct_name)})

        # If return value is a plain map (e.g., {:ok, %{movies_scheduled: 10}}), merge it
        {:ok, result_map} when is_map(result_map) ->
          Map.merge(job_meta, stringify_keys(result_map))

        # If return value is just :ok, use only job.meta
        :ok ->
          job_meta

        # If return value is an error tuple, store the error reason but keep job.meta
        {:error, reason} ->
          Map.put(job_meta, "error_reason", inspect(reason))

        # If return value is a struct, just store reference
        %{__struct__: struct_name, id: id} ->
          Map.merge(job_meta, %{"result_type" => inspect(struct_name), "result_id" => id})

        %{__struct__: struct_name} ->
          Map.merge(job_meta, %{"result_type" => inspect(struct_name)})

        # If return value is a plain map, merge it
        result_map when is_map(result_map) ->
          Map.merge(job_meta, stringify_keys(result_map))

        # For any other return value, just use job.meta
        _other ->
          job_meta
      end

    # Add cancellation reason to results if present
    results =
      if cancel_reason do
        Map.put(results, "cancel_reason", cancel_reason)
      else
        results
      end

    # Categorize errors for exceptions that bypass MetricsTracker.record_failure()
    # This ensures ALL failures get categorized, not just those that explicitly call record_failure
    # Only add if error_category is not already set (from job.meta via MetricsTracker)
    results =
      if state in [:failure, :discard] and not Map.has_key?(results, "error_category") do
        # Extract the exception reason from metadata
        exception_reason = Map.get(metadata, :reason)

        category =
          if exception_reason do
            ErrorCategories.categorize_error(exception_reason) |> to_string()
          else
            "uncategorized_error"
          end

        Map.put(results, "error_category", category)
      else
        results
      end

    # Build summary attributes
    attrs = %{
      job_id: job.id,
      worker: job.worker,
      queue: job.queue,
      state: db_state,
      args: job.args,
      results: results,
      error: error_message,
      attempted_at: job.attempted_at,
      completed_at: DateTime.utc_now(),
      duration_ms: duration_ms
    }

    # Record asynchronously to avoid blocking job completion
    Task.start(fn ->
      case EventasaurusDiscovery.JobExecutionSummaries.JobExecutionSummary.record_execution(attrs) do
        {:ok, _summary} ->
          Logger.debug("📊 Recorded job execution summary for #{job.worker} [#{job.id}]")

        {:error, changeset} ->
          Logger.error("❌ Failed to record job execution summary: #{inspect(changeset.errors)}")
      end
    end)
  end

  # Detect if an error is related to rate limiting
  defp rate_limit_error?(reason) when is_binary(reason) do
    reason
    |> String.downcase()
    |> String.contains?("rate limit")
  end

  defp rate_limit_error?(:rate_limited), do: true

  defp rate_limit_error?(%{reason: :rate_limited}), do: true

  defp rate_limit_error?(%{reason: reason}) when is_binary(reason) do
    reason
    |> String.downcase()
    |> String.contains?("rate limit")
  end

  defp rate_limit_error?(_), do: false

  # Detect if an exception is actually a job cancellation
  # Jobs return {:cancel, reason} to skip execution intentionally
  defp cancellation_reason?({:cancel, _reason}), do: true

  defp cancellation_reason?(%Oban.PerformError{reason: {:cancel, _reason}}), do: true

  defp cancellation_reason?(_), do: false

  # Extract the cancellation reason for logging
  defp extract_cancel_reason({:cancel, reason}) when is_atom(reason) do
    reason
    |> Atom.to_string()
    |> String.replace("_", " ")
  end

  defp extract_cancel_reason({:cancel, reason}) when is_binary(reason), do: reason

  defp extract_cancel_reason(%Oban.PerformError{reason: {:cancel, reason}}) do
    extract_cancel_reason({:cancel, reason})
  end

  defp extract_cancel_reason(_), do: "unknown"

  # Report errors to Sentry (if configured)
  defp report_to_sentry(error_type, job, metadata) do
    if Code.ensure_loaded?(Sentry) do
      # Build error context
      context =
        %{
          worker: job.worker,
          job_id: job.id,
          queue: job.queue,
          attempt: job.attempt,
          max_attempts: job.max_attempts,
          args: job.args
        }
        |> Map.merge(metadata)

      # Create error title
      title =
        case error_type do
          :rate_limit_error -> "Rate Limit Error: #{job.worker}"
          :job_discarded -> "Job Discarded: #{job.worker}"
          :job_exception -> "Job Exception: #{job.worker}"
        end

      # Create error tags for better filtering in Sentry
      tags = %{
        error_type: to_string(error_type),
        worker: job.worker,
        queue: job.queue,
        oban_job_id: job.id
      }

      # Report to Sentry with context
      Sentry.capture_message(title,
        level: if(error_type == :rate_limit_error, do: :warning, else: :error),
        extra: context,
        tags: tags
      )

      Logger.debug("📡 Reported #{error_type} to Sentry: #{title}")
    else
      Logger.debug("Sentry not available - #{error_type} not reported")
    end
  end
end
