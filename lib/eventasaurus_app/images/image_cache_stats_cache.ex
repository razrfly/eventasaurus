defmodule EventasaurusApp.Images.ImageCacheStatsCache do
  @moduledoc """
  GenServer-based cache for image cache stats dashboard.

  Reads pre-computed stats from the database (image_cache_stats_snapshots table).
  Stats are computed by ComputeImageCacheStatsJob running daily via Oban.

  This architecture ensures instant dashboard loading with zero database queries.
  Stats are held in memory and updated when new snapshots are computed.

  ## Usage

      # Get cached stats (instant - reads from memory)
      ImageCacheStatsCache.get_stats()

      # Force trigger a new computation (queues Oban job)
      ImageCacheStatsCache.refresh()

      # Get freshness information
      ImageCacheStatsCache.last_refreshed_at()

  ## Architecture

  - Stats are computed by ComputeImageCacheStatsJob daily at 6 AM UTC
  - Results stored in image_cache_stats_snapshots table
  - This GenServer caches the latest snapshot in memory
  - Dashboard reads from memory (no DB connection needed)
  - Falls back to database if memory cache is empty
  """

  use GenServer
  require Logger

  alias EventasaurusApp.Images.{ImageCacheStatsSnapshot, ComputeImageCacheStatsJob}

  # Check for new snapshots every 60 seconds
  @poll_interval :timer.seconds(60)

  # Client API

  @doc """
  Start the image cache stats GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get cached stats (instant - reads from memory).

  Returns a map with stats data and metadata:
  - :stats - the actual stats data (summary, by_entity_type, etc.)
  - :computed_at - when the stats were computed
  - :computation_time_ms - how long computation took
  - :is_stale - true if stats are older than 25 hours

  Returns nil if no stats are available.
  """
  def get_stats do
    try do
      GenServer.call(__MODULE__, :get_stats, 5_000)
    catch
      :exit, {:timeout, _} ->
        Logger.warning("Image cache stats cache timeout - falling back to database")
        load_from_database()

      :exit, {:noproc, _} ->
        Logger.warning("Image cache stats cache not started - falling back to database")
        load_from_database()
    end
  end

  @doc """
  Force trigger a new stats computation by queueing an Oban job.
  Returns {:ok, job} or {:error, reason}.
  """
  def refresh do
    case ComputeImageCacheStatsJob.trigger_now() do
      {:ok, job} ->
        Logger.info("Queued image cache stats computation job ##{job.id}")
        {:ok, job}

      error ->
        Logger.error("Failed to queue image cache stats computation: #{inspect(error)}")
        error
    end
  end

  @doc """
  Get the timestamp of the last successful stats computation.
  """
  def last_refreshed_at do
    try do
      GenServer.call(__MODULE__, :last_refreshed_at, 5_000)
    catch
      :exit, _ ->
        case ImageCacheStatsSnapshot.get_latest() do
          nil -> nil
          snapshot -> snapshot.computed_at
        end
    end
  end

  @doc """
  Notify the cache that new stats are available.
  Called by ComputeImageCacheStatsJob after successful computation.
  """
  def notify_update do
    try do
      GenServer.cast(__MODULE__, :reload_from_database)
      :ok
    catch
      :exit, _ -> :ok
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting ImageCacheStatsCache (database-backed)...")

    # Load initial data from database
    state = load_initial_state()

    # Schedule periodic polling for new snapshots
    schedule_poll()

    {:ok, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    # If we have cached stats, return them with metadata
    result =
      if state.stats do
        %{
          stats: state.stats,
          computed_at: state.computed_at,
          computation_time_ms: state.computation_time_ms,
          is_stale: is_stale?(state.computed_at)
        }
      else
        # Try loading from database
        load_from_database()
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:last_refreshed_at, _from, state) do
    {:reply, state.computed_at, state}
  end

  @impl true
  def handle_cast(:reload_from_database, _state) do
    # Called by ComputeImageCacheStatsJob when new stats are available
    Logger.info(
      "Reloading image cache stats from database (notified by ComputeImageCacheStatsJob)"
    )

    new_state = load_initial_state()
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:poll_for_updates, state) do
    # Check if there's a newer snapshot in the database
    new_state =
      try do
        case ImageCacheStatsSnapshot.get_latest() do
          nil ->
            state

          snapshot ->
            if state.snapshot_id != snapshot.id do
              Logger.info("Found new image cache stats snapshot ##{snapshot.id}, updating cache")

              %{
                stats: ImageCacheStatsSnapshot.get_latest_stats(),
                computed_at: snapshot.computed_at,
                computation_time_ms: snapshot.computation_time_ms,
                snapshot_id: snapshot.id
              }
            else
              state
            end
        end
      rescue
        _ -> state
      end

    # Schedule next poll
    schedule_poll()

    {:noreply, new_state}
  end

  # Private Functions

  defp schedule_poll do
    Process.send_after(self(), :poll_for_updates, @poll_interval)
  end

  defp load_initial_state do
    try do
      case ImageCacheStatsSnapshot.get_latest() do
        nil ->
          Logger.warning(
            "No image cache stats snapshot found - stats will load live until first computation"
          )

          %{stats: nil, computed_at: nil, computation_time_ms: nil, snapshot_id: nil}

        snapshot ->
          Logger.info(
            "Loaded image cache stats snapshot ##{snapshot.id} from database (computed at #{snapshot.computed_at})"
          )

          %{
            stats: ImageCacheStatsSnapshot.get_latest_stats(),
            computed_at: snapshot.computed_at,
            computation_time_ms: snapshot.computation_time_ms,
            snapshot_id: snapshot.id
          }
      end
    rescue
      # Handle case where table doesn't exist yet (migration not run)
      e ->
        Logger.warning("Failed to load image cache stats snapshot: #{Exception.message(e)}")
        %{stats: nil, computed_at: nil, computation_time_ms: nil, snapshot_id: nil}
    end
  end

  defp load_from_database do
    try do
      case ImageCacheStatsSnapshot.get_latest() do
        nil ->
          nil

        snapshot ->
          %{
            stats: ImageCacheStatsSnapshot.get_latest_stats(),
            computed_at: snapshot.computed_at,
            computation_time_ms: snapshot.computation_time_ms,
            is_stale: is_stale?(snapshot.computed_at)
          }
      end
    rescue
      # Handle case where table doesn't exist yet
      _ -> nil
    end
  end

  # Stats are considered stale if older than 25 hours (slightly more than daily refresh)
  defp is_stale?(nil), do: true

  defp is_stale?(computed_at) do
    twenty_five_hours_ago = DateTime.utc_now() |> DateTime.add(-25, :hour)
    DateTime.compare(computed_at, twenty_five_hours_ago) == :lt
  end
end
