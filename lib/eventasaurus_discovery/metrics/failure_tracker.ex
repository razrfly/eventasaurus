defmodule EventasaurusDiscovery.Metrics.FailureTracker do
  @moduledoc """
  Tracks and aggregates event processing failures.

  Upserts failure records, grouping identical errors (same source + category + message)
  and maintaining sample external_ids for debugging. Provides queries for failure
  analysis and breakdown.

  ## Usage

      # Track a failure (upsert)
      FailureTracker.track_failure(source_id, :validation_error, "Title is required", "evt_123")

      # Get all failures for a source
      FailureTracker.get_failures_by_source(source_id)

      # Get failure breakdown by category
      FailureTracker.get_failure_summary(source_id)
      #=> %{
      #     "validation_error" => 42,
      #     "geocoding_error" => 15,
      #     "network_error" => 3
      #   }

      # Get top failures across all sources
      FailureTracker.get_top_failures(limit: 10)

  ## Aggregation Strategy

  Failures are grouped by:
  - source_id
  - error_category
  - error_message

  For each unique combination, we track:
  - occurrence_count (incremented on each occurrence)
  - sample_external_ids (up to 5 samples for debugging)
  - first_seen_at (when first observed)
  - last_seen_at (when most recently observed)

  ## Performance

  - Upserts use find-or-create pattern (2 queries max)
  - Indexes on [source_id, error_category, error_message] for fast lookups
  - Sample IDs limited to 5 to prevent unbounded growth
  - Old records pruned by FailurePruningWorker (90-day retention)
  """

  require Logger

  import Ecto.Query

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Metrics.EventFailure

  @max_sample_ids 5

  @doc """
  Records a failure, upserting if the same error already exists.

  Groups by source_id + error_category + error_message.
  Maintains up to 5 sample external_ids.

  ## Parameters

  - `source_id` - The source ID (integer)
  - `error_category` - The error category atom (e.g., :validation_error)
  - `error_message` - The error message string (will be truncated to 500 chars)
  - `external_id` - The external ID of the failed event

  ## Examples

      iex> track_failure(1, :validation_error, "Title required", "evt_123")
      {:ok, %EventFailure{occurrence_count: 1, ...}}

      iex> track_failure(1, :validation_error, "Title required", "evt_456")
      {:ok, %EventFailure{occurrence_count: 2, ...}}

  ## Returns

  - `{:ok, event_failure}` - Successfully tracked failure
  - `{:error, changeset}` - Validation or database error
  """
  def track_failure(source_id, error_category, error_message, external_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    error_category_str = to_string(error_category)
    error_message_truncated = String.slice(error_message, 0, 500)
    external_id_str = to_string(external_id)

    # Use atomic upsert with on_conflict to avoid race conditions
    # instead of find-then-insert pattern
    %EventFailure{}
    |> EventFailure.changeset(%{
      source_id: source_id,
      error_category: error_category_str,
      error_message: error_message_truncated,
      sample_external_ids: [external_id_str],
      occurrence_count: 1,
      first_seen_at: now,
      last_seen_at: now
    })
    |> Repo.insert(
      on_conflict: [
        set: [
          sample_external_ids:
            fragment(
              "CASE WHEN ? = ANY(sample_external_ids) THEN sample_external_ids ELSE array_append(sample_external_ids[greatest(0, array_length(sample_external_ids, 1) - ? + 1):], ?) END",
              ^external_id_str,
              ^@max_sample_ids,
              ^external_id_str
            ),
          occurrence_count: fragment("event_failures.occurrence_count + 1"),
          last_seen_at: now
        ]
      ],
      conflict_target: [:source_id, :error_category, :error_message]
    )
  rescue
    error ->
      Logger.error("""
      Failed to track failure:
        Source ID: #{source_id}
        Category: #{error_category}
        Message: #{error_message}
        Error: #{inspect(error)}
      """)

      {:error, error}
  end

  @doc """
  Get all failures for a source, ordered by occurrence count.

  ## Options

  - `:limit` - Maximum number of failures to return (default: 100)
  - `:order_by` - Order by field (default: :occurrence_count)
  - `:order` - Sort order :desc or :asc (default: :desc)

  ## Examples

      iex> get_failures_by_source(1)
      [%EventFailure{occurrence_count: 42, ...}, ...]

      iex> get_failures_by_source(1, limit: 10, order_by: :last_seen_at)
      [%EventFailure{last_seen_at: ~U[2025-01-19 ...], ...}, ...]
  """
  def get_failures_by_source(source_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    order_by_field = Keyword.get(opts, :order_by, :occurrence_count)
    order = Keyword.get(opts, :order, :desc)

    from(f in EventFailure,
      where: f.source_id == ^source_id,
      order_by: [{^order, field(f, ^order_by_field)}],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Get failure breakdown by category for a source.

  Returns a map of error_category => occurrence_count.

  ## Examples

      iex> get_failure_summary(1)
      %{
        "validation_error" => 42,
        "geocoding_error" => 15,
        "network_error" => 3
      }
  """
  def get_failure_summary(source_id) do
    from(f in EventFailure,
      where: f.source_id == ^source_id,
      group_by: f.error_category,
      select: {f.error_category, sum(f.occurrence_count)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Get top failures across all sources.

  ## Options

  - `:limit` - Number of top failures to return (default: 10)

  ## Examples

      iex> get_top_failures(limit: 5)
      [
        %EventFailure{
          source_id: 1,
          error_category: "validation_error",
          occurrence_count: 150,
          ...
        },
        ...
      ]
  """
  def get_top_failures(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    from(f in EventFailure,
      order_by: [desc: f.occurrence_count, desc: f.last_seen_at],
      limit: ^limit,
      preload: [:source]
    )
    |> Repo.all()
  end

  @doc """
  Get failures by error category across all sources.

  ## Examples

      iex> get_failures_by_category(:validation_error, limit: 5)
      [%EventFailure{...}, ...]
  """
  def get_failures_by_category(category, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    category_str = to_string(category)

    from(f in EventFailure,
      where: f.error_category == ^category_str,
      order_by: [desc: f.occurrence_count],
      limit: ^limit,
      preload: [:source]
    )
    |> Repo.all()
  end

  @doc """
  Get total failure count for a source.

  ## Examples

      iex> get_total_failure_count(1)
      157
  """
  def get_total_failure_count(source_id) do
    result =
      from(f in EventFailure,
        where: f.source_id == ^source_id,
        select: sum(f.occurrence_count)
      )
      |> Repo.one()

    result || 0
  end

  @doc """
  Delete failures older than the specified date.

  Used by FailurePruningWorker for retention management.

  ## Examples

      iex> cutoff = DateTime.add(DateTime.utc_now(), -90, :day)
      iex> delete_old_failures(cutoff)
      {42, nil}  # Deleted 42 records
  """
  def delete_old_failures(cutoff_date) do
    from(f in EventFailure,
      where: f.last_seen_at < ^cutoff_date
    )
    |> Repo.delete_all()
  end

  # Private helper functions

  defp update_sample_ids(existing_samples, new_id) do
    # Add new_id if not already present, keep max 5 samples (most recent)
    if new_id in existing_samples do
      existing_samples
    else
      (existing_samples ++ [new_id])
      |> Enum.take(-@max_sample_ids)
    end
  end
end
