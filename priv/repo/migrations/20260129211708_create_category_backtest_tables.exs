defmodule EventasaurusApp.Repo.Migrations.CreateCategoryBacktestTables do
  use Ecto.Migration

  def change do
    # Create the backtest runs table (metadata for each backtest)
    create table(:category_backtest_runs) do
      # Run identification
      add :name, :string, null: false, size: 255

      # Model configuration
      add :model_name, :string, null: false, default: "facebook/bart-large-mnli", size: 255
      add :candidate_labels, :map, null: false  # JSONB: the category labels used
      add :threshold, :float, null: false, default: 0.5

      # Sample configuration
      add :sample_size, :integer, null: false
      add :source_filter, :string, size: 100  # Optional: filter to specific source

      # Results summary (populated after completion)
      add :accuracy, :float
      add :precision_macro, :float
      add :recall_macro, :float
      add :f1_macro, :float

      # Execution status
      add :status, :string, null: false, default: "pending", size: 50
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :error_message, :text

      # Additional metadata (timings, config, notes)
      add :metadata, :map, default: %{}

      timestamps()
    end

    # Index for listing runs by status and date
    create index(:category_backtest_runs, [:status])
    create index(:category_backtest_runs, [:inserted_at])

    # Create the backtest results table (individual predictions)
    create table(:category_backtest_results) do
      add :backtest_run_id, references(:category_backtest_runs, on_delete: :delete_all),
        null: false

      # Input data (from category_mappings)
      add :source, :string, null: false, size: 100
      add :external_term, :string, null: false, size: 500

      # Expected result (from DB mappings)
      add :expected_category_slug, :string, null: false, size: 100

      # ML Prediction
      add :predicted_category_slug, :string, size: 100
      add :prediction_score, :float
      add :all_scores, :map  # JSONB: full breakdown of all category scores

      # Result analysis
      add :is_correct, :boolean

      # Timing
      add :classification_time_ms, :integer

      timestamps(updated_at: false)  # Results are immutable, no updates
    end

    # Index for fast lookups by run
    create index(:category_backtest_results, [:backtest_run_id])

    # Index for analyzing incorrect predictions
    create index(:category_backtest_results, [:backtest_run_id, :is_correct])

    # Index for analyzing by category
    create index(:category_backtest_results, [:backtest_run_id, :expected_category_slug])
    create index(:category_backtest_results, [:backtest_run_id, :predicted_category_slug])

    # Index for analyzing by source
    create index(:category_backtest_results, [:backtest_run_id, :source])
  end
end
