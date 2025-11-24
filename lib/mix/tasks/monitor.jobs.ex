defmodule Mix.Tasks.Monitor.Jobs do
  @moduledoc """
  CLI tool for monitoring Oban job executions.

  ## Usage

      mix monitor.jobs [command] [options]

  ## Commands

      mix monitor.jobs list                     # Show recent executions (default: 50)
      mix monitor.jobs list --limit 100         # Show specific number
      mix monitor.jobs list --state failure     # Filter by state
      mix monitor.jobs list --source week_pl    # Filter by source

      mix monitor.jobs failures                 # Show recent failures (default: 20)
      mix monitor.jobs failures --limit 50      # More failures
      mix monitor.jobs failures --source karnet # Source-specific failures

      mix monitor.jobs stats                    # Show statistics (default: last 24h)
      mix monitor.jobs stats --hours 168        # Last week
      mix monitor.jobs stats --source week_pl   # Source-specific stats

      mix monitor.jobs worker SyncJob           # Filter by worker type

  ## Options

      --limit      Number of results to show (default varies by command)
      --state      Filter by state: success, failure, cancelled, discarded
      --source     Filter by source name (e.g., week_pl, bandsintown)
      --worker     Filter by worker name (e.g., SyncJob, EventDetailJob)
      --hours      Time range in hours for stats (default: 24)

  ## Examples

      # Recent failures from week_pl source
      mix monitor.jobs failures --source week_pl

      # Last 100 executions with success status
      mix monitor.jobs list --limit 100 --state success

      # Statistics for the last week
      mix monitor.jobs stats --hours 168

      # All SyncJob executions
      mix monitor.jobs worker SyncJob

  ## Output

  The tool provides formatted tables with color-coded state indicators:
  - Green: success
  - Red: failure
  - Yellow: cancelled
  - Magenta: discarded

  Statistics include:
  - Total executions
  - Success/failure counts and rates
  - Average duration
  - Per-source breakdown
  """

  use Mix.Task
  alias EventasaurusDiscovery.Monitoring.JobExecutionCLI

  @shortdoc "Monitor Oban job executions from the command line"

  @impl Mix.Task
  def run(args) do
    # Start application to ensure Repo is available
    Mix.Task.run("app.start")

    case args do
      [] -> list_executions([])
      ["list" | opts] -> list_executions(opts)
      ["failures" | opts] -> show_failures(opts)
      ["stats" | opts] -> show_stats(opts)
      ["worker", worker | opts] -> filter_by_worker(worker, opts)
      [command | _] -> unknown_command(command)
    end
  end

  defp list_executions(opts) do
    parsed_opts = parse_options(opts)

    JobExecutionCLI.list_executions(parsed_opts)
  end

  defp show_failures(opts) do
    parsed_opts = parse_options(opts)

    JobExecutionCLI.show_failures(parsed_opts)
  end

  defp show_stats(opts) do
    parsed_opts = parse_options(opts)

    JobExecutionCLI.show_stats(parsed_opts)
  end

  defp filter_by_worker(worker, opts) do
    parsed_opts = parse_options(opts)
    parsed_opts = Keyword.put(parsed_opts, :worker, worker)

    JobExecutionCLI.list_executions(parsed_opts)
  end

  defp unknown_command(command) do
    Mix.shell().error("Unknown command: #{command}")
    Mix.shell().info("\nAvailable commands:")
    Mix.shell().info("  list      - Show recent executions")
    Mix.shell().info("  failures  - Show recent failures")
    Mix.shell().info("  stats     - Show execution statistics")
    Mix.shell().info("  worker    - Filter by worker type")
    Mix.shell().info("\nRun 'mix help monitor.jobs' for detailed usage")
  end

  # Parse command line options
  defp parse_options(opts) do
    {parsed, _, _} =
      OptionParser.parse(opts,
        strict: [
          limit: :integer,
          state: :string,
          source: :string,
          worker: :string,
          hours: :integer
        ]
      )

    # Convert state string to atom (only valid states to prevent crashes)
    parsed =
      case Keyword.get(parsed, :state) do
        nil ->
          parsed

        state_str ->
          case state_str do
            "success" ->
              Keyword.put(parsed, :state, :success)

            "failure" ->
              Keyword.put(parsed, :state, :failure)

            "cancelled" ->
              Keyword.put(parsed, :state, :cancelled)

            "discarded" ->
              Keyword.put(parsed, :state, :discarded)

            other ->
              Mix.shell().error(
                "Invalid state: #{other}. Must be one of: success, failure, cancelled, discarded"
              )

              Mix.shell().info("Ignoring --state filter")
              parsed
          end
      end

    parsed
  end
end
