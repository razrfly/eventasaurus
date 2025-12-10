defmodule EventasaurusDiscovery.Admin.DiscoveryStatsCache do
  @moduledoc """
  GenServer-based cache for discovery stats page.

  Reads pre-computed stats from the database (discovery_stats_snapshots table).
  Stats are computed by ComputeStatsJob running every 15 minutes via Oban.

  This architecture solves the OOM issue where stats computation was too memory-intensive
  for the 1GB web VM. The Oban job runs on a worker process that can handle the load.

  ## Usage

      # Get cached stats (fast - reads from memory, falls back to database)
      DiscoveryStatsCache.get_stats()

      # Force trigger a new computation (queues Oban job)
      DiscoveryStatsCache.refresh()

      # Get freshness information
      DiscoveryStatsCache.last_refreshed_at()

  ## Architecture

  - Stats are computed by ComputeStatsJob every 15 minutes
  - Results stored in discovery_stats_snapshots table
  - This GenServer caches the latest snapshot in memory
  - Falls back to database if memory cache is empty
  - Shows "last updated at" timestamp for freshness indication
  """

  use GenServer
  require Logger

  alias EventasaurusDiscovery.Admin.{DiscoveryStatsSnapshot, ComputeStatsJob}

  # Check for new snapshots every 60 seconds
  @poll_interval :timer.seconds(60)

  # Client API

  @doc """
  Start the stats cache GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get cached stats (fast - reads from memory, falls back to database).

  Returns a map with stats data and metadata:
  - :stats - the actual stats data
  - :computed_at - when the stats were computed
  - :computation_time_ms - how long computation took
  - :is_stale - true if stats are older than 30 minutes

  Returns nil if no stats are available.
  """
  def get_stats do
    try do
      GenServer.call(__MODULE__, :get_stats, 5_000)
    catch
      :exit, {:timeout, _} ->
        Logger.warning("Stats cache timeout - falling back to database")
        load_from_database()

      :exit, {:noproc, _} ->
        Logger.warning("Stats cache not started - falling back to database")
        load_from_database()
    end
  end

  @doc """
  Force trigger a new stats computation by queueing an Oban job.
  Returns {:ok, job} or {:error, reason}.
  """
  def refresh do
    case ComputeStatsJob.trigger_now() do
      {:ok, job} ->
        Logger.info("Queued stats computation job ##{job.id}")
        {:ok, job}

      error ->
        Logger.error("Failed to queue stats computation: #{inspect(error)}")
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
        case DiscoveryStatsSnapshot.get_latest() do
          nil -> nil
          snapshot -> snapshot.computed_at
        end
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting DiscoveryStatsCache (database-backed)...")

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
        case load_from_database() do
          nil -> nil
          data -> data
        end
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:last_refreshed_at, _from, state) do
    {:reply, state.computed_at, state}
  end

  @impl true
  def handle_cast(:reload_from_database, _state) do
    # Called by ComputeStatsJob when new stats are available
    Logger.info("Reloading stats from database (notified by ComputeStatsJob)")
    new_state = load_initial_state()
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:poll_for_updates, state) do
    # Check if there's a newer snapshot in the database
    new_state =
      case DiscoveryStatsSnapshot.get_latest() do
        nil ->
          state

        snapshot ->
          if state.snapshot_id != snapshot.id do
            Logger.info("Found new stats snapshot ##{snapshot.id}, updating cache")
            %{
              stats: DiscoveryStatsSnapshot.get_latest_stats(),
              computed_at: snapshot.computed_at,
              computation_time_ms: snapshot.computation_time_ms,
              snapshot_id: snapshot.id
            }
          else
            state
          end
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
      case DiscoveryStatsSnapshot.get_latest() do
        nil ->
          Logger.warning("No stats snapshot found in database - stats will show zeros until first computation")
          %{stats: nil, computed_at: nil, computation_time_ms: nil, snapshot_id: nil}

        snapshot ->
          Logger.info("Loaded stats snapshot ##{snapshot.id} from database (computed at #{snapshot.computed_at})")
          %{
            stats: DiscoveryStatsSnapshot.get_latest_stats(),
            computed_at: snapshot.computed_at,
            computation_time_ms: snapshot.computation_time_ms,
            snapshot_id: snapshot.id
          }
      end
    rescue
      # Handle case where table doesn't exist yet (migration not run)
      Postgrex.Error ->
        Logger.warning("discovery_stats_snapshots table not found - migration may not be run yet")
        %{stats: nil, computed_at: nil, computation_time_ms: nil, snapshot_id: nil}
    end
  end

  defp load_from_database do
    try do
      case DiscoveryStatsSnapshot.get_latest() do
        nil ->
          nil

        snapshot ->
          %{
            stats: DiscoveryStatsSnapshot.get_latest_stats(),
            computed_at: snapshot.computed_at,
            computation_time_ms: snapshot.computation_time_ms,
            is_stale: is_stale?(snapshot.computed_at)
          }
      end
    rescue
      # Handle case where table doesn't exist yet
      Postgrex.Error -> nil
    end
  end

  # Stats are considered stale if older than 30 minutes
  defp is_stale?(nil), do: true

  defp is_stale?(computed_at) do
    thirty_minutes_ago = DateTime.utc_now() |> DateTime.add(-30, :minute)
    DateTime.compare(computed_at, thirty_minutes_ago) == :lt
  end
end
