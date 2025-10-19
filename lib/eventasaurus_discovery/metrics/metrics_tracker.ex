defmodule EventasaurusDiscovery.Metrics.MetricsTracker do
  @moduledoc """
  Tracks event processing metrics in Oban job metadata.

  Updates the current job's meta field with success/failure information
  and categorized error details. This provides real-time visibility into
  event processing outcomes without requiring additional database tables.

  ## Usage

  In your Oban worker's `perform/1` function:

      def perform(%Oban.Job{args: args} = job) do
        external_id = args["external_id"]

        case process_event(args) do
          {:ok, event} ->
            MetricsTracker.record_success(job, external_id)
            {:ok, event}

          {:error, reason} = error ->
            MetricsTracker.record_failure(job, reason, external_id)
            error
        end
      end

  ## Metadata Structure

  Success case:

      %{
        "status" => "success",
        "external_id" => "bandsintown_12345",
        "processed_at" => "2025-01-07T12:00:00Z"
      }

  Failure case:

      %{
        "status" => "failed",
        "error_category" => "validation_error",
        "error_message" => "Event title is required",
        "external_id" => "bandsintown_12345",
        "processed_at" => "2025-01-07T12:00:00Z"
      }
  """

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Metrics.ErrorCategories

  @doc """
  Records successful event processing in job metadata.

  Updates the job's meta field with success status, external_id,
  and processing timestamp.

  ## Examples

      iex> record_success(job, "bandsintown_12345")
      {:ok, %Oban.Job{meta: %{"status" => "success", ...}}}

  ## Parameters

  - `job` - The Oban.Job struct for the current job
  - `external_id` - The external identifier for the processed event

  ## Returns

  - `{:ok, updated_job}` - Successfully updated job metadata
  - `{:error, reason}` - Failed to update metadata (logged as error)
  """
  def record_success(%Oban.Job{} = job, external_id) do
    metadata = %{
      "status" => "success",
      "external_id" => to_string(external_id),
      "processed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    update_job_metadata(job, metadata)
  end

  @doc """
  Records failed event processing in job metadata with categorized error.

  Updates the job's meta field with failure status, error category,
  error message, external_id, and processing timestamp.

  ## Examples

      iex> record_failure(job, "Event title is required", "evt_123")
      {:ok, %Oban.Job{meta: %{"status" => "failed", ...}}}

      iex> record_failure(job, %ArgumentError{message: "bad value"}, "evt_456")
      {:ok, %Oban.Job{meta: %{"status" => "failed", ...}}}

  ## Parameters

  - `job` - The Oban.Job struct for the current job
  - `error_reason` - The error reason (string, exception, or any term)
  - `external_id` - The external identifier for the failed event

  ## Returns

  - `{:ok, updated_job}` - Successfully updated job metadata
  - `{:error, reason}` - Failed to update metadata (logged as error)
  """
  def record_failure(%Oban.Job{} = job, error_reason, external_id) do
    error_category = ErrorCategories.categorize_error(error_reason)
    error_message = format_error_message(error_reason)

    metadata = %{
      "status" => "failed",
      "error_category" => to_string(error_category),
      "error_message" => error_message,
      "external_id" => to_string(external_id),
      "processed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    update_job_metadata(job, metadata)
  end

  @doc """
  Gets the current status from job metadata.

  ## Examples

      iex> get_status(job)
      "success"

      iex> get_status(job_without_meta)
      nil
  """
  def get_status(%Oban.Job{meta: nil}), do: nil
  def get_status(%Oban.Job{meta: meta}), do: Map.get(meta, "status")

  @doc """
  Gets the error category from job metadata (if failed).

  ## Examples

      iex> get_error_category(failed_job)
      "validation_error"

      iex> get_error_category(success_job)
      nil
  """
  def get_error_category(%Oban.Job{meta: nil}), do: nil
  def get_error_category(%Oban.Job{meta: meta}), do: Map.get(meta, "error_category")

  @doc """
  Gets the external_id from job metadata.

  ## Examples

      iex> get_external_id(job)
      "bandsintown_12345"
  """
  def get_external_id(%Oban.Job{meta: nil}), do: nil
  def get_external_id(%Oban.Job{meta: meta}), do: Map.get(meta, "external_id")

  # Private functions

  defp update_job_metadata(job, new_metadata) do
    # Merge new metadata with existing metadata (preserving other fields)
    updated_meta = Map.merge(job.meta || %{}, new_metadata)

    # CRITICAL: Directly update the job in the database using Ecto
    # Oban does NOT automatically persist struct changes from perform/1
    import Ecto.Query

    query =
      from(j in Oban.Job,
        where: j.id == ^job.id,
        update: [set: [meta: ^updated_meta]]
      )

    case Repo.update_all(query, []) do
      {1, _} ->
        # Successfully updated
        Logger.debug("""
        Updated job metadata in database:
          Job ID: #{job.id}
          Worker: #{job.worker}
          Status: #{Map.get(new_metadata, "status")}
          External ID: #{Map.get(new_metadata, "external_id")}
        """)

        # Return updated job struct (even though we already persisted)
        updated_job = %{job | meta: updated_meta}
        {:ok, updated_job}

      {0, _} ->
        Logger.error("""
        Job not found for metadata update:
          Job ID: #{job.id}
        """)

        {:error, :job_not_found}

      error ->
        Logger.error("""
        Failed to update job metadata:
          Job ID: #{job.id}
          Error: #{inspect(error)}
        """)

        {:error, error}
    end
  rescue
    error ->
      Logger.error("""
      Exception updating job metadata:
        Job ID: #{job.id}
        Error: #{inspect(error)}
      """)

      {:error, error}
  end

  defp format_error_message(reason) when is_binary(reason) do
    # Truncate long error messages to 500 characters
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
