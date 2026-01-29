defmodule EventasaurusDiscovery.Categories.CategoryBacktester do
  @moduledoc """
  Orchestrates ML category classification backtests.

  Runs backtests comparing ML predictions against existing DB mappings
  to measure accuracy before production integration.

  ## Usage

      # Run a backtest
      {:ok, run} = CategoryBacktester.run("baseline_test", sample_size: 100)

      # Get results
      {:ok, results} = CategoryBacktester.get_results(run.id)

      # Generate confusion matrix
      {:ok, matrix} = CategoryBacktester.confusion_matrix(run.id)

  ## Process

  1. Load sample of category mappings from database
  2. For each mapping, classify the external_term using ML
  3. Compare ML prediction to expected category_slug
  4. Calculate accuracy, precision, recall, F1 metrics
  5. Store results for analysis
  """

  require Logger

  import Ecto.Query, warn: false

  alias EventasaurusApp.Repo
  alias EventasaurusDiscovery.Categories.CategoryBacktestRun
  alias EventasaurusDiscovery.Categories.CategoryBacktestResult
  alias EventasaurusDiscovery.Categories.CategoryClassifier
  alias EventasaurusDiscovery.Categories.CategoryMapping

  @doc """
  Run a backtest against existing DB mappings.

  ## Options

  - `:sample_size` - Number of mappings to test (default: 100)
  - `:source` - Filter to specific source (default: nil = all sources)
  - `:threshold` - Classification confidence threshold (default: 0.5)
  - `:model` - Model name (default: "facebook/bart-large-mnli")

  ## Returns

  - `{:ok, %CategoryBacktestRun{}}` on success
  - `{:error, reason}` on failure
  """
  @spec run(String.t(), keyword()) :: {:ok, CategoryBacktestRun.t()} | {:error, term()}
  def run(name, opts \\ []) do
    sample_size = Keyword.get(opts, :sample_size, 100)
    source_filter = Keyword.get(opts, :source)
    threshold = Keyword.get(opts, :threshold, 0.5)
    model_name = Keyword.get(opts, :model, CategoryClassifier.model_name())

    Logger.info("[CategoryBacktester] Starting backtest '#{name}' with #{sample_size} samples")

    # Create the run record
    run_attrs = %{
      name: name,
      model_name: model_name,
      candidate_labels: CategoryClassifier.category_labels(),
      threshold: threshold,
      sample_size: sample_size,
      source_filter: source_filter
    }

    with {:ok, run} <- create_run(run_attrs),
         {:ok, run} <- start_run(run),
         {:ok, mappings} <- load_mappings(sample_size, source_filter),
         {:ok, run} <- execute_backtest(run, mappings, threshold),
         {:ok, run} <- calculate_metrics(run) do
      Logger.info("[CategoryBacktester] Completed '#{name}': accuracy=#{run.accuracy}")
      {:ok, run}
    else
      {:error, reason} = error ->
        Logger.error("[CategoryBacktester] Failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Get a backtest run by ID with results preloaded.
  """
  @spec get_run(integer()) :: {:ok, CategoryBacktestRun.t()} | {:error, :not_found}
  def get_run(run_id) do
    case Repo.get(CategoryBacktestRun, run_id) do
      nil -> {:error, :not_found}
      run -> {:ok, Repo.preload(run, :results)}
    end
  end

  @doc """
  Get the most recent backtest run.
  """
  @spec get_latest_run() :: {:ok, CategoryBacktestRun.t()} | {:error, :not_found}
  def get_latest_run do
    query =
      from r in CategoryBacktestRun,
        order_by: [desc: r.inserted_at],
        limit: 1

    case Repo.one(query) do
      nil -> {:error, :not_found}
      run -> {:ok, Repo.preload(run, :results)}
    end
  end

  @doc """
  List all backtest runs.

  ## Options

  - `:limit` - Number of runs to return (default: 20)
  - `:status` - Filter by status (default: nil = all)
  """
  @spec list_runs(keyword()) :: [CategoryBacktestRun.t()]
  def list_runs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    status = Keyword.get(opts, :status)

    query =
      from r in CategoryBacktestRun,
        order_by: [desc: r.inserted_at],
        limit: ^limit

    query =
      if status do
        from r in query, where: r.status == ^status
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Get results for a specific run with optional filtering.

  ## Options

  - `:only_incorrect` - Only return incorrect predictions (default: false)
  - `:source` - Filter by source
  - `:category` - Filter by expected or predicted category
  - `:limit` - Limit results
  """
  @spec get_results(integer(), keyword()) :: {:ok, [CategoryBacktestResult.t()]} | {:error, term()}
  def get_results(run_id, opts \\ []) do
    only_incorrect = Keyword.get(opts, :only_incorrect, false)
    source = Keyword.get(opts, :source)
    category = Keyword.get(opts, :category)
    limit = Keyword.get(opts, :limit)

    query =
      from r in CategoryBacktestResult,
        where: r.backtest_run_id == ^run_id,
        order_by: [asc: r.source, asc: r.external_term]

    query =
      if only_incorrect do
        from r in query, where: r.is_correct == false
      else
        query
      end

    query =
      if source do
        from r in query, where: r.source == ^source
      else
        query
      end

    query =
      if category do
        from r in query,
          where: r.expected_category_slug == ^category or r.predicted_category_slug == ^category
      else
        query
      end

    query =
      if limit do
        from r in query, limit: ^limit
      else
        query
      end

    {:ok, Repo.all(query)}
  end

  @doc """
  Generate a confusion matrix for a backtest run.

  Returns a map where keys are `{expected, predicted}` tuples and values are counts.
  """
  @spec confusion_matrix(integer()) :: {:ok, map()} | {:error, term()}
  def confusion_matrix(run_id) do
    query =
      from r in CategoryBacktestResult,
        where: r.backtest_run_id == ^run_id,
        group_by: [r.expected_category_slug, r.predicted_category_slug],
        select: {r.expected_category_slug, r.predicted_category_slug, count(r.id)}

    results = Repo.all(query)

    matrix =
      results
      |> Enum.reduce(%{}, fn {expected, predicted, count}, acc ->
        Map.put(acc, {expected, predicted}, count)
      end)

    {:ok, matrix}
  end

  @doc """
  Get summary statistics for a run.
  """
  @spec get_summary(integer()) :: {:ok, map()} | {:error, term()}
  def get_summary(run_id) do
    with {:ok, run} <- get_run(run_id) do
      correct_count = Enum.count(run.results, & &1.is_correct)
      incorrect_count = length(run.results) - correct_count

      by_source =
        run.results
        |> Enum.group_by(& &1.source)
        |> Enum.map(fn {source, results} ->
          correct = Enum.count(results, & &1.is_correct)
          {source, %{total: length(results), correct: correct, accuracy: correct / length(results)}}
        end)
        |> Map.new()

      summary = %{
        run_id: run.id,
        name: run.name,
        status: run.status,
        total: length(run.results),
        correct: correct_count,
        incorrect: incorrect_count,
        accuracy: run.accuracy,
        precision_macro: run.precision_macro,
        recall_macro: run.recall_macro,
        f1_macro: run.f1_macro,
        by_source: by_source,
        duration_ms: CategoryBacktestRun.duration_ms(run)
      }

      {:ok, summary}
    end
  end

  # Private functions

  defp create_run(attrs) do
    %CategoryBacktestRun{}
    |> CategoryBacktestRun.changeset(attrs)
    |> Repo.insert()
  end

  defp start_run(run) do
    run
    |> CategoryBacktestRun.start_changeset()
    |> Repo.update()
  end

  defp load_mappings(sample_size, source_filter) do
    query =
      from m in CategoryMapping,
        where: m.is_active == true,
        where: m.mapping_type == "direct",
        order_by: fragment("RANDOM()"),
        limit: ^sample_size,
        select: %{
          source: m.source,
          external_term: m.external_term,
          category_slug: m.category_slug
        }

    query =
      if source_filter do
        from m in query, where: m.source == ^source_filter
      else
        query
      end

    mappings = Repo.all(query)

    if Enum.empty?(mappings) do
      {:error, :no_mappings_found}
    else
      Logger.info("[CategoryBacktester] Loaded #{length(mappings)} mappings for testing")
      {:ok, mappings}
    end
  end

  defp execute_backtest(run, mappings, threshold) do
    Logger.info("[CategoryBacktester] Initializing ML model...")

    # Pre-load the serving once for all classifications
    serving = CategoryClassifier.get_serving()

    case serving do
      {:error, reason} ->
        fail_run(run, "Failed to load ML model: #{inspect(reason)}")

      serving ->
        Logger.info("[CategoryBacktester] Running classifications...")

        results =
          mappings
          |> Enum.with_index(1)
          |> Enum.map(fn {mapping, idx} ->
            if rem(idx, 50) == 0 do
              Logger.info("[CategoryBacktester] Progress: #{idx}/#{length(mappings)}")
            end

            classify_mapping(run.id, mapping, serving, threshold)
          end)

        # Batch insert results
        {inserted_count, _} =
          Repo.insert_all(
            CategoryBacktestResult,
            results,
            returning: false
          )

        Logger.info("[CategoryBacktester] Inserted #{inserted_count} results")

        {:ok, run}
    end
  end

  defp classify_mapping(run_id, mapping, serving, threshold) do
    start_time = System.monotonic_time(:millisecond)

    prediction =
      case CategoryClassifier.classify(mapping.external_term,
             serving: serving,
             threshold: threshold
           ) do
        {:ok, result} -> result
        {:error, _} -> %{category: nil, score: 0.0, all_scores: %{}}
      end

    end_time = System.monotonic_time(:millisecond)
    time_ms = end_time - start_time

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    CategoryBacktestResult.from_prediction(run_id, mapping, prediction, time_ms)
    |> Map.put(:inserted_at, now)
  end

  defp calculate_metrics(run) do
    {:ok, results} = get_results(run.id)

    if Enum.empty?(results) do
      fail_run(run, "No results to calculate metrics")
    else
      metrics = compute_classification_metrics(results)

      run
      |> CategoryBacktestRun.complete_changeset(metrics)
      |> Repo.update()
    end
  end

  defp compute_classification_metrics(results) do
    total = length(results)
    correct = Enum.count(results, & &1.is_correct)
    accuracy = if total > 0, do: correct / total, else: 0.0

    # Get all unique categories
    categories =
      results
      |> Enum.flat_map(fn r ->
        [r.expected_category_slug, r.predicted_category_slug]
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    # Calculate per-category precision, recall
    category_metrics =
      Enum.map(categories, fn cat ->
        # True positives: predicted=cat AND expected=cat
        tp = Enum.count(results, &(&1.predicted_category_slug == cat && &1.expected_category_slug == cat))

        # False positives: predicted=cat AND expected!=cat
        fp = Enum.count(results, &(&1.predicted_category_slug == cat && &1.expected_category_slug != cat))

        # False negatives: predicted!=cat AND expected=cat
        fn_ = Enum.count(results, &(&1.predicted_category_slug != cat && &1.expected_category_slug == cat))

        precision = if tp + fp > 0, do: tp / (tp + fp), else: 0.0
        recall = if tp + fn_ > 0, do: tp / (tp + fn_), else: 0.0
        f1 = if precision + recall > 0, do: 2 * precision * recall / (precision + recall), else: 0.0

        {cat, %{precision: precision, recall: recall, f1: f1}}
      end)

    # Macro averages (simple average across categories)
    num_categories = length(category_metrics)

    precision_macro =
      if num_categories > 0 do
        category_metrics
        |> Enum.map(fn {_, m} -> m.precision end)
        |> Enum.sum()
        |> Kernel./(num_categories)
      else
        0.0
      end

    recall_macro =
      if num_categories > 0 do
        category_metrics
        |> Enum.map(fn {_, m} -> m.recall end)
        |> Enum.sum()
        |> Kernel./(num_categories)
      else
        0.0
      end

    f1_macro =
      if num_categories > 0 do
        category_metrics
        |> Enum.map(fn {_, m} -> m.f1 end)
        |> Enum.sum()
        |> Kernel./(num_categories)
      else
        0.0
      end

    %{
      accuracy: Float.round(accuracy, 4),
      precision_macro: Float.round(precision_macro, 4),
      recall_macro: Float.round(recall_macro, 4),
      f1_macro: Float.round(f1_macro, 4)
    }
  end

  defp fail_run(run, error_message) do
    run
    |> CategoryBacktestRun.fail_changeset(error_message)
    |> Repo.update()
  end
end
