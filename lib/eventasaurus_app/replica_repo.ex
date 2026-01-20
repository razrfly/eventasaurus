defmodule EventasaurusApp.ReplicaRepo do
  @moduledoc """
  Read-only Ecto Repo for read-heavy queries.

  Provides a dedicated connection pool for read-heavy operations,
  reducing contention on the primary Repo connection pool.

  ## When to Use

  Use for read-heavy operations where eventual consistency is acceptable:
  - Admin dashboards and analytics
  - DiscoveryStatsCache background refresh
  - CityGalleryCache background refresh
  - Monitoring/metrics queries
  - Public event listings (lag-tolerant)
  - Background job reads

  ## When NOT to Use

  - Any write operations (will be rejected by Ecto)
  - Reads immediately after writes (use primary for read-your-own-writes)
  - User authentication checks
  - Real-time collaborative features
  - Transaction-critical operations

  ## Usage

  Do NOT use this repo directly. Instead, use the `replica/0` helper
  in `EventasaurusApp.Repo` which handles:
  - Test environment routing to primary
  - Kill switch support via USE_REPLICA env var
  - Consistent API across environments

      # Good: Use the helper
      Repo.replica().all(query)

      # Bad: Direct usage (won't work in tests)
      ReplicaRepo.all(query)

  ## Fallback Behavior

  Use `safe_all/2`, `safe_one/2`, etc. for automatic fallback to primary
  on replica connection failures. These wrappers emit telemetry events
  for monitoring.

  ## Configuration

  Configured in `runtime.exs` with:
  - Direct connection to port 5432 (not PgBouncer 6432)
  - Username with |replica suffix for replica routing
  - Smaller pool size (default 5) than primary
  """

  use Ecto.Repo,
    otp_app: :eventasaurus,
    adapter: Ecto.Adapters.Postgres,
    read_only: true

  require Logger

  @doc """
  Safe wrapper for `all/2` with automatic fallback to primary on failure.

  Emits telemetry events for monitoring replica vs primary usage.
  """
  @spec safe_all(Ecto.Queryable.t(), keyword()) :: [term()]
  def safe_all(query, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    try do
      result = __MODULE__.all(query, opts)
      emit_telemetry(:all, :replica, start_time, :success)
      result
    rescue
      e in [DBConnection.ConnectionError, Postgrex.Error] ->
        Logger.warning("ReplicaRepo.safe_all failed, falling back to primary: #{inspect(e)}")
        emit_telemetry(:all, :replica, start_time, :fallback)

        result = EventasaurusApp.Repo.all(query, opts)
        emit_telemetry(:all, :primary, start_time, :success)
        result
    end
  end

  @doc """
  Safe wrapper for `one/2` with automatic fallback to primary on failure.
  """
  @spec safe_one(Ecto.Queryable.t(), keyword()) :: term() | nil
  def safe_one(query, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    try do
      result = __MODULE__.one(query, opts)
      emit_telemetry(:one, :replica, start_time, :success)
      result
    rescue
      e in [DBConnection.ConnectionError, Postgrex.Error] ->
        Logger.warning("ReplicaRepo.safe_one failed, falling back to primary: #{inspect(e)}")
        emit_telemetry(:one, :replica, start_time, :fallback)

        result = EventasaurusApp.Repo.one(query, opts)
        emit_telemetry(:one, :primary, start_time, :success)
        result
    end
  end

  @doc """
  Safe wrapper for `aggregate/3` with automatic fallback to primary on failure.
  """
  @spec safe_aggregate(Ecto.Queryable.t(), atom(), atom(), keyword()) :: term()
  def safe_aggregate(query, aggregate, field, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    try do
      result = __MODULE__.aggregate(query, aggregate, field, opts)
      emit_telemetry(:aggregate, :replica, start_time, :success)
      result
    rescue
      e in [DBConnection.ConnectionError, Postgrex.Error] ->
        Logger.warning(
          "ReplicaRepo.safe_aggregate failed, falling back to primary: #{inspect(e)}"
        )

        emit_telemetry(:aggregate, :replica, start_time, :fallback)

        result = EventasaurusApp.Repo.aggregate(query, aggregate, field, opts)
        emit_telemetry(:aggregate, :primary, start_time, :success)
        result
    end
  end

  @doc """
  Safe wrapper for `exists?/2` with automatic fallback to primary on failure.
  """
  @spec safe_exists?(Ecto.Queryable.t(), keyword()) :: boolean()
  def safe_exists?(query, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    try do
      result = __MODULE__.exists?(query, opts)
      emit_telemetry(:exists, :replica, start_time, :success)
      result
    rescue
      e in [DBConnection.ConnectionError, Postgrex.Error] ->
        Logger.warning("ReplicaRepo.safe_exists? failed, falling back to primary: #{inspect(e)}")
        emit_telemetry(:exists, :replica, start_time, :fallback)

        result = EventasaurusApp.Repo.exists?(query, opts)
        emit_telemetry(:exists, :primary, start_time, :success)
        result
    end
  end

  # Emit telemetry for replica query monitoring
  defp emit_telemetry(operation, repo, start_time, status) do
    duration = System.monotonic_time(:millisecond) - start_time

    :telemetry.execute(
      [:eventasaurus, :replica, :query],
      %{duration: duration},
      %{
        operation: operation,
        repo: repo,
        status: status
      }
    )
  end
end
