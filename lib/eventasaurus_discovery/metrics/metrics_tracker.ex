defmodule EventasaurusDiscovery.Metrics.MetricsTracker do
  @moduledoc """
  Tracks event processing metrics in Oban job metadata.

  Updates the current job's meta field with success/failure information,
  categorized error details, and collision/deduplication metrics.
  This provides real-time visibility into event processing outcomes
  without requiring additional database tables.

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

  ## Collision Tracking

  For deduplication handlers that return collision data (3-tuple):

      case DedupHandler.check_duplicate(event_data, source) do
        {:duplicate, existing_event, collision_data} ->
          # Record collision when duplicate is detected
          # collision_data already contains: type, matched_event_id, confidence, etc.
          MetricsTracker.record_collision(job, external_id, collision_data)
          {:ok, :skipped}

        {:unique, event_data} ->
          process_event(event_data)
      end

  For handlers that return only the event (2-tuple), build collision data:

      case DedupHandler.check_duplicate(event_data, source) do
        {:duplicate, existing_event} ->
          collision_data = BaseDedupHandler.build_same_source_collision(existing_event, "deferred")
          MetricsTracker.record_collision(job, external_id, collision_data)
          {:ok, :skipped}

        {:unique, event_data} ->
          process_event(event_data)
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

  Collision case (success with dedup):

      %{
        "status" => "success",
        "external_id" => "kupbilecik_12345",
        "processed_at" => "2025-01-07T12:00:00Z",
        "collision_data" => %{
          "type" => "cross_source",
          "matched_event_id" => 12345,
          "matched_source" => "bandsintown",
          "confidence" => 0.85,
          "match_factors" => ["performer", "venue", "date", "gps"],
          "resolution" => "deferred"
        }
      }
  """

  require Logger

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Metrics.ErrorCategories

  # Note: record_success/2 is handled by record_success/3 with opts \\ %{} default
  # See record_success/3 below for the main implementation

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

  @doc """
  Records a collision/deduplication event in job metadata.

  This should be called when a duplicate event is detected, whether from
  the same source (external_id match) or cross-source (fuzzy match).

  ## Parameters

  - `job` - The Oban.Job struct for the current job
  - `external_id` - The external identifier for the event being processed
  - `collision_data` - Map containing collision details:
    - `:type` - `:same_source` or `:cross_source` (required)
    - `:matched_event_id` - ID of the existing event (required)
    - `:matched_source` - Name/slug of the source that owns the matched event (optional)
    - `:confidence` - Match confidence score 0.0-1.0 (optional, defaults to 1.0 for same_source)
    - `:match_factors` - List of factors used for matching (optional)
    - `:resolution` - How the collision was resolved: "deferred", "created", "updated" (optional)

  ## Examples

      # Same-source deduplication (external_id match)
      record_collision(job, "kupbilecik_12345", %{
        type: :same_source,
        matched_event_id: 123,
        resolution: "deferred"
      })

      # Cross-source deduplication (fuzzy match)
      record_collision(job, "kupbilecik_12345", %{
        type: :cross_source,
        matched_event_id: 456,
        matched_source: "bandsintown",
        confidence: 0.85,
        match_factors: ["performer", "venue", "date", "gps"],
        resolution: "deferred"
      })

  ## Returns

  - `{:ok, updated_job}` - Successfully updated job metadata
  - `{:error, reason}` - Failed to update metadata
  """
  def record_collision(%Oban.Job{} = job, external_id, collision_data)
      when is_map(collision_data) do
    # Validate required fields
    type = collision_data[:type] || collision_data["type"]
    matched_event_id = collision_data[:matched_event_id] || collision_data["matched_event_id"]

    unless type && matched_event_id do
      Logger.warning("record_collision: missing required fields (type, matched_event_id)")
      {:error, :missing_required_fields}
    else
      normalized_type = normalize_collision_type(type)

      unless normalized_type in ["same_source", "cross_source"] do
        Logger.warning("record_collision: invalid type #{inspect(type)}")
        {:error, :invalid_collision_type}
      else
        # Build collision_data structure for storage
        collision_record = %{
          "type" => normalized_type,
          "matched_event_id" => matched_event_id,
          "matched_source" => collision_data[:matched_source] || collision_data["matched_source"],
          "confidence" =>
            collision_data[:confidence] || collision_data["confidence"] ||
              default_confidence(normalized_type),
          "match_factors" =>
            collision_data[:match_factors] || collision_data["match_factors"] || [],
          "resolution" =>
            collision_data[:resolution] || collision_data["resolution"] || "deferred"
        }

        # Remove nil values for cleaner storage
        collision_record =
          collision_record
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new()

        metadata = %{
          "status" => "success",
          "external_id" => to_string(external_id),
          "processed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "collision_data" => collision_record
        }

        update_job_metadata(job, metadata)
      end
    end
  end

  @doc """
  Records successful event processing in job metadata.

  Updates the job's meta field with success status, external_id,
  and processing timestamp. Optionally includes collision context
  when an event was created despite potential matches.

  ## Parameters

  - `job` - The Oban.Job struct for the current job
  - `external_id` - The external identifier for the processed event
  - `opts` - Optional map with additional data:
    - `:collision_data` - Collision context if event was created despite matches

  ## Returns

  - `{:ok, updated_job}` - Successfully updated job metadata
  - `{:error, reason}` - Failed to update metadata (logged as error)

  ## Examples

      # Simple success (2-arity call)
      iex> record_success(job, "bandsintown_12345")
      {:ok, %Oban.Job{meta: %{"status" => "success", ...}}}

      # Success with collision context (created despite lower-priority match)
      iex> record_success(job, "kupbilecik_12345", %{
      ...>   collision_data: %{
      ...>     type: :cross_source,
      ...>     matched_event_id: 456,
      ...>     matched_source: "week_pl",
      ...>     confidence: 0.75,
      ...>     resolution: "created"
      ...>   }
      ...> })
      {:ok, %Oban.Job{meta: %{"status" => "success", "collision_data" => %{...}, ...}}}
  """
  def record_success(job, external_id, opts \\ %{})

  def record_success(%Oban.Job{} = job, external_id, opts) when is_map(opts) do
    base_metadata = %{
      "status" => "success",
      "external_id" => to_string(external_id),
      "processed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Add collision_data if provided
    metadata =
      case opts[:collision_data] || opts["collision_data"] do
        nil ->
          base_metadata

        collision_data when is_map(collision_data) ->
          collision_record = build_collision_record(collision_data)
          Map.put(base_metadata, "collision_data", collision_record)

        _invalid ->
          # Ignore invalid collision_data (non-map)
          Logger.warning("record_success: collision_data must be a map, ignoring invalid value")
          base_metadata
      end

    # Merge any additional metadata from opts (excluding collision_data)
    additional =
      opts
      |> Map.drop([:collision_data, "collision_data"])
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Map.new()

    metadata = Map.merge(metadata, additional)

    update_job_metadata(job, metadata)
  end

  @doc """
  Gets collision data from job metadata.

  ## Examples

      iex> get_collision_data(job_with_collision)
      %{
        "type" => "cross_source",
        "matched_event_id" => 456,
        "confidence" => 0.85
      }

      iex> get_collision_data(job_without_collision)
      nil
  """
  def get_collision_data(%Oban.Job{meta: nil}), do: nil
  def get_collision_data(%Oban.Job{meta: meta}), do: Map.get(meta, "collision_data")

  @doc """
  Checks if job has collision data recorded.

  ## Examples

      iex> has_collision?(job_with_collision)
      true

      iex> has_collision?(job_without_collision)
      false
  """
  def has_collision?(%Oban.Job{} = job) do
    get_collision_data(job) != nil
  end

  @doc """
  Gets the collision type from job metadata.

  ## Examples

      iex> get_collision_type(job)
      "same_source"
  """
  def get_collision_type(%Oban.Job{} = job) do
    case get_collision_data(job) do
      nil -> nil
      data -> data["type"]
    end
  end

  # Private functions

  defp normalize_collision_type(:same_source), do: "same_source"
  defp normalize_collision_type(:cross_source), do: "cross_source"
  defp normalize_collision_type("same_source"), do: "same_source"
  defp normalize_collision_type("cross_source"), do: "cross_source"
  defp normalize_collision_type(other), do: to_string(other)

  defp default_confidence(:same_source), do: 1.0
  defp default_confidence("same_source"), do: 1.0
  defp default_confidence(_), do: nil

  defp build_collision_record(collision_data) do
    type = collision_data[:type] || collision_data["type"]
    matched_event_id = collision_data[:matched_event_id] || collision_data["matched_event_id"]

    # Validate required fields - return empty map if missing
    unless type && matched_event_id do
      Logger.warning("build_collision_record: missing required fields (type, matched_event_id)")
      %{}
    else
      %{
        "type" => normalize_collision_type(type),
        "matched_event_id" => matched_event_id,
        "matched_source" => collision_data[:matched_source] || collision_data["matched_source"],
        "confidence" =>
          collision_data[:confidence] || collision_data["confidence"] || default_confidence(type),
        "match_factors" =>
          collision_data[:match_factors] || collision_data["match_factors"] || [],
        "resolution" => collision_data[:resolution] || collision_data["resolution"] || "created"
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    end
  end

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
