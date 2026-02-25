defmodule EventasaurusWeb.Cache.LiveQueryCircuitBreaker do
  @moduledoc """
  Circuit breaker for live database queries on city pages.

  Protects the system when the database is slow or down by skipping
  live queries and serving degraded data from the materialized view
  or stale cache instead.

  ## States

      :closed (normal) → :open (degraded) → :half_open (probing)

  - `:closed` — Live queries pass through normally. Failures are counted;
    if `failure_threshold` failures occur within `failure_window_ms`, trips to `:open`.
  - `:open` — Live queries are skipped. After `cooldown_ms`, transitions to `:half_open`.
  - `:half_open` — Allows one probe request through. Success → `:closed`, failure → `:open`.

  ## Usage

      case LiveQueryCircuitBreaker.allow_request?() do
        :ok ->
          result = do_live_query()
          LiveQueryCircuitBreaker.record_success()
          result

        {:circuit_open, :serve_fallback} ->
          serve_degraded_fallback()
      end

  ## Admin Controls

      LiveQueryCircuitBreaker.force_open()   # Emergency: skip all live queries
      LiveQueryCircuitBreaker.force_close()  # Resume normal operation
      LiveQueryCircuitBreaker.state()        # Inspect current state
  """

  use GenServer
  require Logger

  @ets_table :live_query_circuit_breaker
  @state_key :circuit_state

  # Defaults (overridable via opts)
  @default_failure_threshold 3
  @default_failure_window_ms 60_000
  @default_cooldown_ms 30_000

  # --- Public API (hot path reads via ETS, writes via GenServer) ---

  @doc "Start the circuit breaker GenServer."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if a live query request is allowed.

  Returns `:ok` when the circuit is closed (or half-open for a probe),
  or `{:circuit_open, :serve_fallback}` when the circuit is open.
  """
  @spec allow_request?() :: :ok | {:circuit_open, :serve_fallback}
  def allow_request? do
    case read_state() do
      %{state: :closed} ->
        :ok

      %{state: :half_open} ->
        # Allow one probe request through
        :ok

      %{state: :open, opened_at: opened_at, cooldown_ms: cooldown_ms} ->
        now = System.monotonic_time(:millisecond)

        if now - opened_at >= cooldown_ms do
          # Cooldown elapsed — transition to half_open
          GenServer.cast(__MODULE__, :transition_to_half_open)
          :ok
        else
          {:circuit_open, :serve_fallback}
        end

      _ ->
        # ETS not ready or unknown state — fail open (allow request)
        :ok
    end
  end

  @doc "Record a successful live query. Resets failure count."
  @spec record_success() :: :ok
  def record_success do
    GenServer.cast(__MODULE__, :record_success)
  end

  @doc "Record a failed live query. May trip the circuit if threshold exceeded."
  @spec record_failure(String.t()) :: :ok
  def record_failure(reason \\ "unknown") do
    GenServer.cast(__MODULE__, {:record_failure, reason})
  end

  @doc "Get the current circuit breaker state."
  @spec state() :: map()
  def state do
    read_state()
  end

  @doc "Force the circuit open (admin override). All live queries will be skipped."
  @spec force_open() :: :ok
  def force_open do
    GenServer.call(__MODULE__, :force_open)
  end

  @doc "Force the circuit closed (admin override). Resume normal operation."
  @spec force_close() :: :ok
  def force_close do
    GenServer.call(__MODULE__, :force_close)
  end

  # --- GenServer Implementation ---

  @impl true
  def init(opts) do
    failure_threshold = Keyword.get(opts, :failure_threshold, @default_failure_threshold)
    failure_window_ms = Keyword.get(opts, :failure_window_ms, @default_failure_window_ms)
    cooldown_ms = Keyword.get(opts, :cooldown_ms, @default_cooldown_ms)

    # Create ETS table for lock-free reads on the hot path
    :ets.new(@ets_table, [:named_table, :public, :set, read_concurrency: true])

    initial_state = %{
      state: :closed,
      failure_count: 0,
      failures: [],
      failure_threshold: failure_threshold,
      failure_window_ms: failure_window_ms,
      cooldown_ms: cooldown_ms,
      opened_at: nil,
      last_state_change: System.monotonic_time(:millisecond),
      last_failure_reason: nil
    }

    write_state(initial_state)

    Logger.info(
      "[CircuitBreaker] Started (threshold=#{failure_threshold}, cooldown=#{cooldown_ms}ms)"
    )

    {:ok, initial_state}
  end

  @impl true
  def handle_cast(:record_success, state) do
    case state.state do
      :half_open ->
        # Probe succeeded — close the circuit
        new_state = %{
          state
          | state: :closed,
            failure_count: 0,
            failures: [],
            opened_at: nil,
            last_state_change: System.monotonic_time(:millisecond)
        }

        write_state(new_state)
        emit_state_change(:half_open, :closed)
        Logger.info("[CircuitBreaker] Probe succeeded — circuit CLOSED")
        {:noreply, new_state}

      :closed ->
        # Normal success — just reset failures
        new_state = %{state | failure_count: 0, failures: []}
        write_state(new_state)
        {:noreply, new_state}

      :open ->
        # Shouldn't happen (requests blocked), but handle gracefully
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:record_failure, reason}, state) do
    now = System.monotonic_time(:millisecond)

    case state.state do
      :half_open ->
        # Probe failed — reopen circuit
        new_state = %{
          state
          | state: :open,
            opened_at: now,
            last_state_change: now,
            last_failure_reason: reason
        }

        write_state(new_state)
        emit_state_change(:half_open, :open)
        Logger.warning("[CircuitBreaker] Probe failed — circuit OPEN (reason: #{reason})")
        {:noreply, new_state}

      :closed ->
        # Add failure to window
        window_start = now - state.failure_window_ms

        recent_failures =
          [{now, reason} | state.failures] |> Enum.filter(fn {ts, _} -> ts >= window_start end)

        failure_count = length(recent_failures)

        if failure_count >= state.failure_threshold do
          # Trip the circuit
          new_state = %{
            state
            | state: :open,
              failure_count: failure_count,
              failures: recent_failures,
              opened_at: now,
              last_state_change: now,
              last_failure_reason: reason
          }

          write_state(new_state)
          emit_state_change(:closed, :open)

          Logger.warning(
            "[CircuitBreaker] #{failure_count} failures in #{state.failure_window_ms}ms — circuit OPEN"
          )

          {:noreply, new_state}
        else
          new_state = %{
            state
            | failure_count: failure_count,
              failures: recent_failures,
              last_failure_reason: reason
          }

          write_state(new_state)
          {:noreply, new_state}
        end

      :open ->
        # Already open — just update reason
        new_state = %{state | last_failure_reason: reason}
        write_state(new_state)
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast(:transition_to_half_open, state) do
    if state.state == :open do
      new_state = %{
        state
        | state: :half_open,
          last_state_change: System.monotonic_time(:millisecond)
      }

      write_state(new_state)
      emit_state_change(:open, :half_open)
      Logger.info("[CircuitBreaker] Cooldown elapsed — circuit HALF_OPEN (probing)")
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_call(:force_open, _from, state) do
    now = System.monotonic_time(:millisecond)
    old_state = state.state

    new_state = %{
      state
      | state: :open,
        opened_at: now,
        last_state_change: now,
        last_failure_reason: "admin_override"
    }

    write_state(new_state)
    emit_state_change(old_state, :open)
    Logger.warning("[CircuitBreaker] FORCE OPEN by admin (was: #{old_state})")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:force_close, _from, state) do
    old_state = state.state

    new_state = %{
      state
      | state: :closed,
        failure_count: 0,
        failures: [],
        opened_at: nil,
        last_state_change: System.monotonic_time(:millisecond),
        last_failure_reason: nil
    }

    write_state(new_state)
    emit_state_change(old_state, :closed)
    Logger.info("[CircuitBreaker] FORCE CLOSE by admin (was: #{old_state})")
    {:reply, :ok, new_state}
  end

  # --- ETS helpers ---

  defp write_state(state) do
    :ets.insert(@ets_table, {@state_key, state})
  end

  defp read_state do
    case :ets.lookup(@ets_table, @state_key) do
      [{@state_key, state}] -> state
      [] -> %{state: :closed}
    end
  rescue
    ArgumentError ->
      # ETS table doesn't exist yet (before init)
      %{state: :closed}
  end

  # --- Telemetry ---

  defp emit_state_change(from, to) do
    :telemetry.execute(
      [:eventasaurus, :circuit_breaker, :state_change],
      %{system_time: System.system_time(:millisecond)},
      %{from: from, to: to}
    )
  end
end
