defmodule Mix.Tasks.Ml.Backtest do
  @moduledoc """
  Run ML category classification backtests.

  Compares ML predictions against existing DB mappings to measure
  accuracy before production integration.

  ## Usage

      # Run backtest with default settings (100 samples)
      mix ml.backtest --name "baseline_test"

      # Run with specific sample size
      mix ml.backtest --name "full_test" --sample-size 500

      # Run with custom confidence threshold
      mix ml.backtest --name "high_conf" --threshold 0.7

      # Filter to specific source
      mix ml.backtest --name "bandsintown_test" --source bandsintown

      # View results of latest run
      mix ml.backtest --results

      # View results of specific run
      mix ml.backtest --results --run-id 1

      # View only incorrect predictions
      mix ml.backtest --results --only-incorrect

      # List all runs
      mix ml.backtest --list

  ## Options

      --name NAME           Name for the backtest run (required for new run)
      --sample-size N       Number of mappings to test (default: 100)
      --threshold FLOAT     Confidence threshold 0.0-1.0 (default: 0.5)
      --source SOURCE       Filter to specific source
      --results             View results instead of running new test
      --run-id ID           Specific run ID for results (default: latest)
      --only-incorrect      Only show incorrect predictions
      --list                List all backtest runs
      --limit N             Limit results (default: 50)
  """

  use Mix.Task
  require Logger

  alias EventasaurusDiscovery.Categories.CategoryBacktester
  alias EventasaurusDiscovery.Categories.CategoryClassifier

  @shortdoc "Run ML category classification backtests"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          name: :string,
          sample_size: :integer,
          threshold: :float,
          source: :string,
          results: :boolean,
          run_id: :integer,
          only_incorrect: :boolean,
          list: :boolean,
          limit: :integer
        ],
        aliases: [
          n: :name,
          s: :sample_size,
          t: :threshold,
          r: :results,
          l: :list
        ]
      )

    # Start application for DB access
    Mix.Task.run("app.start")

    cond do
      Keyword.get(opts, :list) ->
        list_runs(opts)

      Keyword.get(opts, :results) ->
        show_results(opts)

      Keyword.has_key?(opts, :name) ->
        run_backtest(opts)

      true ->
        IO.puts("""
        #{IO.ANSI.red()}Error: Missing required option#{IO.ANSI.reset()}

        Usage:
          mix ml.backtest --name "test_name"     # Run new backtest
          mix ml.backtest --results              # View latest results
          mix ml.backtest --list                 # List all runs

        Run 'mix help ml.backtest' for more options.
        """)

        System.halt(1)
    end
  end

  defp run_backtest(opts) do
    name = Keyword.fetch!(opts, :name)
    sample_size = Keyword.get(opts, :sample_size, 100)
    threshold = Keyword.get(opts, :threshold, 0.5)
    source = Keyword.get(opts, :source)

    IO.puts("""

    #{IO.ANSI.cyan()}🧪 ML Category Backtest#{IO.ANSI.reset()}
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    Name:        #{name}
    Sample Size: #{sample_size}
    Threshold:   #{threshold}
    Source:      #{source || "all sources"}
    Model:       #{CategoryClassifier.model_name()}

    """)

    IO.puts("#{IO.ANSI.yellow()}Loading ML model (this may take a minute)...#{IO.ANSI.reset()}")

    backtest_opts = [
      sample_size: sample_size,
      threshold: threshold,
      source: source
    ]

    case CategoryBacktester.run(name, backtest_opts) do
      {:ok, run} ->
        print_run_summary(run)

      {:error, :no_mappings_found} ->
        IO.puts("""

        #{IO.ANSI.red()}❌ No mappings found#{IO.ANSI.reset()}

        The database has no active direct mappings to test against.
        Run 'mix mappings.validate' to check the mapping status.
        """)

        System.halt(1)

      {:error, reason} ->
        IO.puts("""

        #{IO.ANSI.red()}❌ Backtest failed#{IO.ANSI.reset()}

        Error: #{inspect(reason)}
        """)

        System.halt(1)
    end
  end

  defp show_results(opts) do
    run_id = Keyword.get(opts, :run_id)
    only_incorrect = Keyword.get(opts, :only_incorrect, false)
    limit = Keyword.get(opts, :limit, 50)

    run_result =
      if run_id do
        CategoryBacktester.get_run(run_id)
      else
        CategoryBacktester.get_latest_run()
      end

    case run_result do
      {:ok, run} ->
        print_run_summary(run)

        IO.puts("\n#{IO.ANSI.bright()}Results#{IO.ANSI.reset()}")
        IO.puts("───────────────────────────────────────────────────────────")

        case CategoryBacktester.get_results(run.id,
               only_incorrect: only_incorrect,
               limit: limit
             ) do
          {:ok, results} ->
            if Enum.empty?(results) do
              if only_incorrect do
                IO.puts("#{IO.ANSI.green()}✓ All predictions were correct!#{IO.ANSI.reset()}")
              else
                IO.puts("No results found.")
              end
            else
              print_results_table(results)
              IO.puts("\nShowing #{length(results)} results (limit: #{limit})")

              if only_incorrect do
                IO.puts("#{IO.ANSI.yellow()}Filtered to incorrect predictions only#{IO.ANSI.reset()}")
              end
            end

          {:error, reason} ->
            IO.puts("""

            #{IO.ANSI.red()}Failed to get results#{IO.ANSI.reset()}

            Error: #{inspect(reason)}
            """)
        end

      {:error, :not_found} ->
        IO.puts("""

        #{IO.ANSI.yellow()}No backtest runs found#{IO.ANSI.reset()}

        Run a backtest first with:
          mix ml.backtest --name "test_name"
        """)
    end
  end

  defp list_runs(opts) do
    limit = Keyword.get(opts, :limit, 20)
    runs = CategoryBacktester.list_runs(limit: limit)

    IO.puts("""

    #{IO.ANSI.cyan()}ML Backtest Runs#{IO.ANSI.reset()}
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    """)

    if Enum.empty?(runs) do
      IO.puts("No backtest runs found.")
    else
      IO.puts(
        String.pad_trailing("ID", 6) <>
          String.pad_trailing("Name", 25) <>
          String.pad_trailing("Status", 12) <>
          String.pad_trailing("Samples", 10) <>
          String.pad_trailing("Accuracy", 10) <>
          "Date"
      )

      IO.puts(String.duplicate("─", 80))

      for run <- runs do
        status_color =
          case run.status do
            "completed" -> IO.ANSI.green()
            "failed" -> IO.ANSI.red()
            "running" -> IO.ANSI.yellow()
            _ -> ""
          end

        accuracy_str =
          if run.accuracy do
            "#{Float.round(run.accuracy * 100, 1)}%"
          else
            "-"
          end

        date_str = Calendar.strftime(run.inserted_at, "%Y-%m-%d %H:%M")

        IO.puts(
          String.pad_trailing("#{run.id}", 6) <>
            String.pad_trailing(String.slice(run.name || "", 0, 23), 25) <>
            status_color <>
            String.pad_trailing(run.status, 12) <>
            IO.ANSI.reset() <>
            String.pad_trailing("#{run.sample_size}", 10) <>
            String.pad_trailing(accuracy_str, 10) <>
            date_str
        )
      end
    end

    IO.puts("")
  end

  defp print_run_summary(run) do
    status_color =
      case run.status do
        "completed" -> IO.ANSI.green()
        "failed" -> IO.ANSI.red()
        _ -> IO.ANSI.yellow()
      end

    accuracy_pct = if run.accuracy, do: "#{Float.round(run.accuracy * 100, 1)}%", else: "-"
    precision_pct = if run.precision_macro, do: "#{Float.round(run.precision_macro * 100, 1)}%", else: "-"
    recall_pct = if run.recall_macro, do: "#{Float.round(run.recall_macro * 100, 1)}%", else: "-"
    f1_str = if run.f1_macro, do: "#{Float.round(run.f1_macro, 3)}", else: "-"

    IO.puts("""

    #{IO.ANSI.bright()}Run ##{run.id}: #{run.name}#{IO.ANSI.reset()}
    ───────────────────────────────────────────────────────────

    Status:     #{status_color}#{run.status}#{IO.ANSI.reset()}
    Samples:    #{run.sample_size}
    Threshold:  #{run.threshold}

    #{IO.ANSI.bright()}Metrics#{IO.ANSI.reset()}
    ───────────────────────────────────────────────────────────
    Accuracy:   #{accuracy_pct}
    Precision:  #{precision_pct} (macro)
    Recall:     #{recall_pct} (macro)
    F1 Score:   #{f1_str} (macro)
    """)

    if run.error_message do
      IO.puts("#{IO.ANSI.red()}Error: #{run.error_message}#{IO.ANSI.reset()}\n")
    end
  end

  defp print_results_table(results) do
    IO.puts(
      "\n" <>
        String.pad_trailing("Source", 15) <>
        String.pad_trailing("Term", 30) <>
        String.pad_trailing("Expected", 12) <>
        String.pad_trailing("Predicted", 12) <>
        String.pad_trailing("Score", 8) <>
        "Correct"
    )

    IO.puts(String.duplicate("─", 95))

    for result <- results do
      correct_indicator =
        if result.is_correct do
          "#{IO.ANSI.green()}✓#{IO.ANSI.reset()}"
        else
          "#{IO.ANSI.red()}✗#{IO.ANSI.reset()}"
        end

      score_str =
        if result.prediction_score do
          "#{Float.round(result.prediction_score, 2)}"
        else
          "-"
        end

      term_display = String.slice(result.external_term || "", 0, 28)

      IO.puts(
        String.pad_trailing(result.source || "", 15) <>
          String.pad_trailing(term_display, 30) <>
          String.pad_trailing(result.expected_category_slug || "", 12) <>
          String.pad_trailing(result.predicted_category_slug || "-", 12) <>
          String.pad_trailing(score_str, 8) <>
          correct_indicator
      )
    end
  end
end
