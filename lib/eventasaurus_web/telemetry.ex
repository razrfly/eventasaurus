defmodule EventasaurusWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics for Ecto Repos (Issue #3160)
      # Monitor connection pool health across all repos to detect exhaustion

      # Repo (web requests via PgBouncer)
      summary("eventasaurus.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "Total time spent on Repo queries"
      ),
      summary("eventasaurus.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "Time spent waiting for Repo connection"
      ),

      # ObanRepo (Oban jobs via PgBouncer - Issue #3160)
      summary("eventasaurus.oban_repo.query.total_time",
        unit: {:native, :millisecond},
        description: "Total time spent on ObanRepo queries"
      ),
      summary("eventasaurus.oban_repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "Time spent waiting for ObanRepo connection"
      ),

      # SessionRepo (migrations via direct connection)
      summary("eventasaurus.session_repo.query.total_time",
        unit: {:native, :millisecond},
        description: "Total time spent on SessionRepo queries"
      ),
      summary("eventasaurus.session_repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "Time spent waiting for SessionRepo connection"
      ),

      # ReplicaRepo (read-heavy queries via direct connection)
      summary("eventasaurus.replica_repo.query.total_time",
        unit: {:native, :millisecond},
        description: "Total time spent on ReplicaRepo queries"
      ),
      summary("eventasaurus.replica_repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "Time spent waiting for ReplicaRepo connection"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # Monitor connection pool stats for all repos (Issue #3160)
      # These measurements are called every 10 seconds to track pool health
      {__MODULE__, :measure_repo_pool_stats, []}
    ]
  end

  @doc """
  Measures connection pool statistics for all Ecto repos.
  Emits telemetry events that can be observed for alerting on pool exhaustion.
  """
  @spec measure_repo_pool_stats() :: :ok
  def measure_repo_pool_stats do
    repos = [
      {:repo, EventasaurusApp.Repo},
      {:oban_repo, EventasaurusApp.ObanRepo},
      {:session_repo, EventasaurusApp.SessionRepo},
      {:replica_repo, EventasaurusApp.ReplicaRepo}
    ]

    for {name, repo} <- repos do
      try do
        # Get pool configuration and calculate utilization
        config = repo.config()
        pool_size = Keyword.get(config, :pool_size, 10)

        # Try to get checkout queue length from DBConnection
        # This reflects how many processes are waiting for a connection
        case Process.whereis(repo) do
          nil ->
            :ok

          _pid ->
            # Emit pool metrics
            # pool_size: configured connections
            # Note: Actual checkout count requires DBConnection internals
            # which aren't exposed publicly, so we emit config for monitoring
            :telemetry.execute(
              [:eventasaurus, name, :pool],
              %{pool_size: pool_size},
              %{repo: repo}
            )
        end
      rescue
        _ -> :ok
      end
    end

    :ok
  end
end
